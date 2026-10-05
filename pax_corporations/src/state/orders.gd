extends RefCounted
## The player's orders about companies (design doc 17). The game hands every order to mods before carrying it
## out (hook «order_parsed», main.gd); this module recognises the ones about companies by their words and the
## company's name, starts an operation and settles it when its time is up (the game's own order runs alongside —
## its days are set to the operation's). Kinds:
##
##   национализация — by decree (the state takes the company; compensation 50 % of the market value unless the
##       order says «без компенсации» / «с полной компенсацией»), or by a scheme (a front man, forged papers,
##       a raider seizure, bribes): cheaper, quiet, but it may fail or come out later — a scandal. The front man
##       holds the control stake as a private person; the state gets its dividends (corp_data.state_take).
##   покупка — the state buys a block (or the control stake) at once. The antimonopoly service reviews it; the
##       company sells its big holders' shares only if it likes the player's country (attitude), else only the
##       free float at a higher premium; a foreign company's government may ban the deal — going ahead anyway
##       («несмотря», «любой ценой») brings its answer: sanctions or other measures chosen by the game's AI.
##   спасение — money for shares (or a state loan): a company in trouble accepts, a healthy one only for a
##       small stake; it ends a bankruptcy procedure.
##   основание — the state looks for investors and enthusiasts: after a search, private companies are founded
##       in the goods with the biggest unmet demand in the country (or the ones the order names); how many and
##       how big depends on the investment climate. Names come from the game's AI (templates if it is silent).
##   давление — a tax audit (hidden taxes found → a fine into the treasury) or a case through the special services
##       and courts (the head arrested, assets frozen, a stake confiscated if ordered). It may collapse: then the
##       company and business at large turn against the government.
##
## Attitude of a company to the player's country (0..1): its home country's relation to the player, sanctions,
## its trust in the state (home companies) and the memory of what the player did to it and to its country's companies.

const Zones := preload("res://mods/pax_corporations/src/zones/zones.gd")
const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")
const Rivals := preload("res://mods/pax_corporations/src/companies/rivals.gd")
const Stakes := preload("res://mods/pax_corporations/src/market/stakes.gd")
const Debt := preload("res://mods/pax_corporations/src/companies/debt.gd")
const Founding := preload("res://mods/pax_corporations/src/founding/founding.gd")
const Antitrust := preload("res://mods/pax_corporations/src/state/antitrust.gd")

const W_NATIONALISE := ["национализ", "в госсобственност", "забрать у", "отобрать у", "изъять компани", "захват", "отжать", "присвоить",
	"взять под контроль", "nationaliz", "nationalis", "seize", "take control"]
const W_SCHEME := ["подстав", "поддел", "фальсиф", "рейдер", "афер", "схем", "тайно", "подкуп", "фиктив", "незаметно",
	"front man", "forged", "raid", "scheme", "covert", "bribe"]
const W_BUY := ["купить", "выкупить", "приобрести", "скупить", "контрольный пакет", "buy", "acquire", "purchase", "controlling stake"]
const W_RESCUE := ["спасти", "спасение", "выделить помощь", "оказать помощь", "финансовую помощь", "господдерж", "санаци", "докапитализ",
	"rescue", "bail out", "bailout", "recapitali"]
const W_FOUND := ["основать", "создать компан", "создать предприят", "учредить", "открыть компан", "стартап",
	"found a company", "start a company", "startup"]
const W_INVESTORS := ["инвестор", "энтузиаст", "investor", "enthusiast"]
const W_SEEK := ["найти", "привлечь", "искать", "поиск", "собрать", "find", "attract", "look for", "raise"]
const W_PRESS := ["налоговая проверк", "налоговую проверк", "проверить налог", "проверку налог", "проверк", "спецслужб", "фсб", "кгб", "сбу ",
	"полици", "обыск", " суд", "судеб", "арест", "уголовн", "прокурат", "надавить", "давлени",
	"tax audit", "audit", "police", "court", "arrest", "prosecut", "pressure", "special service"]
const W_INSIST := ["несмотря", "любой ценой", "враждебн", "всё равно", "все равно", "принудительн", "regardless", "at any cost", "hostile"]

var ops: Array = []              # running: {номер, вид, id, с_дня, до_дня, параметры…}
var memory: Dictionary = {}      # company id or "страна:<name>" -> attitude change from the player's actions
var news: Array = []
var _next := 1
var _rng := RandomNumberGenerator.new()
var db: Data
var game: PaxGame
var goods: Goods
var rivals: Rivals
var antitrust: Antitrust
var mod: PaxMod
var say: Callable                # func(text: String) — a notification + a letter (main.gd)
var on_control: Callable         # func(company) — the state took control: the head answers, a civil servant takes over (main.gd)
var ask_terms: Callable          # func(company, stake, amount, fee, buy, on_accept) — the service's new terms: the player decides (main.gd)
var on_conflict: Callable        # func(why, country, company) — a crisis with a foreign country (arena.gd)
var replace_head: Callable       # func(company, role, day, why) — lifecycle.replace_head (the change is saved)
var _player := ""


func setup(m: PaxMod, d: Data, g: PaxGame, gd: Goods, r: Rivals, a: Antitrust, say_cb: Callable) -> void:
	mod = m
	db = d
	game = g
	goods = gd
	rivals = r
	antitrust = a
	say = say_cb


func start_new() -> void:
	_rng.randomize()


func _cfg() -> Dictionary:
	return db.balance.get("приказы", {})


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


func _say(key: String, args: Array) -> void:
	var line := _t(key)
	var n := line.count("%s") + line.count("%d")
	if n > 0:
		var a := args.slice(0, n)
		while a.size() < n:
			a.append("")
		line = line % a
	if say.is_valid():
		say.call(line)


# ---------- the order ----------

## Called from the «order_parsed» hook. Returns true when the order was about a company and was taken.
func handle(d: Dictionary) -> bool:
	_player = str(game.player_faction().get("name", ""))
	var text := " " + str(d.get("order", "")).to_lower() + " "
	var day := game.day()
	var c := Antitrust.find_company(db, text)
	if (_has(text, W_FOUND) or (_has(text, W_INVESTORS) and _has(text, W_SEEK))) and not _has(text, W_NATIONALISE):
		_start_founding(text, d, day)
		return true
	if c.is_empty():
		return false
	if _has(text, W_NATIONALISE):
		_start_nationalisation(c, text, d, day)
		return true
	if _has(text, W_RESCUE):
		_rescue(c, text, day)
		return true
	if _has(text, W_BUY):
		_buy(c, text, day)
		return true
	if _has(text, W_PRESS):
		_start_pressure(c, text, d, day)
		return true
	return false


static func _has(text: String, words: Array) -> bool:
	for w in words:
		if text.contains(str(w)):
			return true
	return false


## «30%» in the order → 0.3; -1 if none.
static func _percent(text: String) -> float:
	var re := RegEx.new()
	re.compile("(\\d+(?:[.,]\\d+)?)\\s*%")
	var m := re.search(text)
	return float(m.get_string(1).replace(",", ".")) / 100.0 if m != null else -1.0


## «2 млрд», «500 млн», «1.5 trillion» in the order → млн $; -1 if none.
static func _money(text: String) -> float:
	var re := RegEx.new()
	re.compile("(\\d+(?:[.,]\\d+)?)\\s*(трлн|млрд|млн|trillion|billion|million|bn|mln)")
	var m := re.search(text)
	if m == null:
		return -1.0
	var v := float(m.get_string(1).replace(",", "."))
	match m.get_string(2):
		"трлн", "trillion":
			return v * 1e6
		"млрд", "billion", "bn":
			return v * 1e3
	return v


func _register(kind: String, cid: String, weeks: int, extra: Dictionary, d: Dictionary, day: int) -> Dictionary:
	var op := {"number": _next, "вид": kind, "id": cid, "from_day": day, "until_day": day + weeks * 7}
	op.merge(extra)
	_next += 1
	ops.append(op)
	# The game's own order runs as long as the operation.
	if d.get("request") is Dictionary:
		(d["request"] as Dictionary)["дней"] = weeks * 7
	return op


# ---------- attitude ----------

## How a company feels about the player's country, 0..1.
func attitude(c: Dictionary) -> float:
	var home := str(c.get("_country", ""))
	var a := 0.5
	if home == _player:
		var e := db.econ(c)
		a = 0.5 + (float(e.get("trust", 50.0)) - 50.0) / 100.0
	else:
		a = 0.4
		for f in game.factions():
			if str((f as Dictionary).get("name", "")) == home:
				a = float((f as Dictionary).get("relations", 0.4))
				break
		if not Rivals.open_border(db.balance.get("competition", {}), home, _player):
			a -= 0.4
	a += float(memory.get(str(c["id"]), 0.0)) + float(memory.get("страна:" + home, 0.0))
	return clampf(a, 0.0, 1.0)


func _remember(c: Dictionary, delta: float) -> void:
	var cid := str(c["id"])
	memory[cid] = clampf(float(memory.get(cid, 0.0)) + delta, -1.0, 1.0)
	var home := str(c.get("_country", ""))
	if home != _player:
		memory["страна:" + home] = clampf(float(memory.get("страна:" + home, 0.0)) + delta * 0.3, -0.6, 0.6)


## The state buys into a company — the independent business of the country tenses up, whatever the antimonopoly
## service said: every company with no state share loses trust, those of the same industry most, a stake that gives
## control more (balance «реакция_бизнеса»). Low trust means threats to move abroad and sharper letters (lifecycle.gd,
## letters.gd). Buying abroad tenses nobody at home. Returns how many companies were hit.
func business_reacts(c: Dictionary, stake: float, control: bool, day: int) -> int:
	var cfg: Dictionary = db.balance.get("business_reaction", {})
	var home := str(c.get("_country", ""))
	if home != _player or stake <= 0.0:
		return 0
	var k := float(cfg.get("control", 1.5)) if control else 1.0
	var n := 0
	var same := 0
	var total := 0.0
	for item in db.companies:
		var o: Dictionary = item
		if o == c or str(o.get("_country", "")) != home or db.state_share(o) > 0.0:
			continue
		var e := db.econ(o)
		if not e.has("trust"):
			continue
		var in_sector := str(o.get("sector", "")) == str(c.get("sector", ""))
		var drop := minf(stake * 100.0 * k * float(cfg.get("отрасль", 0.3) if in_sector else cfg.get("country", 0.08)), float(cfg.get("limit", 12.0)))
		if drop < 0.05:
			continue
		e["trust"] = clampf(float(e["trust"]) - drop, 0.0, 100.0)
		e["tension_to"] = day + int(cfg.get("дней", 28))
		n += 1
		total += drop
		if in_sector:
			same += 1
	if n > 0:
		var entry := {"день": day, "вид": "business_reaction", "count_value": n, "отрасль": same, "доля": -total / float(n) / 100.0}
		(c["_chronicle"] as Array).append(entry)
		news.append({"c": c, "entry": entry, "tone": "bad", "size": 0.35, "big": false})
		_say("ord_business_tense", [str(n), str(same), db.name_of(c)])
	return n


## Trust of every home company falls (or rises) — business watches what the state does to one of them.
func _chill(points: float, except_id: String) -> void:
	for item in db.companies:
		var c: Dictionary = item
		if str(c.get("_country", "")) != _player or str(c["id"]) == except_id:
			continue
		var e := db.econ(c)
		if e.has("trust"):
			e["trust"] = clampf(float(e["trust"]) + points, 0.0, 100.0)


func _treasury() -> float:
	return float(game.resources(game.home_body()).get("money", 0.0))


func _pay(amount: float) -> void:
	game.add_resource(game.home_body(), "money", -amount)


# ---------- nationalisation ----------

func _start_nationalisation(c: Dictionary, text: String, d: Dictionary, day: int) -> void:
	if str(c.get("_country", "")) != _player and not _has_sites_here(c):
		_say("ord_no_jurisdiction", [db.name_of(c)])
		return
	if str(c.get("_country", "")) == _player and db.state_share(c) > 0.5:
		_say("ord_already_state", [db.name_of(c)])
		return
	var cfg: Dictionary = _cfg().get("nationalisation", {})
	if _has(text, W_SCHEME):
		var bribes := db.cap(c) * float(cfg.get("bribes_from_cap", 0.015))
		_pay(minf(bribes, maxf(_treasury(), 0.0)))
		var weeks := _rng.randi_range(int(cfg.get("scheme_weeks_from", 8)), int(cfg.get("scheme_weeks_to", 12)))
		_register("схема", str(c["id"]), weeks, {"bribes": bribes}, d, day)
		_say("ord_scheme_started", [db.name_of(c), str(weeks), db.money(bribes)])
	else:
		var comp := float(cfg.get("compensation", 0.5))
		if _has(text, ["без компенсац", "бесплатно", "without compensation", "for free"]):
			comp = 0.0
		elif _has(text, ["полн", "рыночн", "full compensation", "market price"]):
			comp = 1.0
		var weeks := int(cfg.get("decree_weeks", 4))
		_register("nationalisation", str(c["id"]), weeks, {"compensation": comp}, d, day)
		_say("ord_nationalise_started", [db.name_of(c), str(weeks), db.percent(comp)])
	_remember(c, -0.3)


func _has_sites_here(c: Dictionary) -> bool:
	var owners: Variant = Data.province_owners()
	for p in c.get("sites", []):
		if p is Dictionary and Data.owner_in(owners, int((p as Dictionary).get("province", -1))) == _player:
			return true
	return false


## The decree: every non-state holder of the player's country's company hands its shares to the state for
## compensation; a foreign company loses its sites in the player's country (they become a new state company).
func _finish_nationalisation(op: Dictionary, c: Dictionary, day: int) -> void:
	var comp := float(op.get("compensation", 0.5))
	if str(c.get("_country", "")) != _player:
		_seize_foreign_sites(c, comp, day)
		return
	var taken := 1.0 - db.state_share(c)
	var paid := db.cap(c) * taken * comp
	paid = minf(paid, maxf(_treasury(), 0.0))
	_pay(paid)
	var foreign := _foreign_share(c)
	c["owners"] = [{"кто": {"ru": "Государство (%s)" % _player, "en": "The state (%s)" % _player}, "type": "polity", "country": _player, "доля": 1.0}]
	c["_owners_changed"] = true
	Stakes._retype(db, c)
	var e := db.econ(c)
	e["шок"] = float(e.get("шок", 0.0)) + log(float((_cfg().get("nationalisation", {}) as Dictionary).get("crash", 0.7)))
	e["H"] = clampf(float(e.get("H", 0.5)) - 0.1, 0.02, 0.98)
	_chill(-float((_cfg().get("nationalisation", {}) as Dictionary).get("business_fear", 10.0)), str(c["id"]))
	_note(c, day, {"вид": "приказ", "что": "nationalisation", "count_value": paid}, "bad", 0.8)
	_say("ord_nationalise_done", [db.name_of(c), db.money(paid)])
	antitrust.remember(db, "founding", 2.0)
	for country in foreign.keys():
		if float(foreign[country]) >= 0.05:
			_retaliate(str(country), "nationalisation", c, day)


func _foreign_share(c: Dictionary) -> Dictionary:
	var out := {}
	for o in c.get("owners", []):
		var od: Dictionary = o
		var country := str(od.get("country", ""))
		if not country.is_empty() and country != _player and str(od.get("type", "")) != "частные":
			out[country] = float(out.get(country, 0.0)) + float(od.get("доля", 0.0))
	return out


## A foreign company's sites in the player's country are taken: they stop working for it (lost), the
## company's country answers.
func _seize_foreign_sites(c: Dictionary, comp: float, day: int) -> void:
	var owners: Variant = Data.province_owners()
	var e := db.econ(c)
	var shares: Array = e.get("site_shares", [])
	var taken := 0.0
	var pts: Array = c.get("sites", [])
	for i in pts.size():
		var p: Dictionary = pts[i]
		if Data.owner_in(owners, int(p.get("province", -1))) == _player and str(p.get("_status", "")).is_empty() and i < shares.size():
			taken += float(shares[i])
			p["_status"] = "конфискована"
			(e["strikes"] as Array).append({"site": i, "weeks": 100000, "людей": float(e["N"]) * float(shares[i]), "sabotage": true, "война": true})
	c["_sites_changed"] = true
	var paid := minf(db.cap(c) * taken * comp, maxf(_treasury(), 0.0))
	_pay(paid)
	_note(c, day, {"вид": "приказ", "что": "confiscation", "доля": taken, "count_value": paid}, "bad", 0.7)
	_say("ord_seized_sites", [db.name_of(c), db.percent(taken), db.money(paid)])
	_retaliate(str(c.get("_country", "")), "confiscation", c, day)


## The scheme ends: success — a front man holds the control stake and runs the company; failure — it comes
## out at once.
func _finish_scheme(op: Dictionary, c: Dictionary, day: int) -> void:
	var cfg: Dictionary = _cfg().get("nationalisation", {})
	var corr := db.country_corruption(_player)
	var indep := _status(c, "независимость", 50.0) / 100.0
	var foreign := 0.0
	for v in _foreign_share(c).values():
		foreign += float(v)
	var p := clampf(float(cfg.get("scheme_base", 0.2)) + 0.7 * corr + 0.2 * (1.0 - indep) - 0.15 * foreign, 0.05, 0.9)
	if _rng.randf() >= p:
		_scandal(c, "схема_провал", day)
		return
	var person := Founding.invent_person(db, _rng)
	var need := 0.51 - db.state_share(c)
	var owners: Array = c.get("owners", [])
	var left := need
	for kind in ["частные", "крупный", "founder", "company"]:
		for o in owners:
			var od: Dictionary = o
			if left <= 0.0 or str(od.get("type", "")) != kind or str(od.get("country", _player)) != _player:
				continue
			var take := minf(left, float(od.get("доля", 0.0)))
			od["доля"] = float(od["доля"]) - take
			left -= take
	owners.append({"кто": {"ru": person, "en": person}, "type": "крупный", "country": _player, "доля": need - left, "proxy": true})
	c["owners"] = owners.filter(func(o): return float((o as Dictionary).get("доля", 0.0)) > 0.00005)
	c["_owners_changed"] = true
	if replace_head.is_valid():
		replace_head.call(c, "ставленник_государства", day, "схема")
		(c["глава"] as Dictionary)["name"] = {"ru": person, "en": person}   # the front man runs it himself
		(c["глава"] as Dictionary)["доля"] = need - left
	c["_proxy"] = {"from_day": day, "человек": person}
	_note(c, day, {"вид": "приказ", "что": "схема_успех", "name": person}, "neutral", 0.5)
	_say("ord_scheme_done", [db.name_of(c), person, db.percent(need - left)])


## A scheme or a case comes out: the press, business, the antimonopoly service, the owners' countries.
func _scandal(c: Dictionary, why: String, day: int) -> void:
	var cfg: Dictionary = _cfg().get("nationalisation", {})
	_chill(-float(cfg.get("scandal_trust", 12.0)), "")
	_remember(c, -0.4)
	antitrust.remember(db, "ban", 3.0)
	var e := db.econ(c)
	e["шок"] = float(e.get("шок", 0.0)) + log(0.85)
	_note(c, day, {"вид": "приказ", "что": why}, "bad", 0.9)
	_say("ord_" + why, [db.name_of(c)])
	game.chronicle(game.home_body(), _t("ord_" + why) % db.name_of(c), "bad", 3)
	for country in _foreign_share(c).keys():
		_retaliate(str(country), "scandal", c, day)


static func _status(c: Dictionary, key: String, fallback: float) -> float:
	return float(((c.get("_statuses", {}) as Dictionary).get(key, {}) as Dictionary).get("value", fallback))


# ---------- buying ----------

func _buy(c: Dictionary, text: String, day: int) -> void:
	var cfg: Dictionary = _cfg().get("purchase", {})
	var want := _percent(text)
	var own := Stakes.state_stake(c, _player)
	if want < 0.0 or _has(text, ["контрольн", "controlling", "control"]):
		want = maxf(want, 0.51 - own)
	want = clampf(want, 0.0, 1.0 - own)
	if want <= 0.001:
		_say("ord_buy_nothing", [db.name_of(c)])
		return
	var foreign := str(c.get("_country", "")) != _player
	var insist := _has(text, W_INSIST)
	# The target's government (a foreign company): a strategic industry or a cold relation — no.
	if foreign:
		var ban := _foreign_ban(c)
		if ban == "закрытая_зона":
			_say("ord_zone_closed", [str(c.get("_country", "")), db.name_of(c)])
			return   # a closed zone cannot be forced: there is no way in
		if not ban.is_empty() and not insist:
			_say("ord_buy_banned_abroad", [str(c.get("_country", "")), db.name_of(c)])
			_remember(c, -0.05)
			return
		if not ban.is_empty():
			_retaliate(str(c.get("_country", "")), "покупка_против_запрета", c, day)
	var friendly := attitude(c) >= float(cfg.get("consent_from", 0.5)) and not insist
	var avail := Stakes.free_float(c)
	if friendly:
		for o in c.get("owners", []):
			if str((o as Dictionary).get("type", "")) in ["крупный", "founder", "сама"]:
				avail += float((o as Dictionary).get("доля", 0.0))
	var stake := minf(want, avail)
	if foreign and Zones.screened(c, _player):
		# The target's union screens outside capital in strategic industries: no more than the cap, no control.
		stake = minf(stake, maxf(0.0, Zones.screen_cap() - Stakes.state_stake(c, _player)))
		if stake <= 0.001:
			_say("ord_zone_screened", [db.name_of(c), db.percent(Zones.screen_cap())])
			return
	if stake <= 0.001:
		_say("ord_buy_refused", [db.name_of(c)])
		return
	var premium := float(cfg.get("premium_friendly", 0.2)) if friendly else float(cfg.get("premium_hostile", 0.35))
	var amount := db.cap(c) * stake * (1.0 + premium)
	var verdict := antitrust.review_stake(db, c, stake, amount, true, day)
	if str(verdict["decision"]) == "ban":
		_say(str(verdict["ключ"]), [db.name_of(c), db.percent(float(verdict.get("блок", stake)))])
		return
	if str(verdict["decision"]) == "условие" and ask_terms.is_valid():
		# The service approves only with a fee: the player sees the new terms and decides.
		ask_terms.call(c, stake, amount, float(verdict["fee"]), true, func() -> void:
			_buy_now(c, stake, amount + float(verdict["fee"]), friendly, day, float(verdict["fee"])))
		return
	_buy_now(c, stake, amount + float(verdict["fee"]), friendly, day, float(verdict["fee"]))


## The purchase itself, after the service's verdict (and the player's consent to its terms).
func _buy_now(c: Dictionary, stake: float, amount: float, friendly: bool, day: int, fee: float = 0.0) -> void:
	if amount > _treasury():
		_say("ord_no_money", [db.money(amount)])
		return
	_pay(amount)
	var had := db.state_share(c)
	var owners: Array = c.get("owners", [])
	var left := stake
	for kinds in [["частные"], ["крупный", "founder", "сама"]]:
		for o in owners:
			var od: Dictionary = o
			if left <= 0.0 or not (str(od.get("type", "")) in kinds):
				continue
			var take := minf(left, float(od.get("доля", 0.0)))
			od["доля"] = float(od["доля"]) - take
			left -= take
	var holder := Stakes._state_holder(c, _player, true)
	holder["доля"] = float(holder.get("доля", 0.0)) + (stake - left)
	c["owners"] = (c["owners"] as Array).filter(func(o): return float((o as Dictionary).get("доля", 0.0)) > 0.00005)
	c["_owners_changed"] = true
	Stakes._retype(db, c)
	_remember(c, 0.0 if friendly else -0.2)
	antitrust.remember(db, "state_stake", stake * 10.0)
	(c["_chronicle"] as Array).append({"день": day, "вид": "state_stake", "что": "buyout", "доля": stake - left, "count_value": amount - fee, "fee": fee, "country": _player})
	_say("ord_buy_done_friendly" if friendly else "ord_buy_done_hostile", [db.percent(stake - left), db.name_of(c), db.money(amount)])
	business_reacts(c, stake - left, had <= 0.5 and db.state_share(c) > 0.5, day)
	if had <= 0.5 and db.state_share(c) > 0.5 and on_control.is_valid():
		on_control.call(c)


## The target's government says no: "" — fine, else the reason.
func _foreign_ban(c: Dictionary) -> String:
	if Zones.closed(str(c.get("_country", "")), _player):
		return "закрытая_зона"
	if Zones.free_capital(str(c.get("_country", "")), _player):
		return ""   # one zone with free movement of capital
	var a := attitude(c)
	var strategic: Array = ((db.balance.get("competition", {}) as Dictionary).get("foreign_list", {}) as Dictionary).get("strategic", [])
	if not Rivals.open_border(db.balance.get("competition", {}), str(c.get("_country", "")), _player):
		return "санкции"
	if str(c.get("profile", "")) in strategic and a < 0.6:
		return "стратегическая"
	if a < 0.3:
		return "отношения"
	return ""


# ---------- rescue ----------

func _rescue(c: Dictionary, text: String, day: int) -> void:
	var e := db.econ(c)
	var cfg: Dictionary = _cfg().get("rescue", {})
	var troubled := e.has("банкротство") or float(e.get("P", 0.0)) < 0.0 or float(c.get("_q", 0.5)) < 0.4 or float(e.get("money", 0.0)) < 0.0
	var amount := _money(text)
	if amount <= 0.0:
		amount = maxf(0.0, -float(e.get("money", 0.0))) + float(cfg.get("debt_share", 0.3)) * float(e.get("debt", 0.0)) if troubled \
			else float(e.get("R", 0.0)) * float(cfg.get("revenue_share", 0.05))
	amount = maxf(amount, 1.0)
	var loan := _has(text, ["кредит", "заём", "займ", "гаранти", "loan", "guarantee"])
	var stake := _percent(text)
	if stake < 0.0 and not loan:
		stake = clampf(amount / maxf(db.cap(c) + amount, 1.0) * (float(cfg.get("trouble_markup", 1.3)) if troubled else 1.0), 0.01, 0.75)
	if amount > _treasury():
		_say("ord_no_money", [db.money(amount)])
		return
	# A company in trouble takes the money; a healthy one only for a small stake, and only if it likes the state.
	if not loan and not troubled and (stake > float(cfg.get("healthy_max_share", 0.1)) or attitude(c) < 0.4):
		_say("ord_rescue_refused", [db.name_of(c), db.percent(stake)])
		_remember(c, -0.05)
		return
	_pay(amount)
	e["money"] = float(e.get("money", 0.0)) + amount
	if loan:
		var l := {"creditor": {"ru": "Государство (%s)" % _player, "en": "The state (%s)" % _player}, "вид": "polity", "company": "",
			"amount": amount, "floating": false, "repayment": day + 5 * 52 * 7, "rate": float(cfg.get("state_loan_rate", 0.03))}
		if not (e.get("loans") is Array):
			e["loans"] = []
		(e["loans"] as Array).append(l)
	else:
		Debt.dilute(c, {"кто": {"ru": "Государство (%s)" % _player, "en": "The state (%s)" % _player}, "type": "polity", "country": _player}, stake)
		Stakes._retype(db, c)
	e["state_rescue"] = true
	if e.has("банкротство"):
		e.erase("банкротство")
	e["H"] = clampf(float(e.get("H", 0.5)) + 0.05, 0.02, 0.98)
	if e.has("trust"):
		e["trust"] = clampf(float(e["trust"]) + 15.0, 0.0, 100.0)
	_remember(c, 0.2)
	_note(c, day, {"вид": "приказ", "что": "rescue", "count_value": amount, "доля": 0.0 if loan else stake}, "good", 0.6)
	_say("ord_rescue_loan" if loan else "ord_rescue_done", [db.name_of(c), db.money(amount), db.percent(stake)])


# ---------- founding by investors ----------

func _start_founding(text: String, d: Dictionary, day: int) -> void:
	var picks := _wanted_goods(text)
	if picks.is_empty():
		_say("ord_found_no_market", [])
		return
	var cfg: Dictionary = _cfg().get("founding", {})
	var weeks := _rng.randi_range(int(cfg.get("search_weeks_from", 6)), int(cfg.get("search_weeks_to", 12)))
	var share := _percent(text)
	var pid := _named_province(text)
	_register("founding", "", weeks, {"goods": picks, "state_share": clampf(share, 0.0, 0.49) if share > 0.0 else 0.0, "province": pid}, d, day)
	_say("ord_found_started", [", ".join(PackedStringArray(picks.map(func(g): return _goods_name(str(g))))), str(weeks)])
	if pid >= 0:
		_say("ord_found_place", [db.province_name(pid)])


## The province of the player's country the order names («в Баварии», «in Bavaria»): the longest name whose stem
## (its first letters, so that any case ending fits) is in the text; -1 — none named.
func _named_province(text: String) -> int:
	var low := text.to_lower()
	var best := -1
	var best_len := 0
	for pid in Data.provinces_of(Data.province_owners(), _player):
		var info := db.province_info(int(pid))
		var names: Dictionary = info.get("имена", {}) if info.get("имена") is Dictionary else {}
		for lang in ["ru", "en"]:
			var n := str(names.get(lang, "")).to_lower().strip_edges()
			if n.length() < 3:
				continue
			# Each word of the name by its stem: «Северный Рейн-Вестфалия» fits «в Северном Рейне-Вестфалии».
			var ok := true
			for w in n.replace("-", " ").split(" ", false):
				var stem := w.substr(0, maxi(3, w.length() - 2)) if w.length() > 4 else w
				if not low.contains(stem):
					ok = false
					break
			if ok and n.length() > best_len:
				best = int(pid)
				best_len = n.length()
	return best


## The goods the order names, or the three with the biggest unmet demand in the player's country.
func _wanted_goods(text: String) -> Array:
	var all: Dictionary = db.goods.get("goods", {})
	var named: Array = []
	for key in all.keys():
		var names: Dictionary = (all[key] as Dictionary).get("name", {})
		for n in [str(key), str(names.get("ru", "")), str(names.get("en", ""))]:
			var stem: String = str(n).to_lower().substr(0, maxi(4, mini(str(n).length(), 6)))
			if stem.length() >= 3 and text.contains(stem):
				named.append(str(key))
				break
	if not named.is_empty():
		return named.slice(0, 3)
	var gaps: Array = []
	for key in all.keys():
		gaps.append([str(key), _gap(str(key))])
	gaps.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return gaps.slice(0, 3).filter(func(g): return float(g[1]) > 0.0).map(func(g): return g[0])


## Unmet demand for goods in the player's country, млн $ a year: the market minus what the game's companies sell.
func _gap(key: String) -> float:
	var pool := "дом|%s|%s" % [key, _player]
	var m: Dictionary = goods.markets.get(pool, {})
	var people_now := float(goods.now_people.get(_player, 0.0))
	var size := float(m.get("объём", 0.0))
	if size <= 0.0:
		var per := float(((db.goods.get("goods", {}) as Dictionary).get(key, {}) as Dictionary).get("consumption", 300.0))
		size = people_now * per / 1e6
	else:
		size *= people_now / maxf(float(goods.start_people.get(_player, people_now)), 1e-6)
	return size - float(goods.pool_volume.get(pool, 0.0))


func _goods_name(key: String) -> String:
	return db.text((((db.goods.get("goods", {}) as Dictionary).get(key, {}) as Dictionary).get("name", key)))


## Investment climate 0..1: trust of home business, corruption, war, the antimonopoly service.
func climate() -> float:
	var trust := 0.0
	var n := 0
	for item in db.companies:
		var c: Dictionary = item
		if str(c.get("_country", "")) == _player and db.econ(c).has("trust"):
			trust += float(db.econ(c)["trust"])
			n += 1
	var t := trust / float(n) / 100.0 if n > 0 else 0.5
	var war := 0.0
	for f in game.factions():
		if str((f as Dictionary).get("treaty", "")) == "война":
			war = 0.2
	return clampf(0.3 + 0.5 * t - 0.4 * (db.country_corruption(_player) - 0.3) - war, 0.05, 1.0)


func _finish_founding(op: Dictionary, day: int) -> void:
	var cfg: Dictionary = _cfg().get("founding", {})
	var cl := climate()
	var picks: Array = op.get("goods", [])
	var plans: Array = []
	for key in picks:
		var gap := _gap(str(key))
		if gap <= 0.0 or _rng.randf() > cl + 0.2:
			continue
		var capital := clampf(gap * float(cfg.get("gap_share", 0.03)) * cl * _rng.randf_range(0.5, 1.5),
			float(cfg.get("capital_min", 5.0)), float(cfg.get("capital_max", 3000.0)))
		plans.append({"goods_key": str(key), "capital": capital})
	if plans.is_empty():
		_say("ord_found_nobody", [])
		return
	# Names, ideas and founders from the game's AI; templates when it is silent.
	var data := {"country": _player, "язык": "ru" if db.lang() == "ru" else "en",
		"companies": plans.map(func(p): return {"goods_key": _goods_name(str(p["goods_key"])), "capital_mln_usd": roundi(float(p["capital"]))})}
	var prompt := "You invent new private companies founded by investors and enthusiasts in the given country, one per item of " \
		+ "«компании» (same order). For each give a short brand name, a one-sentence description of the idea and the founder's " \
		+ "full name typical for the country, in the language «язык». Return ONLY JSON: " \
		+ "{\"companies\": [{\"название\": \"…\", \"description\": \"…\", \"founder\": \"…\"}]}"
	var asked: bool = mod.ask_ai("corp_found", prompt, data, func(answer: Dictionary) -> void: _found_with(plans, answer, op, day))
	if not asked:
		_found_with(plans, {}, op, day)


func _found_with(plans: Array, answer: Dictionary, op: Dictionary, day: int) -> void:
	if db == null or game == null:
		return
	var ai: Array = answer.get("companies", []) if answer.get("companies") is Array else []
	var names: PackedStringArray = []
	for i in plans.size():
		var plan: Dictionary = plans[i]
		var info: Dictionary = ai[i] if i < ai.size() and ai[i] is Dictionary else {}
		var c := found_private(str(plan["goods_key"]), float(plan["capital"]), info, float(op.get("state_share", 0.0)), day, int(op.get("province", -1)))
		if not c.is_empty():
			names.append(db.name_of(c))
	if names.is_empty():
		_say("ord_found_nobody", [])
	else:
		_say("ord_found_done", [", ".join(names)])


## A private company of the player's country: the founder holds most, investors the rest (the state, if the
## order asked for a share, pays its part).
## pid — the province the order named (the map's numbering), -1 — the country's business centre: the province where
## most of its companies have their headquarters (not a random company's office).
func found_private(goods_key: String, capital: float, info: Dictionary, state_share: float, day: int, pid: int = -1) -> Dictionary:
	var p := Founding.propose(db, goods, null, _player, goods_key, capital)
	if not bool(p.get("ok", false)):
		return {}
	var hq: Dictionary = {}
	var named := db.province_info(pid) if pid >= 0 else {}
	if not named.is_empty():
		hq = {"province": pid, "ш": float(named["ш"]), "д": float(named["д"]), "name": named.get("имена", {})}
	else:
		var count := {}
		var first := {}
		for x in db.companies:
			if str((x as Dictionary).get("_country", "")) == _player:
				var h := db.hq_of(x)
				var hp := int(h.get("province", -1))
				count[hp] = int(count.get(hp, 0)) + 1
				if not first.has(hp):
					first[hp] = h
		var top := -1
		for k in count.keys():
			if top < 0 or int(count[k]) > int(count[top]):
				top = int(k)
		if top < 0:
			return {}
		hq = first[top]
	var hq_name: Variant = hq.get("name", "")
	var founder := str(info.get("founder", "")).strip_edges()
	if founder.is_empty():
		founder = Founding.invent_person(db, _rng)
	var title := str(info.get("название", "")).strip_edges()
	if title.is_empty():
		title = "%s %s" % [_goods_name(goods_key), str(_rng.randi_range(1, 99))]
	var spec := {"название": title, "description": str(info.get("description", _t("ord_found_desc") % _goods_name(goods_key))), "goods_key": goods_key,
		"country": _player, "capital": capital, "polity": false, "founder": founder, "год": int(game.date().get("year", 2026)), "день": day,
		"место": {"province": int(hq.get("province", 0)), "ш": float(hq.get("ш", 0.0)), "д": float(hq.get("д", 0.0)),
			"name_ru": str((hq_name as Dictionary).get("ru", "")) if hq_name is Dictionary else str(hq_name),
			"имя_en": str((hq_name as Dictionary).get("en", "")) if hq_name is Dictionary else str(hq_name)}}
	var c := Founding.build(db, p, spec, _rng)
	var n := 1
	while not db.company("inv_%d" % n).is_empty():
		n += 1
	c["id"] = "inv_%d" % n
	c.erase("made_by_player")
	var founder_part := _rng.randf_range(0.3, 0.6) * (1.0 - state_share)
	var owners: Array = [{"кто": {"ru": founder, "en": founder}, "type": "founder", "country": _player, "доля": founder_part}]
	owners.append({"кто": {"ru": "Частные инвесторы", "en": "Private investors"}, "type": "крупный", "country": _player, "доля": 1.0 - state_share - founder_part})
	if state_share > 0.0:
		owners.append({"кто": {"ru": "Государство (%s)" % _player, "en": "The state (%s)" % _player}, "type": "polity", "country": _player, "доля": state_share})
		_pay(minf(capital * state_share, maxf(_treasury(), 0.0)))
	c["owners"] = owners
	c["type"] = "частная"
	c["_chronicle"] = [{"день": day, "вид": "birth", "что": "investors", "count_value": capital}]
	db.add_company(c)
	return c


# ---------- pressure ----------

func _start_pressure(c: Dictionary, text: String, d: Dictionary, day: int) -> void:
	if str(c.get("_country", "")) != _player and not _has_sites_here(c):
		_say("ord_no_jurisdiction", [db.name_of(c)])
		return
	var cfg: Dictionary = _cfg().get("давление", {})
	var tax := _has(text, ["налог", "tax", "аудит", "audit"])
	var confiscate := _has(text, ["конфиск", "изъять", "актив", "имуществ", "confiscat", "assets"])
	var weeks := int(cfg.get("taxes_weeks", 4)) if tax else _rng.randi_range(int(cfg.get("case_weeks_from", 4)), int(cfg.get("case_weeks_to", 8)))
	_register("taxes" if tax else "дело", str(c["id"]), weeks, {"confiscation": confiscate}, d, day)
	_say("ord_tax_started" if tax else "ord_case_started", [db.name_of(c), str(weeks)])
	c["_digging_until"] = day + 365   # a scandal is three times likelier while the services dig (influence.gd, 20.9)
	_remember(c, -0.15)
	var e := db.econ(c)
	e["шок"] = float(e.get("шок", 0.0)) + log(0.95)


## A tax audit: what the company hid (owed − paid) over a few years is found as much as the prosecutors can.
func _finish_tax(c: Dictionary, day: int) -> void:
	var cfg: Dictionary = _cfg().get("давление", {})
	var e := db.econ(c)
	var hidden := maxf(0.0, float(e.get("tax_owed", 0.0)) - float(e.get("tax_pays", 0.0))) * _rng.randf_range(1.0, 3.0)
	var corr := db.country_corruption(_player)
	var found := hidden * clampf(0.3 + 0.5 * (1.0 - corr), 0.2, 0.9)
	if found < float(e.get("R", 0.0)) * 0.001:
		_backlash(c, "налоги_пусто", day)
		return
	var fine := found * float(cfg.get("fine_multiplier", 1.5))
	e["money"] = float(e.get("money", 0.0)) - fine
	game.add_resource(game.home_body(), "money", fine)
	if e.has("trust"):
		e["trust"] = clampf(float(e["trust"]) - 15.0, 0.0, 100.0)
	_chill(-3.0, str(c["id"]))
	_note(c, day, {"вид": "приказ", "что": "taxes", "count_value": fine}, "bad", 0.6)
	_say("ord_tax_done", [db.name_of(c), db.money(fine)])


## A case through the special services and courts: corrupt courts obey, a clean company with independent
## owners is hard to break.
func _finish_case(op: Dictionary, c: Dictionary, day: int) -> void:
	var cfg: Dictionary = _cfg().get("давление", {})
	var corr := db.country_corruption(_player)
	var dirt := _status(c, "corruption", 30.0) / 100.0
	var indep := _status(c, "независимость", 50.0) / 100.0
	var p := clampf(float(cfg.get("case_base", 0.3)) + 0.4 * corr + 0.3 * dirt - 0.2 * indep, 0.05, 0.95)
	if _rng.randf() >= p:
		_backlash(c, "дело_развалилось", day)
		return
	var e := db.econ(c)
	var arrested := db.text((c.get("глава", {}) as Dictionary).get("name", ""))
	if replace_head.is_valid():
		replace_head.call(c, "временный_управляющий", day, "арест")
	e["шок"] = float(e.get("шок", 0.0)) + log(0.75)
	e["H"] = clampf(float(e.get("H", 0.5)) - 0.1, 0.02, 0.98)
	if e.has("trust"):
		e["trust"] = clampf(float(e["trust"]) - 25.0, 0.0, 100.0)
	var share := 0.0
	if bool(op.get("confiscation", false)):
		share = float(cfg.get("confiscation_share", 0.25))
		Debt.dilute(c, {"кто": {"ru": "Государство (%s)" % _player, "en": "The state (%s)" % _player}, "type": "polity", "country": _player}, share)
		Stakes._retype(db, c)
	_chill(-5.0, str(c["id"]))
	_note(c, day, {"вид": "приказ", "что": "дело", "name": arrested, "доля": share}, "bad", 0.8)
	_say("ord_case_confiscated" if share > 0.0 else "ord_case_done", [db.name_of(c), arrested, db.percent(share)])
	for country in _foreign_share(c).keys():
		if float(_foreign_share(c)[country]) >= 0.25:
			_retaliate(str(country), "дело", c, day)


## The pressure found nothing / the case fell apart: the company and business turn against the government.
func _backlash(c: Dictionary, why: String, day: int) -> void:
	var e := db.econ(c)
	if e.has("trust"):
		e["trust"] = clampf(float(e["trust"]) - 20.0, 0.0, 100.0)
	_chill(-5.0, str(c["id"]))
	_remember(c, -0.2)
	_note(c, day, {"вид": "приказ", "что": why}, "neutral", 0.5)
	_say("ord_" + why, [db.name_of(c)])


# ---------- answers of other countries ----------

## A foreign government answers a hostile act (a nationalisation, a seizure, a deal against its ban, a case).
## The GAME rolls the measure by the relation (balance «приказы» «возмездие_веса»); the AI only writes the statement.
func _retaliate(country: String, why: String, c: Dictionary, day: int) -> void:
	if country.is_empty() or country == _player:
		return
	if on_conflict.is_valid():
		on_conflict.call(why, country, c)
	var rel := 0.4
	for f in game.factions():
		if str((f as Dictionary).get("name", "")) == country:
			rel = float((f as Dictionary).get("relations", 0.4))
	var measure := _roll_retaliation(why, rel)
	var data := {"country": country, "to_country": _player, "повод": why, "company": db.name_of(c), "отрасль": db.sector_name(str(c.get("sector", ""))),
		"мера": measure, "язык": "ru" if db.lang() == "ru" else "en"}
	var prompt := "You are the government of «страна». Another country («к_стране») did this to a company of yours: «повод». " \
		+ "Your government has decided the answer «мера» (fixed — do not change it). Write one short sentence of your official " \
		+ "statement announcing it, in the language «язык», inventing no other facts. Return ONLY JSON: {\"заявление\": \"…\"}"
	var asked: bool = mod.ask_ai("corp_retaliation", prompt, data, func(answer: Dictionary) -> void: _apply_retaliation(country, why, c, measure, answer, day))
	if not asked:
		_apply_retaliation(country, why, c, measure, {}, day)


const RETALIATIONS := ["note", "company_sanctions", "asset_freeze", "mirror_nationalisation", "ничего"]


## The measure rolled by weights of the relation band; a seizure (national­isation, confiscation) is answered harder.
func _roll_retaliation(why: String, rel: float) -> String:
	var w: Dictionary = (_cfg().get("retaliation_weights", {}) as Dictionary)
	var band := "enemy" if rel < 0.2 else ("холодно" if rel < 0.45 else "friendship")
	var weights: Dictionary = (w.get(band, {}) as Dictionary).duplicate()
	if weights.is_empty():
		weights = {"note": 1.0}
	if why in ["nationalisation", "confiscation", "захват"]:
		for k in ["asset_freeze", "mirror_nationalisation"]:
			weights[k] = float(weights.get(k, 0.0)) * float(w.get("seizure_multiplier", 2.0))
	var total := 0.0
	for k in weights.keys():
		total += maxf(0.0, float(weights[k]))
	var r := _rng.randf() * total
	for k in weights.keys():
		r -= maxf(0.0, float(weights[k]))
		if r <= 0.0 and str(k) in RETALIATIONS:
			return str(k)
	return "note"


func _apply_retaliation(country: String, why: String, c: Dictionary, measure: String, answer: Dictionary, day: int) -> void:
	if db == null or game == null:
		return
	if not (measure in RETALIATIONS):
		measure = "note"
	var hit := 0
	match measure:
		"note":
			_relations(country, -0.03)
		"company_sanctions":
			_relations(country, -0.05)
			for item in db.companies:
				var o: Dictionary = item
				if str(o.get("_country", "")) == _player and float(o.get("export", 0.3)) > 0.2:
					var e := db.econ(o)
					e["demand"] = float(e["demand"]) * 0.98
					hit += 1
		"asset_freeze", "mirror_nationalisation":
			_relations(country, -0.08 if measure == "asset_freeze" else -0.12)
			var owners: Variant = Data.province_owners()
			for item in db.companies:
				var o: Dictionary = item
				if str(o.get("_country", "")) != _player:
					continue
				var e := db.econ(o)
				var shares: Array = e.get("site_shares", [])
				var pts: Array = o.get("sites", [])
				for i in pts.size():
					var p: Dictionary = pts[i]
					if Data.owner_in(owners, int(p.get("province", -1))) != country or not str(p.get("_status", "")).is_empty() or i >= shares.size():
						continue
					p["_status"] = "frozen_f" if measure == "asset_freeze" else "конфискована"
					(e["strikes"] as Array).append({"site": i, "weeks": 100000 if measure != "asset_freeze" else 26,
						"людей": float(e["N"]) * float(shares[i]), "sabotage": true, "война": true})
					o["_sites_changed"] = true
					hit += 1
	var statement := str(answer.get("заявление", "")).strip_edges()
	_say("ord_answer_" + measure, [country, str(hit)])
	if not statement.is_empty():
		game.chronicle(game.home_body(), "%s: «%s»" % [country, statement], "bad", 2)


func _relations(country: String, delta: float) -> void:
	for f in game.factions():
		var fd: Dictionary = f
		if str(fd.get("name", "")) == country and fd.has("relations"):
			fd["relations"] = clampf(float(fd["relations"]) + delta, 0.0, 1.0)


# ---------- weekly ----------

func step(day: int) -> void:
	news.clear()
	_player = str(game.player_faction().get("name", ""))
	var left: Array = []
	for item in ops:
		var op: Dictionary = item
		if int(op["until_day"]) > day:
			left.append(op)
			continue
		var c := db.company(str(op.get("id", "")))
		match str(op["вид"]):
			"nationalisation":
				if not c.is_empty():
					_finish_nationalisation(op, c, day)
			"схема":
				if not c.is_empty():
					_finish_scheme(op, c, day)
			"taxes":
				if not c.is_empty():
					_finish_tax(c, day)
			"дело":
				if not c.is_empty():
					_finish_case(op, c, day)
			"founding":
				_finish_founding(op, day)
	ops = left
	# A front man may be exposed later: the more honest the country, the likelier.
	var weekly := float((_cfg().get("nationalisation", {}) as Dictionary).get("disclosure_per_year", 0.25)) * db.dt / 52.0
	for item in db.companies:
		var c: Dictionary = item
		if c.has("_proxy") and _rng.randf() < weekly * (1.0 - db.country_corruption(_player)):
			c.erase("_proxy")
			for o in c.get("owners", []):
				(o as Dictionary).erase("proxy")
			_scandal(c, "схема_раскрыта", day)
	for k in memory.keys():
		memory[k] = float(memory[k]) * pow(0.995, db.dt)   # grudges fade over years


func operations_text() -> PackedStringArray:
	var out: PackedStringArray = []
	for item in ops:
		var op: Dictionary = item
		var c := db.company(str(op.get("id", "")))
		out.append(_t("ord_op_" + str(op["вид"])) % [db.name_of(c) if not c.is_empty() else "", str(maxi(0, (int(op["until_day"]) - game.day()) / 7))])
	return out


func _note(c: Dictionary, day: int, entry: Dictionary, tone: String, size: float) -> void:
	entry["день"] = day
	(c["_chronicle"] as Array).append(entry)
	news.append({"c": c, "entry": entry, "tone": tone, "size": size, "big": true})


# ---------- save ----------

func save_state() -> Dictionary:
	var fronts := {}
	for item in db.companies:
		var c: Dictionary = item
		if c.has("_proxy"):
			fronts[str(c["id"])] = c["_proxy"]
	return {"operations": ops, "память": memory, "number": _next, "proxies": fronts, "зерно": str(_rng.seed), "состояние": str(_rng.state)}


func load_state(state: Dictionary) -> void:
	ops = (state.get("operations", []) as Array).duplicate(true) if state.get("operations") is Array else []
	memory = (state.get("память", {}) as Dictionary).duplicate() if state.get("память") is Dictionary else {}
	_next = int(state.get("number", 1))
	var fronts: Variant = state.get("proxies", {})
	if fronts is Dictionary:
		for cid in (fronts as Dictionary).keys():
			var c := db.company(str(cid))
			if not c.is_empty():
				c["_proxy"] = (fronts as Dictionary)[cid]
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
