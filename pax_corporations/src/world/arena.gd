extends RefCounted
## Stage 4: the world arena (design doc 14, 20.16; config balance.json «арена»). Companies move their countries'
## standing in the world and tie countries together with dependencies, from which conflicts grow.
##
## Prestige (20.16): Пр = Σ over the country's companies in the world top-100 of (101 − place) / 50
##   + 2 × its companies whose value grew by more than half in a year − the flight of companies (relocations away,
##   seizures of foreign assets — investors' fear; fades). Scaled 0–100 against the best country. Every 10 points
##   of the player's prestige gained or lost move the powers' relation to the player by 1 point, and each
##   country's loan rate by 0.2 % (debt.gd through db.rate_shift); prestige also draws relocating companies
##   (lifecycle.gd attractiveness).
##
## Dependencies: country X gets from foreign company Y the share of its market of Y's goods that Y's exports
##   cover: export_Y × X's weight / the world's weight outside Y's home, against X's market (population ×
##   wealth × consumption). Shown both ways for the player in the «Арена» tab.
##
## Conflicts:
##   • the player's sanctions against a company (orders: «санкции против X»): it loses the player's market;
##     the countries that depend on it (≥ «зависимость_от») are angry with the player, its country answers;
##     sanctions against a whole country stop all its exports to the player;
##   • tariffs and trade wars (orders: «пошлины 30% на сталь из Китая», «торговая война с X»): the taxed
##     companies lose that part of the player's market, the player's rivals of the same goods gain, the
##     treasury collects the duty; the other country answers — the game's AI chooses: a note, mirror tariffs,
##     sanctions against the player's companies, expelling diplomats or nothing. A long corporate war between a
##     company of the player and a foreign one in a country cold to the player turns into its tariffs;
##   • industrial espionage (orders: «украсть технологии у X»): a few weeks; success lifts the player's company
##     of the same goods and hurts the target; caught spies — a scandal and an answer. Hostile countries spy on
##     the player's companies too;
##   • a nationalised or seized foreign company — a diplomatic crisis with its country (orders.gd → crisis()).

const Zones := preload("res://mods/pax_corporations/src/zones/zones.gd")
const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")
const Rivals := preload("res://mods/pax_corporations/src/companies/rivals.gd")
const Antitrust := preload("res://mods/pax_corporations/src/state/antitrust.gd")

const W_SANCTION := ["санкци", "эмбарго", "запретить импорт", "sanction", "embargo", "ban imports"]
const W_TARIFF := ["пошлин", "тариф", "торговая война", "торговую войну", "торговой войн", "tariff", "duty", "duties", "trade war"]
const W_SPY := ["шпионаж", "украсть технолог", "выкрасть", "похитить технолог", "промышленн развед", "espionage", "steal technolog", "spy on"]
const W_LIFT := ["отменить", "снять", "убрать", "прекратить", "lift", "remove", "cancel", "end the"]
const ANSWERS := ["note", "retaliatory_tariffs", "company_sanctions", "diplomat_expulsion", "ничего"]

var prestige: Dictionary = {}    # country -> 0..100 now
var prestige0: Dictionary = {}   # at the start (the effects count from it)
var _applied := -1.0             # the player's prestige whose relation effect is already applied
var tariffs: Array = []          # {от: who imposes, на: on whom, товар: "" | goods key, ставка, вид: пошлины|санкции, с_дня}
var sanctions: Array = []        # the player's sanctions on single companies: {id, с_дня}
var ops: Array = []              # espionage: {вид, id, свой, до_дня}
var flight: Dictionary = {}      # country -> prestige points lost to fleeing companies and investors' fear (fades)
var conflicts: Array = []        # the latest: {день, ключ, args}
var deps_in: Array = []          # the player's country depends on: [{id, доля}]
var deps_out: Array = []         # countries that depend on the player's companies: [{страна, id, доля}]
var news: Array = []
var revenue_weeks: Array = []    # duties collected by the player, week by week
var _rng := RandomNumberGenerator.new()
var db: Data
var game: PaxGame
var goods: Goods
var rivals: Rivals
var mod: PaxMod
var say: Callable                # func(text) — a notification + a letter (main.gd)
var _player := ""


func setup(m: PaxMod, d: Data, g: PaxGame, gd: Goods, r: Rivals, say_cb: Callable) -> void:
	mod = m
	db = d
	game = g
	goods = gd
	rivals = r
	say = say_cb


func start_new() -> void:
	_rng.randomize()


func _cfg() -> Dictionary:
	return db.balance.get("arena", {})


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


func _say(key: String, args: Array) -> void:
	var line := _t(key)
	var n := line.count("%s")
	if n > 0:
		var a := args.slice(0, n)
		while a.size() < n:
			a.append("")
		line = line % a
	if say.is_valid():
		say.call(line)


func _log(key: String, args: Array, day: int) -> void:
	conflicts.append({"день": day, "ключ": key, "args": args.map(func(x): return str(x))})
	while conflicts.size() > 30:
		conflicts.pop_front()


# ---------- weekly ----------

func step(day: int, life_events: Array) -> void:
	news.clear()
	_player = str(game.player_faction().get("name", ""))
	_prestige(day, life_events)
	_dependencies()
	_tariff_effects()
	_ai_trade_wars(day)
	_spies(day)


func _prestige(_day: int, life_events: Array) -> void:
	var cfg := _cfg()
	for ev in life_events:
		if str((ev as Dictionary).get("вид", "")) == "переезд":
			var from := str((ev as Dictionary).get("откуда", ""))
			flight[from] = float(flight.get(from, 0.0)) + float(cfg.get("flight_per_move", 3.0))
	var raw := {}
	for item in db.companies:
		var c: Dictionary = item
		var country := str(c.get("_country", ""))
		var place := int(c.get("_world_place", 999))
		var v := float(raw.get(country, 0.0))
		if place <= 100:
			v += float(101 - place) / 50.0
		if db.change(c, 52) > 0.5:
			v += 2.0
		raw[country] = v
	var top := 0.0
	for country in raw.keys():
		raw[country] = (maxf(0.0, float(raw[country]) - float(flight.get(country, 0.0))) + float(db.tech_prestige.get(str(country), 0.0))) * db.cfx(str(country), "prestige")
		top = maxf(top, float(raw[country]))
	for country in raw.keys():
		prestige[country] = 100.0 * float(raw[country]) / top if top > 0.0 else 0.0
	if prestige0.is_empty():
		prestige0 = prestige.duplicate()
	for k in flight.keys():
		flight[k] = float(flight[k]) * pow(1.0 - float(cfg.get("flight_decay", 0.02)), db.dt)
	# Loans: −0.2 % for every 10 points gained since the start (and the other way).
	var rates := {}
	for country in prestige.keys():
		rates[country] = -float(cfg.get("rate_per_10", 0.002)) * (float(prestige[country]) - float(prestige0.get(country, prestige[country]))) / 10.0
	db.rate_shift = rates
	db.prestige = prestige
	# The powers: 1 point of relation for every 10 points of the player's prestige.
	var mine := float(prestige.get(_player, 0.0))
	if _applied < 0.0:
		_applied = mine
	var delta := (mine - _applied) / 10.0 * float(cfg.get("relation_per_10", 0.01))
	if absf(delta) >= 0.0005:
		for f in game.factions():
			var fd: Dictionary = f
			if fd.has("relations"):
				fd["relations"] = clampf(float(fd["relations"]) + delta, 0.0, 1.0)
		_applied = mine


## The player's place in the prestige table (1 — the first).
func place_of(country: String) -> int:
	var mine := float(prestige.get(country, 0.0))
	var n := 1
	for k in prestige.keys():
		if float(prestige[k]) > mine:
			n += 1
	return n


# ---------- dependencies ----------

## The share of country X's market of company Y's goods that Y's exports cover (0..1).
func dep(country: String, c: Dictionary) -> float:
	var home := str(c.get("_country", ""))
	if country == home:
		return 0.0
	var w_x := float(goods.now_people.get(country, 0.0))
	var outside := goods.now_world - float(goods.now_people.get(home, 0.0))
	if w_x <= 0.0 or outside <= 0.0:
		return 0.0
	var e := db.econ(c)
	var into := goods.export_share(db, c) * float(e.get("R", 0.0)) * w_x / outside
	var per := float(((db.goods.get("goods", {}) as Dictionary).get(goods.goods_of(c), {}) as Dictionary).get("consumption", 300.0))
	var market := w_x * per / 1e6 * float(e.get("цены", 1.0))
	return clampf(into / market, 0.0, 1.0) if market > 0.0 else 0.0


func _dependencies() -> void:
	deps_in.clear()
	deps_out.clear()
	var from := float(_cfg().get("show_from", 0.02))
	for item in db.companies:
		var c: Dictionary = item
		if db.econ(c).is_empty():
			continue
		if str(c.get("_country", "")) != _player:
			var d := dep(_player, c)
			if d >= from:
				deps_in.append({"id": str(c["id"]), "доля": d})
		else:
			for country in goods.now_people.keys():
				if str(country) == _player:
					continue
				var d := dep(str(country), c)
				if d >= from * 2.5:
					deps_out.append({"country": str(country), "id": str(c["id"]), "доля": d})
	deps_in.sort_custom(func(a, b): return float(a["доля"]) > float(b["доля"]))
	deps_out.sort_custom(func(a, b): return float(a["доля"]) > float(b["доля"]))
	deps_in = deps_in.slice(0, 15)
	deps_out = deps_out.slice(0, 15)


# ---------- tariffs and sanctions ----------

## Every week: who loses or gains demand from the tariffs and sanctions in force; the player's duties.
func _tariff_effects() -> void:
	var cfg := _cfg()
	var el := float(cfg.get("elasticity", 1.5))
	var protect := float(cfg.get("protect_own", 0.5))
	for item in db.companies:
		db.econ(item)["tariff_demand"] = 1.0
	var duty := 0.0
	var taxed_import := {}   # goods -> share of the player's home market taxed
	var zone_people := {}    # zone id -> the people of its members (its market)
	for z in Zones.all():
		var s := 0.0
		for m in Zones.members(z):
			s += float(goods.now_people.get(str(m), 0.0))
		zone_people[str((z as Dictionary).get("id", ""))] = s
	var single_k := float(Zones.cfg.get("single_market_k", 0.12))
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty():
			continue
		var home := str(c.get("_country", ""))
		var g := goods.goods_of(c)
		var factor := 1.0
		for t in tariffs:
			var td: Dictionary = t
			if str(td["on_value"]) != home or not (str(td["goods_key"]).is_empty() or str(td["goods_key"]) == g):
				continue
			if Zones.free_trade(str(td["from_value"]), home):
				continue   # one free-trade zone: duties between members do nothing
			var market_country := str(td["from_value"])
			var d := dep(market_country, c)
			var lost := d * minf(1.0, float(td["rate"]) * el)
			# What the company sold into that market, as a part of its revenue.
			var part := _export_part(c, market_country)
			factor *= 1.0 - part * minf(1.0, float(td["rate"]) * el)
			if market_country == _player:
				duty += part * float(e.get("R", 0.0)) * (1.0 - minf(1.0, float(td["rate"]) * el)) * float(td["rate"])
				taxed_import[g] = float(taxed_import.get(g, 0.0)) + lost
		for s in sanctions:
			if str((s as Dictionary)["id"]) == str(c["id"]):
				factor *= 1.0 - _export_part(c, _player)
				taxed_import[g] = float(taxed_import.get(g, 0.0)) + dep(_player, c)
		e["tariff_demand"] = (1.0 - (1.0 - factor) * db.cfx(home, "tariffs_against")) * _zone_factor(c, home, zone_people, single_k, el)   # space discoveries blunt tariffs
	# The player's own companies of taxed goods get the market the imports lose.
	for item in db.companies:
		var c: Dictionary = item
		if str(c.get("_country", "")) != _player:
			continue
		var g := goods.goods_of(c)
		if taxed_import.has(g):
			var e := db.econ(c)
			e["tariff_demand"] = float(e.get("tariff_demand", 1.0)) * (1.0 + protect * minf(1.0, float(taxed_import[g])))
	if duty > 0.0:
		game.add_resource(game.home_body(), "money", duty * db.dt / 52.0)
	revenue_weeks.append(duty / 52.0)
	while revenue_weeks.size() > 52:
		revenue_weeks.pop_front()


## The part of a company's revenue that comes from one foreign country.
## The economic zones in a company's demand (zones.gd): inside a single market its sales to the partners count
## almost as at home (+); outside a union with an external tariff its sales there lose (−); inside such a union
## its home market is a little protected (+).
func _zone_factor(c: Dictionary, home: String, zone_people: Dictionary, single_k: float, el: float) -> float:
	var outside := goods.now_world - float(goods.now_people.get(home, 0.0))
	if outside <= 0.0:
		return 1.0
	var xs := goods.export_share(db, c)
	var f := 1.0
	var protect := float(_cfg().get("protect_own", 0.5))
	for z in Zones.all():
		var zd: Dictionary = z
		var ppl := float(zone_people.get(str(zd.get("id", "")), 0.0))
		var inside: bool = home in Zones.members(zd)
		if inside and Zones.has_rule(zd, "единый_рынок"):
			f *= 1.0 + single_k * xs * (ppl - float(goods.now_people.get(home, 0.0))) / outside
		var rate := float(zd.get("external_tariff", 0.0))
		if rate > 0.0:
			f *= 1.0 + protect * rate * 0.5 if inside else 1.0 - minf(1.0, xs * ppl / outside) * minf(1.0, rate * el)
	return f


func _export_part(c: Dictionary, country: String) -> float:
	var home := str(c.get("_country", ""))
	if country == home:
		return 0.0
	var outside := goods.now_world - float(goods.now_people.get(home, 0.0))
	return goods.export_share(db, c) * float(goods.now_people.get(country, 0.0)) / outside if outside > 0.0 else 0.0


func duties_year() -> float:
	var s := 0.0
	for v in revenue_weeks:
		s += float(v)
	return s * 52.0 / maxf(1.0, float(revenue_weeks.size()))


func _has_tariff(from: String, on: String, g: String) -> bool:
	for t in tariffs:
		var td: Dictionary = t
		if str(td["from_value"]) == from and str(td["on_value"]) == on and (str(td["goods_key"]).is_empty() or str(td["goods_key"]) == g):
			return true
	return false


## A long corporate war between the player's company and a foreign one, in a country cold to the player, becomes
## that country's tariffs on the player's goods of that kind.
func _ai_trade_wars(day: int) -> void:
	var cfg := _cfg()
	for w in rivals.wars:
		var a := db.company(str(w["a"]))
		var b := db.company(str(w["b"]))
		if a.is_empty() or b.is_empty() or int(w.get("weeks", 0)) < int(cfg.get("war_to_tariffs_weeks", 26)):
			continue
		var mine: Dictionary = a if str(a.get("_country", "")) == _player else (b if str(b.get("_country", "")) == _player else {})
		if mine.is_empty():
			continue
		var other: Dictionary = b if str(mine["id"]) == str(a["id"]) else a
		var country := str(other.get("_country", ""))
		var g := goods.goods_of(mine)
		if country == _player or _relation(country) >= float(cfg.get("cold_below", 0.45)) or _has_tariff(country, _player, g) \
				or Zones.free_trade(country, _player):
			continue
		if _rng.randf() < float(cfg.get("war_to_tariffs_chance", 0.1)) * db.dt / 52.0:
			var rate := snappedf(_rng.randf_range(0.15, 0.35), 0.05)
			tariffs.append({"from_value": country, "on_value": _player, "goods_key": g, "rate": rate, "вид": "tariffs", "from_day": day})
			_log("arena_ai_tariff", [country, _goods_name(g), db.percent(rate), db.name_of(other)], day)
			_say("arena_ai_tariff", [country, _goods_name(g), db.percent(rate), db.name_of(other)])


# ---------- espionage ----------

func _spies(day: int) -> void:
	var cfg := _cfg()
	var left: Array = []
	for item in ops:
		var op: Dictionary = item
		if int(op["until_day"]) > day:
			left.append(op)
			continue
		var c := db.company(str(op["id"]))
		if not c.is_empty():
			_finish_spy(op, c, day)
	ops = left
	# Hostile countries spy on the player's companies now and then.
	if _rng.randf() < float(cfg.get("foreign_espionage_per_year", 0.8)) * db.dt / 52.0:
		var hostile: Array = []
		for f in game.factions():
			var fd: Dictionary = f
			if float(fd.get("relations", 0.5)) < float(cfg.get("hostile_below", 0.3)) and db.countries.has(str(fd.get("name", ""))):
				hostile.append(str(fd["name"]))
		var mine: Array = db.companies.filter(func(x): return str(x.get("_country", "")) == _player)
		if not hostile.is_empty() and not mine.is_empty():
			mine.sort_custom(func(a, b): return db.cap(a) > db.cap(b))
			var target: Dictionary = mine[_rng.randi_range(0, mini(9, mine.size() - 1))]
			# Defences: the industry tree and the country's technologies (tree.gd).
			if _rng.randf() > db.tree(target, "шпионаж_против", 1.0) * float((db.tree_country.get(_player, {}) as Dictionary).get("espionage_countries", 1.0)):
				return
			var who := str(hostile[_rng.randi_range(0, hostile.size() - 1)])
			var e := db.econ(target)
			e["demand"] = float(e["demand"]) * (1.0 - float(cfg.get("espionage_damage", 0.02)))
			Goods.reputation_event(db, e, -1.0, 0.03)
			_log("arena_spied_on", [who, db.name_of(target)], day)
			_say("arena_spied_on", [who, db.name_of(target)])


func _finish_spy(op: Dictionary, c: Dictionary, day: int) -> void:
	var cfg := _cfg()
	var country := str(c.get("_country", ""))
	var p := clampf((float(cfg.get("espionage_base", 0.55)) - 0.3 * float(prestige.get(country, 50.0)) / 100.0) * db.cfx(_player, "our_espionage"), 0.15, 0.95)
	var ok := _rng.randf() < p
	var caught := _rng.randf() < (float(cfg.get("caught_on_failure", 0.7)) if not ok else float(cfg.get("caught_on_success", 0.15)))
	if ok:
		var mine := db.company(str(op.get("own_m", "")))
		if not mine.is_empty():
			var em := db.econ(mine)
			var gain := float(cfg.get("espionage_gain", 0.04))
			em["R0"] = float(em["R0"]) * (1.0 + gain)
			Goods.reputation_event(db, em, 1.0, 0.05)
			(mine["_chronicle"] as Array).append({"день": day, "вид": "arena", "что": "шпионаж_выгода", "rival": str(c["id"])})
		var et := db.econ(c)
		et["demand"] = float(et["demand"]) * (1.0 - float(cfg.get("espionage_damage", 0.02)))
		_say("arena_spy_ok", [db.name_of(c), db.name_of(mine) if not mine.is_empty() else "—"])
	else:
		_say("arena_spy_failed", [db.name_of(c)])
	if caught:
		_relations(country, -float(cfg.get("espionage_scandal", 0.08)))
		flight[_player] = float(flight.get(_player, 0.0)) + 1.0
		_log("arena_spy_caught", [country, db.name_of(c)], day)
		_say("arena_spy_caught", [country, db.name_of(c)])
		_answer(country, "шпионаж", c, day)


# ---------- the player's orders ----------

## The order is about the arena (sanctions, tariffs, a trade war, espionage, lifting them). True when taken.
func handle(d: Dictionary) -> bool:
	_player = str(game.player_faction().get("name", ""))
	var text := " " + str(d.get("order", "")).to_lower() + " "
	var day := game.day()
	var spy := _has(text, W_SPY)
	var tariff := _has(text, W_TARIFF)
	var sanction := _has(text, W_SANCTION)
	if not (spy or tariff or sanction):
		return false
	var c := Antitrust.find_company(db, text)
	var country := find_country(text)
	if _has(text, W_LIFT) and (tariff or sanction):
		return _lift(c, country, text, day)
	if spy:
		if c.is_empty() or str(c.get("_country", "")) == _player:
			return false
		_start_spy(c, text, d, day)
		return true
	if sanction and not c.is_empty() and str(c.get("_country", "")) != _player:
		_sanction_company(c, day)
		return true
	if country.is_empty() or country == _player:
		return false
	var g := _goods_in(text)
	var rate := _percent(text)
	if sanction:
		_impose(country, g, 1.0, "санкции", day)
	else:
		_impose(country, g, rate if rate > 0.0 else float(_cfg().get("tariff_default", 0.25)), "tariffs", day)
	return true


static func _has(text: String, words: Array) -> bool:
	for w in words:
		if text.contains(str(w)):
			return true
	return false


static func _percent(text: String) -> float:
	var re := RegEx.new()
	re.compile("(\\d+(?:[.,]\\d+)?)\\s*%")
	var m := re.search(text)
	return float(m.get_string(1).replace(",", ".")) / 100.0 if m != null else -1.0


## A country named in the order: its name (or, for a long one, without the last letter or two — Russian cases).
func find_country(low: String) -> String:
	var best := ""
	var best_len := 0
	for country in db.countries.keys():
		var name := str(country).to_lower()
		var hit := false
		if name.length() <= 3:
			hit = low.contains(" " + name + " ") or low.contains(" " + name + ",") or low.contains(" " + name + ".")
		else:
			hit = low.contains(name) or (name.length() >= 5 and low.contains(name.substr(0, name.length() - 1))) \
				or (name.length() >= 6 and low.contains(name.substr(0, name.length() - 2)))
		if hit and name.length() > best_len:
			best = str(country)
			best_len = name.length()
	return best


func _goods_in(text: String) -> String:
	var all: Dictionary = db.goods.get("goods", {})
	for key in all.keys():
		var names: Dictionary = (all[key] as Dictionary).get("name", {})
		for n in [str(key), str(names.get("ru", "")), str(names.get("en", ""))]:
			var stem: String = str(n).to_lower().substr(0, maxi(4, mini(str(n).length(), 6)))
			if stem.length() >= 4 and text.contains(stem):
				return str(key)
	return ""


func _goods_name(key: String) -> String:
	if key.is_empty():
		return _t("arena_all_goods")
	return db.text((((db.goods.get("goods", {}) as Dictionary).get(key, {}) as Dictionary).get("name", key)))


func _impose(country: String, g: String, rate: float, kind: String, day: int) -> void:
	if kind == "tariffs" and Zones.free_trade(_player, country):
		_say("zone_no_tariffs", [country])   # one free-trade zone: the order cannot work
		return
	tariffs = tariffs.filter(func(t): return not (str(t["from_value"]) == _player and str(t["on_value"]) == country and str(t["goods_key"]) == g))
	tariffs.append({"from_value": _player, "on_value": country, "goods_key": g, "rate": rate, "вид": kind, "from_day": day})
	_relations(country, -float(_cfg().get("relations_per_tariffs", 0.04)) * (2.0 if kind == "санкции" else 1.0))
	_log("arena_imposed_" + kind, [country, _goods_name(g), db.percent(rate)], day)
	_say("arena_imposed_" + kind, [country, _goods_name(g), db.percent(rate)])
	_answer(country, kind, {}, day)
	# A customs union answers as one: every other member mirrors the duties (zones.gd «общая_торговая_политика»).
	if kind == "tariffs":
		var bloc := Zones.trade_bloc(country)
		if not bloc.is_empty() and not (_player in bloc):
			for m in bloc:
				if not _has_tariff(str(m), _player, g):
					tariffs.append({"from_value": str(m), "on_value": _player, "goods_key": g, "rate": rate, "вид": "tariffs", "from_day": day})
				_relations(str(m), -0.02)
			_say("zone_bloc_answer", [country, ", ".join(PackedStringArray(bloc.slice(0, 6))) + ("…" if bloc.size() > 6 else "")])


## Sanctions on one foreign company: it loses the player's market; the countries that depend on it are angry.
func _sanction_company(c: Dictionary, day: int) -> void:
	var cid := str(c["id"])
	if not sanctions.any(func(s): return str(s["id"]) == cid):
		sanctions.append({"id": cid, "from_day": day})
	var home := str(c.get("_country", ""))
	var angry: PackedStringArray = []
	var from := float(_cfg().get("dependency_from", 0.05))
	for country in goods.now_people.keys():
		var name := str(country)
		if name == _player or name == home:
			continue
		var d := dep(name, c)
		if d >= from:
			_relations(name, -d * float(_cfg().get("dependants_anger", 0.3)))
			angry.append(name)
	_relations(home, -float(_cfg().get("relations_per_tariffs", 0.04)) * 1.5)
	_log("arena_sanctioned", [db.name_of(c), home, str(angry.size())], day)
	_say("arena_sanctioned", [db.name_of(c), home, ", ".join(angry.slice(0, 5)) if not angry.is_empty() else _t("arena_nobody")])
	(c["_chronicle"] as Array).append({"день": day, "вид": "arena", "что": "санкции", "country": _player})
	_answer(home, "санкции_компании", c, day)


func _lift(c: Dictionary, country: String, text: String, day: int) -> bool:
	if not c.is_empty():
		var cid := str(c["id"])
		var before := sanctions.size()
		sanctions = sanctions.filter(func(s): return str(s["id"]) != cid)
		if sanctions.size() < before:
			_relations(str(c.get("_country", "")), 0.03)
			_say("arena_lifted_company", [db.name_of(c)])
			return true
	if country.is_empty():
		return false
	var g := _goods_in(text)
	var before2 := tariffs.size()
	tariffs = tariffs.filter(func(t): return not (str(t["from_value"]) == _player and str(t["on_value"]) == country and (g.is_empty() or str(t["goods_key"]) == g)))
	if tariffs.size() < before2:
		_relations(country, 0.03)
		_log("arena_lifted", [country], day)
		_say("arena_lifted", [country])
		return true
	return false


func _start_spy(c: Dictionary, text: String, d: Dictionary, day: int) -> void:
	var cfg := _cfg()
	var mine: Dictionary = {}
	var low := text
	# Who gets the technology: a company of the player named in the order, else its biggest of the same goods.
	for item in db.companies:
		var o: Dictionary = item
		if str(o.get("_country", "")) == _player and str(o["id"]) != str(c["id"]):
			var n := db.name_of(o).to_lower()
			if n.length() >= 4 and low.contains(n):
				mine = o
	if mine.is_empty():
		for item in db.companies:
			var o: Dictionary = item
			if str(o.get("_country", "")) == _player and goods.goods_of(o) == goods.goods_of(c) and (mine.is_empty() or db.cap(o) > db.cap(mine)):
				mine = o
	var weeks := _rng.randi_range(int(cfg.get("espionage_weeks_from", 6)), int(cfg.get("espionage_weeks_to", 10)))
	ops.append({"вид": "шпионаж", "id": str(c["id"]), "own_m": str(mine.get("id", "")), "until_day": day + weeks * 7})
	if d.get("request") is Dictionary:
		(d["request"] as Dictionary)["дней"] = weeks * 7
	_say("arena_spy_started", [db.name_of(c), str(weeks)])


# ---------- answers and crises ----------

## A foreign government answers the player (tariffs, sanctions, spies). The GAME rolls the measure by the relation and
## the two countries' prestige (balance «арена» «ответ_веса»); the AI only writes the official statement.
func _answer(country: String, why: String, c: Dictionary, day: int) -> void:
	if country.is_empty() or country == _player:
		return
	var rel := _relation(country)
	var measure := _roll_answer(country, why, rel)
	var data := {"country": country, "to_country": _player, "повод": why, "company": db.name_of(c) if not c.is_empty() else "",
		"мера": measure, "язык": "ru" if db.lang() == "ru" else "en"}
	var prompt := "You are the government of «страна». Another country («к_стране») just did this to you or your company: «повод» " \
		+ "(«компания» if given). Your government has decided the answer «мера» (fixed — do not change it). Write one short sentence of " \
		+ "your official statement announcing it, in the language «язык», inventing no other facts. Return ONLY JSON: {\"заявление\": \"…\"}"
	var asked: bool = mod.ask_ai("corp_arena", prompt, data, func(answer: Dictionary) -> void: _apply_answer(country, why, measure, answer, day))
	if not asked:
		_apply_answer(country, why, measure, {}, day)


## The answer rolled by weights: hostile countries sanction and tax, friendly ones send a note; a weak country
## (prestige well below the player's) is careful; a caught spy is answered with expelled diplomats more often.
func _roll_answer(country: String, why: String, rel: float) -> String:
	var w: Dictionary = (_cfg().get("answer_weights", {}) as Dictionary)
	var band := "enemy" if rel < 0.2 else ("холодно" if rel < 0.45 else "friendship")
	var weights: Dictionary = (w.get(band, {}) as Dictionary).duplicate()
	if weights.is_empty():
		weights = {"note": 1.0}
	if why == "шпионаж":
		weights["diplomat_expulsion"] = float(weights.get("diplomat_expulsion", 0.0)) + float(w.get("espionage_expulsion", 0.4))
	var mine := float(prestige.get(_player, 0.0))
	var theirs := float(prestige.get(country, 0.0))
	if mine > 0.0 and theirs < mine * 0.5:
		weights["note"] = float(weights.get("note", 0.0)) + float(w.get("weak_note", 0.4))
	var total := 0.0
	for k in weights.keys():
		total += maxf(0.0, float(weights[k]))
	var r := _rng.randf() * total
	for k in weights.keys():
		r -= maxf(0.0, float(weights[k]))
		if r <= 0.0 and str(k) in ANSWERS:
			return str(k)
	return "note"


func _apply_answer(country: String, why: String, measure: String, answer: Dictionary, day: int) -> void:
	if db == null or game == null:
		return
	if not (measure in ANSWERS):
		measure = "note"
	match measure:
		"note":
			_relations(country, -0.02)
		"diplomat_expulsion":
			_relations(country, -0.06)
		"retaliatory_tariffs":
			if Zones.free_trade(country, _player):
				_log("arena_answer_нота", [country], day)
				return
			var rate := 0.25
			for t in tariffs:
				if str(t["from_value"]) == _player and str(t["on_value"]) == country:
					rate = maxf(rate, float(t["rate"]))
			tariffs.append({"from_value": country, "on_value": _player, "goods_key": "", "rate": minf(rate, 0.5), "вид": "tariffs", "from_day": day})
			_relations(country, -0.03)
		"company_sanctions":
			tariffs.append({"from_value": country, "on_value": _player, "goods_key": "", "rate": 1.0, "вид": "санкции", "from_day": day})
			_relations(country, -0.06)
	_log("arena_answer_" + measure, [country], day)
	_say("arena_answer_" + measure, [country])
	var statement := str(answer.get("заявление", "")).strip_edges()
	if not statement.is_empty():
		game.chronicle(game.home_body(), "%s: «%s»" % [country, statement], "bad", 2)


## A nationalised or seized foreign company: a diplomatic crisis with its country, investors take fright.
func crisis(why: String, country: String, c: Dictionary) -> void:
	if not (why in ["nationalisation", "confiscation"]):
		return
	var day := game.day()
	_relations(country, -float(_cfg().get("crisis_relations", 0.1)))
	flight[_player] = float(flight.get(_player, 0.0)) + float(_cfg().get("flight_per_seizure", 3.0))
	_log("arena_crisis", [country, db.name_of(c)], day)
	_say("arena_crisis", [country, db.name_of(c)])


func _relation(country: String) -> float:
	for f in game.factions():
		if str((f as Dictionary).get("name", "")) == country:
			return float((f as Dictionary).get("relations", 0.4))
	return 0.4


func _relations(country: String, delta: float) -> void:
	for f in game.factions():
		var fd: Dictionary = f
		if str(fd.get("name", "")) == country and fd.has("relations"):
			fd["relations"] = clampf(float(fd["relations"]) + delta, 0.0, 1.0)


# ---------- save ----------

func save_state() -> Dictionary:
	return {"prestige0": prestige0, "applied": _applied, "tariffs": tariffs, "санкции": sanctions, "operations": ops, "flight": flight,
		"conflicts": conflicts, "fees": revenue_weeks, "зерно": str(_rng.seed), "состояние": str(_rng.state)}


func load_state(state: Dictionary) -> void:
	prestige0 = (state.get("prestige0", {}) as Dictionary).duplicate() if state.get("prestige0") is Dictionary else {}
	_applied = float(state.get("applied", -1.0))
	tariffs = (state.get("tariffs", []) as Array).duplicate(true) if state.get("tariffs") is Array else []
	sanctions = (state.get("санкции", []) as Array).duplicate(true) if state.get("санкции") is Array else []
	ops = (state.get("operations", []) as Array).duplicate(true) if state.get("operations") is Array else []
	flight = (state.get("flight", {}) as Dictionary).duplicate() if state.get("flight") is Dictionary else {}
	conflicts = (state.get("conflicts", []) as Array).duplicate(true) if state.get("conflicts") is Array else []
	revenue_weeks = (state.get("fees", []) as Array).duplicate() if state.get("fees") is Array else []
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
