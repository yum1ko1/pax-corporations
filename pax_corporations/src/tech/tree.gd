extends RefCounted
## Development trees of industries (ideas doc 1–6, as agreed with the player; config/trees.json).
## One tree per industry per country: its bonuses go to every company of that industry in the country. Nodes are
## bought with «Гос вложения» (GV), no cap. The bottom branch «Технологии» is developed only by the country's
## leading company of the industry (the first by index): a bought tech node takes «недель» weeks, then its bonus
## works and the country has the technology. No company of the industry in the country — the tree is closed.
## The leader is lost (bankrupt, gone abroad, under foreign control) — the tech branch loses one node, the deepest
## first, at random among the ones nothing else stands on; simply overtaken — the leadership passes, nothing lost.
## GV: every country earns development points a week from its companies (config «гв»); AI countries spend them
## automatically on their trees. Effects reach the formulas through corp_data.tree(c, key, neutral).
## The research industries (AI, science, space — «валюта»: «но») are paid in «НО», scientific discoveries: they build
## slower (config «но»: from the revenue of those industries and their companies in the world top-300) and buy only
## those trees. All their branches are discoveries that change the mod's mechanics for the whole country («страна» →
## db.tree_country, read through corp_data.cfx).
const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const PERCENT := ["выручка", "издержки", "производительность", "taxes", "profit", "export"]
const MULT := ["банкротство", "takeover", "санкции", "шпионаж_против", "antitrust"]
const POINTS := ["stability", "trust", "popularity", "corruption", "независимость"]

var cfg: Dictionary = {}
var gv: Dictionary = {}          # country -> {есть, прогресс, получено, разбивка: {…}, всего_очков}
var opened: Dictionary = {}      # "country|sector" -> {node id: true}
var dev: Dictionary = {}         # "country|sector" -> {node id: ready day} — tech nodes being developed
var leaders: Dictionary = {}     # "country|sector" -> company id
var news: Array = []
var _caps: Dictionary = {}       # country -> [market value, last 14 weeks]
var _rng := RandomNumberGenerator.new()
var _nodes: Dictionary = {}      # sector -> {id: node} (with «ветка», «технологии»)
var _bonus: Dictionary = {}      # country -> development points from foreign investors this week (investments.gd)
var no: Dictionary = {}          # country -> {есть, прогресс, получено, разбивка, за_неделю} — scientific discoveries (НО)
const RESEARCH := ["ии", "наука", "космос"]


func load_cfg(m: PaxMod) -> void:
	var raw: Variant = GameApi.json(m, "config/trees.json", {})
	cfg = raw if raw is Dictionary else {}
	_nodes.clear()
	for sector in trees().keys():
		var by := {}
		var t: Dictionary = trees()[sector]
		var root: Dictionary = (t.get("root_node", {}) as Dictionary).duplicate()
		root["branch"] = ""
		by[str(root.get("id", "root"))] = root
		for b in t.get("ветки", []):
			for n in (b as Dictionary).get("nodes", []):
				var node: Dictionary = (n as Dictionary).duplicate()
				node["branch"] = str((b as Dictionary)["id"])
				node["технологии"] = bool((b as Dictionary).get("технологии", false))
				if not node.has("requires"):
					node["requires"] = [str(root.get("id", "root"))] if str(node.get("место", "")) == "founding" else []
				by[str(node["id"])] = node
			# The three 3-GV nodes of a branch exclude each other: one choice per branch.
			var outers: Array = []
			for n in (b as Dictionary).get("nodes", []):
				if str((n as Dictionary).get("место", "")) in ["левый", "центр", "правый"]:
					outers.append(str((n as Dictionary)["id"]))
			for id in outers:
				var ex: Array = (by[id] as Dictionary).get("excludes", []).duplicate()
				for other in outers:
					if other != id and not (other in ex):
						ex.append(other)
				(by[id] as Dictionary)["excludes"] = ex
		_nodes[sector] = by


func trees() -> Dictionary:
	return cfg.get("trees", {})


func has_tree(sector: String) -> bool:
	return trees().has(sector)


func node(sector: String, id: String) -> Dictionary:
	return (_nodes.get(sector, {}) as Dictionary).get(id, {})


func start_new() -> void:
	_rng.randomize()


static func key_of(country: String, sector: String) -> String:
	return country + "|" + sector


func is_open(country: String, sector: String, id: String) -> bool:
	return (opened.get(key_of(country, sector), {}) as Dictionary).has(id)


## Closed by a choice: another node it excludes is open or being developed (shown with a padlock).
func locked(country: String, sector: String, id: String) -> bool:
	for ex in node(sector, id).get("excludes", []):
		if is_open(country, sector, str(ex)) or developing(country, sector, str(ex)) >= 0:
			return true
	return false


func developing(country: String, sector: String, id: String) -> int:
	return int((dev.get(key_of(country, sector), {}) as Dictionary).get(id, -1))


## Development points that foreign investors bring (investments.gd): counted into the next week's GV.
func add_bonus(country: String, points: float) -> void:
	_bonus[country] = float(_bonus.get(country, 0.0)) + points


## A company under foreign control (over half its shares held from abroad) is out of its industry's tree.
static func _foreign_control(c: Dictionary) -> bool:
	var home := str(c.get("_country", ""))
	var s := 0.0
	for o in c.get("owners", []):
		var od: Dictionary = o
		var country := str(od.get("country", ""))
		if str(od.get("type", "")) in ["polity", "company"] and not country.is_empty() and country != home:
			s += float(od.get("доля", 0.0))
	return s > 0.5


## The country's companies of the industry, the leader first (not those under foreign control).
func members(db: Data, country: String, sector: String) -> Array:
	var list: Array = db.companies.filter(func(c): return str(c.get("_country", "")) == country and str(c.get("sector", "")) == sector and not _foreign_control(c))
	list.sort_custom(func(a, b): return float(a.get("_index", 0.0)) > float(b.get("_index", 0.0)))
	return list


## The country's GV record (created with the starting GV the first time it is asked for — before the first week
## too, so the window and the purchase agree).
func state_of(country: String) -> Dictionary:
	if not gv.has(country):
		gv[country] = {"has_flag": int((cfg.get("gw", {}) as Dictionary).get("старт", 1)), "прогресс": 0.0, "получено": 0}
	return gv[country]


## The tree's currency: «гв» or «но» (the research industries).
func currency(sector: String) -> String:
	return str((trees().get(sector, {}) as Dictionary).get("currency", "gw"))


## The country's wallet the tree is paid from (GV or НО).
func wallet(country: String, sector: String) -> Dictionary:
	return science_of(country) if currency(sector) == "but_value" else state_of(country)


func science_of(country: String) -> Dictionary:
	if not no.has(country):
		no[country] = {"has_flag": int((cfg.get("but_value", {}) as Dictionary).get("старт", 1)), "прогресс": 0.0, "получено": 0}
	return no[country]


## The next GV or НО costs this many points.
func threshold_for(sector: String, got: int) -> float:
	if currency(sector) == "but_value":
		var c: Dictionary = cfg.get("but_value", {})
		return float(c.get("threshold", 25.0)) * pow(float(c.get("множитель", 1.15)), float(got))
	return threshold(got)


## Can the node be bought now: "" — yes, else the reason key (lang «tree_why_<key>»).
func can_buy(db: Data, country: String, sector: String, id: String) -> String:
	var n := node(sector, id)
	if n.is_empty():
		return "none"
	if members(db, country, sector).is_empty():
		return "no_companies"
	if is_open(country, sector, id) or developing(country, sector, id) >= 0:
		return "opened"
	if locked(country, sector, id):
		return "fork"
	var req: Array = n.get("requires", [])
	if not req.is_empty() and not req.any(func(r): return is_open(country, sector, str(r))):
		return "path"
	if int(wallet(country, sector).get("has_flag", 0)) < int(n.get("price", 1)):
		return "no" if currency(sector) == "but_value" else "gv"
	return ""


## Buys the node: tech nodes start their development by the leader, the rest work at once.
func buy(db: Data, country: String, sector: String, id: String, day: int) -> bool:
	if not can_buy(db, country, sector, id).is_empty():
		return false
	var n := node(sector, id)
	var g := wallet(country, sector)
	g["has_flag"] = int(g["has_flag"]) - int(n.get("price", 1))
	var k := key_of(country, sector)
	if bool(n.get("технологии", false)):
		if not dev.has(k):
			dev[k] = {}
		# Research trees can speed up every development of the country («технологии_срок»).
		(dev[k] as Dictionary)[id] = day + maxi(1, roundi(float(n.get("weeks", 26)) * db.cfx(country, "tech_term"))) * 7
	else:
		_open(k, id)
	_note_bought(db, country, sector, n, day)
	recompute(db)
	return true


func _open(k: String, id: String) -> void:
	if not opened.has(k):
		opened[k] = {}
	(opened[k] as Dictionary)[id] = true


func _note_bought(db: Data, country: String, sector: String, n: Dictionary, day: int) -> void:
	var list := members(db, country, sector)
	if list.is_empty():
		return
	var lead: Dictionary = list[0]
	var entry := {"день": day, "вид": "tree", "что": "узел", "текст": db.text(n.get("name", "")), "технология": bool(n.get("технологии", false))}
	(lead["_chronicle"] as Array).append(entry)
	# A big step (3 and 4 GV) of any country of the world goes to the newspaper — as rumours or an official statement.
	var paper := int(n.get("price", 1)) >= 3 and not bool(n.get("технологии", false)) and currency(sector) == "gw"
	news.append({"c": lead, "entry": entry, "tone": "good", "size": 0.25 + 0.05 * float(n.get("price", 1)), "big": int(lead.get("_world_place", 999)) <= 10,
		"газета": paper, "paper_kind": "узел", "отрасль": sector, "tree_country": country})


# ---------- weekly ----------

func step(db: Data, day: int, player: String, life_events: Array) -> void:
	news.clear()
	_relocated(db, day, life_events)
	_earn(db, life_events)
	_earn_no(db)
	_developments(db, day)
	_leaders(db, day)
	_ai_spend(db, player, day)
	recompute(db)


## A company that moved its headquarters brings its know-how: the new country gets one node of the company's
## industry tree for free — the cheapest one it can open now (ordinary nodes before technologies).
func _relocated(db: Data, day: int, life_events: Array) -> void:
	for ev in life_events:
		var e: Dictionary = ev
		if str(e.get("вид", "")) != "переезд":
			continue
		var c: Dictionary = e.get("c", {})
		var to := str(e.get("country", ""))
		var sector := str(c.get("sector", ""))
		if to.is_empty() or not has_tree(sector):
			continue
		var id := _gift_node(to, sector)
		if id.is_empty():
			continue
		var n := node(sector, id)
		_open(key_of(to, sector), id)
		var entry := {"день": day, "вид": "tree", "что": "переезд", "текст": db.text(n.get("name", "")), "country": to}
		(c["_chronicle"] as Array).append(entry)
		news.append({"c": c, "entry": entry, "tone": "good", "size": 0.4, "big": false})


func _gift_node(country: String, sector: String) -> String:
	var best := ""
	var best_score := INF
	var nodes: Dictionary = _nodes.get(sector, {})
	for id in nodes.keys():
		var n: Dictionary = nodes[id]
		var sid := str(id)
		if is_open(country, sector, sid) or developing(country, sector, sid) >= 0 or locked(country, sector, sid):
			continue
		var req: Array = n.get("requires", [])
		if not req.is_empty() and not req.any(func(r): return is_open(country, sector, str(r))):
			continue
		var score := float(n.get("price", 1)) + (10.0 if bool(n.get("технологии", false)) else 0.0) + _rng.randf() * 0.5
		if score < best_score:
			best_score = score
			best = sid
	return best


## Development points of every country (config «гв»).
func _earn(db: Data, life_events: Array) -> void:
	var c: Dictionary = cfg.get("gw", {})
	var cap := {}
	var top := {}
	var stab := {}
	var n := {}
	for item in db.companies:
		var co: Dictionary = item
		var country := str(co.get("_country", ""))
		cap[country] = float(cap.get(country, 0.0)) + db.cap(co)
		if int(co.get("_world_place", 999)) <= 100:
			top[country] = int(top.get(country, 0)) + 1
		stab[country] = float(stab.get(country, 0.0)) + float(((co.get("_statuses", {}) as Dictionary).get("stability", {}) as Dictionary).get("value", 60.0)) / 100.0
		n[country] = int(n.get(country, 0)) + 1
	var born := {}
	var dead := {}
	for ev in life_events:
		var e: Dictionary = ev
		var country := str((e.get("c", {}) as Dictionary).get("_country", ""))
		if str(e.get("вид", "")) == "birth":
			born[country] = int(born.get(country, 0)) + 1
		elif str(e.get("вид", "")) in ["банкротство", "ликвидация"]:
			dead[country] = int(dead.get(country, 0)) + 1
	for country in cap.keys():
		var hist: Array = _caps.get(country, [])
		hist.append(float(cap[country]))
		while hist.size() > 14:
			hist.pop_front()
		_caps[country] = hist
		var g := 0.0
		if hist.size() >= 2 and float(hist[0]) > 0.0:
			g = pow(float(hist[hist.size() - 1]) / float(hist[0]), 1.0 / float(hist.size() - 1)) - 1.0
		var parts := {"рост": float(c.get("рост", 100.0)) * maxf(0.0, g), "top100": float(c.get("top100", 0.5)) * sqrt(float(top.get(country, 0))),
			"stability": float(c.get("stability", 2.0)) * (float(stab[country]) / float(n[country]) - 0.5),
			"новые": float(c.get("новые", 0.3)) * float(born.get(country, 0)), "bankruptcies": -float(c.get("bankruptcies", 1.0)) * float(dead.get(country, 0))}
		if _bonus.has(country):
			parts["investors"] = float(_bonus[country]) / maxf(float(db.dt), 1.0)   # × dt below
		var o := 0.0
		for v in parts.values():
			o += float(v)
		o *= float(db.dt) * (db.cfx(str(country), "gw_multiplier") if o > 0.0 else 1.0)
		var st := state_of(str(country))
		st["breakdown"] = parts
		st["per_week"] = o / float(db.dt)
		st["прогресс"] = maxf(0.0, float(st["прогресс"]) + o)
		while float(st["прогресс"]) >= threshold(int(st["получено"])):
			st["прогресс"] = float(st["прогресс"]) - threshold(int(st["получено"]))
			st["получено"] = int(st["получено"]) + 1
			st["has_flag"] = int(st["has_flag"]) + 1
		gv[country] = st
	_bonus.clear()


## Scientific discoveries of every country (config «но»): from the revenue of its AI, science and space companies and
## how many of them are in the world top-300; × the research trees' «но_множитель». Slower than GV on purpose.
func _earn_no(db: Data) -> void:
	var c: Dictionary = cfg.get("but_value", {})
	var rev := {}
	var top := {}
	for item in db.companies:
		var co: Dictionary = item
		if not (str(co.get("sector", "")) in RESEARCH):
			continue
		var country := str(co.get("_country", ""))
		rev[country] = float(rev.get(country, 0.0)) + maxf(0.0, db.fund(co, "выручка"))
		if int(co.get("_world_place", 999)) <= 300:
			top[country] = int(top.get(country, 0)) + 1
	for country in rev.keys():
		var parts := {"выручка": float(c.get("per_revenue", 0.12)) * sqrt(float(rev[country]) / 1000.0),
			"топ": float(c.get("per_top", 0.2)) * float(top.get(country, 0))}
		var o := (float(parts["выручка"]) + float(parts["топ"])) * db.cfx(str(country), "but_multiplier") * float(db.dt)
		var st := science_of(str(country))
		st["breakdown"] = parts
		st["per_week"] = o / float(db.dt)
		st["прогресс"] = float(st["прогресс"]) + o
		var need := float(c.get("threshold", 25.0)) * pow(float(c.get("множитель", 1.15)), float(st["получено"]))
		while float(st["прогресс"]) >= need:
			st["прогресс"] = float(st["прогресс"]) - need
			st["получено"] = int(st["получено"]) + 1
			st["has_flag"] = int(st["has_flag"]) + 1
			need = float(c.get("threshold", 25.0)) * pow(float(c.get("множитель", 1.15)), float(st["получено"]))
		no[country] = st


func threshold(got: int) -> float:
	var c: Dictionary = cfg.get("gw", {})
	return float(c.get("threshold", 10.0)) * pow(float(c.get("множитель", 1.1)), float(got))


## Tech nodes whose development is done open; their country gets the technology.
func _developments(db: Data, day: int) -> void:
	for k in dev.keys():
		var d: Dictionary = dev[k]
		for id in d.keys():
			if int(d[id]) <= day:
				d.erase(id)
				_open(str(k), str(id))
				var parts := str(k).split("|")
				var n := node(parts[1], str(id))
				var list := members(db, parts[0], parts[1])
				if not list.is_empty():
					var entry := {"день": day, "вид": "tree", "что": "технология", "текст": db.text(n.get("name", ""))}
					((list[0] as Dictionary)["_chronicle"] as Array).append(entry)
					# Every research for НО and every technology node of 3–4 GV finished anywhere in the world is news.
					var paper := currency(parts[1]) == "but_value" or int(n.get("price", 1)) >= 3
					news.append({"c": list[0], "entry": entry, "tone": "good", "size": 0.6, "big": true,
						"газета": paper, "paper_kind": "исследование" if currency(parts[1]) == "but_value" else "технология", "отрасль": parts[1], "tree_country": parts[0]})


## The leaders: overtaken — the leadership passes; lost (gone, moved, foreign control) — one tech node rolls back.
func _leaders(db: Data, day: int) -> void:
	var seen := {}
	for item in db.companies:
		var c: Dictionary = item
		var sector := str(c.get("sector", ""))
		if has_tree(sector):
			seen[key_of(str(c.get("_country", "")), sector)] = true
	for k in leaders.keys() + seen.keys():
		var parts := str(k).split("|")
		var list := members(db, parts[0], parts[1])
		var was := str(leaders.get(k, ""))
		var now := str((list[0] as Dictionary)["id"]) if not list.is_empty() else ""
		if was == now:
			continue
		if not was.is_empty() and _lost(db, was, parts[0]):
			_rollback(db, parts[0], parts[1], was, day)
		if now.is_empty():
			leaders.erase(k)
		else:
			leaders[k] = now


func _lost(db: Data, cid: String, country: String) -> bool:
	var c := db.company(cid)
	if c.is_empty() or str(c.get("_country", "")) != country:
		return true
	var foreign := 0.0
	for o in c.get("owners", []):
		var od: Dictionary = o
		if od.has("country") and str(od["country"]) != country and str(od.get("type", "")) != "частные":
			foreign += float(od.get("доля", 0.0))
	return foreign > 0.5


func _rollback(db: Data, country: String, sector: String, lost_id: String, day: int) -> void:
	var k := key_of(country, sector)
	# A research tree may protect the country's knowledge («откат»: 0.5 — half as often, 0 — never).
	if _rng.randf() >= db.cfx(country, "kickback"):
		return
	var have: Array = []
	for id in (opened.get(k, {}) as Dictionary).keys():
		if bool(node(sector, str(id)).get("технологии", false)):
			have.append(str(id))
	# Developments in progress stop too.
	if dev.has(k):
		dev.erase(k)
	if have.is_empty():
		return
	var leaves: Array = []
	for id in have:
		if not _holds_up(sector, str(id), have):
			leaves.append(id)
	var top := 0
	for id in leaves:
		top = maxi(top, int(node(sector, str(id)).get("price", 1)))
	var pick: Array = leaves.filter(func(id): return int(node(sector, str(id)).get("price", 1)) == top)
	if pick.is_empty():
		return
	var lost := str(pick[_rng.randi_range(0, pick.size() - 1)])
	(opened[k] as Dictionary).erase(lost)
	var text := db.text(node(sector, lost).get("name", ""))
	var list := members(db, country, sector)
	if not list.is_empty():
		var entry := {"день": day, "вид": "tree", "что": "kickback", "текст": text, "rival": lost_id}
		((list[0] as Dictionary)["_chronicle"] as Array).append(entry)
		news.append({"c": list[0], "entry": entry, "tone": "bad", "size": 0.7, "big": true})


## Does some other opened node stand only on this one (so taking it away would break the path)?
func _holds_up(sector: String, id: String, have: Array) -> bool:
	for o in have:
		if str(o) == id:
			continue
		var req: Array = node(sector, str(o)).get("requires", [])
		if not (id in req):
			continue
		var other := false
		for r in req:
			if str(r) != id and str(r) in have:
				other = true
		if not other:
			return true
	return false


## AI countries spend their GV at once: the cheapest open node, a random branch (the technologies a bit more often).
func _ai_spend(db: Data, player: String, day: int) -> void:
	var countries := gv.duplicate()
	countries.merge(no)   # every country with GV or НО, once
	for country in countries.keys():
		if str(country) == player:
			continue
		for sector in trees().keys():
			if int(wallet(str(country), str(sector)).get("has_flag", 0)) <= 0 or members(db, str(country), str(sector)).is_empty():
				continue
			var options: Array = []
			for id in (_nodes[sector] as Dictionary).keys():
				if can_buy(db, str(country), str(sector), str(id)).is_empty():
					options.append(str(id))
			if options.is_empty():
				continue
			options.sort_custom(func(a, b): return int(node(sector, a).get("price", 1)) < int(node(sector, b).get("price", 1)))
			var cheapest := int(node(sector, options[0]).get("price", 1))
			var pool: Array = options.filter(func(id): return int(node(sector, id).get("price", 1)) == cheapest)
			var tech: Array = pool.filter(func(id): return bool(node(sector, id).get("технологии", false)))
			var use: Array = tech if not tech.is_empty() and _rng.randf() < 0.4 else pool
			var id := str(use[_rng.randi_range(0, use.size() - 1)])
			buy(db, str(country), str(sector), id, day)
			break


# ---------- effects ----------

## db.tree_fx[country|sector] = combined effects; db.tree_country[country] = country-wide effects of techs.
func recompute(db: Data) -> void:
	var fx := {}
	var country_fx := {}
	for k in opened.keys():
		var parts := str(k).split("|")
		var sector := parts[1]
		var sum := {}
		var scale := 1.0
		var ids: Dictionary = opened[k]
		for id in ids.keys():
			var n := node(sector, str(id))
			var eff: Dictionary = n.get("effects", {})
			if n.has("on_the_way"):
				for via in (n["on_the_way"] as Dictionary).keys():
					if ids.has(str(via)):
						eff = ((n["on_the_way"] as Dictionary)[via] as Dictionary).get("effects", {})
			for e in eff.keys():
				var v := float(eff[e])
				if str(e) == "все":
					scale *= v
				elif str(e) in MULT:
					sum[e] = float(sum.get(e, 1.0)) * v
				else:
					sum[e] = float(sum.get(e, 0.0)) + v
			# A research tree's mechanics are as strong as the country's best company of the industry is advanced:
			# × (0.5 + 0.5·T/F) of the change (techlevel.gd; 1 before the first week).
			var strength := 0.5 + 0.5 * float(db.tech_ratio.get(parts[0] + "|" + sector, 1.0)) if sector in RESEARCH else 1.0
			for e in (n.get("country", {}) as Dictionary).keys():
				var cf: Dictionary = country_fx.get(parts[0], {})
				var mv := 1.0 + (float((n["country"] as Dictionary)[e]) - 1.0) * strength
				cf[e] = float(cf.get(e, 1.0)) * mv
				country_fx[parts[0]] = cf
		if scale != 1.0:
			for e in sum.keys():
				if str(e) in MULT:
					if float(sum[e]) < 1.0:
						sum[e] = 1.0 - (1.0 - float(sum[e])) * scale
				else:
					sum[e] = float(sum[e]) * scale
		fx[k] = sum
	db.tree_fx = fx
	db.tree_country = country_fx


# ---------- save ----------

func save_state() -> Dictionary:
	return {"gw": gv, "but_value": no, "nodes": opened, "development": dev, "лидеры": leaders, "caps": _caps, "зерно": str(_rng.seed), "состояние": str(_rng.state)}


func load_state(state: Dictionary) -> void:
	gv = (state.get("gw", {}) as Dictionary).duplicate(true) if state.get("gw") is Dictionary else {}
	no = (state.get("but_value", {}) as Dictionary).duplicate(true) if state.get("but_value") is Dictionary else {}
	opened = (state.get("nodes", {}) as Dictionary).duplicate(true) if state.get("nodes") is Dictionary else {}
	dev = (state.get("development", {}) as Dictionary).duplicate(true) if state.get("development") is Dictionary else {}
	leaders = (state.get("лидеры", {}) as Dictionary).duplicate() if state.get("лидеры") is Dictionary else {}
	_caps = (state.get("caps", {}) as Dictionary).duplicate(true) if state.get("caps") is Dictionary else {}
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
