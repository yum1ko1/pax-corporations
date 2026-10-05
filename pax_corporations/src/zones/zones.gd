extends RefCounted
## Economic zones and unions (config/zones.json): the Eurozone, the EAEU common economic space, China's closed capital
## market, USMCA, ASEAN, Mercosur, the GCC — and the unions the player founds. Their rules work in the game:
## INSIDE a union
##   без_пошлин — tariffs and trade wars between members do nothing (arena.gd);
##   единый_рынок — members sell to each other almost as at home: + «единый_рынок_k» demand per share of their sales
##     inside the union (arena.gd);
##   свободный_капитал — a member's government never forbids other members to buy shares (orders.gd);
##   лёгкий_переезд — companies move between members more willingly (lifecycle.gd); takeovers inside are likelier (rivals.gd);
##   общая_конкуренция — the members' antimonopoly strictness × «конкуренция_k» (corp_data.gd).
## BETWEEN zones
##   внешний_тариф — a company from outside loses demand on the union's market (its sales there × the tariff), the
##     members' companies of the same goods get part of it (arena.gd);
##   общая_торговая_политика — duties against one member are answered by the whole union (arena.gd);
##   фильтр_инвестиций — outsiders cannot buy more than «фильтр_доля» of a member's company in a strategic industry, nor
##     take it over (orders.gd, main.gd, rivals.gd);
##   закрытый_капитал — outsiders buy no shares and take over nothing at all (China).
## Unions live: the player joins, leaves (a share shock, colder partners) or founds one; a country is in one customs
## union at most. The membership changes are saved (state()).
const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")

static var cfg: Dictionary = {}
static var _of: Dictionary = {}       # country -> [zone…]
static var _zones: Array = []         # the zones now (the config's with today's members + founded ones)


static func load_cfg(m: PaxMod) -> void:
	var v: Variant = GameApi.json(m, "config/zones.json", {})
	cfg = v if v is Dictionary else {}
	_zones = (cfg.get("zones", []) as Array).duplicate(true)
	_index()


static func _index() -> void:
	_of.clear()
	for z in _zones:
		for c in (z as Dictionary).get("members", []):
			if not _of.has(str(c)):
				_of[str(c)] = []
			(_of[str(c)] as Array).append(z)


## What the save keeps: every zone's members and the founded unions.
static func state() -> Dictionary:
	var members := {}
	var founded: Array = []
	for z in _zones:
		var zd: Dictionary = z
		members[str(zd.get("id", ""))] = zd.get("members", [])
		if bool(zd.get("own_f", false)):
			founded.append(zd)
	return {"members": members, "свои": founded}


static func load_state(st: Dictionary) -> void:
	_zones = (cfg.get("zones", []) as Array).duplicate(true)
	for f in st.get("свои", []):
		if f is Dictionary:
			_zones.append((f as Dictionary).duplicate(true))
	var members: Dictionary = st.get("members", {}) if st.get("members") is Dictionary else {}
	for z in _zones:
		var id := str((z as Dictionary).get("id", ""))
		if members.has(id) and members[id] is Array:
			(z as Dictionary)["members"] = (members[id] as Array).duplicate()
	_index()


static func all() -> Array:
	return _zones


static func zone(id: String) -> Dictionary:
	for z in _zones:
		if str((z as Dictionary).get("id", "")) == id:
			return z
	return {}


static func zones_of(country: String) -> Array:
	return _of.get(country, [])


static func has_rule(z: Dictionary, rule: String) -> bool:
	return rule in (z.get("правила", []) as Array)


static func members(z: Dictionary) -> Array:
	return z.get("members", [])


## Both countries in one zone with this rule.
static func shared(a: String, b: String, rule: String) -> bool:
	if a == b:
		return false
	for z in zones_of(a):
		if has_rule(z, rule) and b in members(z):
			return true
	return false


## Takeovers between companies of one zone are twice as likely (rivals.gd) — every zone.
static func same_zone_rule_takeover() -> bool:
	return true


static func same_zone(a: String, b: String) -> bool:
	if a == b:
		return false
	for z in zones_of(a):
		if b in members(z):
			return true
	return false


## The target's zone is closed to outside capital and the buyer is outside it.
static func closed(target_country: String, buyer_country: String) -> bool:
	if target_country == buyer_country:
		return false
	for z in zones_of(target_country):
		if has_rule(z, "закрытый_капитал") and not (buyer_country in members(z)):
			return true
	return false


## The target's zone screens outside capital in strategic industries: the buyer is outside and the industry is
## strategic — no control, at most «фильтр_доля».
static func screened(target: Dictionary, buyer_country: String) -> bool:
	var home := str(target.get("_country", ""))
	if home == buyer_country or not (str(target.get("sector", "")) in (cfg.get("strategic", []) as Array)):
		return false
	for z in zones_of(home):
		if has_rule(z, "фильтр_инвестиций") and not (buyer_country in members(z)):
			return true
	return false


static func screen_cap() -> float:
	return float(cfg.get("filter_share", 0.1))


static func free_trade(a: String, b: String) -> bool:
	return shared(a, b, "без_пошлин")


static func free_capital(a: String, b: String) -> bool:
	return shared(a, b, "свободный_капитал")


static func move_bonus(a: String, b: String) -> float:
	return float(cfg.get("move_bonus", 0.12)) if shared(a, b, "лёгкий_переезд") else 0.0


static func antitrust_k(country: String) -> float:
	var k := 1.0
	for z in zones_of(country):
		if has_rule(z, "общая_конкуренция"):
			k *= float((z as Dictionary).get("competition_k", 1.15))
	return k


## The unions whose common trade policy covers this country (an answer comes from every member).
static func trade_bloc(country: String) -> Array:
	var out: Array = []
	for z in zones_of(country):
		if has_rule(z, "общая_торговая_политика"):
			for m in members(z):
				if str(m) != country and not out.has(str(m)):
					out.append(str(m))
	return out


static func customs_union_of(country: String) -> Dictionary:
	for z in zones_of(country):
		if bool((z as Dictionary).get("customs", false)):
			return z
	return {}


# ---------- joining, leaving, founding ----------

## Why the country cannot join the zone ("" — it can). relation: func(country) -> 0..1 attitude of a country to it.
static func join_block(country: String, z: Dictionary, relation: Callable) -> String:
	if not bool(z.get("союз", true)):
		return "zones_why_not_union"
	if country in members(z):
		return "zones_why_member"
	if bool(z.get("customs", false)) and not customs_union_of(country).is_empty():
		return "zones_why_customs"
	var need := float(cfg.get("accession_relations", 0.5))
	var sum := 0.0
	var n := 0
	for m in members(z):
		sum += float(relation.call(str(m))) if relation.is_valid() else 0.5
		n += 1
	if n > 0 and sum / float(n) < need:
		return "zones_why_relations"
	return ""


static func join(country: String, z: Dictionary) -> void:
	if not (country in members(z)):
		(z["members"] as Array).append(country)
	_index()


static func leave(country: String, z: Dictionary) -> void:
	(z["members"] as Array).erase(country)
	if bool(z.get("own_f", false)) and members(z).size() < 2:
		_zones.erase(z)   # a founded union of one is no union
	_index()


## A new union of the player's country and the partners who agree (their attitude ≥ the joining threshold).
static func found(country: String, partners: Array, title: String) -> Dictionary:
	var id := "own_%d" % (Time.get_unix_time_from_system() as int)
	var z := {"id": id, "name": {"ru": title, "en": title}, "type": {"ru": "свой союз", "en": "own union"},
		"colour": [randf_range(0.3, 0.95), randf_range(0.3, 0.95), randf_range(0.3, 0.95)], "own_f": true, "союз": true,
		"description": {"ru": "Союз, основанный вашей страной: торговля без пошлин, единый рынок и свободное движение капитала между членами.",
			"en": "A union your country founded: duty-free trade, a single market and free movement of capital between members."},
		"members": [country] + partners, "правила": ["без_пошлин", "единый_рынок", "свободный_капитал", "лёгкий_переезд"]}
	_zones.append(z)
	_index()
	return z


static func name_of(z: Dictionary, lang: String) -> String:
	var n: Variant = z.get("name", "")
	return str((n as Dictionary).get(lang, (n as Dictionary).get("ru", ""))) if n is Dictionary else str(n)


static func text_of(z: Dictionary, key: String, lang: String) -> String:
	var n: Variant = z.get(key, "")
	return str((n as Dictionary).get(lang, (n as Dictionary).get("ru", ""))) if n is Dictionary else str(n)


static func color_of(z: Dictionary) -> Color:
	var c: Variant = z.get("colour", [0.5, 0.5, 0.5])
	if c is Array and (c as Array).size() >= 3:
		return Color(float(c[0]), float(c[1]), float(c[2]))
	return Color(0.5, 0.5, 0.5)
