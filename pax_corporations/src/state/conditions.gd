extends RefCounted
## Companies and the state of the country (ideas doc, section 13; config balance.json «условия»).
## Seven conditions, each 0..1, per country (and per province where the game knows more):
##   дороги, связь, энергия — the country's level × how developed the province is (Main.провинции.мощность);
##   здоровье, образование, институты — the country;
##   безопасность — the country, 0 in a province with a battle (Main.армии.бои).
## Where they come from:
##   • the player's country — the game's own scales of the home colony (Main.мир.колонии[home].шкалы:
##     «инфраструктура», «сеть», «наука»), its economy (Main.хозяйства[home]: power capacity against the load, what
##     share of energy and medicines is met), corruption and the courts' independence (Main.власть.гос.суд), mixed
##     with the quality of the mod's state departments (автодор, жкх, здравоохранение, образование, полиция,
##     прокуратура — departments.gd);
##   • other countries — their services' level (departments.gd ai_quality), wealth (goods.gd, ranked against the
##     world), corruption and war.
## Supplier industries slowly lift their condition in their country (13.5): +0.005 a year for every 1 % of GDP their
## companies' revenue makes, at most +0.03 a year, up to «бонус_предел» in all.
## Index of a company: U = Σ w(sector, v) · x(v, province of the point), averaged over its points by staff. The
## company reads (economy.gd, market.gd): «U» — revenue (a level that moves 0.004·(U − 0.5) a week, within ±15 %),
## costs × (1 + 0.3·(0.5 − U)), the price's drift + 0.001·(U − 0.5) and a jolt 2·ΔU; satisfaction + 20·(health − 0.5)
## + 10·(security − 0.5) points; blackouts (energy < 0.2: plants, data centres and chip makers there make half),
## communication failures (< 0.2: IT, banks, media and AI there −30 %). Every failure is a chronicle entry.

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const VARS := ["roads", "связь", "energy", "здоровье", "образование", "security", "institutions"]
const LOCAL := ["roads", "связь", "energy"]     # also depend on the province's development
## Industries that build their condition (13.5).
const SUPPLIERS := {"строительство": "roads", "it": "связь", "энергетика": "energy", "pharma": "здоровье", "наука": "образование",
	"defence": "security", "banks": "institutions"}
const BLACKOUT_SECTORS := ["semiconductors", "ии"]
const BLACKOUT_POINTS := ["завод", "датацентр"]
const COMM_SECTORS := ["it", "banks", "медиа", "ии"]

var country_vars: Dictionary = {}   # country -> {var: 0..1}
var bonus: Dictionary = {}          # country -> {var: built up by its supplier industries}
var prov_k: Dictionary = {}         # province id -> development factor of the province (0.6..1.3), player's provinces
var battles: Dictionary = {}        # province id -> true while fighting
var news: Array = []
var db: Data
var game: PaxGame


func setup(d: Data, g: PaxGame) -> void:
	db = d
	game = g


func _cfg() -> Dictionary:
	return db.balance.get("условия", {})


## Weights of a sector (13.3), the sum is 1.
func weights(sector: String) -> Dictionary:
	var all: Dictionary = _cfg().get("weights", {})
	var w: Variant = all.get(sector, all.get("_others", {}))
	return w if w is Dictionary else {}


# ---------- weekly ----------

func step(departments: Object, goods: Object, events: Object, day: int) -> void:
	news.clear()
	_read_provinces()
	_countries(departments, goods, events)
	_suppliers(departments, goods)
	var owners: Variant = Data.province_owners()   # read once a week, not per company
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty():
			continue
		_company(c, e, owners, day)


## The player's provinces: how developed each is (the game's «мощность» against the average) and where battles go.
func _read_provinces() -> void:
	prov_k.clear()
	battles.clear()
	var main: Object = game.main
	var pr: Variant = main.get("провинции")
	if pr is Dictionary and (pr as Dictionary).get("capacity") is Dictionary:
		var m: Dictionary = (pr as Dictionary)["capacity"]
		var sum := 0.0
		for v in m.values():
			sum += float(v)
		var avg := sum / float(m.size()) if m.size() > 0 else 0.0
		if avg > 0.0:
			for k in m.keys():
				prov_k[int(str(k).to_int())] = clampf(float(m[k]) / avg, 0.6, 1.3)
	var arm: Variant = main.get("армии")
	if arm is Dictionary and (arm as Dictionary).get("бои") is Array:
		for b in (arm as Dictionary)["бои"]:
			if b is Dictionary:
				battles[int((b as Dictionary).get("province", -1))] = true


## A Dictionary that may come as a JSON string (the game keeps some of its scales that way).
static func _dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v
	if v is String and str(v).strip_edges().begins_with("{"):   # plain text or "" would only log a parse error
		var parsed: Variant = JSON.parse_string(str(v))
		return parsed if parsed is Dictionary else {}
	return {}


func _countries(departments: Object, goods: Object, events: Object) -> void:
	var player := str(game.player_faction().get("name", ""))
	# Wealth ranked against the world (0 — the poorest, 1 — the richest).
	var wealth := {}
	for k in db.countries.keys():
		var info: Dictionary = goods.call("country_info", str(k)) if goods != null else {}
		wealth[str(k)] = float(info.get("богатство", 0.0))
	var order: Array = wealth.keys()
	order.sort_custom(func(a, b): return float(wealth[a]) < float(wealth[b]))
	var rank := {}
	for i in order.size():
		rank[order[i]] = float(i) / maxf(float(order.size() - 1), 1.0)
	var aiq: Dictionary = departments.get("ai_quality") if departments != null else {}
	var q_player: Dictionary = departments.get("quality") if departments != null else {}
	var sig_all: Dictionary = events.get("signals") if events != null else {}
	for k in db.countries.keys():
		var name := str(k)
		var corr := db.country_corruption(name)
		var war := float((sig_all.get(name, {}) as Dictionary).get("война", 0.0))
		var x := {}
		if name == player and not q_player.is_empty():
			x = _player_vars(q_player, corr)
		else:
			var q := float(aiq.get(name, 50.0)) / 100.0
			var w := float(rank.get(name, 0.5))
			x["roads"] = 0.5 * q + 0.5 * w
			x["связь"] = 0.4 * q + 0.6 * w
			x["energy"] = 0.5 * q + 0.5 * w
			x["здоровье"] = 0.6 * q + 0.4 * w
			x["образование"] = 0.6 * q + 0.4 * w
			x["security"] = 0.6 * (1.0 - corr) + 0.4 * q
			x["institutions"] = 0.7 * (1.0 - corr) + 0.3 * q
		x["security"] = float(x["security"]) - 0.3 * war
		var b: Dictionary = bonus.get(name, {})
		for v in VARS:
			x[v] = clampf(float(x.get(v, 0.5)) + float(b.get(v, 0.0)), 0.0, 1.0)
		country_vars[name] = x
		var mean := 0.0
		for v in VARS:
			mean += float(x[v]) / float(VARS.size())
		db.cond_index[name] = mean


## The player's country: the game's scales and economy mixed with the mod's departments.
func _player_vars(q: Dictionary, corr: float) -> Dictionary:
	var main: Object = game.main
	var home := game.home_body()
	var scales := {}
	# Main.мир is a live object in the game (a dictionary only in saves).
	var world: Variant = main.get("мир")
	var cols: Variant = null
	if world is Dictionary:
		cols = (world as Dictionary).get("колонии")
	elif world is Object and is_instance_valid(world):
		cols = (world as Object).get("колонии")
	if cols != null:
		var col: Dictionary = _dict(_dict(cols).get(home))
		scales = _dict(col.get("шкалы"))
	var econ := {}
	var farms: Variant = main.get("хозяйства")
	if farms is Dictionary:
		econ = _dict((farms as Dictionary).get(home))
	var met := _dict(econ.get("fulfilled_need"))
	var load := float(econ.get("load", 0.0))
	var grid := 0.6
	if load > 0.0:
		grid = clampf((float(econ.get("мощность_всего", econ.get("capacity", load))) / load - 0.8) / 0.6, 0.0, 1.0) * float(met.get("energy", 1.0))
	var courts := 0.4
	var power: Variant = main.get("власть")
	if power is Dictionary:
		courts = float(_dict(_dict(_dict(power).get("гос")).get("суд")).get("независимость", 0.4))
	var d := func(key: String) -> float: return float(q.get(key, 50.0)) / 100.0
	var s := func(key: String) -> float: return clampf(float(scales.get(key, 50.0)) / 100.0, 0.0, 1.0)
	return {
		"roads": 0.5 * float(s.call("инфраструктура")) + 0.5 * float(d.call("автодор")),
		"связь": 0.8 * float(s.call("сеть")) + 0.2 * float(d.call("автодор")),
		"energy": 0.6 * grid + 0.4 * float(d.call("жкх")),
		"здоровье": 0.5 * float(met.get("medicine", 1.0)) + 0.5 * float(d.call("здравоохранение")),
		"образование": 0.5 * float(s.call("наука")) + 0.5 * float(d.call("образование")),
		"security": 0.5 * float(d.call("полиция")) + 0.5 * (1.0 - corr),
		"institutions": 0.4 * (1.0 - corr) + 0.3 * courts + 0.3 * float(d.call("прокуратура")),
	}


## 13.5: supplier industries build their condition up — +0.005 a year for every 1 % of GDP, at most +0.03 a year.
func _suppliers(departments: Object, goods: Object) -> void:
	var cfg := _cfg()
	var player := str(game.player_faction().get("name", ""))
	var rev := {}
	for item in db.companies:
		var c: Dictionary = item
		var v := str(SUPPLIERS.get(str(c.get("sector", "")), ""))
		if v.is_empty():
			continue
		var key := str(c.get("_country", "")) + "|" + v
		rev[key] = float(rev.get(key, 0.0)) + maxf(0.0, db.fund(c, "выручка"))
	for key in rev.keys():
		var parts := str(key).split("|")
		var country := parts[0]
		var gdp := 0.0
		if country == player and departments != null and goods != null:
			gdp = float(departments.call("gdp", game, goods, player))
		if gdp <= 0.0:
			for f in game.factions():
				if str((f as Dictionary).get("name", "")) == country:
					gdp = float((f as Dictionary).get("budget", 0.0)) / float(cfg.get("budget_gdp_share", 0.3))
		if gdp <= 0.0:
			continue
		var pct := 100.0 * float(rev[key]) / gdp
		var per_year := minf(float(cfg.get("growth_per_percent", 0.005)) * pct, float(cfg.get("growth_cap", 0.03)))
		var b: Dictionary = bonus.get(country, {})
		b[parts[1]] = minf(float(b.get(parts[1], 0.0)) + per_year * float(db.dt) / 52.0, float(cfg.get("bonus_cap", 0.3)))
		bonus[country] = b


## The value of a condition at one province (the owner's country; the province's development; battles).
func at(v: String, province: int, country: String) -> float:
	var x := float((country_vars.get(country, {}) as Dictionary).get(v, 0.5))
	if v in LOCAL and prov_k.has(province):
		x *= float(prov_k[province])
	if v == "security" and battles.has(province):
		x = 0.0
	return clampf(x, 0.0, 1.0)


## The company's index and conditions this week; failures go to the chronicle.
func _company(c: Dictionary, e: Dictionary, owners: Variant, day: int) -> void:
	var cfg := _cfg()
	var w := weights(str(c.get("sector", "")))
	var pts: Array = c.get("sites", [])
	var shares: Array = e.get("site_shares", [])
	var home := str(c.get("_country", ""))
	var sector := str(c.get("sector", ""))
	var sum := {}
	var u := 0.0
	var total := 0.0
	var black := 0.0
	var mute := 0.0
	var fight := 0.0
	var worst_point := {}
	for i in pts.size():
		var p: Dictionary = pts[i]
		var share := float(shares[i]) if i < shares.size() else 1.0 / float(maxi(pts.size(), 1))
		var pid := int(p.get("province", -1))
		var owner := Data.owner_in(owners, pid)
		var country := owner if not owner.is_empty() and db.countries.has(owner) else home
		var up := 0.0
		for v in VARS:
			var x := at(v, pid, country)
			sum[v] = float(sum.get(v, 0.0)) + x * share
			up += float(w.get(v, 1.0 / 7.0)) * x
		u += up * share
		total += share
		var energy := at("energy", pid, country)
		if energy < float(cfg.get("blackout_below", 0.2)) and (sector in BLACKOUT_SECTORS or str(p.get("type", "")) in BLACKOUT_POINTS):
			black += share
			worst_point = {"вид": "blackout", "site": i}
		if at("связь", pid, country) < float(cfg.get("link_below", 0.2)) and sector in COMM_SECTORS:
			mute += share
			if worst_point.is_empty():
				worst_point = {"вид": "связь", "site": i}
		if battles.has(pid):
			fight += share
			if worst_point.is_empty():
				worst_point = {"вид": "бои", "site": i}
	if total <= 0.0:
		return
	u /= total
	for v in VARS:
		sum[v] = float(sum[v]) / total
	var known := e.has("U")   # the first week after the update or a load: no news about what already was
	var prev: Dictionary = e.get("условия", {})
	var was := float(e.get("U", u))
	e["U"] = u
	e["dU"] = u - was if e.has("U_was") else 0.0
	e["U_was"] = was
	e["условия"] = sum
	e["blackout"] = black / total
	e["unlinked"] = mute / total
	e["in_battles"] = fight / total
	# The revenue level moves with the conditions, within ±15 %.
	var lvl := float(e.get("U_level", 1.0)) + float(cfg.get("growth_per_week", 0.004)) * (u - 0.5) * float(db.dt)
	e["U_level"] = clampf(lvl, 1.0 - float(cfg.get("level_cap", 0.15)), 1.0 + float(cfg.get("level_cap", 0.15)))
	# The price: slow drift and a jolt from a change (a new power line, roads destroyed).
	var jolt := clampf(float(cfg.get("leap_per_dU", 2.0)) * float(e["dU"]), -0.15, 0.15) + float(cfg.get("drift", 0.001)) * (u - 0.5) * float(db.dt)
	if absf(jolt) > 0.0001:
		e["шок"] = float(e.get("шок", 0.0)) + jolt
	# A failure that starts or ends is news.
	var state := str(worst_point.get("вид", ""))
	var before := str(e.get("провал", ""))
	if state != before and not known:
		e["провал"] = state
	elif state != before:
		e["провал"] = state
		var entry := {"день": day, "вид": "условия", "что": state if not state.is_empty() else "конец_" + before}
		if not state.is_empty():
			entry["site"] = int(worst_point.get("site", 0))
		(c["_chronicle"] as Array).append(entry)
		news.append({"c": c, "entry": entry, "tone": "bad" if not state.is_empty() else "good", "size": 0.35 + 0.5 * maxf(black, maxf(mute, fight)) / total})
	if absf(float(e["dU"])) >= float(cfg.get("notable_dU", 0.05)):
		var entry2 := {"день": day, "вид": "условия", "что": "лучше" if float(e["dU"]) > 0.0 else "хуже", "count_value": float(e["dU"]), "main_flag": main_problem(c)}
		# What changed most (weight × change) and where — the newspaper ties the share move to it.
		var cause := ""
		var top := 0.0
		for v in VARS:
			var d := (float(sum[v]) - float(prev.get(v, sum[v]))) * float(w.get(v, 1.0 / 7.0))
			if absf(d) > absf(top):
				top = d
				cause = v
		if not cause.is_empty():
			entry2["reason"] = cause
			entry2["было"] = roundi(float(prev.get(cause, sum[cause])) * 100.0)
			entry2["стало"] = roundi(float(sum[cause]) * 100.0)
			entry2["province"] = db.province_name(int(db.hq_of(c).get("province", 0)))
			entry2["shares"] = jolt
		(c["_chronicle"] as Array).append(entry2)
		news.append({"c": c, "entry": entry2, "tone": "good" if float(e["dU"]) > 0.0 else "bad", "size": 0.3 + absf(float(e["dU"]))})


## The condition that pulls the company down most: weight × (1 − value).
func main_problem(c: Dictionary) -> String:
	var e := db.econ(c)
	var cond: Dictionary = e.get("условия", {})
	var w := weights(str(c.get("sector", "")))
	var best := ""
	var worst := -1.0
	for v in VARS:
		var loss := float(w.get(v, 1.0 / 7.0)) * (1.0 - float(cond.get(v, 0.5)))
		if loss > worst:
			worst = loss
			best = v
	return best


# ---------- save ----------

func save_state() -> Dictionary:
	return {"bonus": bonus}


func load_state(state: Dictionary) -> void:
	bonus = (state.get("bonus", {}) as Dictionary).duplicate(true) if state.get("bonus") is Dictionary else {}
