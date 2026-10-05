extends RefCounted
## What the states want (config balance.json «state_goals»). The world's events are no longer mostly dice: every
## country with companies looks at itself every few months and decides what it lacks, what it fears and what it
## wants — and acts. The act is an event: demand and share prices of the companies it touches move.
##
## Motives, each scored 0..1 for the country (the strongest one above «threshold» is acted on, one decision per
## review; a motive is not repeated for «cooldown_weeks»):
##   defence     — fear of war: the country is at war, or the player is at war and the country is cold to them →
##                 arms orders: its defence companies grow, tourism and airlines lose.
##   shortage    — it lacks goods: the home market's unmet demand (as orders.gd counts it for the player) → contracts
##                 and subsidies to its own makers of the goods, or imports from friendly countries' companies
##                 (the player's first when the relations are good).
##   independence — fear of the player: grievances from the player's acts against it and its companies (orders.gd
##                 memory), sanctions, a cold relation → it buys less from the player's companies, its own rivals
##                 of them get the orders. A reaction to the player — always told.
##   partnership — it likes the player (a warm relation, the player's friendly acts): orders to the player's
##                 companies of the goods it lacks or the biggest of them. Always told.
##   technology  — fear of falling behind: the player makes breakthroughs and the country is not a friend → it pours
##                 money into its IT, AI, chips and science.
##   rescue      — fear of collapse in a world crisis: the state props up its banks and its biggest company.
##   champion    — prestige: a big economy with a low world prestige backs its biggest company.
## The player's own country decides by the player's orders — it is not run here.

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")
const Events := preload("res://mods/pax_corporations/src/news/events.gd")
const Rivals := preload("res://mods/pax_corporations/src/companies/rivals.gd")
const TECH := ["it", "ии", "semiconductors", "наука"]

var news: Array = []                 # this week's: {c, entry, tone, size, big, always}
var agenda: Dictionary = {}          # country -> {motive: score} at its last review (console, dossier)
var _last: Dictionary = {}           # "country|motive" -> the day it was last acted on
var _rng := RandomNumberGenerator.new()
var db: Data
var game: PaxGame
var goods: Goods
var events: Events
var orders: Object                   # orders.gd: its «memory» — "страна:<name>" -> the player's acts, −1..1


func setup(d: Data, g: PaxGame, gd: Goods, ev: Events, ord: Object) -> void:
	db = d
	game = g
	goods = gd
	events = ev
	orders = ord


func start_new() -> void:
	_rng.randomize()


func _cfg() -> Dictionary:
	return db.balance.get("state_goals", {})


# ---------- weekly ----------

func step(day: int) -> void:
	news.clear()
	var cfg := _cfg()
	if not bool(cfg.get("enabled_flag", true)):
		return
	var player := str(game.player_faction().get("name", ""))
	var factions := {}
	for f in game.factions():
		factions[str((f as Dictionary).get("name", ""))] = f
	var player_at_war := false
	for f in game.factions():
		if str((f as Dictionary).get("treaty", "")) == "война":
			player_at_war = true
	var chance := float(db.dt) / maxf(1.0, float(cfg.get("review_weeks", 13)))
	var limit := int(cfg.get("per_week", 3))
	var done := 0
	var order: Array = db.countries.keys()
	order.shuffle()
	for item in order:
		var country := str(item)
		if country == player or _rng.randf() >= chance:
			continue
		var scores := _scores(country, player, factions, player_at_war)
		agenda[country] = scores
		var best := ""
		var best_v := float(cfg.get("threshold", 0.25))
		for m in scores.keys():
			var v := float(scores[m])
			if v > best_v and day - int(_last.get(country + "|" + str(m), -100000)) >= int(cfg.get("cooldown_weeks", 52)) * 7:
				best = str(m)
				best_v = v
		if best.is_empty():
			continue
		var about_player := best in ["independence", "partnership"]
		if not about_player and done >= limit:
			continue
		if _act(country, player, best, best_v, factions, day):
			_last[country + "|" + best] = day
			if not about_player:
				done += 1


## The country's motives, 0..1 each.
func _scores(country: String, player: String, factions: Dictionary, player_at_war: bool) -> Dictionary:
	var sig: Dictionary = events.signals.get(country, {}) if events != null else {}
	var f: Dictionary = factions.get(country, {})
	var rel := float(f.get("relations", 0.5)) if not f.is_empty() else 0.5
	var memory: Dictionary = orders.get("memory") if orders != null and orders.get("memory") is Dictionary else {}
	var grudge := -float(memory.get("страна:" + country, 0.0))   # > 0 — the player wronged it
	var out := {}
	var threat := 0.0
	if player_at_war and rel < 0.45:
		threat = 0.5 * (0.45 - rel) / 0.45 + 0.3
	out["defence"] = clampf(float(sig.get("война", 0.0)) + threat, 0.0, 1.0)
	out["shortage"] = clampf(float(_shortage(country)[1]) * 1.5, 0.0, 1.0)
	if not f.is_empty():
		out["independence"] = clampf(maxf(grudge * 1.5, (0.25 - rel) * 3.0) + (0.3 if not Rivals.open_border(db.balance.get("competition", {}), country, player) else 0.0), 0.0, 1.0)
		out["partnership"] = clampf(maxf(-grudge * 1.5, (rel - 0.65) * 2.5), 0.0, 1.0)
		var psig: Dictionary = events.signals.get(player, {}) if events != null else {}
		out["technology"] = clampf(float(psig.get("breakthrough", 0.0)) * (1.0 - rel) * 1.2, 0.0, 1.0)
	out["rescue"] = clampf(float(sig.get("кризис", 0.0)) * 0.8, 0.0, 1.0)
	var people := float(goods.now_people.get(country, 0.0)) / maxf(goods.now_world, 1e-6)
	var prestige := float(db.prestige.get(country, 50.0)) / 100.0
	out["champion"] = clampf(people * 20.0 * (1.0 - prestige) - 0.1, 0.0, 0.6)
	return out


## The goods the country lacks most: [goods key, unmet share of its market 0..1].
func _shortage(country: String) -> Array:
	var best := ["", 0.0]
	var people_now := float(goods.now_people.get(country, 0.0))
	if people_now <= 0.0:
		return best
	var items: Dictionary = db.goods.get("goods", {})
	for k in items.keys():
		var key := str(k)
		var pool := "дом|%s|%s" % [key, country]
		var m: Dictionary = goods.markets.get(pool, {})
		var size := float(m.get("объём", 0.0))
		if size <= 0.0:
			size = people_now * float((items[k] as Dictionary).get("consumption", 300.0)) / 1e6
		else:
			size *= people_now / maxf(float(goods.start_people.get(country, people_now)), 1e-6)
		if size < float(_cfg().get("market_min", 500.0)):
			continue   # a tiny market — not a matter of state
		var gap := (size - float(goods.pool_volume.get(pool, 0.0))) / size
		# The «others» (makers the mod does not list) fill most markets: only a gap beyond their usual part counts.
		gap -= float(m.get("others_rest", 0.5))
		if gap > float(best[1]):
			best = [key, gap]
	return best


# ---------- the decision ----------

func _act(country: String, player: String, motive: String, score: float, factions: Dictionary, day: int) -> bool:
	var cfg := _cfg()
	var k := float(cfg.get("strength", 0.12)) * score
	var home: Array = db.companies.filter(func(x): return str(x.get("_country", "")) == country)
	var mine: Array = db.companies.filter(func(x): return str(x.get("_country", "")) == player)
	var touched: Array = []
	var hurt: Array = []
	var what := ""
	match motive:
		"defence":
			touched = home.filter(func(x): return str(x.get("sector", "")) == "defence")
			hurt = home.filter(func(x): return str(x.get("sector", "")) in ["tourism", "авиа"])
		"shortage":
			var lack := _shortage(country)
			what = str(lack[0])
			if what.is_empty():
				return false
			touched = home.filter(func(x): return str(x.get("profile", "")) == what)
			if touched.is_empty():
				# Nobody makes it at home: imports from the companies of open countries, the player's first if liked.
				var rel := float((factions.get(player, {}) as Dictionary).get("relations", 0.5))
				var sellers: Array = db.companies.filter(func(x): return str(x.get("profile", "")) == what \
					and Rivals.open_border(db.balance.get("competition", {}), str(x.get("_country", "")), country))
				sellers.sort_custom(func(a, b): return _weight(a, player, rel) > _weight(b, player, rel))
				touched = sellers.slice(0, 3)
		"independence":
			touched = mine.filter(func(x): return float(x.get("export", 0.3)) >= 0.15)
			if touched.is_empty():
				return false
			# Its own makers of the same goods take the orders.
			var keys := {}
			for c in touched:
				keys[str((c as Dictionary).get("profile", ""))] = true
			var rivals_here: Array = home.filter(func(x): return keys.has(str(x.get("profile", ""))))
			hurt = touched
			touched = rivals_here
		"partnership":
			var lack2 := _shortage(country)
			what = str(lack2[0])
			touched = mine.filter(func(x): return not what.is_empty() and str(x.get("profile", "")) == what)
			if touched.is_empty():
				var big := mine.duplicate()
				big.sort_custom(func(a, b): return db.cap(a) * float(a.get("export", 0.3)) > db.cap(b) * float(b.get("export", 0.3)))
				touched = big.slice(0, 2)
		"technology":
			touched = home.filter(func(x): return str(x.get("sector", "")) in TECH)
		"rescue":
			touched = home.filter(func(x): return str(x.get("sector", "")) == "banks")
			var top := _biggest(home)
			if not top.is_empty() and not (top in touched):
				touched.append(top)
		"champion":
			var top2 := _biggest(home)
			if not top2.is_empty():
				touched = [top2]
	touched = touched.filter(func(x): return not db.econ(x).is_empty())
	hurt = hurt.filter(func(x): return not db.econ(x).is_empty())
	if touched.is_empty() and hurt.is_empty():
		return false
	var share := float(cfg.get("export_part", 0.5))   # an act abroad reaches only the part of the business sold there
	for c in touched:
		var abroad := str((c as Dictionary).get("_country", "")) != country
		_push(c, k * (share if abroad else 1.0))
	for c in hurt:
		var abroad2 := str((c as Dictionary).get("_country", "")) != country
		_push(c, -k * (share if abroad2 else 1.0) * float(cfg.get("hurt_part", 0.6)))
	var about_player := motive in ["independence", "partnership"]
	var lead: Dictionary = (hurt[0] if motive == "independence" and not hurt.is_empty() else (touched[0] if not touched.is_empty() else hurt[0]))
	var entry := {"вид": "state_goal", "что": motive, "country": country, "goods": what, "count_value": touched.size() + hurt.size(),
		"доля": k, "день": day}
	for c in touched + hurt:
		var own := entry.duplicate()
		own["mine_up"] = c in touched
		((c as Dictionary)["_chronicle"] as Array).append(own)
	var tone := "bad" if motive == "independence" else "good"
	entry["mine_up"] = lead in touched
	news.append({"c": lead, "entry": entry, "tone": tone, "size": maxf(k, 0.05), "big": about_player or k >= 0.08, "always": about_player})
	return true


## A company's pull for an import deal: the player's when the relations are good, then the biggest.
func _weight(c: Dictionary, player: String, rel: float) -> float:
	return db.cap(c) * (3.0 if str(c.get("_country", "")) == player and rel >= 0.45 else 1.0)


func _biggest(list: Array) -> Dictionary:
	var best: Dictionary = {}
	for item in list:
		var c: Dictionary = item
		if best.is_empty() or db.cap(c) > db.cap(best):
			best = c
	return best


## Demand (fades like any event's, events.gd «events_decay») and the share price move by k (−1..1).
func _push(c: Dictionary, k: float) -> void:
	var e := db.econ(c)
	e["event_demand"] = float(e.get("event_demand", 1.0)) * maxf(0.3, 1.0 + k)
	e["шок"] = float(e.get("шок", 0.0)) + log(maxf(0.1, 1.0 + k * 0.6))


# ---------- console and save ----------

func agenda_text() -> PackedStringArray:
	var out: PackedStringArray = []
	for country in agenda.keys():
		var parts: PackedStringArray = []
		var s: Dictionary = agenda[country]
		for m in s.keys():
			if float(s[m]) >= 0.05:
				parts.append("%s %.2f" % [str(m), float(s[m])])
		if not parts.is_empty():
			out.append("%s: %s" % [str(country), ", ".join(parts)])
	return out


func save_state() -> Dictionary:
	return {"last": _last, "agenda": agenda, "зерно": str(_rng.seed), "состояние": str(_rng.state)}


func load_state(state: Dictionary) -> void:
	_last = (state.get("last", {}) as Dictionary).duplicate() if state.get("last") is Dictionary else {}
	agenda = (state.get("agenda", {}) as Dictionary).duplicate(true) if state.get("agenda") is Dictionary else {}
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
