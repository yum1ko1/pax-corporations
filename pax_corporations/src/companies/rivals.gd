extends RefCounted
## Stage 3: companies act on each other (config: balance.json «конкуренция»). Once a week:
##
## 1. Competition. Each company now and then moves against the market: an advertising campaign (its
##    reputation, so its popularity and share, goes up — goods.gd), a price war (a discount that costs margin
##    but weighs more on the market), poaching people from a rival that pays less, a lawsuit or smear against
##    a rival. How often — the company's aggressiveness (founders more, state companies less) and how much
##    market it is losing. Rivals are the other companies selling the same goods at home or in the world.
## 2. Tension. Every attack raises the tension between the two; it fades with time. Past the threshold the
##    rivalry turns into a corporate war: both attack each other often, both pay for it, and in corrupt
##    countries it turns physical — sites are sabotaged and stand still. A war between a company of the
##    player's country and a foreign one sours the relations of the two countries. It ends in a truce when
##    one side runs out of money, when enough time has passed, or when one side buys the other.
## 3. Takeovers. A company several times bigger than a rival in the same goods tries to buy control of it:
##    from the free float, and — if the owners agree — from them; a hostile bid gets only the float. The
##    buyer pays from its money or borrows. The competition authority may block a deal that makes one
##    company too big on its home market. Owned companies pay their dividends to the parent.
## 4. Breakups. The yearly breakup chance (corp_data «_распад», section 8 / 20.11) now comes true: a site
##    with its people and its part of the business becomes a new company owned by the same shareholders.
##    A monopoly on the home market may be split by the regulator.
##
## New companies and changed sites are saved with the game (save_state / restore).
const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")

const Zones := preload("res://mods/pax_corporations/src/zones/zones.gd")
const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")
const Debt := preload("res://mods/pax_corporations/src/companies/debt.gd")
const Stakes := preload("res://mods/pax_corporations/src/market/stakes.gd")
const MOVES := ["реклама", "демпинг", "переманивание", "иск"]

var wars: Array = []             # {a, b, с_дня, недель, накал}
var tension: Dictionary = {}     # "a|b" (sorted) -> 0..
var deals: Array = []            # the latest takeovers and breakups for the «Markets» tab: {день, вид, a, b, доля, сумма}
var news: Array = []             # this week's: {c, entry, tone, size, big}
var stats: Dictionary = {}       # counters since the start: moves, wars, takeovers, blocked, breakups
var _rng := RandomNumberGenerator.new()
var _mod: PaxMod
var _lang_ru: Dictionary = {}
var _lang_en: Dictionary = {}


func start_new() -> void:
	_rng.randomize()


func setup(m: PaxMod) -> void:
	_mod = m
	var ru: Variant = GameApi.json(m, "data/lang/ru.json", {})
	var en: Variant = GameApi.json(m, "data/lang/en.json", {})
	_lang_ru = ru if ru is Dictionary else {}
	_lang_en = en if en is Dictionary else {}


# ---------- weekly ----------

func step(db: Data, game: PaxGame, goods: Goods, debt: Debt, day: int) -> void:
	news.clear()
	var cfg: Dictionary = db.balance.get("competition", {})
	var fade := 1.0 - pow(1.0 - float(cfg.get("tension_decay", 0.02)), db.dt)
	for k in tension.keys():
		tension[k] = float(tension[k]) * (1.0 - fade)
		if float(tension[k]) < 0.01:
			tension.erase(k)
	for item in db.companies:
		var e := db.econ(item)
		if not e.is_empty():
			e["extra_costs"] = 0.0
			_tick_campaigns(e, cfg)
	# 1. moves
	var per_week := float(cfg.get("actions_per_year", 1.5)) * db.dt / 52.0
	for item in db.companies.duplicate():
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty():
			continue
		var losing := maxf(0.0, 1.0 - float(e.get("market_demand", 1.0)))
		var hit_back := float(cfg.get("answer_multiplier", 2.0)) if not str(e.get("ответ", "")).is_empty() else 1.0
		if _rng.randf() < per_week * aggression(db, c) * (1.0 + 5.0 * losing) * hit_back:
			var rival := _pick_rival(db, goods, c)
			_move(db, c, rival, cfg, day, false)
	# 2. wars
	_wars_step(db, game, goods, debt, cfg, day)
	# 3. takeovers
	var seek := float(cfg.get("takeovers_per_year", 0.03)) * db.dt / 52.0
	for item in db.companies.duplicate():
		var c: Dictionary = item
		if not db.econ(c).is_empty() and _rng.randf() < seek * aggression(db, c):
			_try_takeover(db, goods, debt, c, {}, cfg, day)
	# 4. breakups
	for item in db.companies.duplicate():
		var c: Dictionary = item
		if db.econ(c).is_empty():
			continue
		var yearly := float((c.get("_breakup", {}) as Dictionary).get("value", 0.0)) / 100.0 * float(cfg.get("breakup_from_chance", 1.0))
		if _rng.randf() < yearly * db.dt / 52.0:
			split(db, c, "breakup", day)
			continue
		var mono := float(((c.get("_statuses", {}) as Dictionary).get("monopolism", {}) as Dictionary).get("value", 0.0)) / 100.0
		# The competition authority's strictness: its quality and, at home, its mood (departments.gd).
		if mono >= float(cfg.get("antitrust_split_from", 0.6)) and db.state_share(c) < 0.5 \
				and _rng.randf() < float(cfg.get("antitrust_split_chance", 0.03)) * db.antitrust(str(c.get("_country", ""))) * db.tree(c, "antitrust", 1.0) * db.dt / 52.0:
			split(db, c, "antitrust", day)
	_pay_parents(db)
	db.wars = wars


## 0.1..1: founders and owner-managers push harder, state companies less; the rest is the company's temper.
func aggression(db: Data, c: Dictionary) -> float:
	var role := str((c.get("глава", {}) as Dictionary).get("роль", ""))
	var a := 0.35 + (0.25 if role in ["founder", "акционер_владелец"] else 0.0) - (0.2 if db.state_share(c) > 0.5 else 0.0)
	a += float(absi(str(c["id"]).hash()) % 100) / 250.0
	return clampf(a, 0.1, 1.0)


## A rival: another company selling the same goods — at home first, else in the world; bigger shares are
## likelier. Companies of one group (parent and child) do not fight.
func _pick_rival(db: Data, goods: Goods, c: Dictionary) -> Dictionary:
	# Hit back at whoever attacked us last — the way rivalries escalate.
	var e := db.econ(c)
	var back := str(e.get("ответ", ""))
	if not back.is_empty():
		e["ответ"] = ""
		var attacker := db.company(back)
		if not attacker.is_empty() and not same_group(c, attacker) and _rng.randf() < 0.7:
			return attacker
	var home: Array = goods.members.get(goods.home_pool(c), [])
	var pool: Array = home if home.size() >= 2 else goods.members.get(goods.world_pool(c), [])
	var total := 0.0
	var options: Array = []
	for cid in pool:
		var o := db.company(str(cid))
		if o.is_empty() or str(o["id"]) == str(c["id"]) or same_group(c, o):
			continue
		var w := float(db.econ(o).get("R", 1.0))
		options.append([o, w])
		total += w
	var x := _rng.randf() * total
	for opt in options:
		x -= float(opt[1])
		if x <= 0.0:
			return opt[0]
	return {}


static func parent_of(c: Dictionary) -> String:
	for o in c.get("owners", []):
		var od: Dictionary = o
		if str(od.get("type", "")) == "company" and float(od.get("доля", 0.0)) > 0.5 and not str(od.get("company", "")).is_empty():
			return str(od["company"])
	return ""


## One group: parent and child, two children of one parent, or companies split from each other
## («выделена_из» — the same shareholders own both).
static func same_group(a: Dictionary, b: Dictionary) -> bool:
	var pa := parent_of(a)
	var pb := parent_of(b)
	var ia := str(a["id"])
	var ib := str(b["id"])
	var sa := str(a.get("split_from", ""))
	var sb := str(b.get("split_from", ""))
	return pa == ib or pb == ia or (not pa.is_empty() and pa == pb) or sa == ib or sb == ia or (not sa.is_empty() and sa == sb)


## Can a company of one country take over a company of another at all (sanctions both ways)?
static func open_border(cfg: Dictionary, from: String, to: String) -> bool:
	if from == to:
		return true
	var sanctions: Dictionary = (cfg.get("foreign_list", {}) as Dictionary).get("санкции", {})
	return not (str(to) in (sanctions.get(from, []) as Array) or str(from) in (sanctions.get(to, []) as Array))


# ---------- 1. competition moves ----------

func _move(db: Data, c: Dictionary, rival: Dictionary, cfg: Dictionary, day: int, at_war: bool) -> void:
	var e := db.econ(c)
	var kind := "реклама"
	if not rival.is_empty():
		var weights := [0.3 if not at_war else 0.1, 0.25, 0.2, 0.15]
		var re := db.econ(rival)
		if float(e["W"]) / maxf(float(e["market_wage"]), 1.0) <= float(re.get("W", 0.0)) / maxf(float(re.get("market_wage", 1.0)), 1.0):
			weights[2] = 0.0   # people go only to those who pay better
		if float(e.get("money", 0.0)) < 0.0:
			weights[1] = 0.0   # no money for a price war
		var corrupt := db.country_corruption(str(c.get("_country", "")))
		weights[3] = float(weights[3]) + 0.3 * corrupt
		var sum := 0.0
		for w in weights:
			sum += float(w)
		var x := _rng.randf() * sum
		for i in weights.size():
			x -= float(weights[i])
			if x <= 0.0:
				kind = MOVES[i]
				break
		# A strong police makes violence rarer (departments.gd «силовые»).
		if at_war and corrupt >= float(cfg.get("forces_corruption_from", 0.35)) \
				and _rng.randf() < float(cfg.get("forces_chance", 0.3)) * db.dept(str(c.get("_country", "")), "security_forces", 1.0):
			kind = "силовое"
	var entry := {"вид": "competition", "что": kind, "rival": str(rival.get("id", ""))}
	match kind:
		"реклама":
			_campaign(e, "реклама", int(cfg.get("ads_weeks", 8)))
			Goods.reputation_event(db, e, 1.0, float(cfg.get("ads_reputation", 0.12)))
		"демпинг":
			_campaign(e, "демпинг", int(cfg.get("dumping_weeks", 12)))
		"переманивание":
			var re := db.econ(rival)
			var people := minf(float(re["N"]) * float(cfg.get("poaching_share", 0.01)), float(e["N"]) * 0.03)
			re["N"] = float(re["N"]) - people
			e["N"] = float(e["N"]) + people
			re["H"] = clampf(float(re.get("H", 0.5)) - 0.03, 0.02, 0.98)
			entry["count_value"] = people
		"иск":
			var re := db.econ(rival)
			Goods.reputation_event(db, re, -1.0, float(cfg.get("lawsuit_reputation", 0.1)))
			var fine := float(re.get("R", 0.0)) * float(cfg.get("lawsuit_fine", 0.005))
			re["money"] = float(re.get("money", 0.0)) - fine
			entry["count_value"] = fine
		"силовое":
			_sabotage(db, rival, day)
	stats[kind] = int(stats.get(kind, 0)) + 1
	_chron(c, day, entry)
	if not rival.is_empty() and kind != "реклама":
		db.econ(rival)["ответ"] = str(c["id"])
		var back := entry.duplicate()
		back["rival"] = str(c["id"])
		back["против"] = true
		_chron(rival, day, back)
		_raise_tension(c, rival, float(cfg.get("tension_per_attack", 0.25)) * (2.0 if kind == "силовое" else 1.0))
	var target: Dictionary = rival if not rival.is_empty() and kind != "реклама" else c
	news.append({"c": target, "entry": _chron_last(target), "tone": "bad" if str(target["id"]) != str(c["id"]) else "good", "size": 0.25 if kind == "силовое" else 0.12,
		"big": kind == "силовое"})


## Running campaigns (advertising, a price war) cost a share of revenue each week; a price war also makes
## the goods weigh more on the market (goods.gd reads e["dumping_weeks"]).
func _campaign(e: Dictionary, kind: String, weeks: int) -> void:
	e[kind + "_недель"] = maxi(int(e.get(kind + "_недель", 0)), weeks)


func _tick_campaigns(e: Dictionary, cfg: Dictionary) -> void:
	var cost := 0.0
	for kind in ["реклама", "демпинг"]:
		var left := int(e.get(kind + "_недель", 0))
		if left > 0:
			e[kind + "_недель"] = left - 1
			cost += float(cfg.get("ads_spending", 0.03)) if kind == "реклама" else float(cfg.get("dumping_discount", 0.06))
	e["extra_costs"] = float(e.get("extra_costs", 0.0)) + cost


## A site of the rival stands still for a few weeks (like a strike, economy.gd counts its people out).
func _sabotage(db: Data, rival: Dictionary, day: int) -> void:
	var re := db.econ(rival)
	var shares: Array = re.get("site_shares", [])
	if shares.is_empty():
		return
	var i := _rng.randi_range(0, shares.size() - 1)
	var strikes: Array = re["strikes"]
	strikes.append({"site": i, "weeks": _rng.randi_range(2, 5), "людей": float(re["N"]) * float(shares[i]), "sabotage": true})
	re["шок"] = float(re.get("шок", 0.0)) + log(0.95)
	Goods.reputation_event(db, re, -1.0, 0.05)


func _raise_tension(a: Dictionary, b: Dictionary, amount: float) -> void:
	var k := _pair(str(a["id"]), str(b["id"]))
	tension[k] = float(tension.get(k, 0.0)) + amount


static func _pair(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


# ---------- 2. corporate wars ----------

func _wars_step(db: Data, game: PaxGame, goods: Goods, debt: Debt, cfg: Dictionary, day: int) -> void:
	# New wars: tension over the threshold.
	for k in tension.keys():
		if float(tension[k]) < float(cfg.get("war_threshold", 1.0)) or at_war_pair(str(k)):
			continue
		var ids := str(k).split("|")
		var a := db.company(ids[0])
		var b := db.company(ids[1])
		if a.is_empty() or b.is_empty() or same_group(a, b):
			continue
		wars.append({"a": ids[0], "b": ids[1], "from_day": day, "weeks": 0, "heat": 0.3})
		stats["войн"] = int(stats.get("войн", 0)) + 1
		for pair in [[a, b], [b, a]]:
			_chron(pair[0], day, {"вид": "война", "что": "начало", "rival": str((pair[1] as Dictionary)["id"])})
		news.append({"c": a, "entry": _chron_last(a), "tone": "bad", "size": 0.6, "big": true})
		_relations(db, game, a, b, day, true, cfg)
	# Running wars.
	var left: Array = []
	for w in wars:
		var war: Dictionary = w
		var a := db.company(str(war["a"]))
		var b := db.company(str(war["b"]))
		if a.is_empty() or b.is_empty() or same_group(a, b):
			continue   # one side was bought by the other (or its group) — the war is over
		war["weeks"] = int(war["weeks"]) + 1
		war["heat"] = clampf(float(war["heat"]) + _rng.randf_range(-0.05, 0.08), 0.1, 1.0)
		var attacks := float(cfg.get("war_attacks_per_week", 0.25)) * (0.5 + float(war["heat"]))
		for side in [[a, b], [b, a]]:
			var ea := db.econ(side[0])
			ea["extra_costs"] = float(ea.get("extra_costs", 0.0)) + float(cfg.get("war_spending", 0.01)) * float(war["heat"])
			if _rng.randf() < attacks:
				_move(db, side[0], side[1], cfg, day, true)
			# The bigger side may try to end it by buying the other.
			if db.cap(side[0]) >= 2.0 * db.cap(side[1]) and _rng.randf() < 0.01:
				_try_takeover(db, goods, debt, side[0], side[1], cfg, day)
		_relations(db, game, a, b, day, false, cfg)
		var tired := 0.0
		for side in [a, b]:
			var es := db.econ(side)
			if float(es.get("money", 0.0)) < 0.0 or float(es.get("P", 0.0)) < 0.0:
				tired += 0.08
		if int(war["weeks"]) >= int(cfg.get("war_min_weeks", 12)) \
				and _rng.randf() < float(cfg.get("war_end_chance", 0.03)) + tired:
			for pair in [[a, b], [b, a]]:
				_chron(pair[0], day, {"вид": "война", "что": "конец", "rival": str((pair[1] as Dictionary)["id"]), "weeks": int(war["weeks"])})
			news.append({"c": a, "entry": _chron_last(a), "tone": "neutral", "size": 0.4, "big": true})
			tension.erase(_pair(str(war["a"]), str(war["b"])))
			continue
		left.append(war)
	wars = left


func at_war_pair(key: String) -> bool:
	for w in wars:
		if _pair(str((w as Dictionary)["a"]), str((w as Dictionary)["b"])) == key:
			return true
	return false


func wars_of(cid: String) -> Array:
	return wars.filter(func(w): return str(w["a"]) == cid or str(w["b"]) == cid)


## A war between a company of the player's country and a foreign one sours the relations of the countries
## (the game's faction «отношение» towards the player).
func _relations(db: Data, game: PaxGame, a: Dictionary, b: Dictionary, day: int, first: bool, cfg: Dictionary) -> void:
	var player := str(game.player_faction().get("name", ""))
	var ca := str(a.get("_country", ""))
	var cb := str(b.get("_country", ""))
	if ca == cb or (ca != player and cb != player):
		return
	var other := cb if ca == player else ca
	for f in game.factions():
		var fd: Dictionary = f
		if str(fd.get("name", "")) == other and fd.has("relations"):
			fd["relations"] = maxf(0.0, float(fd["relations"]) - float(cfg.get("relations_per_week", 0.002)))
			if first:
				var mine: Dictionary = a if ca == player else b
				_chron(mine, day, {"вид": "война", "что": "дипломатия", "country": other})
				news.append({"c": mine, "entry": _chron_last(mine), "tone": "bad", "size": 0.5, "big": true})
			return


# ---------- 3. takeovers ----------

func _try_takeover(db: Data, goods: Goods, debt: Debt, buyer: Dictionary, forced: Dictionary, cfg: Dictionary, day: int) -> void:
	var eb := db.econ(buyer)
	# Snowball protection (20.19): one deal a year per company, and a pause after a takeover.
	if forced.is_empty() and day - int(eb.get("deal_day", -99999)) < int(cfg.get("deal_pause_days", 364)):
		return
	var target := forced
	if target.is_empty():
		var options: Array = []
		var total := 0.0
		var seen := {}
		for pool in [goods.home_pool(buyer), goods.world_pool(buyer)]:
			for cid in goods.members.get(pool, []):
				var o := db.company(str(cid))
				if o.is_empty() or str(o["id"]) == str(buyer["id"]) or seen.has(str(cid)) or same_group(buyer, o) or db.state_share(o) > 0.5 \
						or not parent_of(o).is_empty():   # already controlled by another group
					continue
				seen[str(cid)] = true
				if db.cap(o) * float(cfg.get("takeover_size", 3.0)) > db.cap(buyer) \
						or not open_border(cfg, str(buyer.get("_country", "")), str(o.get("_country", ""))) \
						or Zones.closed(str(o.get("_country", "")), str(buyer.get("_country", ""))) \
						or Zones.screened(o, str(buyer.get("_country", ""))):
					continue
				var home_w := float((cfg.get("foreign_list", {}) as Dictionary).get("own_weight", 5.0))
				var w := (1.0 + maxf(0.0, -db.change(o, 52))) * (home_w if str(o.get("_country", "")) == str(buyer.get("_country", "")) else 1.0) \
					* (2.0 if Zones.same_zone(str(o.get("_country", "")), str(buyer.get("_country", ""))) else 1.0)   # a union integrates its companies
				options.append([o, w])
				total += w
		var x := _rng.randf() * total
		for opt in options:
			x -= float(opt[1])
			if x <= 0.0:
				target = opt[0]
				break
	if target.is_empty() or db.state_share(target) > 0.5 or same_group(buyer, target) or not parent_of(target).is_empty() \
			or not open_border(cfg, str(buyer.get("_country", "")), str(target.get("_country", ""))) \
			or Zones.closed(str(target.get("_country", "")), str(buyer.get("_country", ""))) \
			or Zones.screened(target, str(buyer.get("_country", ""))):
		return
	var bid := str(buyer["id"])
	# A foreigner taking control of a strategic industry: the target's government usually says no.
	var foreign := str(buyer.get("_country", "")) != str(target.get("_country", ""))
	var fcfg: Dictionary = cfg.get("foreign_list", {})
	if foreign and str(target.get("profile", "")) in (fcfg.get("strategic", []) as Array) \
			and _rng.randf() < float(fcfg.get("strategic_ban", 0.8)):
		stats["forbidden"] = int(stats.get("forbidden", 0)) + 1
		_chron(buyer, day, {"вид": "takeover", "что": "запрет_власти", "rival": str(target["id"]), "country": str(target.get("_country", ""))})
		_chron(target, day, {"вид": "takeover", "что": "запрет_цель", "rival": bid})
		news.append({"c": target, "entry": _chron_last(target), "tone": "neutral", "size": 0.3, "big": false})
		return
	var own := stake_of(target, bid)
	var want := 0.51 - own
	if want <= 0.0:
		return
	# Who sells: the free float always; the big private holders only in a friendly deal.
	var independence := float(((target.get("_statuses", {}) as Dictionary).get("независимость", {}) as Dictionary).get("value", 50.0)) / 100.0
	var hostile := _rng.randf() < float(cfg.get("hostile_chance", 0.4)) * (0.5 + independence)
	if _rng.randf() > db.tree(target, "takeover", 1.0):
		return   # the industry tree's takeover defence (tree.gd)
	var free := 0.0
	var private := 0.0
	for o in target.get("owners", []):
		var od: Dictionary = o
		var kind := str(od.get("type", ""))
		if kind == "частные":
			free += float(od.get("доля", 0.0))
		elif kind in ["крупный", "founder", "company", "сама"] and str(od.get("company", "")) != bid:
			private += float(od.get("доля", 0.0))
	# A hostile bid: a target with money buys back its own shares (20.6) — fewer shares left for the raider,
	# and often the raider gives up.
	if hostile and Stakes.buyback(db, target, float(cfg.get("defence_buyout", 0.05)), day, "защита") > 0.0:
		free = Stakes.free_float(target)
		if _rng.randf() < float(cfg.get("defence_success", 0.5)):
			stats["repelled"] = int(stats.get("repelled", 0)) + 1
			_chron(buyer, day, {"вид": "takeover", "что": "repelled", "rival": str(target["id"])})
			news.append({"c": target, "entry": _chron_last(target), "tone": "good", "size": 0.3, "big": false})
			_raise_tension(buyer, target, 0.5)
			return
	# A white knight: a friendly company of the target's country outbids the raider and takes the stake itself.
	if hostile and _rng.randf() < float(cfg.get("white_knight_chance", 0.35)):
		var knight := _white_knight(db, target, buyer, cfg)
		if not knight.is_empty():
			var kstake := minf(0.51 - stake_of(target, str(knight["id"])), free + private)
			var kcost := db.cap(target) * kstake * (1.0 + float(cfg.get("premium", 0.3)) + float(cfg.get("white_knight_markup", 0.1)))
			var ek := db.econ(knight)
			ek["money"] = float(ek.get("money", 0.0)) - kcost
			ek["deal_day"] = day
			_transfer(target, knight, kstake, false)
			target["_owners_changed"] = true
			if stake_of(target, str(knight["id"])) > 0.5:
				target["_new_owner"] = str(knight["id"])
			stats["white_knights"] = int(stats.get("white_knights", 0)) + 1
			_chron(buyer, day, {"вид": "takeover", "что": "рыцарь_перебил", "rival": str(target["id"]), "knight": str(knight["id"])})
			_chron(target, day, {"вид": "takeover", "что": "белый_рыцарь", "rival": str(knight["id"]), "доля": kstake, "count_value": kcost})
			news.append({"c": target, "entry": _chron_last(target), "tone": "good", "size": 0.5, "big": true})
			deals.append({"день": day, "вид": "белый_рыцарь", "a": str(knight["id"]), "b": str(target["id"]), "доля": kstake, "amount": kcost, "control": true})
			_raise_tension(buyer, knight, 0.5)
			return
	var stake := minf(want, free + (0.0 if hostile else private))
	if stake + own < 0.25:
		return   # not even a blocking stake — no deal
	# The competition authority: one company must not hold too much of its home market. How strict it is —
	# its quality and, in the player's country, its mood towards the player (departments.gd).
	var same_home := goods.home_pool(buyer) == goods.home_pool(target)
	if same_home and float(eb.get("home_share", 0.0)) + float(db.econ(target).get("home_share", 0.0)) > float(cfg.get("antitrust_threshold", 0.4)) \
			and _rng.randf() < clampf(float(cfg.get("antitrust_ban", 0.7)) * db.antitrust(str(target.get("_country", ""))), 0.0, 0.98):
		stats["forbidden"] = int(stats.get("forbidden", 0)) + 1
		_chron(buyer, day, {"вид": "takeover", "что": "ban", "rival": str(target["id"])})
		_chron(target, day, {"вид": "takeover", "что": "запрет_цель", "rival": bid})
		news.append({"c": buyer, "entry": _chron_last(buyer), "tone": "neutral", "size": 0.3, "big": false})
		_raise_tension(buyer, target, 0.3)
		return
	var cost := db.cap(target) * stake * (1.0 + float(cfg.get("premium", 0.3)))
	var cash := float(eb.get("money", 0.0))
	var borrow := maxf(0.0, cost - maxf(cash, 0.0))
	if borrow > 0.0 and (float(eb.get("debt", 0.0)) + borrow) / maxf(float(eb.get("R", 1.0)), 1.0) > float(cfg.get("debt_to_revenue_max", 2.5)):
		return   # the banks will not lend that much
	eb["money"] = cash - (cost - borrow)
	if borrow > 0.0:
		var loan := {"creditor": {"ru": "Кредит на поглощение", "en": "Acquisition loan"}, "вид": "bank", "company": "",
			"amount": borrow, "floating": true, "repayment": day + _rng.randi_range(4, 7) * 52 * 7}
		loan["rate"] = debt.market_rate(db, buyer, "bank")
		(eb["loans"] as Array).append(loan)
		debt._sum(eb)
	_transfer(target, buyer, stake, hostile)
	target["_owners_changed"] = true
	var et := db.econ(target)
	et["шок"] = float(et.get("шок", 0.0)) + log(1.0 + 0.5 * float(cfg.get("premium", 0.3)))
	eb["шок"] = float(eb.get("шок", 0.0)) + log(0.97)
	et["c_nl"] = float(et["c_nl"]) * 0.99   # the group buys and sells together
	var control := own + stake >= 0.5
	eb["deal_day"] = day
	if control:
		target["_new_owner"] = bid   # lifecycle.gd puts the parent's man in charge
	stats["поглощений" if control else "пакетов"] = int(stats.get("поглощений" if control else "пакетов", 0)) + 1
	var entry := {"вид": "takeover", "что": "купила", "rival": str(target["id"]), "доля": stake, "count_value": cost, "hostile": hostile, "control": control}
	_chron(buyer, day, entry)
	_chron(target, day, {"вид": "takeover", "что": "куплена", "rival": bid, "доля": stake, "count_value": cost, "hostile": hostile, "control": control})
	news.append({"c": target, "entry": _chron_last(target), "tone": "neutral", "size": 0.7 if control else 0.4, "big": control})
	deals.append({"день": day, "вид": "takeover", "a": bid, "b": str(target["id"]), "доля": stake, "amount": cost, "control": control})
	while deals.size() > 40:
		deals.pop_front()
	if hostile:
		_raise_tension(buyer, target, 0.5)


## A friendly company that would save the target from a raider: the target's country, big and rich enough,
## not in the raider's group, not at war with the target.
func _white_knight(db: Data, target: Dictionary, raider: Dictionary, cfg: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var need := db.cap(target) * 0.51 * (1.0 + float(cfg.get("premium", 0.3)) + float(cfg.get("white_knight_markup", 0.1)))
	for item in db.companies:
		var o: Dictionary = item
		if str(o.get("_country", "")) != str(target.get("_country", "")) or str(o["id"]) == str(target["id"]) or str(o["id"]) == str(raider["id"]):
			continue
		if same_group(o, raider) or same_group(o, target) or at_war_pair(_pair(str(o["id"]), str(target["id"]))):
			continue
		if float(db.econ(o).get("money", 0.0)) < need or db.cap(o) < db.cap(target):
			continue
		if best.is_empty() or db.cap(o) > db.cap(best):
			best = o
	return best


static func stake_of(c: Dictionary, holder_id: String) -> float:
	var s := 0.0
	for o in c.get("owners", []):
		if str((o as Dictionary).get("company", "")) == holder_id:
			s += float((o as Dictionary).get("доля", 0.0))
	return s


static func _transfer(target: Dictionary, buyer: Dictionary, stake: float, hostile: bool) -> void:
	var owners: Array = target.get("owners", [])
	var left := stake
	for pass_kinds in [["частные"], ["крупный", "founder", "company", "сама"]]:
		if hostile and pass_kinds.size() > 1:
			break
		for o in owners:
			var od: Dictionary = o
			if left <= 0.0 or not (str(od.get("type", "")) in pass_kinds) or str(od.get("company", "")) == str(buyer["id"]):
				continue
			var take := minf(left, float(od.get("доля", 0.0)))
			od["доля"] = float(od["доля"]) - take
			left -= take
	var holder: Dictionary = {}
	for o in owners:
		if str((o as Dictionary).get("company", "")) == str(buyer["id"]):
			holder = o
	if holder.is_empty():
		holder = {"кто": (buyer.get("название", {}) as Dictionary).duplicate(), "type": "company", "country": str(buyer.get("_country", "")),
			"company": str(buyer["id"]), "доля": 0.0}
		owners.append(holder)
	holder["доля"] = float(holder["доля"]) + (stake - left)
	target["owners"] = owners.filter(func(o): return float((o as Dictionary).get("доля", 0.0)) > 0.00005)


## Owned companies pay their dividends to the parent (its money).
func _pay_parents(db: Data) -> void:
	for item in db.companies:
		var c: Dictionary = item
		var div := float(db.econ(c).get("dividends_now", 0.0))
		if div <= 0.0:
			continue
		for o in c.get("owners", []):
			var od: Dictionary = o
			var pid := str(od.get("company", ""))
			if str(od.get("type", "")) == "company" and not pid.is_empty():
				var pe := db.econ(db.company(pid))
				if not pe.is_empty():
					pe["money"] = float(pe.get("money", 0.0)) + float(od.get("доля", 0.0)) * div * db.dt / 52.0


# ---------- 4. breakups ----------

## A site with its people and part of the business becomes a new company of the same shareholders.
## why: «распад» (the company falls apart) or «антимонополия» (the regulator splits a monopoly).
## Returns the new company ({} when the company has nothing to split off).
func split(db: Data, c: Dictionary, why: String, day: int) -> Dictionary:
	var e := db.econ(c)
	var pts: Array = c.get("sites", [])
	var hq := db.hq_of(c)
	var shares: Array = e.get("site_shares", [])
	var best := -1
	for i in pts.size():
		if pts[i] == hq:
			continue
		if best < 0 or (i < shares.size() and best < shares.size() and float(shares[i]) > float(shares[best])):
			best = i
	if best < 0:
		return {}
	var s := clampf(float(shares[best]) if best < shares.size() else 0.2, 0.1, 0.4)
	var site: Dictionary = (pts[best] as Dictionary).duplicate(true)
	# The new company's own data (what companies/*.json would hold).
	var child := {}
	for k in c.keys():
		if not str(k).begins_with("_"):
			child[k] = c[k].duplicate(true) if (c[k] is Dictionary or c[k] is Array) else c[k]
	var n := 2
	while not db.company("%s_%d" % [str(c["id"]), n]).is_empty():
		n += 1
	var year := int(Pax.game.date().get("year", 2026)) if Pax.game != null else 2026
	child["id"] = "%s_%d" % [str(c["id"]), n]
	child["split_from"] = str(c["id"])
	child["название"] = {"ru": "%s: %s" % [str((c["название"] as Dictionary).get("ru", "")), str((site["name"] as Dictionary).get("ru", ""))],
		"en": "%s: %s" % [str((c["название"] as Dictionary).get("en", "")), str((site["name"] as Dictionary).get("en", ""))]}
	child["description"] = _both("spinoff_desc_" + why, [str((c["название"] as Dictionary).get("ru", "")), year],
		[str((c["название"] as Dictionary).get("en", "")), year])
	child["founded"] = year
	child["type"] = "частная" if str(c.get("type", "")) == "частная" else str(c.get("type", ""))
	child["sites"] = [site]
	child["промыслы"] = []
	child["рынок"] = {"shares_mln": db.shares(c) * s, "market_cap": db.cap(c) * s}
	var f: Dictionary = c.get("fundamental", {})
	child["fundamental"] = {"выручка": db.fund(c, "выручка") * s, "profit": db.fund(c, "profit") * s, "debt": db.fund(c, "debt") * s,
		"money": db.fund(c, "money") * s, "dividends": float(f.get("dividends", 0.0)) * s}
	child["глава"] = {"name": _both("spinoff_head", [], []), "роль": "наёмный_управляющий", "с_года": year, "born_year": year - 50, "доля": 0.0,
		"характер": (c.get("глава", {}) as Dictionary).get("характер", "")}
	child["staff"] = int(float(e["N"]) * s)
	child["wage"] = float(e["W"])
	child["оценка"] = []
	child["_country"] = str(c.get("_country", ""))
	child["_new"] = true
	child["_price"] = db.price(c)
	child["_history"] = [db.price(c)]
	child["_chronicle"] = []
	child["_statuses"] = {}
	# The money side: the child takes its part of everything, the parent keeps the rest.
	var ce: Dictionary = e.duplicate(true)
	for key in ["N", "D0", "R0", "P0", "cap0", "money", "debt", "R", "P", "фот", "нужно", "demand_money", "offer", "interest",
			"fair", "home_share0", "world_share0", "home_share", "world_share", "market_home", "market_world"]:
		if e.has(key):
			ce[key] = float(e[key]) * s
			e[key] = float(e[key]) * (1.0 - s)
	for loans_of in [[ce, s], [e, 1.0 - s]]:
		for loan in (loans_of[0] as Dictionary).get("loans", []):
			(loan as Dictionary)["amount"] = float((loan as Dictionary)["amount"]) * float(loans_of[1])
	ce["site_shares"] = [1.0]
	ce["strikes"] = []
	ce["flows"] = []
	ce["headcount_history"] = [float(ce["N"])]
	ce["fired26"] = 0.0
	for hkey in ["R_history", "debt_history"]:
		if ce.get(hkey) is Array:
			ce[hkey] = (ce[hkey] as Array).map(func(v): return float(v) * s)
			e[hkey] = (e[hkey] as Array).map(func(v): return float(v) * (1.0 - s))
	child["_ec"] = ce
	# The parent loses the site; its share price falls by the part that left (the history is rescaled so the
	# chart stays continuous — like an exchange adjusts prices for a spin-off).
	pts.remove_at(best)
	c["sites"] = pts
	c["_sites_changed"] = true
	if best < shares.size():
		shares.remove_at(best)
		var sum := 0.0
		for v in shares:
			sum += float(v)
		e["site_shares"] = shares.map(func(v): return float(v) / sum if sum > 0.0 else 0.0)
	e["strikes"] = []
	c["_price"] = db.price(c) * (1.0 - s)
	c["_history"] = (c["_history"] as Array).map(func(v): return float(v) * (1.0 - s))
	db.add_company(child)
	stats["распадов" if why == "breakup" else "разделов"] = int(stats.get("распадов" if why == "breakup" else "разделов", 0)) + 1
	_chron(c, day, {"вид": "breakup", "что": why, "rival": str(child["id"]), "доля": s})
	_chron(child, day, {"вид": "breakup", "что": "новая", "rival": str(c["id"]), "доля": s})
	news.append({"c": c, "entry": _chron_last(c), "tone": "bad", "size": 0.6, "big": true})
	deals.append({"день": day, "вид": why, "a": str(c["id"]), "b": str(child["id"]), "доля": s, "amount": db.cap(child)})
	while deals.size() > 40:
		deals.pop_front()
	return child


## A {"ru", "en"} text from the mod's language files (data stays bilingual like companies/*.json).
func _both(key: String, args_ru: Array, args_en: Array) -> Dictionary:
	var ru := str(_lang_ru.get("pax_corporations_" + key, key))
	var en := str(_lang_en.get("pax_corporations_" + key, key))
	return {"ru": ru % args_ru if not args_ru.is_empty() else ru, "en": en % args_en if not args_en.is_empty() else en}


# ---------- helpers ----------

func _chron(c: Dictionary, day: int, entry: Dictionary) -> void:
	entry["день"] = day
	(c["_chronicle"] as Array).append(entry)


func _chron_last(c: Dictionary) -> Dictionary:
	var ch: Array = c["_chronicle"]
	return ch[ch.size() - 1]


# ---------- save ----------

## Companies born in the game (breakups) are saved whole — their data is in no file; the sites of the
## companies that lost one are saved too.
func save_state(db: Data) -> Dictionary:
	var born: Array = []
	var sites := {}
	for item in db.companies:
		var c: Dictionary = item
		if bool(c.get("_new", false)):
			var data := {}
			for k in c.keys():
				if not str(k).begins_with("_") or str(k) == "_country":
					data[k] = c[k]
			born.append(data)
		if bool(c.get("_sites_changed", false)):
			sites[str(c["id"])] = c.get("sites", [])
	return {"зерно": str(_rng.seed), "состояние": str(_rng.state), "wars": wars, "tension": tension, "deals": deals,
		"results": stats, "новые": born, "sites": sites}


## Before the other modules load their state: the born companies must exist, the changed sites be back.
static func restore_companies(db: Data, state: Dictionary) -> void:
	for item in state.get("новые", []):
		if not (item is Dictionary) or not db.company(str((item as Dictionary).get("id", ""))).is_empty():
			continue
		var c: Dictionary = (item as Dictionary).duplicate(true)
		c["_new"] = true
		var market: Dictionary = c.get("рынок", {})
		c["_price"] = float(market.get("market_cap", 0.0)) / maxf(float(market.get("shares_mln", 1.0)), 0.001)
		c["_history"] = [c["_price"]]
		c["_chronicle"] = []
		c["_statuses"] = {}
		db.add_company(c)
	var sites: Variant = state.get("sites", {})
	if sites is Dictionary:
		for cid in (sites as Dictionary).keys():
			var c := db.company(str(cid))
			if not c.is_empty() and (sites as Dictionary)[cid] is Array:
				c["sites"] = ((sites as Dictionary)[cid] as Array).duplicate(true)
				c["_sites_changed"] = true


func load_state(state: Dictionary) -> void:
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
	wars = (state.get("wars", []) as Array).duplicate(true) if state.get("wars") is Array else []
	tension = (state.get("tension", {}) as Dictionary).duplicate() if state.get("tension") is Dictionary else {}
	deals = (state.get("deals", []) as Array).duplicate(true) if state.get("deals") is Array else []
	stats = (state.get("results", {}) as Dictionary).duplicate() if state.get("results") is Dictionary else {}
