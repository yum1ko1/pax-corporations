extends RefCounted
## Debt and creditors (sections 6, 9, 20.14). Each company's debt is a set of loans:
##   {кредитор: {ru, en}, вид: банк|облигации|государство|иностранный|штраф, компания: id of a bank in the mod or "",
##    сумма (млн $), ставка (a year), плавающая: bool, погашение: game day}
## The rate = the country's base rate + the spread of the company's credit rating (20.14) + the lender's markup.
## Bank loans float after the market rate, bonds are fixed. Interest goes into the profit (economy.gd),
## so more debt or a worse rating means less profit and cheaper shares.
##
## Every week: loans that fall due are refinanced (a decent rating), repaid from cash, taken over by the state
## (state companies) — or the company defaults and the lender takes shares. A company out of cash draws an
## emergency loan; one with spare cash repays early. Random debt events raise the debt (a loan for a project,
## a fine, currency revaluation) or pay it off (state support for shares, the owner, a write-off, early repayment).

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const LENDER_MARKUP := {"bank": 0.01, "bonds": 0.0, "polity": -0.02, "foreign": -0.01, "fine": 0.0}
## Banks of the mod that lend to companies of their own country, biggest first.
const BIG_BANKS := ["sber", "vtb", "gazprombank", "alfa", "psb", "domrf", "rshb", "sovcombank",
	"jpmorgan", "bofa", "wellsfargo", "goldman", "morganstanley",
	"deutschebank", "commerzbank", "bnp", "creditagricole", "socgen", "intesa", "unicredit", "bancobpm", "mps",
	"icbc", "ccb", "abc", "boc", "cmb", "bocom",
	"hsbc", "barclays", "lloyds", "natwest", "fab", "enbd", "adcb", "mufg", "smfg", "mizuho",
	"santander", "bbva", "caixabank", "isbank", "ziraat", "garanti", "akbank", "nordea", "op",
	"ing", "abnamro", "rabobank", "seb", "handelsbanken", "swedbank", "pkobp", "pekao", "santanderpl", "mbank", "danske", "jyske", "nykredit", "kbc", "belfius", "erste", "rbi", "aib", "boi", "bcp", "cgd", "komercni", "moneta", "nbg", "eurobank", "piraeus", "alphabank", "bancatransilvania", "brd", "otp", "mbh", "fib", "zaba", "bankofcyprus", "hellenicbank", "lhv", "citadele", "siauliubankas", "nlb",
	"firstrand", "standardbank", "zenith", "access", "gtco", "nbe", "cib", "attijariwafa", "bcpmaroc", "bna", "equity", "kcb", "bfa", "gcb", "cbe", "awash", "crdb", "biat", "stanbicug", "fnbb", "mcb", "bk",
	"rbc", "td", "bmo", "scotiabank", "banorte", "bbvamexico", "privatbank", "belarusbank", "maib", "popular", "republicfin",
	"hdfcbank", "icici", "sbi", "kbfin", "shinhan", "cathay", "fubon", "leumi", "hapoalim", "itau", "bradesco", "bancodobrasil", "nubank", "btg", "galicia", "bancochile", "bancolombia", "credicorp", "pichincha", "cba", "nab", "westpac", "anz", "macquarie", "ubs", "dnb", "arion", "alrajhi", "snb", "riyadbank", "qnb", "nbk", "kfh", "bankmelli", "rafidain", "bankmuscat", "arabbank", "bca", "bri", "mandiri", "kbank", "maybank", "publicbank", "cimb", "vietcombank", "bdo", "halyk", "hbl", "bracbank", "ibaz", "kapitalbank", "tbc", "bog", "ameriabank", "acleda", "ecobank"]
## Where exporters of a country borrow abroad when the West is closed to them.
const FOREIGN_LENDERS := {"Россия": {"ru": "Китайские банки", "en": "Chinese banks"}}

var news: Array = []
var _rng := RandomNumberGenerator.new()


func start_new() -> void:
	_rng.randomize()


# ---------- setup ----------

func init_all(db: Data, day: int) -> void:
	for item in db.companies:
		init_company(db, item, day)


## Splits the starting debt into loans and takes the interest out of the other costs, so the starting
## profit stays what the data says.
func init_company(db: Data, c: Dictionary, day: int) -> void:
	var e := db.econ(c)
	if e.is_empty() or e.has("loans"):
		return
	var total := float(e.get("debt", 0.0))
	var loans: Array = []
	if total > 0.0:
		for part in _lenders(db, c):
			var share := float(part["доля"])
			var pieces := 2 if share >= 0.25 else 1
			for i in pieces:
				var loan := {"creditor": part["кто"], "вид": part["вид"], "company": part.get("company", ""),
					"amount": total * share / pieces, "floating": str(part["вид"]) == "bank",
					"repayment": day + _rng.randi_range(52, 6 * 52) * 7}
				loan["rate"] = market_rate(db, c, str(part["вид"]))
				loans.append(loan)
	e["loans"] = loans
	_sum(e)
	var r0 := maxf(float(e.get("R0", 1.0)), 1.0)
	e["c_nl"] = maxf(0.0, float(e.get("c_nl", 0.0)) - float(e["interest"]) / r0)


## Who lends to a company: the market (bonds), two big banks of the mod, and the state (state companies)
## or foreign banks (exporters). Banks themselves are not given loans — their debt is deposits.
func _lenders(db: Data, c: Dictionary) -> Array:
	var out: Array = []
	var banks: Array = []
	for bid in BIG_BANKS:
		var b := db.company(str(bid))
		if not b.is_empty() and str(b["id"]) != str(c["id"]) and str(b.get("_country", "")) == str(c.get("_country", "")):
			banks.append(b)
	var exporter := str(c.get("sector", "")) in ["oil_gas", "metallurgy"] and FOREIGN_LENDERS.has(str(c.get("_country", "")))
	var state := db.state_share(c) > 0.5
	out.append({"кто": {"ru": "Облигации на бирже", "en": "Bonds on the exchange"}, "вид": "bonds", "доля": 0.35})
	if banks.size() >= 1:
		var first: Dictionary = banks[0]
		out.append({"кто": first["название"], "вид": "bank", "company": str(first["id"]), "доля": 0.3})
	if banks.size() >= 2:
		var second: Dictionary = banks[_rng.randi_range(1, banks.size() - 1)]
		out.append({"кто": second["название"], "вид": "bank", "company": str(second["id"]), "доля": 0.2})
	var rest := 1.0
	for p in out:
		rest -= float(p["доля"])
	if state:
		out.append({"кто": {"ru": "ФНБ (государство)", "en": "National Wealth Fund (the state)"}, "вид": "polity", "доля": rest})
	elif exporter:
		out.append({"кто": FOREIGN_LENDERS[str(c.get("_country", ""))], "вид": "foreign", "доля": rest})
	else:
		out.append({"кто": {"ru": "Синдикат банков", "en": "A bank syndicate"}, "вид": "bank", "доля": rest})
	return out


## The rate a company would pay today: the country's base + the rating spread (20.14) + the lender's markup.
func market_rate(db: Data, c: Dictionary, kind: String) -> float:
	var cfg: Dictionary = db.balance.get("debt", {})
	var bases: Dictionary = cfg.get("country_rates", {})
	var base := float(bases.get(str(c.get("_country", "")), bases.get("_default", 0.05)))
	# A country's prestige makes its loans cheaper or dearer (arena.gd).
	base += float(db.rate_shift.get(str(c.get("_country", "")), 0.0))
	return maxf(0.01, base + db.spread_of(float(c.get("_q", 0.5))) + float(LENDER_MARKUP.get(kind, 0.0)))


func _sum(e: Dictionary) -> void:
	var total := 0.0
	var interest := 0.0
	for loan in e.get("loans", []):
		total += float(loan["amount"])
		interest += float(loan["amount"]) * float(loan["rate"])
	e["debt"] = total
	e["interest"] = interest
	e["rate"] = interest / total if total > 0.0 else 0.0


# ---------- weekly ----------

func step(db: Data, day: int) -> void:
	news.clear()
	var cfg: Dictionary = db.balance.get("debt", {})
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty():
			continue
		init_company(db, c, day)
		_float_rates(db, c, e)
		_maturities(db, c, e, day, cfg)
		_cash(db, c, e, day, cfg)
		_sum(e)
		var hist: Array = e.get("debt_history", [])
		hist.append(float(e["debt"]))
		while hist.size() > 520:
			hist.pop_front()
		e["debt_history"] = hist
	_random_events(db, day, cfg)
	for item in db.companies:
		var e2 := db.econ(item)
		if not e2.is_empty():
			_sum(e2)


## Bank loans follow the market rate slowly (as they reprice); bonds keep their rate until refinanced.
func _float_rates(db: Data, c: Dictionary, e: Dictionary) -> void:
	for loan in e["loans"]:
		if bool(loan.get("floating", false)):
			var target := market_rate(db, c, str(loan["вид"]))
			loan["rate"] = float(loan["rate"]) + (target - float(loan["rate"])) / 13.0


func _maturities(db: Data, c: Dictionary, e: Dictionary, day: int, cfg: Dictionary) -> void:
	var loans: Array = e["loans"]
	var keep: Array = []
	for loan in loans:
		if int(loan["repayment"]) > day:
			keep.append(loan)
			continue
		var amount := float(loan["amount"])
		var q := float(c.get("_q", 0.5))
		if str(loan["вид"]) == "fine":
			# A fine is paid from cash; if that leaves the company short, next week it borrows (_cash).
			e["money"] = float(e["money"]) - amount
			continue
		var healthy := q >= float(cfg.get("refinancing_from_q", 0.4))
		# A healthy company refinances (and always can when short of cash); only a weak one risks default.
		if healthy and (_rng.randf() < 0.9 or float(e["money"]) < amount):
			loan["repayment"] = day + _rng.randi_range(2 * 52, 5 * 52) * 7
			loan["rate"] = market_rate(db, c, str(loan["вид"]))
			keep.append(loan)
			if amount >= 0.1 * float(e["debt"]):
				_note(c, day, {"вид": "debt", "что": "рефинансирование", "count_value": amount, "rate": float(loan["rate"])}, "neutral", 0.15)
		elif float(e["money"]) >= amount:
			e["money"] = float(e["money"]) - amount
			_note(c, day, {"вид": "debt", "что": "repayment", "count_value": amount}, "good", 0.15)
		elif db.state_share(c) > 0.3 and _rng.randf() < float(cfg.get("state_company_rescue_chance", 0.8)):
			_state_rescue(db, c, e, amount, day, true)
		else:
			_default(db, c, e, loan, day)   # the lender takes shares instead; the loan leaves the books
	e["loans"] = keep


## Out of cash — an emergency bank loan; plenty of cash — early repayment of the nearest loans.
func _cash(db: Data, c: Dictionary, e: Dictionary, day: int, cfg: Dictionary) -> void:
	var r := maxf(float(e.get("R", 1.0)), 1.0)
	var cash := float(e["money"])
	if cash < -0.02 * r:
		var amount := -cash + 0.05 * r
		var bank := _biggest_bank(db, c)
		var loan := {"creditor": bank.get("название", {"ru": "Банк", "en": "A bank"}), "вид": "bank", "company": str(bank.get("id", "")),
			"amount": amount, "floating": true, "repayment": day + 52 * 7}
		loan["rate"] = market_rate(db, c, "bank") + 0.02
		(e["loans"] as Array).append(loan)
		e["money"] = cash + amount
		_note(c, day, {"вид": "debt", "что": "срочный_кредит", "count_value": amount, "rate": float(loan["rate"])}, "bad", 0.2)
	elif cash > float(cfg.get("surplus_money", 0.25)) * r and float(e.get("debt", 0.0)) > 0.0:
		var pay := minf(float(e["debt"]) * 0.1, cash - 0.2 * r)
		if pay >= 0.05 * float(e["debt"]):
			_repay(e, pay)
			e["money"] = cash - pay
			_note(c, day, {"вид": "debt", "что": "early", "count_value": pay}, "good", 0.12)


## Pays `amount` off the loans falling due soonest.
func _repay(e: Dictionary, amount: float) -> void:
	var loans: Array = e["loans"]
	loans.sort_custom(func(a, b): return int(a["repayment"]) < int(b["repayment"]))
	var left := amount
	var keep: Array = []
	for loan in loans:
		if left <= 0.0:
			keep.append(loan)
			continue
		var s := float(loan["amount"])
		if s <= left:
			left -= s
		else:
			loan["amount"] = s - left
			left = 0.0
			keep.append(loan)
	e["loans"] = keep


func _biggest_bank(db: Data, c: Dictionary) -> Dictionary:
	for bid in BIG_BANKS:
		var b := db.company(str(bid))
		if not b.is_empty() and str(b["id"]) != str(c["id"]) and str(b.get("_country", "")) == str(c.get("_country", "")):
			return b
	return {}


# ---------- default and rescue ----------

## The company cannot pay: the lender takes shares for the debt (section 9), the shares crash, the rating
## falls; a bank lender of the mod takes a loss.
func _default(db: Data, c: Dictionary, e: Dictionary, loan: Dictionary, day: int) -> void:
	var amount := float(loan["amount"])
	var cap := maxf(db.cap(c), 1.0)
	var stake := clampf(amount / (cap + amount), 0.0, 0.9)
	var holder := {"кто": loan["creditor"], "type": "polity" if str(loan["вид"]) == "polity" else ("company" if str(loan.get("company", "")) != "" else "крупный"),
		"country": "Китай" if str(loan["вид"]) == "foreign" else str(c.get("_country", ""))}
	if str(loan.get("company", "")) != "":
		holder["company"] = str(loan["company"])
	dilute(c, holder, stake)
	e["шок"] = float(e.get("шок", 0.0)) + log(0.7)
	e["H"] = clampf(float(e.get("H", 0.5)) - 0.1, 0.02, 0.98)
	var lender := db.company(str(loan.get("company", "")))
	if not lender.is_empty():
		var le := db.econ(lender)
		if not le.is_empty():
			le["money"] = float(le["money"]) - amount * 0.5
			le["шок"] = float(le.get("шок", 0.0)) + log(maxf(0.5, 1.0 - 0.5 * amount / maxf(db.cap(lender), 1.0)))
	_note(c, day, {"вид": "debt", "что": "дефолт", "count_value": amount, "доля": stake, "creditor": loan["creditor"]}, "bad", 0.6, true)


## The state pays the debt; for a large sum it takes shares in return — the quiet nationalisation (section 6).
func _state_rescue(db: Data, c: Dictionary, e: Dictionary, amount: float, day: int, due: bool) -> void:
	var cap := maxf(db.cap(c), 1.0)
	var stake := clampf(amount / (cap + amount), 0.0, 0.5) if amount > 0.05 * cap else 0.0
	if stake > 0.0:
		dilute(c, {"кто": {"ru": "Государство (господдержка)", "en": "The state (bailout)"}, "type": "polity",
			"country": str(c.get("_country", ""))}, stake)
	if not due:
		_repay(e, amount)
	_note(c, day, {"вид": "debt", "что": "state_aid", "count_value": amount, "доля": stake}, "neutral", 0.35)


## A new holder gets `stake` of the company; everyone else is diluted. Holders with the same name merge.
static func dilute(c: Dictionary, holder: Dictionary, stake: float) -> void:
	if stake <= 0.0:
		return
	var owners: Array = c.get("owners", [])
	var merged := false
	var name_ru := str((holder["кто"] as Dictionary).get("ru", "")) if holder["кто"] is Dictionary else str(holder["кто"])
	for o in owners:
		var od: Dictionary = o
		od["доля"] = float(od["доля"]) * (1.0 - stake)
		var oname := str((od["кто"] as Dictionary).get("ru", "")) if od["кто"] is Dictionary else str(od["кто"])
		if oname == name_ru and not merged:
			od["доля"] = float(od["доля"]) + stake
			merged = true
	if not merged:
		var h := holder.duplicate(true)
		h["доля"] = stake
		owners.append(h)
	c["owners"] = owners
	c["_owners_changed"] = true   # saved with the game (stakes.gd)


# ---------- random debt events ----------

func _random_events(db: Data, day: int, cfg: Dictionary) -> void:
	var lam := maxf(float(cfg.get("events_min", 0.2)), float(cfg.get("events_per_1000", 1.0)) * db.companies.size() / 1000.0) * db.dt
	var l := exp(-lam)
	var count := -1
	var p := 1.0
	while p > l:
		p *= _rng.randf()
		count += 1
	for i in count:
		var c := _pick(db)
		if not c.is_empty():
			_debt_event(db, c, day)


func _pick(db: Data) -> Dictionary:
	var sum := 0.0
	var weights: Array = []
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		var lev := float(e.get("debt", 0.0)) / maxf(float(e.get("R", 1.0)), 1.0) if not e.is_empty() else 0.0
		var w := 0.0 if e.is_empty() or str(c.get("sector", "")) == "banks" else pow(maxf(db.cap(c), 1.0), 0.3) * (1.0 + 3.0 * lev)
		weights.append(w)
		sum += w
	if sum <= 0.0:
		return {}
	var x := _rng.randf() * sum
	for i in weights.size():
		x -= float(weights[i])
		if x <= 0.0:
			return db.companies[i]
	return {}


## Console test: force one debt event on a company (kind as in _debt_event, "" — a random one).
func force_event(db: Data, c: Dictionary, day: int, kind: String) -> void:
	news.clear()
	init_company(db, c, day)
	_debt_event(db, c, day, kind)
	_sum(db.econ(c))


func _debt_event(db: Data, c: Dictionary, day: int, forced: String = "") -> void:
	var e := db.econ(c)
	var r := maxf(float(e.get("R", 1.0)), 1.0)
	var debt := float(e.get("debt", 0.0))
	var lev := debt / r
	var cash := float(e.get("money", 0.0))
	var state := db.state_share(c)
	var big_owner := _big_owner(c)
	var foreign := (e.get("loans", []) as Array).any(func(l): return str(l["вид"]) == "foreign")
	var kinds := {
		"invest_loan": 1.0,
		"fine": 0.5,
		"revaluation": 0.4 if foreign else 0.0,
		"state_aid": (1.5 * lev if state > 0.3 or lev > 1.5 else 0.0) if debt > 0.0 else 0.0,
		"owner_repaid": (0.5 if not big_owner.is_empty() and lev > 0.5 else 0.0),
		"write_off": (0.4 * lev if lev > 1.0 else 0.0),
		"early": (0.8 if cash > 0.1 * r and debt > 0.0 else 0.0),
	}
	var total := 0.0
	for k in kinds.keys():
		total += float(kinds[k])
	var x := _rng.randf() * total
	var kind := ""
	for k in kinds.keys():
		x -= float(kinds[k])
		if x <= 0.0:
			kind = str(k)
			break
	if not forced.is_empty():
		kind = forced
	match kind:
		"invest_loan":
			var amount := r * _rng.randf_range(0.05, 0.2)
			var bank := _biggest_bank(db, c)
			var loan := {"creditor": bank.get("название", {"ru": "Синдикат банков", "en": "A bank syndicate"}), "вид": "bank",
				"company": str(bank.get("id", "")), "amount": amount, "floating": true, "repayment": day + _rng.randi_range(3, 7) * 52 * 7}
			loan["rate"] = market_rate(db, c, "bank")
			(e["loans"] as Array).append(loan)
			e["money"] = cash + amount * 0.3
			e["demand"] = float(e["demand"]) * 1.03
			_note(c, day, {"вид": "debt", "что": "invest_loan", "count_value": amount, "rate": float(loan["rate"])}, "neutral", 0.2)
		"fine":
			var fine := r * _rng.randf_range(0.01, 0.05)
			(e["loans"] as Array).append({"creditor": {"ru": "Государство (штраф, иск)", "en": "The state (fine, lawsuit)"}, "вид": "fine",
				"company": "", "amount": fine, "rate": 0.0, "floating": false, "repayment": day + 52 * 7})
			e["шок"] = float(e.get("шок", 0.0)) - 0.02
			_note(c, day, {"вид": "debt", "что": "fine", "count_value": fine}, "bad", 0.2)
		"revaluation":
			var up := _rng.randf_range(0.05, 0.15)
			var added := 0.0
			for loan in e["loans"]:
				if str(loan["вид"]) == "foreign":
					added += float(loan["amount"]) * up
					loan["amount"] = float(loan["amount"]) * (1.0 + up)
			_note(c, day, {"вид": "debt", "что": "revaluation", "count_value": added, "доля": up}, "bad", 0.15)
		"state_aid":
			_state_rescue(db, c, e, debt * _rng.randf_range(0.2, 0.5), day, false)
		"owner_repaid":
			var pay := debt * _rng.randf_range(0.1, 0.3)
			var cap := maxf(db.cap(c), 1.0)
			_repay(e, pay)
			dilute(c, big_owner, clampf(pay / (cap + pay), 0.0, 0.3))
			e["шок"] = float(e.get("шок", 0.0)) + 0.03
			_note(c, day, {"вид": "debt", "что": "owner_repaid", "count_value": pay, "creditor": big_owner["кто"]}, "good", 0.25)
		"write_off":
			var banks: Array = (e["loans"] as Array).filter(func(l): return str(l["вид"]) == "bank")
			if banks.is_empty():
				return
			var loan: Dictionary = banks[_rng.randi_range(0, banks.size() - 1)]
			var off := float(loan["amount"]) * _rng.randf_range(0.1, 0.3)
			loan["amount"] = float(loan["amount"]) - off
			var lender := db.company(str(loan.get("company", "")))
			if not lender.is_empty() and not db.econ(lender).is_empty():
				db.econ(lender)["money"] = float(db.econ(lender)["money"]) - off
			_note(c, day, {"вид": "debt", "что": "write_off", "count_value": off, "creditor": loan["creditor"]}, "good", 0.25)
		"early":
			var pay2 := minf(debt * _rng.randf_range(0.1, 0.3), cash * 0.8)
			_repay(e, pay2)
			e["money"] = cash - pay2
			_note(c, day, {"вид": "debt", "что": "early", "count_value": pay2}, "good", 0.15)


func _big_owner(c: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for o in c.get("owners", []):
		var od: Dictionary = o
		if str(od.get("type", "")) in ["крупный", "founder"] and float(od.get("доля", 0.0)) > float(best.get("доля", 0.0)):
			best = od
	return best


func _note(c: Dictionary, day: int, entry: Dictionary, tone: String, size: float, always := false) -> void:
	entry["день"] = day
	(c["_chronicle"] as Array).append(entry)
	news.append({"c": c, "entry": entry, "tone": tone, "size": size, "big": size >= 0.3, "always_mine": always})


# ---------- save ----------

func save_state() -> Dictionary:
	return {"зерно": str(_rng.seed), "состояние": str(_rng.state)}


func load_state(state: Dictionary) -> void:
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
