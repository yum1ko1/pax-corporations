extends RefCounted
## Stage 3: the life and death of companies (design doc 16, 20.3, 20.6, 20.7, 20.10, 20.11, 20.19, 20.20;
## config balance.json «жизненный_цикл»). Once a week, before debt and the economy:
##
## 1. Bankruptcy (20.3). z = −5 + 1.2 L − 8 M + 2 (1 − S) + 1.5 K + 1.5 X − 2 G (+ «сдвиг»), the yearly chance
##    σ(z) becomes a weekly roll for a company in distress (a loss or no money); the hard trigger — a rating of CCC or worse with no money (or a loss) for
##    4 weeks in a row — skips the roll. The company gets a temporary manager for 12 weeks; then it is rescued
##    (back in profit), saved by the state (a state share over 30%: debt written off for shares), bought by a
##    rival with money — or liquidated: it leaves the game, its customers and people go to its rivals.
## 2. Births (20.10). N ~ Poisson(0.5 + 20 · GDP share + occasions) a year per country, × «множитель» (the mod
##    has the biggest companies, not every startup). Occasions: a science breakthrough (+1, IT, chips, pharma),
##    a booming sector (+0.5), a war (+0.5, defence). Capital C₀ = min(2 bn, e^N(ln 50 mln, 1)); the rest is
##    counted like the player's founding (founding.gd).
## 3. Mergers of equals (20.6): two healthy companies of one market and country, 0.5–2× in size, 2% a year;
##    the competition authority may block it. Integration stress: +5% to the breakup chance in the first year,
##    fading over the second, and a dip in the staff's mood.
## 4. Relocation (20.7). A company of the player's country with trust in the state below 30% that has already
##    threatened (the escalation ladder, 8 weeks to react) moves to the most attractive country:
##    A = 0.3 (1 − tax) + 0.2 stability + 0.2 infrastructure + 0.2 market + 0.1 (1 − corruption),
##    P(year) = 0.4 · mobility · (0.3 − T) / 0.3 · max(0, A_best − A_own). Low mobility — only a site leaves.
## 5. Share buybacks (20.15): a rich and stable company buys back and cancels a part of its free float.
## 6. Heads change with the owners: a new parent puts its man in charge, bankruptcy brings a temporary manager,
##    nationalisation — a civil servant. The former heads are kept.
## 7. Companies at war (20.20): a site in a province taken by another country is destroyed (0.5 I), confiscated
##    (0.3) or frozen (the rest); a captured headquarters — destruction, nationalisation, a change of country
##    or survival by weights. Frozen sites come back with the province.

const Zones := preload("res://mods/pax_corporations/src/zones/zones.gd")
const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")
const Debt := preload("res://mods/pax_corporations/src/companies/debt.gd")
const Events := preload("res://mods/pax_corporations/src/news/events.gd")
const Founding := preload("res://mods/pax_corporations/src/founding/founding.gd")
const Rivals := preload("res://mods/pax_corporations/src/companies/rivals.gd")
const Stakes := preload("res://mods/pax_corporations/src/market/stakes.gd")

## Brand names of the companies born in the game: a prefix and the sector's ending (ru / en).
const PREFIX_RU := ["Нова", "Тех", "Гео", "Прайм", "Альта", "Вектор", "Сигма", "Орион", "Терра", "Квант", "Север", "Атлас", "Мега", "Стелла", "Глобал", "Ника"]
const PREFIX_EN := ["Nova", "Tech", "Geo", "Prime", "Alta", "Vector", "Sigma", "Orion", "Terra", "Quant", "North", "Atlas", "Mega", "Stella", "Global", "Nika"]
const SUFFIX := {
	"oil_gas": ["oil", "Oil"], "metallurgy": ["металл", "Metal"], "энергетика": ["энерго", "Energy"], "it": ["софт", "Soft"],
	"semiconductors": ["чип", "Chip"], "banks": ["bank", "Bank"], "pharma": ["фарм", "Pharm"], "defence": ["оборон", "Defence"],
	"авиа": ["авиа", "Air"], "tourism": ["тур", "Travel"], "auto_industry": ["моторс", "Motors"], "retail": ["маркет", "Market"],
	"медиа": ["медиа", "Media"], "строительство": ["regime", "Build"],
	"ии": ["нейро", "AI"], "наука": ["лаб", "Lab"], "космос": ["космос", "Space"],
}

var news: Array = []                 # this week's: {c, entry, tone, size, big}
var world: Array = []                # the world's chronicle of births and deaths: {день, вид, id, название, страна}
var stats: Dictionary = {}
var events_for_letters: Array = []   # this week's for letters.gd: {вид, c, …}
var _owners0: Dictionary = {}        # province id -> its owner when the mod first looked (war checks)
var _moved: Dictionary = {}          # company id -> its country now (relocations, captures)
var _heads: Dictionary = {}          # company id -> {глава, прежние_главы} of the companies whose head changed
var _born := 0
var _week := 0
var _rng := RandomNumberGenerator.new()


func start_new() -> void:
	_rng.randomize()


func _cfg(db: Data) -> Dictionary:
	return db.balance.get("lifecycle", {})


# ---------- weekly ----------

func step(db: Data, game: PaxGame, goods: Goods, debt: Debt, events: Events, rivals: Rivals, day: int) -> void:
	news.clear()
	events_for_letters.clear()
	_goods_ref = goods
	_rivals_ref = rivals
	_week += 1
	var cfg := _cfg(db)
	var changed := false
	_new_heads(db, day)
	changed = _bankruptcy(db, goods, events, cfg, day) or changed
	_buybacks(db, cfg, day)
	changed = _expansion(db, cfg, day) or changed
	changed = _mergers(db, goods, debt, cfg, day) or changed
	changed = _relocations(db, game, goods, events, cfg, day) or changed
	if _week % maxi(1, int(cfg.get("war_once_in_weeks", 2))) == 0:
		changed = _war_damage(db, game, cfg, day) or changed
	changed = _births(db, game, goods, events, cfg, day) or changed
	_ipos(db, cfg, day)
	changed = _consolidate(db, goods, debt, cfg, day) or changed
	_integration(db)
	# Every week: a newborn gets its economy only in the economy phase, so its market shares are counted on the
	# week after its birth (baseline() only touches companies without shares — cheap when there are none).
	goods.baseline(db)
	if changed:
		db.version += 1


# ---------- 1. bankruptcy (20.3) ----------

## The yearly bankruptcy chance σ(z) with its parts (for the dossier).
func bankruptcy_chance(db: Data, c: Dictionary, crisis: bool) -> Dictionary:
	var cfg: Dictionary = _cfg(db).get("банкротство", {})
	var e := db.econ(c)
	var r := maxf(float(e.get("R", 1.0)), 1.0)
	# A bank's «debt» is its depositors' money, not loans it has to roll over — it is not counted (debt.gd).
	var l := 0.0 if str(c.get("sector", "")) == "banks" else float(e.get("debt", 0.0)) / r
	var m := clampf(float(e.get("P", 0.0)) / r, -1.0, 1.0)
	var s := _status(c, "stability", 60.0) / 100.0
	var k := _status(c, "corruption", 30.0) / 100.0
	var g := db.state_share(c)
	var parts: Array = [["base", -5.0 + float(cfg.get("shift", 0.0))], ["debt", 1.2 * minf(l, 6.0)], ["margin", -8.0 * m],
		["stability", 2.0 * (1.0 - s)], ["corruption", 1.5 * k], ["crisis", 1.5 if crisis else 0.0], ["state", -2.0 * g]]
	var z := 0.0
	for p in parts:
		z += float(p[1])
	return {"value": 1.0 / (1.0 + exp(-z)), "parts": parts}


static func _status(c: Dictionary, key: String, fallback: float) -> float:
	return float(((c.get("_statuses", {}) as Dictionary).get(key, {}) as Dictionary).get("value", fallback))


func _bankruptcy(db: Data, goods: Goods, events: Events, cfg_all: Dictionary, day: int) -> bool:
	var cfg: Dictionary = cfg_all.get("банкротство", {})
	var crisis := events.crisis_on() if events != null else false
	var weeks_hard := int(cfg.get("hard_trigger_weeks", 4))
	var weeks_manager := int(cfg.get("manager_weeks", 12))
	var removed := false
	for item in db.companies.duplicate():
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty() or not c.has("_q"):
			continue
		var proc: Dictionary = e.get("банкротство", {})
		if not proc.is_empty():
			proc["weeks"] = int(proc["weeks"]) - db.dt
			if int(proc["weeks"]) <= 0:
				removed = _resolve(db, goods, c, e, cfg, day) or removed
			continue
		# The hard trigger: CCC or worse and no money week after week.
		var bad := float(c.get("_q", 0.5)) < 0.4 and float(e.get("money", 0.0)) < 0.0
		e["trouble_weeks"] = int(e.get("trouble_weeks", 0)) + 1 if bad else 0
		var hit := int(e["trouble_weeks"]) >= weeks_hard
		# The roll only for a company in distress (a loss or no money): a profitable one pays its debts, however
		# big — utilities and landlords live with a high debt to revenue for decades.
		var distress := float(e.get("P", 0.0)) < 0.0 or float(e.get("money", 0.0)) < 0.0
		if not hit and distress:
			var yearly := float(bankruptcy_chance(db, c, crisis)["value"])
			hit = _rng.randf() < 1.0 - pow(1.0 - yearly * db.tree(c, "банкротство", 1.0) * db.cfx_c(c, "country_bankruptcy"), float(db.dt) / 52.0)
		if hit:
			_start_procedure(db, c, e, weeks_manager, day)
	return removed


func _start_procedure(db: Data, c: Dictionary, e: Dictionary, weeks: int, day: int) -> void:
	e["банкротство"] = {"from_day": day, "weeks": weeks}
	e["trouble_weeks"] = 0
	e["шок"] = float(e.get("шок", 0.0)) + log(0.6)
	e["H"] = clampf(float(e.get("H", 0.5)) - 0.15, 0.02, 0.98)
	replace_head(db, c, "временный_управляющий", day, "банкротство")
	stats["procedures"] = int(stats.get("procedures", 0)) + 1
	_note(c, day, {"вид": "банкротство", "что": "управляющий", "weeks": weeks}, "bad", 0.6, true)
	events_for_letters.append({"вид": "банкротство", "c": c})


## The end of the temporary manager's term: rescued, saved by the state, sold or liquidated.
func _resolve(db: Data, goods: Goods, c: Dictionary, e: Dictionary, cfg: Dictionary, day: int) -> bool:
	e.erase("банкротство")
	if float(e.get("P", 0.0)) > 0.0 and float(c.get("_q", 0.0)) >= 0.35:
		_note(c, day, {"вид": "банкротство", "что": "спасена"}, "good", 0.4, false)
		stats["rescued"] = int(stats.get("rescued", 0)) + 1
		return false
	if db.state_share(c) > 0.3 or bool(e.get("state_rescue", false)):
		# The state writes the debt off and takes shares for it (debt.gd's quiet nationalisation).
		var amount := float(e.get("debt", 0.0)) * float(cfg.get("write_off_by_state", 0.6))
		_write_off(e, amount)
		Debt.dilute(c, {"кто": {"ru": "Государство (санация)", "en": "The state (rescue)"}, "type": "polity",
			"country": str(c.get("_country", ""))}, clampf(amount / (db.cap(c) + amount), 0.1, 0.6))
		Stakes._retype(db, c)
		replace_head(db, c, "госслужащий", day, "санация")
		e.erase("state_rescue")
		_note(c, day, {"вид": "банкротство", "что": "санация", "count_value": amount}, "neutral", 0.5, false)
		stats["rescues_count"] = int(stats.get("rescues_count", 0)) + 1
		return false
	var buyer := _buyer_for(db, goods, c)
	if not buyer.is_empty():
		var price := db.cap(c) * float(cfg.get("sale_price", 0.5))
		db.econ(buyer)["money"] = float(db.econ(buyer)["money"]) - price
		_write_off(e, float(e.get("debt", 0.0)) * 0.5)
		c["owners"] = [{"кто": (buyer["название"] as Dictionary).duplicate(), "type": "company", "country": str(buyer.get("_country", "")),
			"company": str(buyer["id"]), "доля": 1.0}]
		c["_owners_changed"] = true
		Stakes._retype(db, c)
		replace_head(db, c, "ставленник_владельца", day, "sale")
		_note(c, day, {"вид": "банкротство", "что": "продана", "rival": str(buyer["id"]), "count_value": price}, "neutral", 0.5, true)
		stats["sold"] = int(stats.get("sold", 0)) + 1
		return false
	liquidate(db, goods, c, day, "ликвидация")
	return true


func _write_off(e: Dictionary, amount: float) -> void:
	var left := amount
	for loan in e.get("loans", []):
		var take := minf(left, float((loan as Dictionary)["amount"]))
		(loan as Dictionary)["amount"] = float((loan as Dictionary)["amount"]) - take
		left -= take
	e["loans"] = (e.get("loans", []) as Array).filter(func(l): return float((l as Dictionary)["amount"]) > 0.001)
	e["debt"] = maxf(0.0, float(e.get("debt", 0.0)) - amount)


## A rival of the same goods and country with money for it (not one that is itself going under).
func _buyer_for(db: Data, goods: Goods, c: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for cid in goods.members.get(goods.home_pool(c), []):
		var o := db.company(str(cid))
		if o.is_empty() or str(o["id"]) == str(c["id"]) or Rivals.same_group(c, o):
			continue
		var eo := db.econ(o)
		if eo.has("банкротство") or float(eo.get("money", 0.0)) < db.cap(c) * 0.5 or db.cap(o) < db.cap(c):
			continue
		if best.is_empty() or db.cap(o) > db.cap(best):
			best = o
	return best


## The company leaves the game. Its customers go to its rivals (their demand grows by what they take of its
## sales), its people follow the work; holdings it had in others go to the free float. A line stays in the
## world's chronicle.
func liquidate(db: Data, goods: Goods, c: Dictionary, day: int, why: String) -> void:
	var e := db.econ(c)
	var cid := str(c["id"])
	var take := float(_cfg(db).get("share_to_rivals", 0.6))
	var dead_r := float(e.get("R", 0.0))
	var pool: Array = goods.members.get(goods.home_pool(c), [])
	if pool.size() < 2:
		pool = goods.members.get(goods.world_pool(c), [])
	var rivals: Array = []
	var total := 0.0
	for x in pool:
		var o := db.company(str(x))
		if o.is_empty() or str(o["id"]) == cid:
			continue
		rivals.append(o)
		total += float(db.econ(o).get("R", 0.0))
	for o in rivals:
		var eo := db.econ(o)
		var part := dead_r * take * float(eo.get("R", 0.0)) / maxf(total, 1e-6)
		var k := 1.0 + part / maxf(float(eo.get("R", 1.0)), 1.0)
		eo["demand"] = float(eo["demand"]) * k
		for key in ["home_share0", "world_share0"]:
			if eo.has(key):
				eo[key] = float(eo[key]) * k
	for item in db.companies:
		var owners: Array = (item as Dictionary).get("owners", [])
		for o in owners:
			if str((o as Dictionary).get("company", "")) == cid:
				(o as Dictionary)["type"] = "частные"
				(o as Dictionary).erase("company")
				(item as Dictionary)["_owners_changed"] = true
	world.append({"день": day, "вид": why, "id": cid, "название": c.get("название", cid), "country": str(c.get("_country", ""))})
	while world.size() > 200:
		world.pop_front()
	stats[why] = int(stats.get(why, 0)) + 1
	var entry := {"вид": "банкротство", "что": why, "день": day}
	(c["_chronicle"] as Array).append(entry)
	news.append({"c": c, "entry": entry, "tone": "bad", "size": 0.8, "big": true})
	events_for_letters.append({"вид": "ликвидация", "c": c})
	db.remove_company(cid, day, why)


# ---------- 2. births (20.10) ----------

func _births(db: Data, game: PaxGame, goods: Goods, events: Events, cfg_all: Dictionary, day: int) -> bool:
	var cfg: Dictionary = cfg_all.get("births", {})
	if db.companies.size() >= int(cfg.get("companies_limit", 1400)):
		return false
	var mult := float(cfg.get("множитель", 0.1))
	var world_w := maxf(goods.now_world, 1e-6)
	var any := false
	for country in db.countries.keys():
		var name := str(country)
		var occasions := 0.0
		var reason := ""
		var sig: Dictionary = events.signals.get(name, {}) if events != null else {}
		if float(sig.get("breakthrough", 0.0)) > 0.5:
			occasions += 1.0
			reason = "breakthrough"
		var trends: Dictionary = events.country_trends.get(name, {}) if events != null else {}
		var boom := ""
		for s in trends.keys():
			if float(trends[s]) > 0.5:
				occasions += 0.5
				boom = str(s)
		if float(sig.get("война", 0.0)) > 0.5:
			occasions += 0.5
			if reason.is_empty():
				reason = "война"
		if reason.is_empty() and not boom.is_empty():
			reason = "бум"
		var lam := (0.5 + 20.0 * float(goods.now_people.get(name, 0.0)) / world_w + occasions) * mult * db.cfx(name, "birth")
		if _rng.randf() >= 1.0 - exp(-lam * db.dt / 52.0):
			continue
		var c := _give_birth(db, game, goods, events, name, reason, boom, cfg, day)
		if not c.is_empty():
			any = true
	return any


func _give_birth(db: Data, game: PaxGame, goods: Goods, events: Events, country: String, reason: String, boom: String,
		cfg: Dictionary, day: int) -> Dictionary:
	var home: Array = db.companies.filter(func(x): return str(x.get("_country", "")) == country)
	if home.is_empty():
		return {}
	var sector := _pick_sector(db, home, reason, boom)
	var goods_key := _pick_goods(db, sector)
	if goods_key.is_empty():
		return {}
	var capital := minf(float(cfg.get("capital_max", 2000.0)), exp(log(float(cfg.get("capital_median", 50.0))) + _rng.randfn(0.0, 1.0)))
	var p := Founding.propose(db, goods, events, country, goods_key, capital)
	if not bool(p.get("ok", false)):
		return {}
	var hq := db.hq_of(home[_rng.randi_range(0, home.size() - 1)])
	if hq.is_empty() or not hq.has("province"):
		return {}
	var names := _brand(db, sector)
	var year := int(game.date().get("year", 2026))
	var place := {"province": int(hq["province"]), "ш": float(hq.get("ш", 0.0)), "д": float(hq.get("д", 0.0)),
		"name_ru": str((hq.get("name", {}) as Dictionary).get("ru", "")) if hq.get("name") is Dictionary else str(hq.get("name", "")),
		"имя_en": str((hq.get("name", {}) as Dictionary).get("en", "")) if hq.get("name") is Dictionary else str(hq.get("name", ""))}
	var spec := {"название": names[0], "description": "", "goods_key": goods_key, "country": country, "место": place, "capital": capital,
		"polity": false, "founder": Founding.invent_person(db, _rng), "год": year, "день": day}
	var c := Founding.build(db, p, spec, _rng)
	_born += 1
	while not db.company("born_%d" % _born).is_empty():
		_born += 1
	c["id"] = "born_%d" % _born
	c.erase("made_by_player")
	c["название"] = {"ru": names[0], "en": names[1]}
	var why_key := "birth_desc_" + (reason if not reason.is_empty() else "обычно")
	var desc := db.mod.tr_key("pax_corporations_" + why_key) % [year, db.sector_name(sector)]
	c["description"] = {"ru": desc, "en": desc}
	c["born_f"] = reason if not reason.is_empty() else "обычно"
	c["_chronicle"] = [{"день": day, "вид": "birth", "что": c["born_f"], "count_value": capital}]
	db.add_company(c)
	stats["births_count"] = int(stats.get("births_count", 0)) + 1
	world.append({"день": day, "вид": "birth", "id": str(c["id"]), "название": c["название"], "country": country})
	news.append({"c": c, "entry": c["_chronicle"][0], "tone": "good", "size": 0.3, "big": false})
	events_for_letters.append({"вид": "birth", "c": c})
	return c


## A sector for a newborn: the occasion's, else weighted by how common the sector is in the world, ×3 where
## the country has fewer than two companies of it (20.19 «new rivals»).
func _pick_sector(db: Data, home: Array, reason: String, boom: String) -> String:
	if reason == "breakthrough":
		return ["it", "semiconductors", "pharma", "ии", "наука", "космос"][_rng.randi_range(0, 5)]
	if reason == "война":
		return "defence"
	if reason == "бум" and db.sectors.has(boom):
		return boom
	var world_count := {}
	for item in db.companies:
		var s := str((item as Dictionary).get("sector", ""))
		world_count[s] = int(world_count.get(s, 0)) + 1
	var home_count := {}
	for item in home:
		var s := str((item as Dictionary).get("sector", ""))
		home_count[s] = int(home_count.get(s, 0)) + 1
	var total := 0.0
	var options: Array = []
	for s in db.sectors.keys():
		var w := float(world_count.get(s, 0)) * (3.0 if int(home_count.get(s, 0)) < 2 else 1.0)
		options.append([str(s), w])
		total += w
	var x := _rng.randf() * total
	for o in options:
		x -= float(o[1])
		if x <= 0.0:
			return str(o[0])
	return str(db.sectors.keys()[0])


## The goods a newborn of this sector sells: one the sector's companies sell, likelier the more common.
func _pick_goods(db: Data, sector: String) -> String:
	var list: Array = []
	for item in db.companies:
		var c: Dictionary = item
		if str(c.get("sector", "")) == sector and (db.goods.get("goods", {}) as Dictionary).has(str(c.get("profile", ""))):
			list.append(str(c["profile"]))
	return str(list[_rng.randi_range(0, list.size() - 1)]) if not list.is_empty() else ""


func _brand(db: Data, sector: String) -> Array:
	var end: Array = SUFFIX.get(sector, ["тех", "Tech"])
	for attempt in 12:
		var i := _rng.randi_range(0, PREFIX_RU.size() - 1)
		var ru := str(PREFIX_RU[i]) + str(end[0])
		var en := str(PREFIX_EN[i]) + str(end[1])
		if attempt >= 6:
			var n := _rng.randi_range(2, 99)
			ru += " %d" % n
			en += " %d" % n
		var taken := false
		for item in db.companies:
			if db.text((item as Dictionary).get("название", "")) in [ru, en]:
				taken = true
				break
		if not taken:
			return [ru, en]
	return ["%s %d" % [str(end[0]).capitalize(), _born], "%s %d" % [str(end[1]), _born]]


# ---------- 3. mergers of equals (20.6) ----------

func _mergers(db: Data, goods: Goods, debt: Debt, cfg_all: Dictionary, day: int) -> bool:
	var cfg: Dictionary = cfg_all.get("mergers", {})
	var chance := float(cfg.get("chance_per_year", 0.02)) * db.dt / 52.0
	var pause := int((db.balance.get("competition", {}) as Dictionary).get("deal_pause_days", 364))
	var any := false
	for pool in goods.members.keys():
		if not str(pool).begins_with("дом|"):
			continue
		var ids: Array = goods.members[pool]
		if ids.size() < 2 or _rng.randf() >= chance * ids.size() / 2.0:
			continue
		var a := db.company(str(ids[_rng.randi_range(0, ids.size() - 1)]))
		var b := db.company(str(ids[_rng.randi_range(0, ids.size() - 1)]))
		if a.is_empty() or b.is_empty() or str(a["id"]) == str(b["id"]) or Rivals.same_group(a, b):
			continue
		if db.cap(b) > db.cap(a):
			var t := a
			a = b
			b = t
		var ratio := db.cap(b) / maxf(db.cap(a), 1e-6)
		var ea := db.econ(a)
		var eb := db.econ(b)
		if ratio < 0.5 or db.state_share(a) > 0.5 or db.state_share(b) > 0.5 or ea.has("банкротство") or eb.has("банкротство") \
				or _status(a, "stability", 0.0) < 50.0 or _status(b, "stability", 0.0) < 50.0 \
				or day - int(ea.get("deal_day", -99999)) < pause or day - int(eb.get("deal_day", -99999)) < pause:
			continue
		# The competition authority looks at the joint share of the home market.
		var joint := float(ea.get("home_share", 0.0)) + float(eb.get("home_share", 0.0))
		var country := str(a.get("_country", ""))
		if joint > float(cfg.get("antitrust_threshold", 0.35)) \
				and _rng.randf() < clampf(float(cfg.get("antitrust_ban", 0.6)) * db.antitrust(country), 0.0, 0.98):
			_note(a, day, {"вид": "слияние", "что": "ban", "rival": str(b["id"])}, "neutral", 0.3, false)
			stats["mergers_forbidden"] = int(stats.get("mergers_forbidden", 0)) + 1
			events_for_letters.append({"вид": "antitrust_ban", "c": a, "b": b})
			continue
		merge(db, debt, a, b, day)
		any = true
	return any


## b joins a: its people, business, money, debt, sites and holders; a's price rises by b's value.
func merge(db: Data, debt: Debt, a: Dictionary, b: Dictionary, day: int, how: String = "слияние") -> void:
	var ea := db.econ(a)
	var eb := db.econ(b)
	var cap_a := db.cap(a)
	var cap_b := db.cap(b)
	var da := _demand_of(ea)
	var db_ := _demand_of(eb)
	var scale := db_ / maxf(da, 1e-6)   # b's starting numbers in a's terms (they share one demand from now on)
	var na := float(ea["N"])
	var nb := float(eb["N"])
	var ra := float(ea["R0"])
	var rb := float(eb["R0"]) * scale
	ea["c_nl"] = (float(ea["c_nl"]) * ra + float(eb["c_nl"]) * rb) / maxf(ra + rb, 1e-6)
	for key in ["R0", "D0"]:
		ea[key] = float(ea[key]) + float(eb[key]) * scale
	for key in ["P0", "cap0", "money", "R", "P", "фот", "fair", "home_share0", "world_share0"]:
		if ea.has(key) or eb.has(key):
			ea[key] = float(ea.get(key, 0.0)) + float(eb.get(key, 0.0))
	ea["W"] = (float(ea["W"]) * na + float(eb["W"]) * nb) / maxf(na + nb, 1.0)
	ea["market_wage"] = (float(ea["market_wage"]) * na + float(eb["market_wage"]) * nb) / maxf(na + nb, 1.0)
	ea["N"] = na + nb
	var shares: Array = []
	for v in ea.get("site_shares", []):
		shares.append(float(v) * na / maxf(na + nb, 1.0))
	for v in eb.get("site_shares", []):
		shares.append(float(v) * nb / maxf(na + nb, 1.0))
	ea["site_shares"] = shares
	if not (ea.get("loans") is Array):
		ea["loans"] = []
	(ea["loans"] as Array).append_array(eb.get("loans", []))
	debt._sum(ea)
	var grow := (na + nb) / maxf(na, 1.0)
	ea["headcount_history"] = (ea.get("headcount_history", []) as Array).map(func(v): return float(v) * grow)
	ea["H"] = clampf(float(ea.get("H", 0.5)) - float((_cfg(db).get("mergers", {}) as Dictionary).get("satisfaction", 0.05)), 0.02, 0.98)
	ea["merger_day"] = day
	ea["deal_day"] = day
	var pts: Array = a.get("sites", [])
	pts.append_array((b.get("sites", []) as Array).duplicate(true))
	a["sites"] = pts
	a["_sites_changed"] = true
	# Holders: each keeps its value, so its part of the joint company is value / joint value.
	var total := cap_a + cap_b
	var owners: Array = []
	for pair in [[a, cap_a], [b, cap_b]]:
		for o in (pair[0] as Dictionary).get("owners", []):
			var od: Dictionary = (o as Dictionary).duplicate(true)
			if str(od.get("company", "")) in [str(a["id"]), str(b["id"])]:
				continue
			od["доля"] = float(od.get("доля", 0.0)) * float(pair[1]) / maxf(total, 1e-6)
			var same := owners.filter(func(x): return db.text(x.get("кто", "")) == db.text(od.get("кто", "")) and str(x.get("type", "")) == str(od.get("type", "")))
			if same.is_empty():
				owners.append(od)
			else:
				(same[0] as Dictionary)["доля"] = float((same[0] as Dictionary)["доля"]) + float(od["доля"])
	a["owners"] = owners
	a["_owners_changed"] = true
	var k := total / maxf(cap_a, 1e-6)
	a["_price"] = db.price(a) * k
	a["_history"] = (a["_history"] as Array).map(func(v): return float(v) * k)
	# Holdings b had in other companies pass to a.
	for item in db.companies:
		for o in (item as Dictionary).get("owners", []):
			if str((o as Dictionary).get("company", "")) == str(b["id"]):
				(o as Dictionary)["company"] = str(a["id"])
				(o as Dictionary)["кто"] = (a["название"] as Dictionary).duplicate()
				(item as Dictionary)["_owners_changed"] = true
	stats["mergers_count"] = int(stats.get("mergers_count", 0)) + 1
	var buyout := how == "buyout"
	_note(a, day, {"вид": "слияние", "что": "выкупила" if buyout else "слились", "rival": str(b["id"]), "count_value": cap_b}, "neutral", 0.3 if buyout else 0.6, not buyout)
	(b["_chronicle"] as Array).append({"день": day, "вид": "слияние", "что": "выкуплена" if buyout else "вошла", "rival": str(a["id"])})
	world.append({"день": day, "вид": "слияние", "id": str(b["id"]), "название": b.get("название", ""), "country": str(b.get("_country", "")), "in_value": str(a["id"])})
	events_for_letters.append({"вид": "слияние", "c": a, "b": b})
	db.remove_company(str(b["id"]), day, "слияние")


static func _demand_of(e: Dictionary) -> float:
	return float(e.get("demand", 1.0)) * float(e.get("climate_demand", 1.0)) * float(e.get("crisis_demand", 1.0)) \
		* float(e.get("event_demand", 1.0)) * float(e.get("market_demand", 1.0))


## Integration stress of a merger: +5 points to the breakup chance in the first year, fading over the second.
func _integration(db: Data) -> void:
	var today := Pax.game.day() if Pax.game != null else 0
	var size := float((_cfg(db).get("mergers", {}) as Dictionary).get("stress", 5.0))
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if not e.has("merger_day"):
			continue
		var weeks := float(today - int(e["merger_day"])) / 7.0
		var v := size if weeks < 52.0 else size * maxf(0.0, 1.0 - (weeks - 52.0) / 52.0)
		if v <= 0.0:
			e.erase("merger_day")
			c.erase("_integration")
		else:
			c["_integration"] = v


# ---------- 4. relocation (20.7) ----------

func _relocations(db: Data, game: PaxGame, goods: Goods, events: Events, cfg_all: Dictionary, day: int) -> bool:
	var cfg: Dictionary = cfg_all.get("переезд", {})
	var player := str(game.player_faction().get("name", ""))
	var wait := int(cfg.get("wait_after_threat_days", 56))
	var low := float(cfg.get("trust_threshold", 30.0))
	var attract := {}
	var any := false
	for item in db.companies.duplicate():
		var c: Dictionary = item
		var e := db.econ(c)
		if str(c.get("_country", "")) != player or e.is_empty() or not e.has("threat_day"):
			continue
		if db.tree(c, "переезд", 1.0) <= 0.0:
			continue   # a foreign investor's blocking stake keeps the company where it is (investments.gd)
		var t := float(e.get("trust", 50.0))
		if t >= low or day - int(e["threat_day"]) < wait:
			continue
		if attract.is_empty():
			attract = _attractiveness(db, game, goods, events, player)
		var own := float(attract.get(player, 0.5))
		var best := ""
		var best_a := own
		var kcfg: Dictionary = db.balance.get("competition", {})
		for country in attract.keys():
			var za := float(attract[country]) + Zones.move_bonus(player, str(country))   # one zone: an easier move
			if str(country) != player and za > best_a and Rivals.open_border(kcfg, player, str(country)) \
					and not Zones.closed(str(country), player):
				best = str(country)
				best_a = za
		if best.is_empty():
			continue
		var mobility := float(db.sector_of(c).get("mobility", 0.3))
		var yearly := 0.4 * mobility * (low / 100.0 - t / 100.0) / (low / 100.0) * (best_a - own) * float(cfg.get("множитель", 1.0))
		if _rng.randf() >= yearly * db.dt / 52.0:
			continue
		e.erase("threat_day")
		if mobility < float(cfg.get("hq_from_mobility", 0.3)):
			_move_site(db, c, e, best, day)
		else:
			_move_hq(db, c, e, best, day)
			any = true
	return any


## Attractiveness of every country with companies (20.7).
func _attractiveness(db: Data, game: PaxGame, goods: Goods, events: Events, player: String) -> Dictionary:
	var out := {}
	var top := 1.0
	for country in db.countries.keys():
		top = maxf(top, float(goods.now_people.get(str(country), 0.0)))
	var tax_default := float((db.balance.get("staff", {}) as Dictionary).get("tax_default", 0.2))
	var tax_player := tax_default
	var farms: Variant = game.main.get("хозяйства")
	if farms is Dictionary:
		tax_player = float(((farms as Dictionary).get(game.home_body(), {}) as Dictionary).get("tax", tax_default))
	for country in db.countries.keys():
		var name := str(country)
		var sig: Dictionary = events.signals.get(name, {}) if events != null else {}
		var stability := clampf(1.0 - 0.6 * float(sig.get("война", 0.0)) - 0.4 * float(sig.get("санкции", 0.0)), 0.0, 1.0)
		var infra := clampf(0.5 + (1.0 - db.dept(name, "издержки", 1.0)) / 0.04, 0.0, 1.0)
		if db.cond_index.has(name):
			infra = float(db.cond_index[name])   # the country's conditions (conditions.gd) instead of the roads alone
		var market := clampf(log(1.0 + float(goods.now_people.get(name, 0.0))) / log(1.0 + top), 0.0, 1.0)
		var tax := tax_player if name == player else tax_default
		out[name] = 0.3 * (1.0 - tax) + 0.2 * stability + 0.2 * infra + 0.2 * market + 0.1 * (1.0 - db.country_corruption(name)) \
			+ 0.1 * float(db.prestige.get(name, 50.0)) / 100.0   # prestige draws companies (arena.gd)
	return out


## Low mobility: the biggest site in the country closes and its work moves abroad; the company shrinks.
func _move_site(db: Data, c: Dictionary, e: Dictionary, to: String, day: int) -> void:
	var shares: Array = e.get("site_shares", [])
	var hq := db.hq_of(c)
	var pts: Array = c.get("sites", [])
	var best := -1
	for i in pts.size():
		if pts[i] == hq or i >= shares.size() or str((pts[i] as Dictionary).get("_status", "")) != "":
			continue
		if best < 0 or float(shares[i]) > float(shares[best]):
			best = i
	if best < 0:
		return
	var s := float(shares[best])
	_lose_site(c, e, best, "переехала")
	stats["site_moves"] = int(stats.get("site_moves", 0)) + 1
	_note(c, day, {"вид": "переезд", "что": "site", "site": best, "country": to, "доля": s}, "bad", 0.5, true)
	events_for_letters.append({"вид": "переезд_точки", "c": c, "country": to})


## High mobility: the headquarters (and the company's home) moves to another country.
func _move_hq(db: Data, c: Dictionary, e: Dictionary, to: String, day: int) -> void:
	var from := str(c.get("_country", ""))
	var there: Array = db.companies.filter(func(x): return str(x.get("_country", "")) == to)
	if there.is_empty():
		return
	var place := db.hq_of(there[_rng.randi_range(0, there.size() - 1)]).duplicate(true)
	var hq := db.hq_of(c)
	var pts: Array = c.get("sites", [])
	for i in pts.size():
		if pts[i] == hq:
			for k in ["ш", "д", "province", "name"]:
				if place.has(k):
					(pts[i] as Dictionary)[k] = place[k]
	c["_sites_changed"] = true
	set_country(db, c, to)
	e["trust"] = 50.0
	e.erase("ladder")
	stats["moves_count"] = int(stats.get("moves_count", 0)) + 1
	_note(c, day, {"вид": "переезд", "что": "штаб", "country": to, "откуда": from}, "bad", 0.8, true)
	events_for_letters.append({"вид": "переезд", "c": c, "country": to, "откуда": from})


## A company's home country changes (relocation, a captured headquarters): its home market is the new
## country's (goods.gd recounts its starting shares), the change is saved.
func set_country(db: Data, c: Dictionary, to: String) -> void:
	c["_country"] = to
	_moved[str(c["id"])] = to
	db._hq.erase(str(c["id"]))
	var e := db.econ(c)
	for key in ["home_share0", "world_share0", "popularity0"]:
		e.erase(key)
	e["market_wage"] = float(db.country_info(to).get("average_wage", 1000.0)) * float(db.sector_of(c).get("wage_premium", 1.0))


## A site stops working for good (moved abroad, destroyed): the business shrinks by its part of the people.
func _lose_site(c: Dictionary, e: Dictionary, i: int, status: String) -> void:
	var shares: Array = e.get("site_shares", [])
	if i >= shares.size():
		return
	var s := clampf(float(shares[i]), 0.0, 0.9)
	for key in ["N", "D0", "R0", "P0", "cap0", "нужно", "fair"]:
		if e.has(key):
			e[key] = float(e[key]) * (1.0 - s)
	shares[i] = 0.0
	var sum := 0.0
	for v in shares:
		sum += float(v)
	e["site_shares"] = shares.map(func(v): return float(v) / sum if sum > 0.0 else 0.0)
	e["strikes"] = (e.get("strikes", []) as Array).filter(func(x): return int((x as Dictionary).get("site", -1)) != i)
	e["шок"] = float(e.get("шок", 0.0)) + log(maxf(0.1, 1.0 - s))
	((c.get("sites", []) as Array)[i] as Dictionary)["_status"] = status
	c["_sites_changed"] = true


# ---------- 5. buybacks ----------

func _buybacks(db: Data, cfg_all: Dictionary, day: int) -> void:
	var cfg: Dictionary = cfg_all.get("buyout", {})
	var chance := float(cfg.get("chance_per_year", 0.15)) * db.dt / 52.0
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty() or float(e.get("P", 0.0)) <= 0.0 or e.has("банкротство"):
			continue
		if float(e.get("money", 0.0)) < float(cfg.get("money_from_revenue", 0.3)) * float(e.get("R", 1.0)) \
				or _status(c, "stability", 0.0) < 60.0 or Stakes.free_float(c) < 0.15:
			continue
		if _rng.randf() < chance:
			var f := minf(float(cfg.get("доля", 0.03)), 0.3 * float(e["money"]) / maxf(db.cap(c), 1e-6))
			if Stakes.buyback(db, c, f, day, "buyout") > 0.0:
				stats["buyouts"] = int(stats.get("buyouts", 0)) + 1


# ---------- 5b. expansion: spare money becomes new capacity ----------

## A healthy company that keeps more money than it needs (over «запас_от_выручки» of its revenue) builds: a project
## takes a part of the spare money and «недель» weeks; then the business grows by the money / the capital intensity
## of its goods (goods.json «основание»): people, revenue, the planned size and the value. A big project opens a new
## site in the home country (a factory or an office in another company's city). One project at a time, never while
## the company is still being built (economy.gd «ramp»), in bankruptcy or at a loss.
func _expansion(db: Data, cfg_all: Dictionary, day: int) -> bool:
	var cfg: Dictionary = cfg_all.get("expansion", {})
	var chance := float(cfg.get("chance_per_year", 0.4)) * db.dt / 52.0
	var intensities: Dictionary = (db.goods.get("founding", {}) as Dictionary).get("capital_intensity", {})
	var any := false
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty():
			continue
		var project: Variant = e.get("project")
		if project is Dictionary:
			if int((project as Dictionary).get("until_day", 0)) <= day:
				e.erase("project")
				any = _expansion_done(db, c, e, project as Dictionary, cfg, day) or any
			continue
		if e.has("ramp") or e.has("банкротство") or float(e.get("P", 0.0)) <= 0.0 or _status(c, "stability", 60.0) < 40.0:
			continue
		var revenue := maxf(float(e.get("R", 0.0)), 1.0)
		var spare := float(e.get("money", 0.0)) - float(cfg.get("keep_from_revenue", 0.3)) * revenue - 0.1 * float(e.get("debt", 0.0))
		if spare < maxf(float(cfg.get("min_amount", 5.0)), float(cfg.get("spare_from_revenue", 0.2)) * revenue):
			continue
		# A company that already holds most of its home market has nowhere to grow at home.
		if float(e.get("home_share_mod", 0.0)) >= float(cfg.get("home_share_max", 0.6)):
			continue
		# The more spare money, the likelier a project this week (a reserve of a year's revenue — almost surely).
		if _rng.randf() >= chance * clampf(spare / revenue / float(cfg.get("spare_from_revenue", 0.2)), 1.0, 5.0):
			continue
		var amount := minf(spare * float(cfg.get("share_of_spare", 0.5)), revenue * float(cfg.get("max_from_revenue", 0.3)))
		var weeks := _rng.randi_range(int(cfg.get("weeks_from", 26)), int(cfg.get("weeks_to", 78)))
		var intensity := maxf(0.05, float(intensities.get(str(c.get("profile", "")), 1.0)))
		e["money"] = float(e["money"]) - amount
		e["project"] = {"amount": amount, "growth": clampf(amount / intensity / revenue, 0.0, float(cfg.get("growth_max", 0.2))),
			"from_day": day, "until_day": day + weeks * 7}
		stats["expansion_started"] = int(stats.get("expansion_started", 0)) + 1
		_note(c, day, {"вид": "expansion", "что": "start", "count_value": amount, "weeks": weeks}, "good", 0.3, amount >= float(cfg.get("big_from", 2000.0)))
	return any


func _expansion_done(db: Data, c: Dictionary, e: Dictionary, project: Dictionary, cfg: Dictionary, day: int) -> bool:
	var g := float(project.get("growth", 0.0))
	if g <= 0.0:
		return false
	for key in ["D0", "R0", "P0", "cap0", "fair", "нужно"]:
		if e.has(key):
			e[key] = float(e[key]) * (1.0 + g)
	var site := -1
	if g >= float(cfg.get("new_site_from", 0.12)):
		site = _new_site(db, c, e, g)
	stats["expansion_done"] = int(stats.get("expansion_done", 0)) + 1
	_note(c, day, {"вид": "expansion", "что": "done", "count_value": float(project.get("amount", 0.0)), "доля": g, "site": site},
		"good", 0.4, float(project.get("amount", 0.0)) >= float(cfg.get("big_from", 2000.0)))
	return site >= 0


## A new site for the grown business: in the home country, in the city of another company's site (a province the
## company has no site in yet, if there is one). Its people are the growth's part of the staff. Returns its index.
func _new_site(db: Data, c: Dictionary, e: Dictionary, g: float) -> int:
	var country := str(c.get("_country", ""))
	var mine := {}
	for p in c.get("sites", []):
		if p is Dictionary:
			mine[int((p as Dictionary).get("province", -1))] = true
	var places: Array = []
	var fresh: Array = []
	for item in db.companies:
		var o: Dictionary = item
		if str(o.get("_country", "")) != country or o == c:
			continue
		for p in o.get("sites", []):
			if not (p is Dictionary) or not (p as Dictionary).has("province") or str((p as Dictionary).get("_status", "")) != "":
				continue
			places.append(p)
			if not mine.has(int((p as Dictionary)["province"])):
				fresh.append(p)
	var pool: Array = fresh if not fresh.is_empty() else places
	if pool.is_empty():
		return -1
	var at: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
	var industry := str(c.get("sector", "")) in ["metallurgy", "oil_gas", "auto_industry", "semiconductors", "строительство", "энергетика", "defence", "pharma"]
	var shares: Array = e.get("site_shares", [])
	var part := g / (1.0 + g)
	var site := {"type": "завод" if industry else "office", "name": at.get("name", ""), "ш": float(at.get("ш", 0.0)) + _rng.randf_range(-0.05, 0.05),
		"д": float(at.get("д", 0.0)) + _rng.randf_range(-0.05, 0.05), "province": int(at["province"]), "_pr2": true,
		"staff": int(float(e.get("N", 0.0)) * part), "_grown": true}
	var pts: Array = c.get("sites", [])
	# The shares follow the sites' order; a company with no shares yet gets them evenly first.
	while shares.size() < pts.size():
		shares.append(1.0 / maxf(1.0, float(pts.size())))
	pts.append(site)
	c["sites"] = pts
	e["site_shares"] = shares.map(func(v): return float(v) * (1.0 - part)) + [part]
	c["_sites_changed"] = true
	db.version += 1
	return pts.size() - 1


# ---------- 6. heads ----------

## The parent's man takes over a company it has just bought control of (rivals.gd marks it).
func _new_heads(db: Data, day: int) -> void:
	for item in db.companies:
		var c: Dictionary = item
		if c.has("_new_owner"):
			c.erase("_new_owner")
			replace_head(db, c, "ставленник_владельца", day, "takeover")


## A new head; the former one goes into «прежние_главы». The name comes from the game's lists (founding.gd).
func replace_head(db: Data, c: Dictionary, role: String, day: int, why: String) -> void:
	var lead: Dictionary = c.get("глава", {})
	var past: Array = c.get("former_heads", [])
	past.append({"name": lead.get("name", ""), "роль": lead.get("роль", ""), "с_года": lead.get("с_года", 0), "until_day": day, "почему": why})
	while past.size() > 6:
		past.pop_front()
	c["former_heads"] = past
	var year := int(Pax.game.date().get("year", 2026)) if Pax.game != null else 2026
	var person := Founding.invent_person(db, _rng)
	c["глава"] = {"name": {"ru": person, "en": person}, "роль": role, "с_года": year, "born_year": year - _rng.randi_range(38, 62), "доля": 0.0,
		"характер": lead.get("характер", "")}
	_heads[str(c["id"])] = {"глава": c["глава"], "former_heads": past}
	(c["_chronicle"] as Array).append({"день": day, "вид": "смена_главы", "что": why, "name": person, "роль": role})


# ---------- 7. companies at war (20.20) ----------

func _war_damage(db: Data, game: PaxGame, cfg_all: Dictionary, day: int) -> bool:
	var cfg: Dictionary = cfg_all.get("война", {})
	var owners: Variant = Data.province_owners()
	if not (owners is PackedStringArray or owners is Dictionary):
		return false
	var intensity := float(cfg.get("intensity", 0.5))
	var removed := false
	for item in db.companies.duplicate():
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty():
			continue
		var home := str(c.get("_country", ""))
		var hq := db.hq_of(c)
		var pts: Array = c.get("sites", [])
		for i in pts.size():
			var p: Dictionary = pts[i]
			if not p.has("province"):
				continue
			var pid := int(p["province"])
			var now := Data.owner_in(owners, pid)
			if now.is_empty():
				continue
			if not _owners0.has(pid):
				_owners0[pid] = now
				continue
			var base := str(_owners0[pid])
			var status := str(p.get("_status", ""))
			var captured := now != base and now != home
			if captured and status.is_empty():
				if p == hq:
					removed = _hq_captured(db, c, e, i, now, intensity, cfg, day) or removed
					if db.company(str(c["id"])).is_empty():
						break
				else:
					_site_captured(c, e, i, now, intensity, day)
			elif not captured and status in ["frozen_f", "конфискована"]:
				# Back with its country: a frozen site works again; a confiscated one only when the war is over.
				if status == "frozen_f" or not _at_war(game, home):
					p.erase("_status")
					e["strikes"] = (e.get("strikes", []) as Array).filter(func(x): return int((x as Dictionary).get("site", -1)) != i)
					c["_sites_changed"] = true
					_note(c, day, {"вид": "война_страны", "что": "возврат", "site": i}, "good", 0.3, false)
	return removed


func _site_captured(c: Dictionary, e: Dictionary, i: int, captor: String, intensity: float, day: int) -> void:
	var x := _rng.randf()
	var what := "frozen_f"
	if x < 0.5 * intensity:
		what = "уничтожена"
	elif x < 0.5 * intensity + 0.3:
		what = "конфискована"
	if what == "уничтожена":
		_lose_site(c, e, i, what)
	else:
		var shares: Array = e.get("site_shares", [])
		var people := float(e["N"]) * (float(shares[i]) if i < shares.size() else 0.0)
		(e["strikes"] as Array).append({"site": i, "weeks": 100000, "людей": people, "sabotage": true, "война": true})
		((c["sites"] as Array)[i] as Dictionary)["_status"] = what
		c["_sites_changed"] = true
	stats["точек_" + what] = int(stats.get("точек_" + what, 0)) + 1
	_note(c, day, {"вид": "война_страны", "что": what, "site": i, "country": captor}, "bad", 0.5, true)
	events_for_letters.append({"вид": "точка_захвачена", "c": c, "country": captor})


## The headquarters is taken: the captor nationalises the company, or it falls apart. Nothing else — a company whose
## headquarters stands in a captured province never stays a foreign one there (before, «survived», «rebuilt
## elsewhere» and «changed hands» left it the old country's: the player could not touch it). The state's share and
## a calm war make nationalisation likelier; a fierce war — a collapse (several sites — 2–4 new companies of the
## captor's country, else liquidation).
func _hq_captured(db: Data, c: Dictionary, e: Dictionary, _i: int, captor: String, intensity: float, cfg: Dictionary, day: int) -> bool:
	var w_nat := float(cfg.get("nationalisation_weight", 0.6)) * (1.0 + db.state_share(c))
	var w_fall := float(cfg.get("collapse_weight", 0.4)) * (0.5 + intensity)
	var what := "nationalisation" if _rng.randf() * (w_nat + w_fall) < w_nat else "распад"
	# Whatever happens hits the company: the price crashes, the people are shaken.
	e["шок"] = float(e.get("шок", 0.0)) + log(_rng.randf_range(0.3, 0.7))
	e["H"] = clampf(float(e.get("H", 0.5)) - 0.3, 0.02, 0.98)
	stats["штабов_" + what] = int(stats.get("штабов_" + what, 0)) + 1
	if what == "распад":
		var pts_n := (c.get("sites", []) as Array).size()
		if pts_n >= 3 and _rivals_ref != null:
			# What is left falls apart into 2–4 new companies of the captor's country; the old one is gone (20.20).
			var parts := _rng.randi_range(2, mini(4, pts_n - 1))
			var made: PackedStringArray = []
			for k in parts:
				var child := _rivals_ref.split(db, c, "война", day)
				if child.is_empty():
					break
				set_country(db, child, captor)
				made.append(db.name_of(child))
			if not made.is_empty():
				_note(c, day, {"вид": "война_страны", "что": "breakup", "country": captor, "count_value": made.size()}, "bad", 0.9, true)
				events_for_letters.append({"вид": "штаб_захвачен", "c": c, "country": captor, "что": "breakup"})
				liquidate(db, _goods_ref, c, day, "война_распад")
				return true
		_note(c, day, {"вид": "война_страны", "что": "уничтожена_штаб", "country": captor}, "bad", 0.9, true)
		events_for_letters.append({"вид": "штаб_захвачен", "c": c, "country": captor, "что": "уничтожение"})
		liquidate(db, _goods_ref, c, day, "война")
		return true
	nationalise_by(db, c, captor, day)
	_note(c, day, {"вид": "война_страны", "что": "nationalisation", "country": captor}, "bad", 0.9, true)
	events_for_letters.append({"вид": "штаб_захвачен", "c": c, "country": captor, "что": what})
	return true


## The country takes the company whole: the state of `country` holds 100 %, a civil servant runs it, its home is
## `country` (the player of that country deals with it as with any state company of theirs), a new name.
func nationalise_by(db: Data, c: Dictionary, country: String, day: int) -> void:
	c["owners"] = [{"кто": {"ru": "Государство (%s)" % country, "en": "The state (%s)" % country}, "type": "polity", "country": country, "доля": 1.0}]
	c["_owners_changed"] = true
	c.erase("_proxy")
	set_country(db, c, country)
	Stakes._retype(db, c)
	replace_head(db, c, "госслужащий", day, "nationalisation")
	rename_for(db, c, country, day)
	db.version += 1


# ---------- a new name, IPOs, the small ones (stage 3) ----------

## A company that passed under another country gets a new name: «old name (country)» at once, and the game's AI
## may find a better one (narrator.gd).
func rename_for(db: Data, c: Dictionary, country: String, day: int) -> void:
	var old: Dictionary = (c.get("название", {}) as Dictionary).duplicate() if c.get("название") is Dictionary else {"ru": str(c.get("название", "")), "en": str(c.get("название", ""))}
	rename(db, c, {"ru": db.mod.tr_key("pax_corporations_rename_ru") % [str(old.get("ru", "")), country],
		"en": db.mod.tr_key("pax_corporations_rename_en") % [str(old.get("en", "")), country]}, day)
	if on_rename.is_valid():
		on_rename.call(c, country)


func rename(db: Data, c: Dictionary, title: Dictionary, day: int) -> void:
	var before := db.name_of(c)
	c["название"] = title
	_names[str(c["id"])] = title
	(c["_chronicle"] as Array).append({"день": day, "вид": "переименование", "old_value": before, "новое": db.text(title)})
	db.version += 1


## IPO: a company with no shares on the exchange (a founder's, a newborn, investors') that grew up and makes money
## sells 15–30 % of new shares: the holders are diluted, the company gets the money, a free float appears.
func _ipos(db: Data, cfg_all: Dictionary, day: int) -> void:
	var cfg: Dictionary = cfg_all.get("ipo", {})
	var chance := float(cfg.get("chance_per_year", 0.1)) * db.dt / 52.0
	var year := int(Pax.game.date().get("year", 2026)) if Pax.game != null else 2026
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty() or db.state_share(c) > 0.5 or Stakes.free_float(c) > 0.02 or float(e.get("P", 0.0)) <= 0.0:
			continue
		if year - int(c.get("founded", year)) < int(cfg.get("years_since_founding", 2)) or db.cap(c) < float(cfg.get("market_cap_from", 100.0)):
			continue
		if _rng.randf() >= chance:
			continue
		var f := _rng.randf_range(float(cfg.get("share_from", 0.15)), float(cfg.get("share_to", 0.3)))
		var owners: Array = c.get("owners", [])
		for o in owners:
			(o as Dictionary)["доля"] = float((o as Dictionary).get("доля", 0.0)) * (1.0 - f)
		owners.append({"кто": {"ru": "Частные акционеры и фонды", "en": "Free float and funds"}, "type": "частные", "доля": f})
		c["owners"] = owners
		c["_owners_changed"] = true
		var raised := db.cap(c) * f * (1.0 - float(cfg.get("commission", 0.07)))
		e["money"] = float(e.get("money", 0.0)) + raised
		e["шок"] = float(e.get("шок", 0.0)) + log(1.0 + _rng.randf_range(-0.05, 0.25))   # the first day on the exchange
		stats["ipo"] = int(stats.get("ipo", 0)) + 1
		_note(c, day, {"вид": "ipo", "доля": f, "count_value": raised}, "good", 0.4, db.cap(c) > 10000.0)


## Too many small companies: the weakest are bought by a bigger company of the same goods (and merge into it) or
## squeezed out of the market (liquidated, their customers go to rivals). With the world over «предел» it goes
## faster; under it only the long-suffering small ones go.
func _consolidate(db: Data, goods: Goods, debt: Debt, cfg_all: Dictionary, day: int) -> bool:
	var cfg: Dictionary = cfg_all.get("small", {})
	var limit := int(cfg.get("limit", 1300))
	var excess := db.companies.size() - limit
	var small_cap := float(cfg.get("small_to", 300.0))
	var weak: Array = []
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty() or db.state_share(c) > 0.5 or db.cap(c) >= small_cap:
			continue
		e["weakness_weeks"] = int(e.get("weakness_weeks", 0)) + db.dt if float(e.get("P", 0.0)) < 0.0 else 0
		if excess > 0 or int(e["weakness_weeks"]) >= int(cfg.get("weakness_weeks", 26)):
			weak.append(c)
	if weak.is_empty():
		return false
	weak.sort_custom(func(a, b): return db.cap(a) < db.cap(b))
	var per_week := float(cfg.get("в_год", 2.0)) / 52.0 * db.dt + (maxf(0.0, float(excess)) * float(cfg.get("surplus_share_per_week", 0.02)) * db.dt)
	var n := int(per_week) + (1 if _rng.randf() < per_week - floorf(per_week) else 0)
	var any := false
	for c in weak.slice(0, n):
		var buyer := _bigger_buyer(db, goods, c, float(cfg.get("buyer_bigger", 5.0)))
		if not buyer.is_empty():
			db.econ(buyer)["money"] = float(db.econ(buyer).get("money", 0.0)) - db.cap(c) * float(cfg.get("price", 1.2))
			stats["small_bought_out"] = int(stats.get("small_bought_out", 0)) + 1
			merge(db, debt, buyer, c, day, "buyout")
		else:
			stats["displaced"] = int(stats.get("displaced", 0)) + 1
			liquidate(db, goods, c, day, "вытеснена")
		any = true
	return any


func _bigger_buyer(db: Data, goods: Goods, c: Dictionary, times: float) -> Dictionary:
	var best: Dictionary = {}
	for pool in [goods.home_pool(c), goods.world_pool(c)]:
		for cid in goods.members.get(pool, []):
			var o := db.company(str(cid))
			if o.is_empty() or str(o["id"]) == str(c["id"]) or db.cap(o) < db.cap(c) * times or db.econ(o).has("банкротство"):
				continue
			if float(db.econ(o).get("money", 0.0)) < db.cap(c) * 1.2:
				continue
			if str(o.get("_country", "")) != str(c.get("_country", "")) and not Rivals.open_border(db.balance.get("competition", {}), str(o.get("_country", "")), str(c.get("_country", ""))):
				continue
			if best.is_empty() or (str(o.get("_country", "")) == str(c.get("_country", "")) and str(best.get("_country", "")) != str(c.get("_country", ""))):
				best = o
		if not best.is_empty():
			break
	return best


var _goods_ref: Goods   # liquidation needs the markets; set by main before step()
var _rivals_ref: Rivals # breakups after a war (rivals.split)
var _names: Dictionary = {}   # company id -> its new name (a change of country) — saved
var on_rename: Callable       # func(company, country) — the game's AI may find a better name (narrator.gd)


func _at_war(game: PaxGame, country: String) -> bool:
	for f in game.factions():
		var fd: Dictionary = f
		if str(fd.get("name", "")) == country:
			return str(fd.get("treaty", "")) == "война"
	if country == str(game.player_faction().get("name", "")):
		for f in game.factions():
			if str((f as Dictionary).get("treaty", "")) == "война":
				return true
	return false


# ---------- helpers ----------

func _note(c: Dictionary, day: int, entry: Dictionary, tone: String, size: float, big: bool) -> void:
	entry["день"] = day
	(c["_chronicle"] as Array).append(entry)
	news.append({"c": c, "entry": entry, "tone": tone, "size": size, "big": big})


# ---------- save ----------

## Liquidated and merged companies (by id — they are dropped from the data on load), moved companies,
## changed heads, the province owners the war checks compare with.
func save_state(db: Data) -> Dictionary:
	return {"зерно": str(_rng.seed), "состояние": str(_rng.state), "left": db.gone, "moves": _moved, "главы": _heads, "имена": _names,
		"провинции": _owners0, "мир": world, "results": stats, "born_n": _born, "неделя": _week}


## Before the other modules load their state (after rivals.restore_companies: born companies are there).
func restore(db: Data, state: Dictionary) -> void:
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
	var gone: Variant = state.get("left", {})
	if gone is Dictionary:
		for cid in (gone as Dictionary).keys():
			var info: Dictionary = (gone as Dictionary)[cid] if (gone as Dictionary)[cid] is Dictionary else {}
			db.remove_company(str(cid), int(info.get("день", 0)), str(info.get("reason", "")))
			db.gone[str(cid)] = info
	var moved: Variant = state.get("moves", {})
	if moved is Dictionary:
		for cid in (moved as Dictionary).keys():
			var c := db.company(str(cid))
			if not c.is_empty():
				c["_country"] = str((moved as Dictionary)[cid])
				_moved[str(cid)] = c["_country"]
	var heads: Variant = state.get("главы", {})
	if heads is Dictionary:
		for cid in (heads as Dictionary).keys():
			var c := db.company(str(cid))
			var h: Variant = (heads as Dictionary)[cid]
			if not c.is_empty() and h is Dictionary:
				c["глава"] = ((h as Dictionary).get("глава", c.get("глава", {})) as Dictionary).duplicate(true)
				c["former_heads"] = ((h as Dictionary).get("former_heads", []) as Array).duplicate(true)
				_heads[str(cid)] = h
	var names: Variant = state.get("имена", {})
	if names is Dictionary:
		for cid in (names as Dictionary).keys():
			var c := db.company(str(cid))
			if not c.is_empty() and (names as Dictionary)[cid] is Dictionary:
				c["название"] = ((names as Dictionary)[cid] as Dictionary).duplicate()
				_names[str(cid)] = c["название"]
	var prov: Variant = state.get("провинции", {})
	if prov is Dictionary:
		for k in (prov as Dictionary).keys():
			_owners0[int(str(k))] = str((prov as Dictionary)[k])
	world = (state.get("мир", []) as Array).duplicate(true) if state.get("мир") is Array else []
	stats = (state.get("results", {}) as Dictionary).duplicate() if state.get("results") is Dictionary else {}
	_born = int(state.get("born_n", 0))
	_week = int(state.get("неделя", 0))
