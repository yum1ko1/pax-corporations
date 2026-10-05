extends RefCounted
## Technologies of the new time (ideas doc, section 7; config/capabilities.json): far-future technologies no country
## has at the start (exoskeletons, combat lasers, fusion, a Mars base…). Hard locks for every country: one is there only
## while the country has companies of the needed industries AND the needed nodes of those industries' trees are open
## (two nodes of two different trees). The way is always open: found a company by order and develop it.
##
## Buying ready-made: «купить технологию лазерного оружия у США» — a friendly country (relation ≥ «продают_от») that
## has the capability of its own sells it; the state hands it to its leading company of the industry, which learns it
## for «освоение_недель» and then works with a temporary debuff (productivity − «дебафф», fading over «дебафф_недель»).
## Own research is always better: a bought capability brings no tree bonuses and is lost when relations fall below
## «теряют_ниже» or sanctions hit the seller.
##
## Orders and research — the game counts, the AI explains: the mod adds a short registry of the country's capabilities
## to the order interpreter's request (main.gd «ai_request»); an order to develop or build something of a closed
## capability is cancelled with a ministry's report and the way to it; a research project of a closed capability
## gets no chance («research_priced»). The decision is always the mod's, by the registry.
const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const W_MAKE := ["разработ", "создат", "создай", "создадим", "построит", "построй", "произв", "наладит", "наладь", "запустит", "запусти",
	"развернут", "разверни", "исследова", "изобрест", "спроектир", "начать производ", "внедрит", "внедри", "освоит",
	"develop", "build", "produce", "launch", "deploy", "research", "create", "design", "manufactur"]
const W_BUY := ["купить технолог", "купить лиценз", "закупить технолог", "приобрести технолог", "купить готов", "закупить у", "купить у",
	"buy technology", "buy the technology", "license from", "purchase technology", "buy from"]

var cfg: Dictionary = {}
var bought: Dictionary = {}      # country -> {cap id: {от, день, готово, получатель}}
var had: Dictionary = {}         # country -> {cap id: true} — what it had last week (news on openings)
var news: Array = []
var db: Data
var game: PaxGame
var mod: PaxMod
var tree: Object                 # tree.gd
var arena: Object                # arena.gd (find_country, tariffs)
var say: Callable                # func(text) — a notification + a letter (main.gd)


func setup(m: PaxMod, d: Data, g: PaxGame, t: Object, a: Object, say_cb: Callable) -> void:
	mod = m
	db = d
	game = g
	tree = t
	arena = a
	say = say_cb
	var raw: Variant = GameApi.json(m, "config/capabilities.json", {})
	cfg = raw if raw is Dictionary else {}


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


func all() -> Array:
	return cfg.get("capabilities_list", [])


func cap(id: String) -> Dictionary:
	for c in all():
		if str((c as Dictionary).get("id", "")) == id:
			return c
	return {}


func name_of(id: String) -> String:
	return db.text(cap(id).get("name", id))


func _player() -> String:
	return str(game.player_faction().get("name", ""))


# ---------- the registry ----------

var _present: Dictionary = {}    # "country|sector" -> true: the country has a company of the industry (refreshed weekly)
var _present_day := -1


## Has the country a company of the industry (not under foreign control, as tree.gd members)? Cached per day.
func _members(country: String, sector: String) -> bool:
	if _present_day != game.day():
		_present.clear()
		for item in db.companies:
			var c: Dictionary = item
			if not bool(tree.call("_foreign_control", c)):
				_present[str(c.get("_country", "")) + "|" + str(c.get("sector", ""))] = true
		_present_day = game.day()
	return _present.has(country + "|" + sector)


## The country's own capability: "own_f" (its trees) or "".
func own(country: String, id: String) -> String:
	var c := cap(id)
	if c.is_empty():
		return ""
	var groups: Array = c.get("нужно", [])
	var all_ok := not groups.is_empty()
	for g in groups:
		var ok := false
		for opt in g:
			var o: Array = opt
			if bool(tree.call("is_open", country, str(o[0]), str(o[1]))) and _members(country, str(o[0])):
				ok = true
				break
		if not ok:
			all_ok = false
			break
	# A technology that needs AI also needs the country's AI at the world frontier (techlevel.gd).
	if all_ok and _needs_ai(c) and float(db.tech_ratio.get(country + "|ии", 1.0)) < 0.8:
		return ""
	return "own_f" if all_ok else ""


func _needs_ai(c: Dictionary) -> bool:
	for g in c.get("нужно", []):
		for opt in g:
			if str((opt as Array)[0]) == "ии":
				return true
	return false


## Everything about one capability for one country: {есть, как, недель (learning), не_хватает: [[text, ok]…], продавцы}.
func status(country: String, id: String) -> Dictionary:
	var how := own(country, id)
	var out := {"has_flag": not how.is_empty(), "как": how, "weeks": 0}
	if how.is_empty():
		var b: Dictionary = (bought.get(country, {}) as Dictionary).get(id, {})
		if not b.is_empty():
			var left := int(b.get("готово", 0)) - game.day()
			out["как"] = "куплена" if left <= 0 else "осваивается"
			out["has_flag"] = left <= 0
			out["weeks"] = maxi(0, ceili(float(left) / 7.0))
			out["from_value"] = str(b.get("from_value", ""))
	var need: Array = []
	for g in cap(id).get("нужно", []):
		var opts: PackedStringArray = []
		var ok := false
		for opt in g:
			var o: Array = opt
			var open := bool(tree.call("is_open", country, str(o[0]), str(o[1])))
			var has := _members(country, str(o[0]))
			ok = ok or (open and has)
			var nd: Dictionary = tree.call("node", str(o[0]), str(o[1]))
			opts.append("%s: «%s»%s" % [db.sector_name(str(o[0])), db.text(nd.get("name", str(o[1]))), "" if has else " (" + _t("cap_no_company") + ")"])
		need.append([_t("cap_or").join(opts), ok])
	if _needs_ai(cap(id)):
		need.append([_t("cap_ai_frontier"), float(db.tech_ratio.get(country + "|ии", 1.0)) >= 0.8])
	out["what_missing"] = need
	out["sellers"] = sellers(id) if not bool(out["has_flag"]) and str(out["как"]) != "осваивается" else []
	return out


## Countries that would sell the capability to the player: their own, friendly, not under the player's sanctions.
func sellers(id: String) -> Array:
	if float(cap(id).get("price", 0.0)) <= 0.0:
		return []
	var out: Array = []
	var me := _player()
	for f in game.factions():
		var fd: Dictionary = f
		var country := str(fd.get("name", ""))
		if country == me or not db.countries.has(country):
			continue
		if float(fd.get("relations", 0.0)) >= float(cfg.get("sell_from", 0.5)) and not _sanctioned(country) and own(country, id) != "":
			out.append(country)
	return out


func _sanctioned(country: String) -> bool:
	if arena == null:
		return false
	for t in arena.get("tariffs"):
		var td: Dictionary = t
		if str(td.get("from_value", "")) == _player() and str(td.get("on_value", "")) == country and str(td.get("вид", "")) == "санкции":
			return true
	return false


func _relation(country: String) -> float:
	for f in game.factions():
		if str((f as Dictionary).get("name", "")) == country:
			return float((f as Dictionary).get("relations", 0.4))
	return 0.4


func has(country: String, id: String) -> bool:
	return bool(status(country, id)["has_flag"])


## A short registry for the AI: what is open, what is closed and what it lacks (only the closed ones' needs).
func registry_text(country: String) -> String:
	var open: PackedStringArray = []
	var closed: PackedStringArray = []
	for c in all():
		var id := str((c as Dictionary)["id"])
		var st := status(country, id)
		if bool(st["has_flag"]):
			open.append(id)
		else:
			var lack: PackedStringArray = []
			for n in st["what_missing"]:
				if not bool((n as Array)[1]):
					lack.append(str((n as Array)[0]))
			closed.append("%s (needs: %s)" % [id, "; ".join(lack)])
	return "Country capabilities (the mod decides by this registry). Open: %s. Closed: %s. If the order is about one of these " \
		% [", ".join(open) if not open.is_empty() else "none", ", ".join(closed)] \
		+ "capabilities, add \"возможность\": \"<id>\" to the JSON request; otherwise \"возможность\": \"нет\"."


# ---------- weekly ----------

func step(day: int) -> void:
	news.clear()
	var me := _player()
	var fx := {}
	# Bought capabilities: learning done, debuffs, lost to relations or sanctions.
	for country in bought.keys():
		var list: Dictionary = bought[country]
		for id in list.keys():
			var b: Dictionary = list[id]
			var seller := str(b.get("from_value", ""))
			if own(str(country), str(id)) != "":
				list.erase(id)   # the country made it its own — the purchase is no longer needed
				continue
			if _relation(seller) < float(cfg.get("lose_below", 0.3)) or (str(country) == me and _sanctioned(seller)):
				list.erase(id)
				_note_company(str(b.get("recipient", "")), day, "потеряна", str(id), "bad")
				if str(country) == me and say.is_valid():
					say.call(_t("cap_lost") % [name_of(str(id)), seller])
				continue
			var ready := int(b.get("готово", 0))
			if ready <= day and not bool(b.get("освоено", false)):
				b["освоено"] = true
				_note_company(str(b.get("recipient", "")), day, "освоена", str(id), "good")
				if str(country) == me and say.is_valid():
					say.call(_t("cap_learned") % name_of(str(id)))
			# The temporary debuff of the company that learns a bought technology.
			var weeks := float(cfg.get("debuff_weeks", 52))
			var since := float(day - int(b.get("день", day))) / 7.0
			if since < weeks + float(cfg.get("mastering_weeks", 26)):
				var k := 1.0 - clampf(since / (weeks + float(cfg.get("mastering_weeks", 26))), 0.0, 1.0)
				var cid := str(b.get("recipient", ""))
				var f: Dictionary = fx.get(cid, {})
				f["производительность"] = float(f.get("производительность", 0.0)) - float(cfg.get("debuff", 0.08)) * k
				fx[cid] = f
	db.cap_fx = fx
	# Openings: news when a country gets a capability of its own (the player's and the world's big ones).
	for k in db.countries.keys():
		var country := str(k)
		if not _any_open(country) and not had.has(country):
			had[country] = {}
			continue
		var now := {}
		for c in all():
			var id := str((c as Dictionary)["id"])
			if own(country, id) == "own_f":
				now[id] = true
		var before: Dictionary = had.get(country, {})
		if had.has(country):
			for id in now.keys():
				if not before.has(id):
					var lead: Array = _leaders_of(country, str(id))
					if not lead.is_empty():
						var entry := {"день": day, "вид": "возможность", "что": "открыта", "текст": name_of(str(id))}
						((lead[0] as Dictionary)["_chronicle"] as Array).append(entry)
						news.append({"c": lead[0], "entry": entry, "tone": "good", "size": 0.9, "big": true,
							"газета": true, "paper_kind": "будущее", "отрасль": "", "tree_country": country})
					if country == me and say.is_valid():
						say.call(_t("cap_opened") % name_of(str(id)))
		had[country] = now


## Has the country opened any node of any tree (no — it cannot have a capability of its own).
func _any_open(country: String) -> bool:
	for k in (tree.get("opened") as Dictionary).keys():
		if str(k).begins_with(country + "|") and not ((tree.get("opened") as Dictionary)[k] as Dictionary).is_empty():
			return true
	return false


## The leading companies behind a capability (the first group's industry with companies).
func _leaders_of(country: String, id: String) -> Array:
	for g in cap(id).get("нужно", []):
		for opt in g:
			var list: Array = tree.call("members", db, country, str((opt as Array)[0]))
			if not list.is_empty():
				return list
	return []


func _note_company(cid: String, day: int, what: String, id: String, tone: String) -> void:
	var c := db.company(cid)
	if c.is_empty():
		return
	var entry := {"день": day, "вид": "возможность", "что": what, "текст": name_of(id)}
	(c["_chronicle"] as Array).append(entry)
	news.append({"c": c, "entry": entry, "tone": tone, "size": 0.4})


# ---------- orders and research ----------

static func _has(text: String, words: Array) -> bool:
	for w in words:
		if text.contains(str(w)):
			return true
	return false


## The capability a text is about ("" — none), by the AI's tag in the request or by the words.
func find(text: String, request: Variant = null) -> String:
	if request is Dictionary:
		var tag := str((request as Dictionary).get("возможность", ""))
		if not cap(tag).is_empty():
			return tag
	var low := " " + text.to_lower() + " "
	for c in all():
		if _has(low, (c as Dictionary).get("слова", [])):
			return str((c as Dictionary)["id"])
	return ""


## «order_parsed»: buying a capability, or an order to develop a closed one (cancelled with a report). True — taken.
func handle(d: Dictionary) -> bool:
	var text := " " + str(d.get("order", "")).to_lower() + " "
	var id := find(text, d.get("request"))
	if id.is_empty():
		return false
	var me := _player()
	if _has(text, W_BUY) and arena != null:
		var seller := str(arena.call("find_country", text))
		if not seller.is_empty() and seller != me:
			_buy(id, seller)
			d["cancel"] = true   # the deal is the mod's; the game's own order would only duplicate it
			return true
	if not _has(text, W_MAKE):
		return false
	var st := status(me, id)
	if bool(st["has_flag"]):
		return false   # open — the game carries the order out
	d["cancel"] = true
	_report_closed(id, st)
	return true


## A ministry's report: why not, and the way — which node of which industry, or who sells it.
func _report_closed(id: String, st: Dictionary) -> void:
	if not say.is_valid():
		return
	if str(st["как"]) == "осваивается":
		say.call(_t("cap_learning") % [name_of(id), int(st["weeks"])])
		return
	var lack: PackedStringArray = []
	for n in st["what_missing"]:
		if not bool((n as Array)[1]):
			lack.append(str((n as Array)[0]))
	var who := _t("cap_office_" + str(cap(id).get("agency", "наука")))
	var line := _t("cap_refused") % [who, name_of(id), "; ".join(lack)]
	var sell: Array = st["sellers"]
	if not sell.is_empty():
		line += " " + _t("cap_can_buy") % [", ".join(PackedStringArray(sell)), sell[0]]
	say.call(line)


func _buy(id: String, seller: String) -> void:
	var me := _player()
	var c := cap(id)
	var price := float(c.get("price", 0.0))
	if has(me, id):
		say.call(_t("cap_buy_have") % name_of(id))
		return
	if price <= 0.0:
		say.call(_t("cap_buy_never") % name_of(id))
		return
	if own(seller, id) == "":
		say.call(_t("cap_buy_seller_none") % [seller, name_of(id)])
		return
	if _relation(seller) < float(cfg.get("sell_from", 0.5)) or _sanctioned(seller):
		say.call(_t("cap_buy_refused") % [seller, name_of(id)])
		return
	var to: Array = _leaders_of(me, id)
	if to.is_empty():
		var sec := str(((c.get("нужно", [[["", ""]]]) as Array)[0] as Array)[0][0])
		say.call(_t("cap_buy_nobody") % [name_of(id), db.sector_name(sec)])
		return
	var home := game.home_body()
	if float(game.resources(home).get("money", 0.0)) < price:
		say.call(_t("cap_buy_money") % db.money(price))
		return
	game.add_resource(home, "money", -price)
	var day := game.day()
	var receiver: Dictionary = to[0]
	if not bought.has(me):
		bought[me] = {}
	(bought[me] as Dictionary)[id] = {"from_value": seller, "день": day, "готово": day + int(cfg.get("mastering_weeks", 26)) * 7,
		"recipient": str(receiver["id"])}
	_note_company(str(receiver["id"]), day, "куплена", id, "neutral")
	say.call(_t("cap_bought") % [name_of(id), seller, db.money(price), db.name_of(receiver), int(cfg.get("mastering_weeks", 26))])


## «research_priced»: a research project of a closed capability gets no chance; one still being learnt takes longer.
func research(d: Dictionary) -> void:
	var r: Variant = d.get("research")
	var answer: Variant = d.get("answer")
	if not (answer is Dictionary):
		return
	var text := JSON.stringify(r) if r != null else ""
	var id := find(text, answer)
	if id.is_empty():
		return
	var st := status(_player(), id)
	if bool(st["has_flag"]):
		return
	var a: Dictionary = answer
	for k in a.keys():
		var key := str(k).to_lower()
		if (a[k] is float or a[k] is int):
			if str(st["как"]) == "осваивается":
				if key.contains("лет") or key.contains("год") or key.contains("year") or key.contains("срок") or key.contains("дн"):
					a[k] = float(a[k]) * 1.5
			elif key.contains("шанс") or key.contains("вероят") or key.contains("chance") or key.contains("prob"):
				a[k] = 0.0
	if str(st["как"]) != "осваивается":
		_report_closed(id, st)


# ---------- save ----------

func save_state() -> Dictionary:
	return {"bought": bought, "было": had}


func load_state(state: Dictionary) -> void:
	bought = (state.get("bought", {}) as Dictionary).duplicate(true) if state.get("bought") is Dictionary else {}
	had = (state.get("было", {}) as Dictionary).duplicate(true) if state.get("было") is Dictionary else {}
