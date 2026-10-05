extends RefCounted
## Foreign investments in the player's companies (ideas doc, section 16; config balance.json «инвестиции»).
## Selling shares to a foreigner is a real decision: the investor brings growth, technology and markets, but gets a
## say in the company and may leave at an awkward moment.
##
## How a foreigner comes in:
##   • the player sells by order: «продать 20% госпакета Росатома Индии» (the state's stake — money to the treasury)
##     or «… новые акции / допэмиссия …» (new shares — money to the company). The country answers by its relation
##     to the player: agrees, haggles (a letter with a lower price) or refuses;
##   • a foreign government offers by letter: «Правительство X готово купить 15% компании Y за N» — accept,
##     haggle or decline (letters.gd). Countries offer when they like the player and lack that industry at home;
##   • a foreign company or state already holding shares (deals of rivals.gd, letters) — the same effects.
##
## Strength: E = min(share / 0.25; 1) · (0.5 + 0.5·K), K — the investor's quality 0..1: the mean of its country's
## prestige, its technology level (its share of tech industries) and its relation to the player.
##
## The company gets (while the investor holds its stake; frozen stakes give nothing):
##   • at the announcement: price + (0.05 + 0.3·E), half of it from a rival country (relation < 0.3);
##   • growth: revenue + 0.003·E per week of the first 52 (up to +15 %), the price drifts + 0.002·E a week then;
##   • the country's development: + 3·E «Гос вложения» points at once and + 0.5·E a week for 26 weeks;
##   • markets: revenue + 10 %·E × the investor country's weight in the world;
##   • by the investor's kind: a technology power — productivity + 5 %·E, a raw-materials one — costs − 4 %·E
##     (supplies), a rich one — a lower bankruptcy chance; K over 0.7 — the credit rating one step up (the bankruptcy
##     chance × 0.7).
## The investor's rights by its share: up to 10 % — a portfolio investor (independence − share); 10–25 % — a strategic
## partner (independence − 10, technology theft in the industry × 1.3); 25–50 % — a blocking stake (no takeover, no
## relocation of the company, independence − 20); over 50 % — foreign control: the company drops out of its
## industry's development tree (tree.gd members).
## The player pays: selling a strategic company (config «стратегические») to a foreigner costs votes (influence.gd
## through db.inv_vote, fading); the investor's country leans on the company in conflicts (sanctions or tariffs
## against it — a threat letter, the price shakes); when the relation falls below 0.4 the investor may sell out:
## P(week) = 0.02 · max(0; (0.4 − relation) · 10); sanctions against its country — it leaves at once unless the
## player froze the stake by order («заморозить долю Индии в Росатоме»). On exit: price − (0.1 + 0.3·E), all bonuses
## gone. The player can buy the stake back by order («выкупить долю Индии в Росатоме») at the price + a premium.
##
## The other way (16.5): the player's state with ≥ 5 % of a foreign company gets dividends (economy.gd) and its
## companies of the same industry a technology exchange (productivity + 3 %·E); when that country falls out with the
## player (relation < 0.3) it may buy its stake back; a country cold to the player refuses to sell (main.quote_trade).

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Stakes := preload("res://mods/pax_corporations/src/market/stakes.gd")
const Debt := preload("res://mods/pax_corporations/src/companies/debt.gd")
const Antitrust := preload("res://mods/pax_corporations/src/state/antitrust.gd")

const W_SELL := ["продать", "продажа", "продаём", "продаем", "уступить", "sell"]
const W_NEW := ["допэмисси", "новые акции", "новых акций", "выпустить акции", "выпуск акций", "new shares", "share issue"]
const W_BACK := ["выкупить долю", "выкуп доли", "вернуть долю", "buy back", "buy out"]
const W_FREEZE := ["заморозить", "заморозка", "freeze"]
const W_UNFREEZE := ["разморозить", "unfreeze"]
const TECH := ["it", "semiconductors", "pharma", "авиа", "ии", "наука", "космос"]
const RAW := ["oil_gas", "metallurgy", "энергетика"]

var known: Dictionary = {}       # "company id|holder name" -> {страна, тип, с_дня, E, K, профиль, заморожено}
var _primed := false             # the holders already there at the start (data, an old save) are taken in quietly
var news: Array = []
var _rng := RandomNumberGenerator.new()
var db: Data
var game: PaxGame
var mod: PaxMod
var tree: Object                 # tree.gd (add_bonus)
var arena: Object                # arena.gd (prestige, tariffs, find_country)
var say: Callable                # func(text) — a notification + a letter (main.gd)
var write_offer: Callable        # func(company, country, text, offer) — a government's letter (letters.gd)
var _player := ""


func setup(m: PaxMod, d: Data, g: PaxGame, t: Object, a: Object, say_cb: Callable) -> void:
	mod = m
	db = d
	game = g
	tree = t
	arena = a
	say = say_cb


func start_new() -> void:
	_rng.randomize()


func _cfg() -> Dictionary:
	return db.balance.get("investments", {})


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


func _say(text: String) -> void:
	if say.is_valid():
		say.call(text)


# ---------- the investor ----------

func relation(country: String) -> float:
	for f in game.factions():
		if str((f as Dictionary).get("name", "")) == country:
			return float((f as Dictionary).get("relations", 0.4))
	return 0.4


func _relations(country: String, delta: float) -> void:
	for f in game.factions():
		var fd: Dictionary = f
		if str(fd.get("name", "")) == country and fd.has("relations"):
			fd["relations"] = clampf(float(fd["relations"]) + delta, 0.0, 1.0)


## The share of a country's market value in technology and in raw-materials industries.
func _mix(country: String) -> Vector2:
	var all := 0.0
	var tech := 0.0
	var raw := 0.0
	for item in db.companies:
		var c: Dictionary = item
		if str(c.get("_country", "")) != country:
			continue
		var v := db.cap(c)
		all += v
		if str(c.get("sector", "")) in TECH:
			tech += v
		elif str(c.get("sector", "")) in RAW:
			raw += v
	return Vector2(tech / all, raw / all) if all > 0.0 else Vector2.ZERO


## K — the investor's quality 0..1: its country's prestige, technology level and relation to the player.
func quality(country: String) -> float:
	var p := float((db.prestige as Dictionary).get(country, 30.0)) / 100.0
	var techl := clampf(_mix(country).x * 2.0, 0.0, 1.0)
	return clampf((p + techl + relation(country)) / 3.0, 0.0, 1.0)


## What the investor mostly brings: «технологии», «поставки» or «деньги».
func profile(country: String) -> String:
	var m := _mix(country)
	if m.x >= 0.3 and m.x >= m.y:
		return "технологии"
	if m.y >= 0.3:
		return "supplies"
	return "money"


static func strength(share: float, k: float) -> float:
	return minf(share / 0.25, 1.0) * (0.5 + 0.5 * k)


## The foreign holders of a company: [{holder: owner entry, страна, доля}] — states and companies of another country.
static func foreign_holders(c: Dictionary) -> Array:
	var home := str(c.get("_country", ""))
	var out: Array = []
	for o in c.get("owners", []):
		var od: Dictionary = o
		var country := str(od.get("country", ""))
		if str(od.get("type", "")) in ["polity", "company"] and not country.is_empty() and country != home and float(od.get("доля", 0.0)) > 0.0005:
			out.append({"holder": od, "country": country, "доля": float(od.get("доля", 0.0))})
	return out


## The part of a company held by foreigners (over a half — foreign control, tree.gd).
static func foreign_share(c: Dictionary) -> float:
	var s := 0.0
	for h in foreign_holders(c):
		s += float((h as Dictionary)["доля"])
	return s


# ---------- weekly ----------

func step(day: int) -> void:
	news.clear()
	_player = str(game.player_faction().get("name", ""))
	var fx := {}
	var seen := {}
	db.inv_vote = float(db.inv_vote) * pow(1.0 - float(_cfg().get("votes_decay", 0.04)), db.dt)
	for item in db.companies.duplicate():
		var c: Dictionary = item
		var home := str(c.get("_country", ""))
		for h in foreign_holders(c):
			var hd: Dictionary = h
			var country := str(hd["country"])
			# Foreign investors in the player's companies; and the player's own stakes abroad (16.5).
			if home != _player and country != _player:
				continue
			var key := str(c["id"]) + "|" + db.text((hd["holder"] as Dictionary).get("кто", ""))
			seen[key] = true
			if not known.has(key):
				if _primed:
					_arrive(c, hd, key, day)
				else:
					known[key] = {"country": country, "from_day": day - 52 * 7, "profile": profile(country), "frozen_n": false}
			var rec: Dictionary = known[key]
			rec["доля"] = float(hd["доля"])
			rec["K"] = quality(country)
			rec["E"] = minf(1.5, strength(float(hd["доля"]), float(rec["K"])) * db.cfx(_player, "investors"))
			if home == _player:
				if _leaves(c, hd, rec, day):
					seen.erase(key)
					continue
				if not bool(rec.get("frozen_n", false)):
					_effects(c, hd, rec, fx, day)
			else:
				_abroad(c, hd, rec, fx, day)
	for key in known.keys():
		if not seen.has(key):
			known.erase(key)
	db.inv_fx = fx
	_primed = true
	_maybe_offer(day)


## The summed strength E of the company's working (not frozen) foreign investors, up to 1.5 (techlevel.gd).
func strength_in(cid: String) -> float:
	var s := 0.0
	for key in known.keys():
		var rec: Dictionary = known[key]
		if str(key).begins_with(cid + "|") and not bool(rec.get("frozen_n", false)):
			s += float(rec.get("E", 0.0))
	return minf(s, 1.5)


## A new foreign holder: the market's jump at the announcement, the country's development points, the newspaper.
func _arrive(c: Dictionary, hd: Dictionary, key: String, day: int) -> void:
	var country := str(hd["country"])
	var k := quality(country)
	var e_str := strength(float(hd["доля"]), k)
	known[key] = {"country": country, "from_day": day, "K": k, "E": e_str, "profile": profile(country), "frozen_n": false}
	if str(c.get("_country", "")) != _player:
		return
	var jump := float(_cfg().get("leap_base", 0.05)) + float(_cfg().get("leap_per_E", 0.3)) * e_str
	if relation(country) < float(_cfg().get("rival_to", 0.3)):
		jump *= 0.5
	var e := db.econ(c)
	if not e.is_empty():
		e["шок"] = float(e.get("шок", 0.0)) + log(1.0 + jump)
	if tree != null:
		tree.call("add_bonus", _player, float(_cfg().get("gw_at_once", 3.0)) * e_str)
	_note(c, day, _t("inv_chron_in_" + profile(country)) % [country, db.percent(float(hd["доля"]))], "good", 0.4 + e_str)


## The company's bonuses from one investor (into db.inv_fx, read by db.tree — economy, statuses, rivals, lifecycle).
func _effects(c: Dictionary, hd: Dictionary, rec: Dictionary, fx: Dictionary, day: int) -> void:
	var cfg := _cfg()
	var e_str := float(rec["E"])
	var share := float(hd["доля"])
	var weeks := float(day - int(rec.get("from_day", day))) / 7.0
	var cid := str(c["id"])
	var f: Dictionary = fx.get(cid, {})
	fx[cid] = f
	var add := func(k: String, v: float) -> void: f[k] = float(f.get(k, 0.0)) + v
	var mul := func(k: String, v: float) -> void: f[k] = float(f.get(k, 1.0)) * v
	# Growth over the first year, then it stays; markets in the investor's country.
	add.call("выручка", minf(float(cfg.get("growth_cap", 0.15)), float(cfg.get("growth_per_week", 0.003)) * e_str * minf(weeks, 52.0)))
	var gw := _weight(str(hd["country"]))
	add.call("выручка", float(cfg.get("markets", 0.1)) * e_str * gw)
	var e := db.econ(c)
	if weeks < 52.0 and not e.is_empty():
		e["шок"] = float(e.get("шок", 0.0)) + log(1.0 + float(cfg.get("drift", 0.002)) * e_str * float(db.dt))
	if weeks < 26.0 and tree != null:
		tree.call("add_bonus", _player, float(cfg.get("gw_per_week", 0.5)) * e_str * float(db.dt))
	match str(rec.get("profile", "money")):
		"технологии":
			add.call("производительность", float(cfg.get("techno", 0.05)) * e_str)
		"supplies":
			add.call("издержки", -float(cfg.get("supplies", 0.04)) * e_str)
		_:
			mul.call("банкротство", 1.0 - 0.3 * e_str)
	if float(rec["K"]) > float(cfg.get("rating_from_K", 0.7)):
		mul.call("банкротство", 0.7)
	# Rights by the share.
	if share < 0.1:
		add.call("независимость", -share * 100.0)
	elif share < 0.25:
		add.call("независимость", -10.0)
		mul.call("шпионаж_против", float(cfg.get("theft_partner", 1.3)))
	else:
		add.call("независимость", -20.0)
		mul.call("шпионаж_против", float(cfg.get("theft_partner", 1.3)))
		f["takeover"] = 0.0
		f["переезд"] = 0.0


## The investor country's weight in the world market (its people × wealth, goods.gd) against the world.
func _weight(country: String) -> float:
	var gd: Variant = arena.get("goods") if arena != null else null
	if not (gd is Object):
		return 0.0
	var people: Dictionary = (gd as Object).get("now_people")
	var world := float((gd as Object).get("now_world"))
	return clampf(float(people.get(country, 0.0)) / world, 0.0, 1.0) if world > 0.0 else 0.0

## Does the investor leave this week: sanctions against its country, or a relation below the threshold.
## A conflict with its country also makes it lean on the company once (a threat letter).
func _leaves(c: Dictionary, hd: Dictionary, rec: Dictionary, day: int) -> bool:
	var country := str(hd["country"])
	var cfg := _cfg()
	var sanctioned := false
	var tariffed := false
	if arena != null:
		for t in arena.get("tariffs"):
			var td: Dictionary = t
			if str(td.get("from_value", "")) == _player and str(td.get("on_value", "")) == country:
				if str(td.get("вид", "")) == "санкции":
					sanctioned = true
				else:
					tariffed = true
	if (sanctioned or tariffed) and float(hd["доля"]) >= 0.1 and not bool(rec.get("pressed", false)):
		rec["pressed"] = true
		var e := db.econ(c)
		if not e.is_empty():
			e["шок"] = float(e.get("шок", 0.0)) + log(1.0 - float(cfg.get("pressure_shock", 0.03)))
		_say(_t("inv_lever") % [country, db.name_of(c), db.percent(float(hd["доля"]))])
	if bool(rec.get("frozen_n", false)):
		return false
	var rel := relation(country)
	var p := float(cfg.get("exit_per_week", 0.02)) * maxf(0.0, (float(cfg.get("exit_threshold", 0.4)) - rel) * 10.0) * float(db.dt)
	if sanctioned or _rng.randf() < p:
		exit(c, hd["holder"], day, "inv_exit_sanctions" if sanctioned else "inv_exit_relations")
		return true
	return false


## The investor sells out: its shares go to the market, the price falls, the bonuses are gone.
func exit(c: Dictionary, holder: Dictionary, day: int, why_key: String) -> void:
	var country := str(holder.get("country", ""))
	var share := float(holder.get("доля", 0.0))
	var k := quality(country)
	var e_str := strength(share, k)
	var owners: Array = c.get("owners", [])
	owners.erase(holder)
	Stakes._float_holder(owners)["доля"] = float(Stakes._float_holder(owners)["доля"]) + share
	c["owners"] = owners
	c["_owners_changed"] = true
	var e := db.econ(c)
	if not e.is_empty():
		e["шок"] = float(e.get("шок", 0.0)) + log(maxf(0.1, 1.0 - float(_cfg().get("exit_shock", 0.1)) - float(_cfg().get("leap_per_E", 0.3)) * e_str))
	known.erase(str(c["id"]) + "|" + db.text(holder.get("кто", "")))
	_note(c, day, _t("inv_chron_out") % [country, db.percent(share)], "bad", 0.5 + e_str)
	_say(_t(why_key) % [country, db.name_of(c), db.percent(share)])


## The player's stake in a foreign company (16.5): the technology exchange for the player's companies of the
## industry; a country that fell out with the player buys its stake back.
func _abroad(c: Dictionary, hd: Dictionary, rec: Dictionary, fx: Dictionary, day: int) -> void:
	var cfg := _cfg()
	var share := float(hd["доля"])
	if share < float(cfg.get("abroad_from", 0.05)):
		return
	var home := str(c.get("_country", ""))
	var e_str := strength(share, quality(home))
	for item in db.companies:
		var mine: Dictionary = item
		if str(mine.get("_country", "")) == _player and str(mine.get("sector", "")) == str(c.get("sector", "")):
			var f: Dictionary = fx.get(str(mine["id"]), {})
			f["производительность"] = minf(float(f.get("производительность", 0.0)) + float(cfg.get("обмен", 0.03)) * e_str, 0.06)
			fx[str(mine["id"])] = f
	if relation(home) < float(cfg.get("buyback_to", 0.3)) and _rng.randf() < float(cfg.get("buyback_chance", 0.02)) * float(db.dt):
		var amount := db.price(c) * db.shares(c) * share * (1.0 + float(cfg.get("premium", 0.1)))
		var owners: Array = c.get("owners", [])
		owners.erase(hd["holder"])
		var st := Stakes._state_holder(c, home, true)
		st["доля"] = float(st.get("доля", 0.0)) + share
		c["_owners_changed"] = true
		Stakes._retype(db, c)
		game.add_resource(game.home_body(), "money", amount)
		known.erase(str(c["id"]) + "|" + db.text((hd["holder"] as Dictionary).get("кто", "")))
		_note(c, day, _t("inv_chron_taken_back") % [home, db.percent(share), db.money(amount)], "bad", 0.4)
		_say(_t("inv_taken_back") % [home, db.name_of(c), db.percent(share), db.money(amount)])


# ---------- offers of foreign governments ----------

## Now and then a friendly, interested country offers to buy into one of the player's companies (a letter).
func _maybe_offer(day: int) -> void:
	var cfg := _cfg()
	if not write_offer.is_valid() or _rng.randf() >= float(cfg.get("offers_per_year", 4.0)) / 52.0 * float(db.dt):
		return
	var mine: Array = db.companies.filter(func(x): return str(x.get("_country", "")) == _player and not db.econ(x).is_empty())
	if mine.is_empty():
		return
	var friends: Array = []
	for f in game.factions():
		var fd: Dictionary = f
		var country := str(fd.get("name", ""))
		if country != _player and db.countries.has(country) and float(fd.get("relations", 0.0)) >= float(cfg.get("offered_from", 0.6)):
			friends.append(country)
	if friends.is_empty():
		return
	var country: String = friends[_rng.randi_range(0, friends.size() - 1)]
	# Interest: an industry the country lacks at home.
	var have := {}
	for item in db.companies:
		if str((item as Dictionary).get("_country", "")) == country:
			have[str((item as Dictionary).get("sector", ""))] = true
	var wanted: Array = mine.filter(func(x): return not have.has(str(x.get("sector", ""))))
	var pool: Array = wanted if not wanted.is_empty() else mine
	pool.sort_custom(func(a, b): return float(a.get("_index", 0.0)) > float(b.get("_index", 0.0)))
	var c: Dictionary = pool[_rng.randi_range(0, mini(pool.size(), 8) - 1)]
	var share := snappedf(_rng.randf_range(float(cfg.get("share_from", 0.05)), float(cfg.get("share_to", 0.2))), 0.01)
	var state := Stakes.state_stake(c, _player)
	var new_shares := state < share
	var amount := db.price(c) * db.shares(c) * share * (1.0 + float(cfg.get("premium", 0.1)) + (0.1 if not wanted.is_empty() else 0.0))
	var text := _t("inv_offer_new" if new_shares else "inv_offer_state") % [country, db.percent(share), db.name_of(c), db.money(amount)]
	text += " " + _t("inv_offer_brings_" + profile(country))
	write_offer.call(c, country, text, {"вид": "иноинвестор", "country": country, "доля": share, "amount": amount, "новые": new_shares, "bargain": true})


## The player accepted (letters.gd): the deal goes through. Returns "" or an error key.
func accept_offer(c: Dictionary, o: Dictionary, day: int) -> String:
	var country := str(o.get("country", ""))
	var share := float(o.get("доля", 0.0))
	var amount := float(o.get("amount", 0.0))
	return sell(c, country, share, amount, bool(o.get("новые", false)), day)


## The player haggles (letters.gd): the country agrees to pay more — or walks away. Returns the line to show.
func haggle(c: Dictionary, o: Dictionary) -> String:
	var country := str(o.get("country", ""))
	var p := clampf(relation(country) - 0.2, 0.15, 0.8)
	o["bargain"] = false
	if _rng.randf() < p:
		o["amount"] = float(o.get("amount", 0.0)) * (1.0 + float(_cfg().get("bargain_markup", 0.15)))
		return _t("inv_haggle_yes") % [country, db.money(float(o["amount"]))]
	_relations(country, -0.01)
	o["отказ"] = true
	return _t("inv_haggle_no") % country


## Sells `share` of the company to the country's state: from the player's state stake (money to the treasury) or as
## new shares (money to the company). Returns "" or an error key.
func sell(c: Dictionary, country: String, share: float, amount: float, new_shares: bool, day: int) -> String:
	var mine := Stakes.state_stake(c, _player)
	if not new_shares and mine < share - 0.0005:
		return "inv_err_no_stake"
	var holder := {"кто": {"ru": "Государство (%s)" % country, "en": "The state (%s)" % country}, "type": "polity", "country": country,
		"доля": share, "investor": true}
	if new_shares:
		Debt.dilute(c, holder, share)
		var e := db.econ(c)
		if not e.is_empty():
			e["money"] = float(e.get("money", 0.0)) + amount
	else:
		var st := Stakes._state_holder(c, _player, false)
		st["доля"] = float(st.get("доля", 0.0)) - share
		(c["owners"] as Array).append(holder)
		c["owners"] = (c["owners"] as Array).filter(func(x): return float((x as Dictionary).get("доля", 0.0)) > 0.00005)
		game.add_resource(game.home_body(), "money", amount)
	c["_owners_changed"] = true
	Stakes._retype(db, c)
	(c["_chronicle"] as Array).append({"день": day, "вид": "state_stake", "что": "sale", "доля": share, "count_value": amount, "country": country})
	_relations(country, 0.02)
	# A strategic company sold to a foreigner costs votes.
	if str(c.get("sector", "")) in (_cfg().get("strategic", ["defence", "энергетика"]) as Array):
		db.inv_vote = float(db.inv_vote) - float(_cfg().get("votes_for_sale", 1.0)) - float(_cfg().get("votes_per_share", 10.0)) * share
		_say(_t("inv_strategic") % db.name_of(c))
	return ""


# ---------- orders ----------

## «продать 20% госпакета Росатома Индии», «выкупить долю Индии в Росатоме», «заморозить долю Индии в Росатоме».
## Returns true when the order was about a foreign investor.
func handle(d: Dictionary) -> bool:
	_player = str(game.player_faction().get("name", ""))
	var text := " " + str(d.get("order", "")).to_lower() + " "
	var sell_w := _has(text, W_SELL)
	var back_w := _has(text, W_BACK)
	var freeze_w := _has(text, W_FREEZE)
	if not (sell_w or back_w or freeze_w):
		return false
	var c := Antitrust.find_company(db, text)
	if c.is_empty() or arena == null:
		return false
	var country := str(arena.call("find_country", text))
	if country.is_empty() or country == _player or country == str(c.get("_country", "")):
		return false
	var day := game.day()
	if back_w or freeze_w:
		var holder := _holder_of(c, country)
		if holder.is_empty():
			_say(_t("inv_no_holder") % [country, db.name_of(c)])
			return true
		if freeze_w:
			var hkey := str(c["id"]) + "|" + db.text(holder.get("кто", ""))
			var rec: Dictionary = known.get(hkey, {})
			known[hkey] = rec
			rec["frozen_n"] = not _has(text, W_UNFREEZE)
			_say(_t("inv_frozen" if bool(rec["frozen_n"]) else "inv_unfrozen") % [country, db.name_of(c)])
			return true
		_buy_back(c, holder, country, day)
		return true
	if str(c.get("_country", "")) != _player:
		return false
	var share := _percent(text)
	if share <= 0.0:
		share = 0.1
	var new_shares := _has(text, W_NEW) or Stakes.state_stake(c, _player) < share - 0.0005
	var amount := db.price(c) * db.shares(c) * share * (1.0 + float(_cfg().get("premium", 0.1)))
	var rel := relation(country)
	var cfg := _cfg()
	if rel < float(cfg.get("refusal_to", 0.2)) or _sanctioned(country):
		_say(_t("inv_order_refused") % [country, db.name_of(c)])
		return true
	if rel < float(cfg.get("bargain_to", 0.35)):
		# Cool relations: the country haggles — a letter with a lower price.
		var low := amount * (1.0 - float(cfg.get("bargain_discount", 0.2)))
		if write_offer.is_valid():
			write_offer.call(c, country, _t("inv_order_counter") % [country, db.percent(share), db.name_of(c), db.money(low)],
				{"вид": "иноинвестор", "country": country, "доля": share, "amount": low, "новые": new_shares, "bargain": false})
		_say(_t("inv_order_counter_note") % country)
		return true
	var err := sell(c, country, share, amount, new_shares, day)
	if not err.is_empty():
		_say(_t(err) % db.name_of(c))
		return true
	_say(_t("inv_order_done") % [country, db.percent(share), db.name_of(c), db.money(amount)])
	return true


func _holder_of(c: Dictionary, country: String) -> Dictionary:
	for h in foreign_holders(c):
		if str((h as Dictionary)["country"]) == country:
			return (h as Dictionary)["holder"]
	return {}


func _sanctioned(country: String) -> bool:
	if arena == null:
		return false
	for t in arena.get("tariffs"):
		var td: Dictionary = t
		if str(td.get("from_value", "")) == _player and str(td.get("on_value", "")) == country and str(td.get("вид", "")) == "санкции":
			return true
	return false


## The state buys the investor's stake back at the market price plus a premium.
func _buy_back(c: Dictionary, holder: Dictionary, country: String, day: int) -> void:
	var share := float(holder.get("доля", 0.0))
	var amount := db.price(c) * db.shares(c) * share * (1.0 + float(_cfg().get("buyout_premium", 0.2)))
	var home := game.home_body()
	if float(game.resources(home).get("money", 0.0)) < amount:
		_say(_t("inv_back_no_money") % db.money(amount))
		return
	game.add_resource(home, "money", -amount)
	var owners: Array = c.get("owners", [])
	owners.erase(holder)
	var st := Stakes._state_holder(c, _player, true)
	st["доля"] = float(st.get("доля", 0.0)) + share
	c["_owners_changed"] = true
	Stakes._retype(db, c)
	known.erase(str(c["id"]) + "|" + db.text(holder.get("кто", "")))
	_relations(country, -0.01)
	_note(c, day, _t("inv_chron_back") % [country, db.percent(share), db.money(amount)], "neutral", 0.3)
	_say(_t("inv_back_done") % [country, db.name_of(c), db.percent(share), db.money(amount)])


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


func _note(c: Dictionary, day: int, text: String, tone: String, size: float) -> void:
	var entry := {"день": day, "вид": "investor", "текст": text}
	(c["_chronicle"] as Array).append(entry)
	news.append({"c": c, "entry": entry, "tone": tone, "size": size, "big": int(c.get("_world_place", 999)) <= 30})


## For the dossier: the company's foreign investors with what they bring and may do.
func describe(c: Dictionary) -> Array:
	var out: Array = []
	for h in foreign_holders(c):
		var hd: Dictionary = h
		var key := str(c["id"]) + "|" + db.text((hd["holder"] as Dictionary).get("кто", ""))
		var rec: Dictionary = known.get(key, {})
		var share := float(hd["доля"])
		var tier := "portfolio" if share < 0.1 else ("partner" if share < 0.25 else ("blocking" if share <= 0.5 else "control"))
		out.append({"country": str(hd["country"]), "доля": share, "E": float(rec.get("E", strength(share, quality(str(hd["country"]))))),
			"profile": str(rec.get("profile", profile(str(hd["country"])))), "права": tier, "frozen_n": bool(rec.get("frozen_n", false)),
			"relations": relation(str(hd["country"]))})
	return out


# ---------- save ----------

func save_state() -> Dictionary:
	return {"known": known, "votes": db.inv_vote, "started": _primed, "зерно": str(_rng.seed), "состояние": str(_rng.state)}


func load_state(state: Dictionary) -> void:
	known = (state.get("known", {}) as Dictionary).duplicate(true) if state.get("known") is Dictionary else {}
	db.inv_vote = float(state.get("votes", 0.0))
	_primed = bool(state.get("started", false))
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
