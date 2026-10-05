extends RefCounted
## The antimonopoly service of the player's country (a state department, config departments.json «антимонополия»
## and balance.json «антимонополия»). Its quality (the money it gets) makes it stronger — the competition
## authority of every country works through corp_data.antitrust(): bans of takeovers and mergers, splits
## of monopolies (rivals.gd, lifecycle.gd). At home it also has a mood towards the player's government, 0–100:
##
##   target = 50 + funding (a service that gets its money is loyal) + corruption (a corrupt one closes its eyes)
##            − the state's grip on the economy against the start − state monopolies − the memory of the
##            government's own deals (stake purchases, state companies in crowded markets, cosy sponsorships;
##            the memory fades); the mood moves towards it slowly.
##
## A hostile service (below «плохо») gets in the way: it blocks the state's stake purchases that give it
## control of a big player, blocks new state companies in markets the state already holds, opens cases
## against monopolists — fines, and orders to split even state monopolies; the stricter, the more often.
## A friendly one (above «хорошо») turns a blind eye: no checks of the state's deals, no cases, fewer bans
## of companies' takeovers. Its letters come to the «Письма» tab (letters.gd).

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")
const Rivals := preload("res://mods/pax_corporations/src/companies/rivals.gd")

var mood := -1.0                 # −1 — not set yet (the first week sets it to its target)
var parts: Array = []            # [[key, points], …] of the target, for the window
var memory := 0.0                # the government's deals the service remembers (points, fade)
var cases: Array = []            # the latest cases: {день, id, что, сумма}
var events_for_letters: Array = []
var news: Array = []
var _conc0 := -1.0               # the state's share of the country's market value at the start
var _zone := "норма"             # плохо | норма | хорошо — letters go out when it changes
var _rng := RandomNumberGenerator.new()


func start_new() -> void:
	_rng.randomize()


func _cfg(db: Data) -> Dictionary:
	return db.balance.get("antitrust", {})


func bad(db: Data) -> bool:
	return mood >= 0.0 and mood < float(_cfg(db).get("плохо", 35.0))


func good(db: Data) -> bool:
	return mood > float(_cfg(db).get("хорошо", 65.0))


# ---------- weekly ----------

func step(db: Data, game: PaxGame, funding: float, rivals: Rivals, day: int) -> void:
	events_for_letters.clear()
	news.clear()
	var cfg := _cfg(db)
	var player := str(game.player_faction().get("name", ""))
	memory *= pow(1.0 - float(cfg.get("memory_decay", 0.015)), db.dt)
	var home: Array = db.companies.filter(func(x): return str(x.get("_country", "")) == player)
	var total := 0.0
	var state_value := 0.0
	var state_monopolies := 0
	for item in home:
		var c: Dictionary = item
		total += db.cap(c)
		state_value += db.cap(c) * db.state_share(c)
		if db.state_share(c) > 0.5 and _mono(c) >= float(cfg.get("monopoly_from", 50.0)):
			state_monopolies += 1
	var conc := state_value / total if total > 0.0 else 0.0
	if _conc0 < 0.0:
		_conc0 = conc
	parts = [["base", 50.0],
		["funding", float(cfg.get("per_funding", 15.0)) * clampf(funding - 1.0, -1.0, 1.0)],
		["corruption", float(cfg.get("per_corruption", 30.0)) * (db.country_corruption(player) - 0.3)],
		["state_grip", -float(cfg.get("per_nationalisation", 60.0)) * maxf(0.0, conc - _conc0)],
		["state_monopolies", -minf(20.0, float(cfg.get("per_state_monopoly", 4.0)) * state_monopolies)],
		["deals", memory]]
	var target := 0.0
	for p in parts:
		target += float(p[1])
	target = clampf(target, 0.0, 100.0)
	mood = target if mood < 0.0 else mood + (1.0 - pow(1.0 - float(cfg.get("speed", 0.05)), db.dt)) * (target - mood)
	db.antitrust_mood = mood
	var zone := "плохо" if bad(db) else ("хорошо" if good(db) else "норма")
	if zone != _zone:
		events_for_letters.append({"вид": "служба_настроение", "zone": zone, "было": _zone})
		_zone = zone
	if not good(db):
		_cases(db, home, rivals, cfg, day)


## Cases against monopolists. A friendly service opens none; a hostile one goes after state monopolies too.
func _cases(db: Data, home: Array, rivals: Rivals, cfg: Dictionary, day: int) -> void:
	var strict := db.antitrust(db.player_country)
	var yearly := float(cfg.get("cases_per_year", 0.2)) * strict
	for item in home:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty() or _mono(c) < float(cfg.get("monopoly_from", 50.0)) or db.tree(c, "antitrust", 1.0) <= 0.0:
			continue
		var state := db.state_share(c) > 0.5
		if state and not bad(db):
			continue
		if _rng.randf() >= yearly * db.dt / 52.0:
			continue
		if state and _mono(c) >= float(cfg.get("split_from_share", 60.0)) and rivals != null:
			var child := rivals.split(db, c, "antitrust", day)
			if not child.is_empty():
				_case(c, day, "section", 0.0, str(child["id"]))
			continue
		var fine := float(e.get("R", 0.0)) * float(cfg.get("fine_from_revenue", 0.02))
		e["money"] = float(e.get("money", 0.0)) - fine
		if e.has("trust"):
			e["trust"] = maxf(0.0, float(e["trust"]) - float(cfg.get("fine_trust", 8.0)))
		_case(c, day, "fine", fine, "")
		db.dept_fines += fine   # main pays the fines into the treasury


func _case(c: Dictionary, day: int, what: String, amount: float, other: String) -> void:
	var entry := {"день": day, "вид": "antitrust", "что": what, "count_value": amount, "rival": other}
	(c["_chronicle"] as Array).append(entry)
	news.append({"c": c, "entry": entry, "tone": "bad", "size": 0.5, "big": true})
	cases.append({"день": day, "id": str(c["id"]), "что": what, "amount": amount})
	while cases.size() > 30:
		cases.pop_front()
	events_for_letters.append({"вид": "служба_дело", "c": c, "что": what, "amount": amount})


static func _mono(c: Dictionary) -> float:
	return float(((c.get("_statuses", {}) as Dictionary).get("monopolism", {}) as Dictionary).get("value", 0.0))


# ---------- instant reviews of the government's own deals ----------
# The service answers right away (main.gd shows its verdict as a notification and a letter): the stake
# purchases and sales of the state, a state company founded, the player's orders about competition or about
# a company (the game's «order_parsed» hook).

## A stake bought (buy) or sold by the state. Returns {решение: молча|одобрено|условие|запрет, сбор: млн $,
## ключ: lang key of the verdict, риск}. «условие» — the deal goes through with an extra fee to the budget.
func review_stake(db: Data, c: Dictionary, fraction: float, amount: float, buy: bool, day: int = 0) -> Dictionary:
	var cfg := _cfg(db)
	var share := float(db.econ(c).get("home_share_mod", 0.0))
	var mono := _mono(c) / 100.0
	if not buy:
		# Privatisation: the state leaves the market — the service likes it.
		if fraction < 0.02:
			return {"decision": "молча", "fee": 0.0, "ключ": "", "риск": 0.0}
		remember(db, "privatisation", -fraction * 10.0)
		return {"decision": "одобрено", "fee": 0.0, "ключ": "am_review_sell", "риск": 0.0}
	var before := db.state_share(c)
	var after := before + fraction
	# Creeping acquisition: the service adds up the state's purchases of this company over «скупка_дней» — five
	# blocks of 10 % are one deal of 50 %, judged (and charged) as one.
	var recent := recent_buys(c, day, int(cfg.get("buyup_days", 365)))
	var block := float(recent["доля"]) + fraction
	var creeping := float(recent["доля"]) >= 0.02
	var significant := block >= 0.02 or after >= 0.25 or share >= 0.15 or mono >= 0.3
	if not significant:
		return {"decision": "молча", "fee": 0.0, "ключ": "", "риск": 0.0, "блок": block}
	var risk := 0.6 * after + float(cfg.get("buyup_weight", 0.5)) * block + share + mono + (0.4 if before <= 0.5 and after > 0.5 else 0.0)
	var strict := risk * db.antitrust(db.player_country)
	if good(db):
		return {"decision": "одобрено", "fee": 0.0, "ключ": "am_review_ok_friendly", "риск": strict, "блок": block}
	if strict >= float(cfg.get("ban_from", 1.4)):
		remember(db, "ban", 1.0)   # the attempt itself irritates the service
		return {"decision": "ban", "fee": 0.0, "ключ": "am_review_ban_creep" if creeping else "am_review_ban", "риск": strict, "блок": block}
	if strict >= float(cfg.get("condition_from", 0.7)):
		var k := clampf(0.03 + 0.07 * (strict - 0.7) / 0.7, 0.03, 0.1)
		# The fee is for the whole block: the earlier pieces that went through free are charged now.
		var fee := maxf(0.0, (amount + float(recent["amount"])) * k - float(recent["fee"]))
		return {"decision": "условие", "fee": fee, "ключ": "am_review_fee_creep" if creeping else "am_review_fee", "риск": strict, "блок": block}
	return {"decision": "одобрено", "fee": 0.0, "ключ": "am_review_ok", "риск": strict, "блок": block}


## The state's purchases of this company in the last `days`: {доля, сумма — paid, сбор — fees paid}.
static func recent_buys(c: Dictionary, day: int, days: int) -> Dictionary:
	var out := {"доля": 0.0, "amount": 0.0, "fee": 0.0}
	for h in c.get("_chronicle", []):
		if h is Dictionary and str((h as Dictionary).get("вид", "")) == "state_stake" and int((h as Dictionary).get("день", -99999)) >= day - days:
			var hd: Dictionary = h
			var sign := 1.0 if str(hd.get("что", "")) == "buyout" else -1.0
			out["доля"] = maxf(0.0, float(out["доля"]) + sign * float(hd.get("доля", 0.0)))
			out["amount"] = maxf(0.0, float(out["amount"]) + sign * float(hd.get("count_value", 0.0)))
			out["fee"] = float(out["fee"]) + float(hd.get("fee", 0.0))
	return out


## The service remembers what the government did: a stake bought, a state company founded, a sponsorship
## (positive size) or a privatisation (negative). The mood moves at once by the same amount.
func remember(db: Data, kind: String, size: float) -> void:
	var w: Dictionary = _cfg(db).get("память", {})
	var delta := -float(w.get(kind, 3.0)) * size
	memory = clampf(memory + delta, -40.0, 20.0)
	if mood >= 0.0:
		mood = clampf(mood + delta, 0.0, 100.0)
		db.antitrust_mood = mood


## A new state company: how much of its market the state already holds decides. Same answer as review_stake.
func review_founding(db: Data, goods: Goods, country: String, goods_key: String, capital: float) -> Dictionary:
	var state_part := 0.0
	for cid in goods.members.get("дом|%s|%s" % [goods_key, country], []):
		var o := db.company(str(cid))
		if not o.is_empty() and db.state_share(o) > 0.5:
			state_part += float(db.econ(o).get("home_share_mod", 0.0))
	if state_part < 0.1 or good(db):
		return {"decision": "молча" if state_part < 0.1 else "одобрено", "fee": 0.0, "ключ": "am_review_found_ok", "риск": state_part}
	var limit := float(_cfg(db).get("state_market_share_for_ban", 0.4))
	if bad(db) and state_part >= limit:
		remember(db, "ban", 1.0)
		return {"decision": "ban", "fee": 0.0, "ключ": "am_review_found_ban", "риск": state_part}
	if state_part >= limit * 0.6:
		return {"decision": "условие", "fee": capital * 0.05, "ключ": "am_review_found_fee", "риск": state_part}
	return {"decision": "одобрено", "fee": 0.0, "ключ": "am_review_found_ok", "риск": state_part}


const SERVICE_WORDS := ["антимонопол", "монопол", "фас ", "конкуренц", "antitrust", "monopol", "competition"]
const DEAL_WORDS := ["национализ", "купить", "выкуп", "поглот", "слия", "объедин", "захват", "отжать",
	"nationaliz", "nationalis", "buy ", "acquire", "take over", "merge"]


## The player's order (the game's «order_parsed» hook), before the game carries it out. Returns
## {вид: "" (not about the service) | дело | сделка | сведение, c: the company named, отмена: bool, ключ, сумма}.
## An order to go after a company opens a case at once: a monopolist is split, anyone else fined. An order to
## take over or nationalise a company is reviewed: a hostile service warns, a furious one blocks it.
func review_order(db: Data, rivals: Rivals, text: String, day: int) -> Dictionary:
	var low := " " + text.to_lower() + " "
	var about_service := _has_any(low, SERVICE_WORDS)
	var about_deal := _has_any(low, DEAL_WORDS)
	if not about_service and not about_deal:
		return {"вид": ""}
	var c := find_company(db, low)
	if about_service and not c.is_empty():
		var e := db.econ(c)
		var justified := _mono(c) >= float(_cfg(db).get("monopoly_from", 50.0))
		remember(db, "case_acquitted" if justified else "case_pressure", 1.0)
		if _mono(c) >= float(_cfg(db).get("split_from_share", 60.0)) and rivals != null:
			var child := rivals.split(db, c, "antitrust", day)
			if not child.is_empty():
				_case(c, day, "section", 0.0, str(child["id"]))
				return {"вид": "дело", "c": c, "отмена": false, "ключ": "am_order_split", "amount": 0.0}
		var fine := float(e.get("R", 0.0)) * float(_cfg(db).get("fine_from_revenue", 0.02)) * (1.0 if justified else 0.5)
		e["money"] = float(e.get("money", 0.0)) - fine
		db.dept_fines += fine
		_case(c, day, "fine", fine, "")
		return {"вид": "дело", "c": c, "отмена": false, "ключ": "am_order_fine" if justified else "am_order_fine_weak", "amount": fine}
	if about_deal and not c.is_empty() and str(c.get("_country", "")) == db.player_country:
		if mood >= 0.0 and mood < float(_cfg(db).get("very_bad", 20.0)):
			remember(db, "ban", 1.0)
			return {"вид": "сделка", "c": c, "отмена": true, "ключ": "am_order_blocked", "amount": 0.0}
		if bad(db):
			remember(db, "order_deal", 1.0)
			return {"вид": "сделка", "c": c, "отмена": false, "ключ": "am_order_warn", "amount": 0.0}
		if good(db):
			return {"вид": "сделка", "c": c, "отмена": false, "ключ": "am_order_ok", "amount": 0.0}
		remember(db, "order_deal", 0.5)
		return {"вид": "сделка", "c": c, "отмена": false, "ключ": "am_order_check", "amount": 0.0}
	if about_service:
		return {"вид": "сведение", "c": {}, "отмена": false, "ключ": "am_order_noted", "amount": 0.0}
	return {"вид": ""}


static func _has_any(text: String, words: Array) -> bool:
	for w in words:
		if text.contains(str(w)):
			return true
	return false


## The company an order names, by words: every word of one of its names must be in the order, a long word also with
## another ending («Роснефти», «Газпрома», «Курчатовского института»), a short one (ВТБ, BMW) as it is. The names
## are the ru and en titles, the brand in brackets («Fast Retailing (Uniqlo)» — also «Uniqlo») and the title without
## its legal form (ПАО, Inc, Group…). Before, the whole title had to stand in the order letter for letter — «купить
## акции Uniqlo» or «купить долю в Курчатовском институте» found nothing. The longest match
## wins; the player's country first.
static func find_company(db: Data, low: String) -> Dictionary:
	var words := words_of(low)
	var best: Dictionary = {}
	var best_len := 0
	for item in db.companies:
		var c: Dictionary = item
		for name_words in _names_of(c):
			var nw: PackedStringArray = name_words
			if not _all_in(nw, words):
				continue
			var score: int = "".join(nw).length() + (100 if str(c.get("_country", "")) == db.player_country else 0)
			if score > best_len:
				best = c
				best_len = score
	return best


static var _name_cache: Dictionary = {}   # "ru|en|id" -> [PackedStringArray of words…]
const LEGAL := ["пао", "оао", "зао", "ао", "ооо", "гк", "нк", "ип", "фгуп", "гуп", "inc", "corp", "corporation", "co", "ltd",
	"plc", "llc", "ag", "sa", "se", "nv", "group", "holding", "holdings", "company", "the", "компания", "группа", "холдинг"]


static func _names_of(c: Dictionary) -> Array:
	var names: Dictionary = c.get("название", {}) if c.get("название") is Dictionary else {"ru": str(c.get("название", ""))}
	var key := "%s|%s|%s" % [str(names.get("ru", "")), str(names.get("en", "")), str(c.get("id", ""))]
	if _name_cache.has(key):
		return _name_cache[key]
	var out: Array = []
	var texts: Array = [str(names.get("ru", "")), str(names.get("en", ""))]
	for t in texts.duplicate():
		var text := str(t)
		var open := text.find("(")
		if open >= 0:
			var close := text.find(")", open)
			texts.append(text.substr(open + 1, (close if close > open else text.length()) - open - 1))
			texts.append(text.substr(0, open))
	for alias in c.get("aliases", []):   # other names people use: «Вайлдберриз», «Пятёрочка» (companies/*.json)
		texts.append(str(alias))
	if not str(c.get("id", "")).begins_with("player_") and not str(c.get("id", "")).begins_with("born_"):
		texts.append(str(c.get("id", "")).replace("_", " "))
	for t in texts:
		var w := words_of(str(t).to_lower())
		var kept: PackedStringArray = []
		for x in w:
			if not (x in LEGAL):
				kept.append(x)
		if kept.is_empty() or "".join(kept).length() < 3:
			continue
		var same := false
		for o in out:
			if o == kept:
				same = true
		if not same:
			out.append(kept)
	_name_cache[key] = out
	return out


## Letters and digits in a row are a word («Сбер-банк» — two words); quotes and brackets are dropped.
static func words_of(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var cur := ""
	for ch in text:
		if ch.is_valid_int() or ch.to_lower() != ch.to_upper():
			cur += ch
		elif not cur.is_empty():
			out.append(cur)
			cur = ""
	if not cur.is_empty():
		out.append(cur)
	return out


## Every word of a name is in the order: a word of 7+ letters by its stem (without its last 2 letters), of 4–6 — without
## the last one (and at most 3 letters longer: «Полюс» is not «полиции»), a shorter one — the same word.
static func _all_in(name_words: PackedStringArray, words: PackedStringArray) -> bool:
	for nw in name_words:
		var n := nw.length()
		var stem := nw.substr(0, n - 2) if n >= 7 else (nw.substr(0, n - 1) if n >= 4 else nw)
		var found := false
		for w in words:
			if (n <= 3 and w == nw) or (n > 3 and w.begins_with(stem) and w.length() <= n + 3):
				found = true
				break
		if not found:
			return false
	return true


# ---------- save ----------

func save_state() -> Dictionary:
	return {"mood": mood, "память": memory, "дела": cases, "nat0": _conc0, "zone": _zone,
		"зерно": str(_rng.seed), "состояние": str(_rng.state)}


func load_state(state: Dictionary) -> void:
	mood = float(state.get("mood", -1.0))
	memory = float(state.get("память", 0.0))
	cases = (state.get("дела", []) as Array).duplicate(true) if state.get("дела") is Array else []
	_conc0 = float(state.get("nat0", -1.0))
	_zone = str(state.get("zone", "норма"))
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
