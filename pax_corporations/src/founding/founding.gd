extends RefCounted
## The player founds a company (the «Found a company» dialog of the window). The player chooses the goods
## (industry), the name, the description, the place of the headquarters and how much money to put in; the rest
## is counted by the analysts from the market (config goods.json «основание»):
##
##   revenue it can reach = capital / capital intensity of the goods, but a newcomer takes at most a few percent
##   of its markets (home and, for its export part, the world — population × consumption × wealth, goods.gd),
##   × the country's situation for the industry (events.gd exposure, as for every company);
##   margin = the industry's typical margin (the median of the companies selling the same goods) × the newcomer
##   factor; people = revenue / the revenue per worker typical for the goods in the country (or the world,
##   scaled by wages); wage = the industry's market wage in the country + a premium to attract people;
##   shares: the company is valued at the money put in, at $10 a share.
##
## Who owns it: a player who leads a state founds a state enterprise (the state holds 100%, a civil servant runs
## it); a player who is a person founds a sole proprietorship (ИП) — or a private company when the capital is big —
## and runs it as the founder. The head of a state enterprise gets a name from the game's own name lists
## (data/names.json — the same lists the game gives its neural network).

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")
const Events := preload("res://mods/pax_corporations/src/news/events.gd")


static func _cfg(db: Data) -> Dictionary:
	return db.goods.get("founding", {})


## The industry (sector) a goods belongs to: the one most companies selling it are in.
static func sector_for(db: Data, goods_key: String) -> String:
	var count := {}
	for item in db.companies:
		var c: Dictionary = item
		if str(c.get("profile", "")) == goods_key:
			var s := str(c.get("sector", ""))
			count[s] = int(count.get(s, 0)) + 1
	var best := ""
	for s in count.keys():
		if best.is_empty() or int(count[s]) > int(count[best]):
			best = str(s)
	if best.is_empty():
		best = str(db.sectors.keys()[0]) if not db.sectors.is_empty() else ""
	return best


## What the analysts expect from a new company: {выручка, прибыль, маржа, сотрудники, зарплата, акций_млн, цена,
## вложено, деньги, рынок, доля, обстановка, сектор, ok, why}. All money in млн $ a year.
static func propose(db: Data, goods: Goods, events: Events, country: String, goods_key: String, capital: float) -> Dictionary:
	var cfg := _cfg(db)
	var out := {"ok": false, "why": "", "sector": sector_for(db, goods_key)}
	if capital < float(cfg.get("capital_min", 1.0)):
		out["why"] = "found_err_capital"
		return out
	var g: Dictionary = (db.goods.get("goods", {}) as Dictionary).get(goods_key, {})
	var per := float(g.get("consumption", 300.0))
	var x := clampf(float(g.get("export", 0.3)), 0.0, 1.0)
	var prices := _price_index(db, country)
	var home := float(goods.now_people.get(country, 0.0)) * per / 1e6 * prices
	var world := goods.now_world * per / 1e6 * prices
	var reach := (1.0 - x) * home + x * world
	var intensity := maxf(0.05, float((cfg.get("capital_intensity", {}) as Dictionary).get(goods_key, 1.0)))
	var revenue := capital / intensity
	var cap_share := float(cfg.get("newcomer_share_max", 0.05))
	if reach > 0.0:
		revenue = minf(revenue, cap_share * reach)
	# The country's situation for this industry (wars, sanctions, oil, science…), as for every company.
	var stub := {"sector": out["sector"], "_country": country}
	var exposure := float(events.exposure(db, stub)["total"]) if events != null else 0.0
	var k_level := float((db.balance.get("события", {}) as Dictionary).get("demand_from_climate", 0.15))
	revenue *= exp(k_level * exposure)
	var peers := _peers(db, goods_key, country)
	var margin := float(peers["margin"]) * float(cfg.get("newcomer_margin", 0.5))
	var avg_wage := float(db.country_info(country).get("average_wage", _avg_wage_any(db)))
	var wage := avg_wage * float((db.sectors.get(out["sector"], {}) as Dictionary).get("wage_premium", 1.0)) \
		* (1.0 + float(cfg.get("wage_markup", 0.05)))
	var per_worker := float(peers["revenue_per_person"]) * (wage / maxf(float(peers["wage"]), 1.0) if not bool(peers["own_country"]) else 1.0)
	var staff := maxf(1.0, revenue / maxf(per_worker, 1e-6))
	# People must not cost more than the business earns before them.
	var room := revenue * (1.0 - margin) * float(cfg.get("payroll_max", 0.8))
	if staff * wage * 12.0 / 1e6 > room and room > 0.0:
		staff = maxf(1.0, room * 1e6 / 12.0 / wage)
	var invested := minf(capital, revenue * intensity)
	var price := float(cfg.get("share_price", 10.0))
	out.merge({"ok": true, "выручка": revenue, "margin": margin, "profit": revenue * margin, "staff": roundf(staff), "wage": roundf(wage),
		"shares_mln": capital / price, "price": price, "invested": invested, "money": capital - invested, "рынок": reach,
		"market_home": home, "доля": revenue / maxf(reach, 1e-6), "обстановка": exposure, "export": x}, true)
	return out


## The typical margin, revenue per worker and wage of the companies selling the same goods — in the country
## if it has some, else in the world.
static func _peers(db: Data, goods_key: String, country: String) -> Dictionary:
	var mine: Array = []
	var all: Array = []
	for item in db.companies:
		var c: Dictionary = item
		if str(c.get("profile", "")) != goods_key or db.staff(c) <= 0.0:
			continue
		var row := [db.fund(c, "profit") / maxf(db.fund(c, "выручка"), 1.0), db.fund(c, "выручка") / db.staff(c), db.wage(c)]
		all.append(row)
		if str(c.get("_country", "")) == country:
			mine.append(row)
	var use: Array = mine if not mine.is_empty() else all
	if use.is_empty():
		return {"margin": 0.08, "revenue_per_person": 0.2, "wage": 2000.0, "own_country": true}
	return {"margin": _median(use, 0), "revenue_per_person": _median(use, 1), "wage": _median(use, 2), "own_country": not mine.is_empty()}


static func _median(rows: Array, i: int) -> float:
	var v: Array = rows.map(func(r): return float(r[i]))
	v.sort()
	return float(v[int(v.size() / 2.0)])


static func _price_index(db: Data, country: String) -> float:
	for item in db.companies:
		var c: Dictionary = item
		if str(c.get("_country", "")) == country and not db.econ(c).is_empty():
			return float(db.econ(c).get("цены", 1.0))
	return 1.0


static func _avg_wage_any(db: Data) -> float:
	var s := 0.0
	for k in db.countries.keys():
		s += float((db.countries[k] as Dictionary).get("average_wage", 1000.0))
	return s / maxf(1.0, float(db.countries.size()))


## A name from the game's own lists for the player's language: {"ru": …, "en": …} (the same text).
static func invent_person(db: Data, rng: RandomNumberGenerator) -> String:
	var raw: Variant = Pax.json("res://data/names.json", {})
	var langs: Dictionary = (raw as Dictionary).get("языки", {}) if raw is Dictionary else {}
	var code := Pax.game.language() if Pax.game != null else "ru"
	var names: Dictionary = langs.get(code, langs.get("en", {}))
	var female := rng.randf() < 0.35
	var first: Array = names.get("женские" if female else "мужские", [])
	var last: Array = names.get("фамилии", [])
	if first.is_empty() or last.is_empty():
		return db.mod.tr_key("pax_corporations_found_head_default")
	var surname := str(last[rng.randi_range(0, last.size() - 1)])
	if female and code == "ru" and (surname.ends_with("ов") or surname.ends_with("ев") or surname.ends_with("ин")):
		surname += "а"
	return "%s %s" % [str(first[rng.randi_range(0, first.size() - 1)]), surname]


## The company's own data (as in companies/*.json) from a proposal and the player's choices.
## spec: {название, описание, товар, страна, место: {ш, д, провинция, имя}, капитал, государство: bool,
##        основатель: player's name (a person player), год}
static func build(db: Data, p: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var n := 1
	while not db.company("player_%d" % n).is_empty():
		n += 1
	var country := str(spec["country"])
	var year := int(spec.get("год", 2026))
	var state := bool(spec.get("polity", true))
	var capital := float(spec["capital"])
	var name := str(spec["название"])
	var desc := str(spec["description"])
	var place: Dictionary = spec["место"]
	var head_name := invent_person(db, rng) if state else str(spec.get("founder", ""))
	if head_name.is_empty():
		head_name = invent_person(db, rng)
	var owners: Array = []
	if state:
		owners.append({"кто": {"ru": "Государство (%s)" % country, "en": "The state (%s)" % country}, "type": "polity", "country": country, "доля": 1.0})
	else:
		owners.append({"кто": {"ru": head_name, "en": head_name}, "type": "founder", "доля": 1.0})
	var kind := "государственная" if state else ("ип" if capital < float(_cfg(db).get("ip_to", 50.0)) else "частная")
	var c := {
		"id": "player_%d" % n, "название": {"ru": name, "en": name}, "sector": p["sector"], "profile": spec["goods_key"], "type": kind,
		"founded": year, "description": {"ru": desc, "en": desc},
		"fundamental": {"выручка": p["выручка"], "profit": p["profit"], "debt": 0.0, "money": p["money"], "dividends": 0.0},
		"рынок": {"shares_mln": p["shares_mln"], "market_cap": capital},
		"owners": owners,
		"глава": {"name": {"ru": head_name, "en": head_name}, "роль": "госслужащий" if state else "founder", "с_года": year,
			"born_year": year - rng.randi_range(32, 58), "доля": 0.0 if state else 1.0,
			"характер": {"ru": str(spec.get("character_ru", "")), "en": str(spec.get("character_en", ""))}},
		"staff": int(p["staff"]), "wage": float(p["wage"]),
		"sites": [{"type": "штаб", "name": {"ru": str(place.get("name_ru", name)), "en": str(place.get("имя_en", name))},
			"ш": float(place["ш"]), "д": float(place["д"]), "province": int(place["province"]), "_pr2": true, "staff": int(p["staff"])}],
		"промыслы": [], "оценка": [], "made_by_player": true, "export": p["export"],
	}
	c["_country"] = country
	c["_new"] = true
	c["_price"] = float(p["price"])
	c["_history"] = [float(p["price"])]
	c["_chronicle"] = [{"день": int(spec.get("день", 0)), "вид": "founding", "count_value": capital}]
	c["_statuses"] = {}
	c["_startup"] = startup_weeks(db, str(spec["goods_key"]), capital)
	return c


## How long a new company is being built before it works at full strength (config goods.json «основание»):
## more money and dearer goods (energy, space) take longer; a shop opens sooner than a power plant.
static func startup_weeks(db: Data, goods_key: String, capital: float) -> int:
	var cfg := _cfg(db)
	var intensity := maxf(0.05, float((cfg.get("capital_intensity", {}) as Dictionary).get(goods_key, 1.0)))
	var w := (float(cfg.get("startup_weeks_base", 20.0)) + float(cfg.get("startup_weeks_per_tenfold", 12.0)) * log(maxf(capital, 1.0)) / log(10.0)) \
		* sqrt(intensity)
	return int(clampf(w, float(cfg.get("startup_weeks_min", 13.0)), float(cfg.get("startup_weeks_max", 156.0))))
