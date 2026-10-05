extends RefCounted
## Companies in the player's country's politics (design doc 13, 20.17) and corruption scandals everywhere (20.9).
## Config balance.json «влияние».
##
## Elections (20.17). Support for the government in a province p, in points:
##   Δp = Σ over the sites in p of 20 × staff / population × (H − 0.5) − 30 × laid off / population
##        + sponsorship + media, at most ±10.
##   Sponsorship: companies that trust the state (≥ 70) pay 0.1 % of revenue a year for the government's campaign,
##   those that back the opposition (trust ≤ 30 or the escalation ladder at «backs the opposition») — against it;
##   +2 points for every 0.1 % of GDP. Media: the mood of the country's media companies, ±3 points.
##   In the game parties are backed by political forces, so the influence reaches the elections through the forces'
##   approval of the government: the unions (the staff's mood and layoffs), the regions (the provinces' Δp, by
##   population), business (the companies' trust and sponsorship), liberals and conservatives (the media). Only the
##   change of the mod's contribution is added each week — the game's own politics moves the rest. When the game
##   counts an election (hook «election_held») the player gets a report on what the companies did.
##
## Scandals (20.9): P(year) = 0.3 × K × (0.5 + 0.5 J) — K the company's corruption, J how independent the courts and
##   the press are (1 − the country's corruption); ×3 while the player's special services dig into the company
##   (orders.gd «давление»). A scandal crashes the price, hurts the reputation and the staff, brings a fine and
##   often a new head; a state company's scandal (or a front man's) hits the government's liberals.

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")
const Politics := preload("res://mods/pax_corporations/src/state/politics.gd")

## Political force -> what of the companies' influence it hears (both presets of the game).
const FORCES := {"профсоюзы": "workers", "регионы": "regions", "народ": "regions", "бизнес": "business", "олигархи": "business",
	"либералы": "media", "консерваторы": "media",
	# 0.24: the forces' names are English (seen: army, bureaucracy, liberals, oligarchs, regions, siloviki)
	"trade_unions": "workers", "unions": "workers", "workers": "workers", "regions": "regions", "people": "regions",
	"business": "business", "oligarchs": "business", "liberals": "media", "conservatives": "media"}

var provinces: Dictionary = {}   # province id -> Δp (points) this week
var national := 0.0              # population-weighted Δ over the country (points)
var parts: Dictionary = {}       # workers, sponsorship, media (points) and business (mood −1..1)
var contribution: Dictionary = {}   # force -> what the mod has added to its approval so far
var forces_found: Array = []     # the forces of the game the mod reaches (for the window)
var scandals: Array = []         # the latest: {день, id, страна, штраф}
var news: Array = []
var _rng := RandomNumberGenerator.new()
var _sampled := false
var db: Data
var game: PaxGame
var goods: Goods
var mod: PaxMod
var replace_head: Callable       # func(company, role, day, why) — lifecycle.replace_head
var say: Callable                # func(text) — a notification + a letter (main.gd)


func setup(m: PaxMod, d: Data, g: PaxGame, gd: Goods, head_cb: Callable, say_cb: Callable) -> void:
	mod = m
	db = d
	game = g
	goods = gd
	replace_head = head_cb
	say = say_cb


func start_new() -> void:
	_rng.randomize()


func _cfg() -> Dictionary:
	return db.balance.get("influence", {})


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


# ---------- weekly ----------

func step(day: int, politics: Politics, gdp_year: float) -> void:
	news.clear()
	var player := str(game.player_faction().get("name", ""))
	_elections(player, politics, gdp_year)
	_apply_forces()
	_scandals(player, day)


## Δp per province of the player's country, the national effect and its parts.
func _elections(player: String, politics: Politics, gdp_year: float) -> void:
	var cfg := _cfg()
	var owners: Variant = Data.province_owners()
	var mine := Data.provinces_of(owners, player)
	provinces.clear()
	if mine.is_empty():
		national = 0.0
		return
	var pops := _populations(mine, player)
	var workers := {}
	for pid in mine:
		provinces[int(pid)] = 0.0
		workers[int(pid)] = 0.0
	# Sites of any company in the player's provinces: their people vote.
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty():
			continue
		var shares: Array = e.get("site_shares", [])
		var pts: Array = c.get("sites", [])
		var h := float(e.get("H", 0.5))
		for i in mini(pts.size(), shares.size()):
			var pid := int((pts[i] as Dictionary).get("province", -1))
			if not provinces.has(pid):
				continue
			var pop := maxf(float(pops.get(pid, 1.0)), 1.0)
			var staff := float(e.get("N", 0.0)) * float(shares[i])
			var laid := float(e.get("fired26", 0.0)) * float(shares[i])
			var v := float(cfg.get("per_satisfaction", 20.0)) * staff / pop * (h - 0.5) - float(cfg.get("per_layoffs", 30.0)) * laid / pop
			workers[pid] = float(workers[pid]) + v
	# Sponsorship and media — over the whole country.
	var sponsor_money := 0.0
	var media_sum := 0.0
	var media_n := 0
	for item in db.companies:
		var c: Dictionary = item
		if str(c.get("_country", "")) != player:
			continue
		var e := db.econ(c)
		var t := float(e.get("trust", 50.0))
		var r := float(e.get("R", 0.0)) * float(cfg.get("sponsorship_from_revenue", 0.001))
		if t >= float(cfg.get("sponsor_from", 70.0)):
			sponsor_money += r
		elif t <= float(cfg.get("opposition_to", 30.0)) or int(e.get("ladder", 0)) >= 3:
			sponsor_money -= r
		if str(c.get("sector", "")) == "медиа":
			media_sum += (t - 50.0) / 50.0
			media_n += 1
	var sponsor := 2.0 * sponsor_money / maxf(0.001 * gdp_year, 1e-6) if gdp_year > 0.0 else 0.0
	sponsor = clampf(sponsor, -float(cfg.get("sponsorship_max", 5.0)), float(cfg.get("sponsorship_max", 5.0)))
	var media := clampf(3.0 * media_sum / float(media_n), -3.0, 3.0) if media_n > 0 else 0.0
	media *= db.cfx(player, "media_ru")   # neural-net media, satellite broadcasting (research trees)
	var cap := float(cfg.get("limit", 10.0))
	var total_pop := 0.0
	var sum := 0.0
	var work_sum := 0.0
	var foreign := float(db.inv_vote)   # strategic companies sold abroad (investments.gd)
	for pid in provinces.keys():
		var w := float(workers[pid])
		provinces[pid] = clampf(w + sponsor + media + foreign, -cap, cap)
		var pop := float(pops.get(pid, 1.0))
		sum += float(provinces[pid]) * pop
		work_sum += clampf(w, -cap, cap) * pop
		total_pop += pop
	national = sum / total_pop if total_pop > 0.0 else 0.0
	parts = {"workers": work_sum / total_pop if total_pop > 0.0 else 0.0, "sponsorship": sponsor, "media": media, "foreign": foreign,
		"business": politics.business_mood, "regions": national}


## Population of each province: the game's survivors in it, else the country's population spread evenly.
func _populations(mine: Array, player: String) -> Dictionary:
	var out := {}
	var map: Variant = game.main.get("полит_карта")
	var prov: Variant = (map as Object).get("пров") if map is Object else null
	var alive: Variant = (prov as Object).get("выжившие") if prov is Object else null
	var people := float(goods.country_info(player).get("humans", 0.0))
	if people <= 0.0:
		people = float((db.goods.get("население", {}) as Dictionary).get(player, 1e7))
	var even := people / maxf(1.0, float(mine.size()))
	for pid in mine:
		var v := 0.0
		if alive is PackedFloat32Array and int(pid) < (alive as PackedFloat32Array).size():
			v = float((alive as PackedFloat32Array)[int(pid)])
		out[int(pid)] = v if v > 0.0 else even
	return out


## The forces' approval of the government: only the change of the mod's contribution goes in each week.
func _apply_forces() -> void:
	var cfg := _cfg()
	var power: Variant = game.main.get("власть")
	if not (is_instance_valid(power) and power is Object):
		return
	var state: Variant = (power as Object).get("гос")
	if not (state is Dictionary):
		return
	var forces: Variant = (state as Dictionary).get("forces", {})
	if not (forces is Dictionary):
		return
	if not _sampled:
		_sampled = true
		_sample_power(state as Dictionary)
	var w: Dictionary = cfg.get("forces_weight", {})
	forces_found.clear()
	for key in (forces as Dictionary).keys():
		var name := str(key)
		if not FORCES.has(name) or not ((forces as Dictionary)[key] is Dictionary):
			continue
		var f: Dictionary = (forces as Dictionary)[key]
		if not f.has("approval"):
			continue
		var what := str(FORCES[name])
		var target := 0.0
		match what:
			"workers":
				target = float(parts.get("workers", 0.0)) / 10.0 * float(w.get("профсоюзы", 0.5))
			"regions":
				target = national / 10.0 * float(w.get("регионы", 0.5))
			"business":
				target = float(parts.get("business", 0.0)) * float(w.get("бизнес", 0.5)) + float(parts.get("sponsorship", 0.0)) / 10.0 * float(w.get("sponsorship", 0.3))
			"media":
				target = float(parts.get("media", 0.0)) / 3.0 * float(w.get("сми", 0.3)) * (1.0 if name == "либералы" else 0.6)
		var inc := clampf(target - float(contribution.get(name, 0.0)), -float(cfg.get("per_week_max", 0.02)) * db.dt, float(cfg.get("per_week_max", 0.02)) * db.dt)
		f["approval"] = clampf(float(f["approval"]) + inc, -1.0, 1.0)
		contribution[name] = float(contribution.get(name, 0.0)) + inc
		forces_found.append(name)


## The structure of the government (keys and types only) — kept in the mod's data to tune the election hook.
func _sample_power(state: Dictionary) -> void:
	mod.save_data("power_sample", _shape(state, 0))


static func _shape(x: Variant, depth: int) -> Variant:
	if depth > 3:
		return type_string(typeof(x))
	if x is Dictionary:
		var out := {}
		var n := 0
		for k in (x as Dictionary).keys():
			out[str(k)] = _shape((x as Dictionary)[k], depth + 1)
			n += 1
			if n >= 25:
				break
		return out
	if x is Array:
		return [type_string(typeof(x)), (x as Array).size(), _shape((x as Array)[0], depth + 1) if not (x as Array).is_empty() else null]
	if x is float or x is int or x is bool:
		return x
	return type_string(typeof(x))


## The game counted an election (hook «election_held»): the player learns what the companies did.
func on_election(d: Dictionary) -> void:
	if db == null:
		return
	mod.save_data("election_sample", {"record": _shape(d.get("record", {}), 0), "state": _shape(d.get("state", {}), 0)})
	var best: Array = []
	for pid in provinces.keys():
		best.append([int(pid), float(provinces[pid])])
	best.sort_custom(func(a, b): return absf(float(a[1])) > absf(float(b[1])))
	var lines: PackedStringArray = []
	for b in best.slice(0, 3):
		if absf(float(b[1])) >= 0.1:
			lines.append("%s %s" % [db.province_name(int(b[0])), ("+" if float(b[1]) >= 0.0 else "−") + db._num(absf(float(b[1])), 1)])
	var text := _t("infl_election") % [("+" if national >= 0.0 else "−") + db._num(absf(national), 1), ", ".join(lines) if not lines.is_empty() else "—"]
	if say.is_valid():
		say.call(text)


# ---------- scandals (20.9) ----------

func _scandals(player: String, day: int) -> void:
	var cfg := _cfg()
	var base := float(cfg.get("scandal_base", 0.3))
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty():
			continue
		var country := str(c.get("_country", ""))
		var k := float(((c.get("_statuses", {}) as Dictionary).get("corruption", {}) as Dictionary).get("value", 30.0)) / 100.0
		var j := clampf(1.0 - db.country_corruption(country), 0.0, 1.0)
		var yearly := base * k * (0.5 + 0.5 * j) * (float(cfg.get("digging_multiplier", 3.0)) if int(c.get("_digging_until", -1)) >= day else 1.0)
		if _rng.randf() < yearly * db.dt / 52.0:
			_scandal(c, e, country == player, day)


func _scandal(c: Dictionary, e: Dictionary, mine: bool, day: int) -> void:
	var cfg := _cfg()
	e["шок"] = float(e.get("шок", 0.0)) + log(_rng.randf_range(0.75, 0.9))
	Goods.reputation_event(db, e, -1.0, float(cfg.get("scandal_reputation", 0.15)))
	e["H"] = clampf(float(e.get("H", 0.5)) - 0.05, 0.02, 0.98)
	var fine := float(e.get("R", 0.0)) * float(cfg.get("scandal_fine", 0.01))
	e["money"] = float(e.get("money", 0.0)) - fine
	if mine:
		game.add_resource(game.home_body(), "money", fine)
	var resigned := _rng.randf() < float(cfg.get("scandal_resignation", 0.4))
	var head := db.text((c.get("глава", {}) as Dictionary).get("name", ""))
	if resigned and replace_head.is_valid():
		replace_head.call(c, "наёмный_управляющий", day, "scandal")
	var entry := {"день": day, "вид": "scandal", "count_value": fine, "name": head if resigned else ""}
	(c["_chronicle"] as Array).append(entry)
	news.append({"c": c, "entry": entry, "tone": "bad", "size": 0.5, "big": true})
	scandals.append({"день": day, "id": str(c["id"]), "country": str(c.get("_country", "")), "fine": fine})
	while scandals.size() > 20:
		scandals.pop_front()
	# A state company (or one run by the state's front man) in a scandal — the government is blamed too.
	if mine and (db.state_share(c) > 0.5 or c.has("_proxy")):
		_hit_force("либералы", -float(cfg.get("state_scandal_liberals", 0.03)))
		if say.is_valid():
			say.call(_t("infl_state_scandal") % db.name_of(c))


func _hit_force(name: String, delta: float) -> void:
	var power: Variant = game.main.get("власть")
	if not (is_instance_valid(power) and power is Object):
		return
	var state: Variant = (power as Object).get("гос")
	var forces: Variant = (state as Dictionary).get("forces", {}) if state is Dictionary else null
	if forces is Dictionary and (forces as Dictionary).get(name) is Dictionary and ((forces as Dictionary)[name] as Dictionary).has("approval"):
		var f: Dictionary = (forces as Dictionary)[name]
		f["approval"] = clampf(float(f["approval"]) + delta, -1.0, 1.0)


# ---------- save ----------

func save_state() -> Dictionary:
	return {"contribution": contribution, "scandals": scandals, "зерно": str(_rng.seed), "состояние": str(_rng.state)}


func load_state(state: Dictionary) -> void:
	contribution = (state.get("contribution", {}) as Dictionary).duplicate() if state.get("contribution") is Dictionary else {}
	scandals = (state.get("scandals", []) as Array).duplicate(true) if state.get("scandals") is Array else []
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
