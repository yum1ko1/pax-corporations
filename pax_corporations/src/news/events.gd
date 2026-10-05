extends RefCounted
## The world's events reach the companies (sections 7, 11, 20.2, 20.4, 20.5, 20.12). Once a week:
##
## 1. Signals: how strong each event is in each country, −1..1 — war, sanctions, oil price, science
##    breakthroughs, the world financial crisis, GDP growth. Read from the game (wars — «связи» and treaties,
##    oil — the world market price against the normal one, sanctions and GDP — only the player's country
##    has them in the game) and from the mod's own crisis.
## 2. Each company is exposed through its sector's sensitivity table (config/sectors.json):
##    exposure = Σ s(sector, event) · I(country, event). It sets the level of demand for the company's work (and so
##    staff and revenue in economy.gd) and the share price; a change of a signal gives a one-off jolt.
## 3. Random rises and falls (20.4): formulas choose who and how much, the text picks a fitting reason.
## 4. Sector trends (20.5) for the «Market news» strip.
## 5. The world financial crisis (20.12): market tension builds up from overheating, debt and shocks,
##    then breaks out in stages — crash, chain reaction, recession, recovery.
##
## News for the player is collected in `news` and handed out by main.gd.

const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")   # Main's methods, 0.24 names
const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")
const EVENTS := ["война", "санкции", "oil_rises", "breakthrough", "кризис", "gdp_growth"]
const STAGE_WEEKS := {1: 0, 2: 2, 3: 6, 4: 26, 5: 52}
const REASONS := 5   # reason_<kind>_<up|down>_1..5 in data/lang

var signals: Dictionary = {}     # country -> {event: I}
var trends: Dictionary = {}      # sector -> T (the world)
var country_trends: Dictionary = {}   # country -> {sector -> T}
var crisis := {"H": 0.0, "stage": 0, "weeks": 0, "глубина": 0.0, "alarm": false, "пауза": 0}
var news: Array = []             # this week's candidate news: {c, text_key, args, tone, size, always}
var _prev: Dictionary = {}       # last week's signals, for the one-off jolts
var _oil_history: Array = []
var _oil_base := -1.0            # the normal oil price from data/market.json, read once
var _rng := RandomNumberGenerator.new()


func start_new() -> void:
	_rng.randomize()
	crisis["пауза"] = 156   # no crash in the first three years of a new game


# ---------- weekly step ----------

func step(db: Data, game: PaxGame, day: int) -> void:
	news.clear()
	var cfg: Dictionary = db.balance.get("события", {})
	_read_signals(db, game)
	_crisis_step(db, cfg, day)
	_apply(db, cfg)
	_random_events(db, cfg, day)
	_trends(db, cfg)
	_prev = signals.duplicate(true)


## Crisis stage for other modules: 2–4 is the bad part (no dividends, the «crisis» sensitivity is on).
func crisis_on() -> bool:
	return int(crisis["stage"]) in [2, 3, 4]


# ---------- 1. signals ----------

func _read_signals(db: Data, game: PaxGame) -> void:
	var main: Object = game.main
	var player := str(game.player_faction().get("name", ""))
	var by_name: Dictionary = {}
	for f in game.factions():
		by_name[str((f as Dictionary).get("name", ""))] = f
	var oil := _oil_signal(main)
	var crisis_i := 1.0 if crisis_on() else 0.0
	signals.clear()
	for country in db.countries.keys():
		var s := {}
		for e in EVENTS:
			s[e] = 0.0
		s["война"] = 1.0 if _at_war(str(country), player, by_name) else 0.0
		s["oil_rises"] = oil
		s["кризис"] = crisis_i
		if str(country) == player:
			s["санкции"] = _player_sanctions(main)
			s["gdp_growth"] = _player_growth(game)
			s["breakthrough"] = _player_science(main)
		# Research trees: accelerators, orbital labs, new physics — breakthroughs of their own («прорыв» > 1).
		var br := db.cfx(str(country), "breakthrough")
		if br > 1.0 and _rng.randf() < 0.03 * (br - 1.0) * float(db.dt):
			s["breakthrough"] = maxf(float(s["breakthrough"]), 1.0)
		signals[country] = s


func _at_war(country: String, player: String, by_name: Dictionary) -> bool:
	if country == player:
		for f in by_name.values():
			if str((f as Dictionary).get("treaty", "")) == "война":
				return true
		return false
	var f: Dictionary = by_name.get(country, {})
	if str(f.get("treaty", "")) == "война":
		return true
	var links: Variant = f.get("связи", {})
	if links is Dictionary:
		for v in (links as Dictionary).values():
			if str(v) == "война":
				return true
	return false


## Oil price against the normal one from data/market.json: +1 when 50% dearer, −1 when 50% cheaper.
func _oil_signal(main: Object) -> float:
	if not GameApi.has(main, "_цена_продукта"):
		return 0.0
	var now := float(GameApi.call_main(main, "_цена_продукта", ["oil"]))
	if _oil_base < 0.0:
		var market: Variant = Pax.json("res://data/market.json", {})
		_oil_base = 0.0
		if market is Dictionary:
			_oil_base = float((((market as Dictionary).get("goods", {}) as Dictionary).get("oil", {}) as Dictionary).get("price", 0.0))
	var base := _oil_base
	_oil_history.append(now)
	while _oil_history.size() > 5:
		_oil_history.pop_front()
	return clampf((now / base - 1.0) / 0.5, -1.0, 1.0) if base > 0.0 else 0.0


func _player_sanctions(main: Object) -> float:
	var worst := 0.0
	if GameApi.has(main, "_санкции_видами"):
		var kinds: Variant = GameApi.call_main(main, "_санкции_видами")
		if kinds is Dictionary:
			for v in (kinds as Dictionary).values():
				worst = maxf(worst, float(v))
	var orgs: Variant = main.get("организации")
	if orgs is Array:
		for o in orgs:
			if o is Dictionary:
				worst = maxf(worst, float((o as Dictionary).get("санкции", 0.0)))
	return clampf(worst, 0.0, 1.0)


## The player's GDP growth a year against 5%: from Main.хозяйства (weekly GDP now vs at the start).
func _player_growth(game: PaxGame) -> float:
	var farms: Variant = game.main.get("хозяйства")
	if not (farms is Dictionary):
		return 0.0
	var h: Dictionary = (farms as Dictionary).get(game.home_body(), {})
	var start := float(h.get("gdp_start", 0.0))
	var now := float(h.get("gdp_week", 0.0))
	if start <= 0.0 or now <= 0.0:
		return 0.0
	var years := maxf(float(game.day()) / 365.0, 0.25)
	return clampf((pow(now / start, 1.0 / years) - 1.0) / 0.05, -1.0, 1.0)


## Breakthroughs of the player's country this week (Main._наука_за_неделю()).
func _player_science(main: Object) -> float:
	if not GameApi.has(main, "_наука_за_неделю"):
		return 0.0
	var week: Variant = GameApi.call_main(main, "_наука_за_неделю")
	if not (week is Dictionary):
		return 0.0
	var mine: Variant = (week as Dictionary).get("country", {})
	var count := 0
	if mine is Dictionary:
		count = (mine as Dictionary).size()
	elif mine is Array:
		count = (mine as Array).size()
	return clampf(0.5 * count, 0.0, 1.0)


# ---------- 2. exposure ----------

func exposure(db: Data, c: Dictionary) -> Dictionary:
	var sens: Dictionary = db.sector_of(c).get("sensitivity", {})
	var sig: Dictionary = signals.get(str(c.get("_country", "")), {})
	var parts := {}
	var total := 0.0
	for e in EVENTS:
		var v := float(sens.get(e, 0.0)) * float(sig.get(e, 0.0)) * (db.tree(c, "санкции", 1.0) if e == "санкции" else 1.0) \
			* db.cfx_c(c, "событие_" + str(e))   # research discoveries soften (or strengthen) an event
		if absf(v) > 0.0001:
			parts[e] = v
			total += v
	return {"total": total, "parts": parts}


func _apply(db: Data, cfg: Dictionary) -> void:
	var k_level := float(cfg.get("demand_from_climate", 0.15))
	var k_drift := float(cfg.get("price_from_climate", 0.003))
	var k_jolt := float(cfg.get("push", 0.08))
	var fade := float(cfg.get("events_decay", 0.01))
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty():
			continue
		var ex := exposure(db, c)
		c["_climate"] = ex
		var total := float(ex["total"])
		var sens: Dictionary = db.sector_of(c).get("sensitivity", {})
		var now: Dictionary = signals.get(str(c.get("_country", "")), {})
		var before: Dictionary = _prev.get(str(c.get("_country", "")), now)
		var jolt := 0.0
		for ev in EVENTS:
			jolt += float(sens.get(ev, 0.0)) * (float(now.get(ev, 0.0)) - float(before.get(ev, 0.0)))
		# The situation sets a demand LEVEL (war keeps oil demand ~8% up while it lasts), reached gradually.
		var level := float(e.get("climate_demand", 1.0))
		e["climate_demand"] = level + 0.05 * (exp(k_level * total) - level)
		e["шок"] = float(e.get("шок", 0.0)) + k_drift * total + k_jolt * jolt + 0.002 * float(trends.get(str(c.get("sector", "")), 0.0))
		# A random event's gain or loss of demand fades: good luck and bad luck both pass with time.
		var ev_level := float(e.get("event_demand", 1.0))
		e["event_demand"] = ev_level + fade * (1.0 - ev_level)
		_crisis_on_company(db, c, e, cfg)
	crisis["crash_now"] = false


# ---------- 3. random rises and falls (20.4) ----------

func _random_events(db: Data, cfg: Dictionary, day: int) -> void:
	if db.companies.is_empty():
		return
	var lam := maxf(float(cfg.get("events_min", 0.3)), float(cfg.get("events_per_1000", 1.33)) * db.companies.size() / 1000.0)
	var count := _poisson(lam)
	for i in count:
		var c := _pick_company(db)
		if c.is_empty():
			continue
		var total := float((c.get("_climate", {}) as Dictionary).get("total", 0.0))
		var momentum := db.change(c, 12)
		var up := _rng.randf() < 1.0 / (1.0 + exp(-(3.0 * total + 2.0 * momentum)))
		var size := minf(0.6, exp(log(0.08) + 0.6 * _rng.randfn(0.0, 1.0)))
		var shot := up and _rng.randf() < float(cfg.get("shot_chance", 0.02))
		if shot:
			size = minf(2.0, size * 3.0)
		var roll := _rng.randf()
		var kind := "price" if roll < 0.5 else ("выручка" if roll < 0.7 else ("репутация" if roll < 0.85 else ("site" if roll < 0.95 else "satisfaction")))
		_apply_random(db, c, kind, up, size)
		var reason := _reason(c, kind, up)
		var entry := {"вид": "событие", "что": kind, "up": up, "доля": size, "shot": shot, "reason": reason}
		entry["день"] = day
		(c["_chronicle"] as Array).append(entry)
		news.append({"c": c, "entry": entry, "tone": "good" if up else "bad", "size": size, "big": shot or size >= 0.2})


func _apply_random(db: Data, c: Dictionary, kind: String, up: bool, size: float) -> void:
	var e := db.econ(c)
	if e.is_empty():
		return
	var dir := 1.0 if up else -1.0
	var level := float(e.get("event_demand", 1.0))
	match kind:
		"price":
			e["шок"] = float(e.get("шок", 0.0)) + log(maxf(0.05, 1.0 + dir * size))
		"выручка":
			e["event_demand"] = level * maxf(0.2, 1.0 + dir * size * 0.5)
			e["шок"] = float(e.get("шок", 0.0)) + log(maxf(0.05, 1.0 + dir * size * 0.4))
		"репутация", "site":
			e["event_demand"] = level * maxf(0.2, 1.0 + dir * size * 0.25)
			if kind == "репутация":
				Goods.reputation_event(db, e, dir, size)   # people remember: popularity of the goods moves (goods.gd)
			e["шок"] = float(e.get("шок", 0.0)) + log(maxf(0.05, 1.0 + dir * size * 0.5))
		"satisfaction":
			e["H"] = clampf(float(e["H"]) + dir * size * 0.3, 0.02, 0.98)


## A reason that fits: the game event that pushes the company hardest, or an inner cause.
func _reason(c: Dictionary, kind: String, up: bool) -> String:
	var parts: Dictionary = (c.get("_climate", {}) as Dictionary).get("parts", {})
	var best := ""
	var best_v := 0.2
	for ev in parts.keys():
		var v := float(parts[ev])
		if (v > 0.0) == up and absf(v) >= best_v:
			best_v = absf(v)
			best = str(ev)
	if not best.is_empty():
		return "because_" + best + ("_up" if up else "_down")
	return "reason_%s_%s_%d" % [kind, "up" if up else "down", _rng.randi_range(1, REASONS)]


func _pick_company(db: Data) -> Dictionary:
	var weights: Array = []
	var sum := 0.0
	for item in db.companies:
		var c: Dictionary = item
		var total := float((c.get("_climate", {}) as Dictionary).get("total", 0.0))
		var w := pow(maxf(db.cap(c), 1.0), 0.3) * (1.0 + 5.0 * db.volatility(c)) * (1.0 + absf(total))
		weights.append(w)
		sum += w
	var x := _rng.randf() * sum
	for i in weights.size():
		x -= float(weights[i])
		if x <= 0.0:
			return db.companies[i]
	return db.companies[db.companies.size() - 1]


func _poisson(lam: float) -> int:
	var l := exp(-lam)
	var k := -1
	var p := 1.0
	while p > l:
		p *= _rng.randf()
		k += 1
	return k


# ---------- 4. sector trends (20.5) ----------

func _trends(db: Data, cfg: Dictionary) -> void:
	var a := float(cfg.get("trend_smoothing", 0.1))
	for key in db.sectors.keys():
		var sens: Dictionary = (db.sectors[key] as Dictionary).get("sensitivity", {})
		var pull := 0.0
		var n := 0
		for country in signals.keys():
			var sig: Dictionary = signals[country]
			for ev in EVENTS:
				pull += float(sens.get(ev, 0.0)) * float(sig.get(ev, 0.0))
			n += 1
		if n > 0:
			pull /= n
		trends[key] = (1.0 - a) * float(trends.get(key, 0.0)) + a * pull
		# The same per country — «Market news» of the player's country reads these.
		for country in signals.keys():
			var own := 0.0
			var csig: Dictionary = signals[country]
			for ev in EVENTS:
				own += float(sens.get(ev, 0.0)) * float(csig.get(ev, 0.0))
			var ct: Dictionary = country_trends.get(country, {})
			ct[key] = (1.0 - a) * float(ct.get(key, 0.0)) + a * own
			country_trends[country] = ct


## Top 3 rising and falling sectors: {"up": [keys], "down": [keys]} — of the world, or of one country.
func market_news(country: String = "") -> Dictionary:
	var tv: Dictionary = trends if country.is_empty() else country_trends.get(country, {})
	var keys: Array = tv.keys()
	keys.sort_custom(func(x, y): return float(tv[x]) > float(tv[y]))
	var up: Array = keys.slice(0, 3).filter(func(k): return float(tv[k]) > 0.01)
	var rev := keys.duplicate()
	rev.reverse()
	var down: Array = rev.slice(0, 3).filter(func(k): return float(tv[k]) < -0.01)
	return {"up": up, "down": down}


# ---------- 5. world financial crisis (20.12) ----------

func _crisis_step(db: Data, cfg: Dictionary, day: int) -> void:
	var ccfg: Dictionary = cfg.get("кризис", {})
	var stage := int(crisis["stage"])
	if stage >= 2:
		crisis["weeks"] = int(crisis["weeks"]) - db.dt
		if int(crisis["weeks"]) <= 0:
			stage = stage + 1 if stage < 5 else 0
			crisis["stage"] = stage
			crisis["weeks"] = _stage_weeks(stage, ccfg)
			if stage == 0:
				crisis["alarm"] = false
				crisis["пауза"] = int(ccfg.get("pause_weeks", 260))
			_crisis_news(stage, day)
		return
	crisis["пауза"] = maxi(0, int(crisis.get("пауза", 0)) - db.dt)

	# Tension: a slow background (the credit cycle) plus bubbles — prices above what the companies earn
	# justifies — plus debt. Price growth that only follows earnings (a recovery) is not a bubble.
	var bubble_from := float(ccfg.get("bubble_threshold", 0.15))
	var overheat := 0.0
	var debt := 0.0
	var n := 0
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		var fair := float(e.get("fair", 0.0))
		if fair > 0.0:
			overheat += maxf(0.0, log(maxf(db.cap(c), 1e-6) / fair) - bubble_from)
		debt += maxf(0.0, db.fund(c, "debt") / maxf(db.fund(c, "выручка"), 1.0) - 1.5)
		n += 1
	if n > 0:
		overheat /= n
		debt /= n
	var shocks := 0.0
	for country in signals.keys():
		var was: Dictionary = _prev.get(country, {})
		if float((signals[country] as Dictionary).get("война", 0.0)) > 0.5 and float(was.get("война", 1.0)) < 0.5:
			shocks += 0.3
	if _oil_history.size() >= 5 and float(_oil_history[0]) > 0.0 and float(_oil_history[4]) / float(_oil_history[0]) > 1.5:
		shocks += 0.2
	var strength := float(cfg.get("crisis_strength", 1.0))
	crisis["H"] = pow(float(ccfg.get("decay", 0.985)), db.dt) * float(crisis["H"]) \
		+ strength * (0.5 * overheat + 0.3 * debt + float(ccfg.get("фон", 0.012))) * db.dt + shocks
	if int(crisis["пауза"]) > 0:
		return   # the world is still healing from the last crisis
	var h := float(crisis["H"])
	if h > 1.2 and not bool(crisis["alarm"]):
		crisis["alarm"] = true
		crisis["stage"] = 1
		_crisis_news(1, day)
	var p := 1.0 - pow(1.0 - clampf(1.0 / (1.0 + exp(-(4.0 * h - 8.0))) * float(cfg.get("crisis_frequency", 1.0)), 0.0, 1.0), db.dt)
	if _rng.randf() < p:
		crisis["глубина"] = clampf(0.2 + 0.3 * h, 0.2, 0.6)
		crisis["stage"] = 2
		crisis["weeks"] = int(STAGE_WEEKS[2])
		crisis["H"] = 0.0
		crisis["crash_now"] = true
		_crisis_news(2, day)


## Force the crash now (console: corp crisis).
func force_crisis(day: int) -> void:
	crisis["глубина"] = 0.35
	crisis["stage"] = 2
	crisis["weeks"] = int(STAGE_WEEKS[2])
	crisis["H"] = 0.0
	crisis["crash_now"] = true
	_crisis_news(2, day)


static func _stage_weeks(stage: int, ccfg: Dictionary) -> int:
	if stage == 5:
		return int(ccfg.get("revival_weeks", STAGE_WEEKS[5]))
	return int(STAGE_WEEKS.get(stage, 0))


## The crisis cuts demand through its own multiplier (e["crisis_demand"]); from the recovery on it grows back
## to 1, so a crisis is a deep dip, not a permanent loss.
func _crisis_on_company(db: Data, c: Dictionary, e: Dictionary, cfg: Dictionary) -> void:
	var stage := int(crisis["stage"])
	var level := float(e.get("crisis_demand", 1.0))
	if stage < 2 or stage == 5:
		if level < 1.0:
			var rec := float((cfg.get("кризис", {}) as Dictionary).get("recovery", 0.03))
			e["crisis_demand"] = level + rec * (1.0 - level)
		return
	var sens := maxf(0.2, -float((db.sector_of(c).get("sensitivity", {}) as Dictionary).get("кризис", -0.5)))
	match stage:
		2:
			if bool(crisis.get("crash_now", false)):
				var depth := float(crisis["глубина"]) * sens
				e["шок"] = float(e.get("шок", 0.0)) + log(maxf(0.1, 1.0 - depth))
				e["crisis_demand"] = level * (1.0 - 0.3 * depth)
		3:
			e["crisis_demand"] = level * (1.0 - 0.01 * sens)
		4:
			e["crisis_demand"] = level * (1.0 - 0.003 * sens)


func _crisis_news(stage: int, day: int) -> void:
	news.append({"c": {}, "entry": {"вид": "кризис", "stage": stage, "день": day}, "tone": "good" if stage in [0, 5] else "bad",
		"size": 1.0, "big": true, "always": true})


# ---------- save ----------

func save_state() -> Dictionary:
	return {"зерно": str(_rng.seed), "состояние": str(_rng.state), "signals": _prev, "trends": trends, "country_trends": country_trends,
		"кризис": crisis, "oil": _oil_history}


func load_state(state: Dictionary) -> void:
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
	if state.get("signals") is Dictionary:
		_prev = (state["signals"] as Dictionary).duplicate(true)
		signals = _prev.duplicate(true)
	if state.get("trends") is Dictionary:
		trends = (state["trends"] as Dictionary).duplicate(true)
	if state.get("country_trends") is Dictionary:
		country_trends = (state["country_trends"] as Dictionary).duplicate(true)
	if state.get("кризис") is Dictionary:
		for k in (state["кризис"] as Dictionary).keys():
			crisis[k] = state["кризис"][k]
	if state.get("oil") is Array:
		_oil_history = (state["oil"] as Array).duplicate()


## Saves from before the long cycles (version < 3): demand lost to crises and bad luck was baked into
## e["demand"] for good. Everything above or below the sector's own trend becomes the fading event level,
## and the tension of the crisis loop is let go.
func migrate_v3(db: Data, weeks: int) -> void:
	for item in db.companies:
		var e := db.econ(item)
		if e.is_empty():
			continue
		var trend := exp(float(db.sector_of(item).get("drift", 0.03)) * float(weeks) / 52.0)
		e["event_demand"] = clampf(float(e["demand"]) / trend, 0.2, 5.0)
		e["demand"] = trend
		e["crisis_demand"] = 1.0
	crisis["H"] = minf(float(crisis["H"]), 0.3)
	if int(crisis["stage"]) < 2:
		crisis["пауза"] = 104
