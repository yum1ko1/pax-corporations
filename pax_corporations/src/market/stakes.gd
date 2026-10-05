extends RefCounted
## The player's state buys and sells company shares at once — even on pause (section 6: ownership).
## Buying takes shares from the free float at the market price plus a premium that grows with the block
## (a big buyer pushes the price up); money leaves the player's treasury right away. Selling puts the shares
## back into the free float at a discount. The state then gets dividends on its stake (economy.gd) and a say in
## the company: its type, independence, trust and rating follow the new owners on the next recompute.
## Changed owner lists are saved with the game (save_state / load_state).

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const FLOAT_KIND := "частные"
const STATE_KIND := "polity"


## What a trade would be: {"ok": bool, "why": error key, "доля": fraction actually traded, "amount": млн $,
## "premium": premium/discount fraction}. `fraction` is of all the company's shares; buy=false sells.
static func quote(db: Data, c: Dictionary, country: String, fraction: float, buy: bool, treasury: float) -> Dictionary:
	var cfg: Dictionary = db.balance.get("stakes", {})
	var f := fraction
	if buy:
		f = minf(f, free_float(c))
		if f <= 0.0005:
			return {"ok": false, "why": "stake_no_float", "доля": 0.0, "amount": 0.0, "premium": 0.0}
	else:
		f = minf(f, state_stake(c, country))
		if f <= 0.0005:
			return {"ok": false, "why": "stake_nothing", "доля": 0.0, "amount": 0.0, "premium": 0.0}
	var base := db.price(c) * db.shares(c) * f
	var premium := float(cfg.get("premium", 0.1)) + float(cfg.get("premium_per_share", 0.5)) * f
	var discount := float(cfg.get("discount", 0.05)) + float(cfg.get("discount_per_share", 0.3)) * f
	var amount := base * (1.0 + premium) if buy else base * (1.0 - discount)
	if buy and amount > treasury:
		return {"ok": false, "why": "stake_no_money", "доля": f, "amount": amount, "premium": premium}
	return {"ok": true, "why": "", "доля": f, "amount": amount, "premium": premium if buy else -discount}


## Carries the trade out on the company (owners, price, type, chronicle). The caller moves the money.
static func apply(db: Data, c: Dictionary, country: String, q: Dictionary, buy: bool, day: int) -> void:
	var cfg: Dictionary = db.balance.get("stakes", {})
	var f := float(q["доля"])
	var owners: Array = c.get("owners", [])
	var holder := _state_holder(c, country, buy)
	if buy:
		_take_from(owners, FLOAT_KIND, f)
		holder["доля"] = float(holder.get("доля", 0.0)) + f
	else:
		holder["доля"] = maxf(0.0, float(holder.get("доля", 0.0)) - f)
		_float_holder(owners)["доля"] = float(_float_holder(owners)["доля"]) + f
	c["owners"] = owners.filter(func(o): return float((o as Dictionary).get("доля", 0.0)) > 0.00005)
	var impact := float(cfg.get("price_influence", 0.3)) * f
	c["_price"] = db.price(c) * (1.0 + impact if buy else maxf(0.1, 1.0 - impact))
	_retype(db, c)
	c["_owners_changed"] = true
	(c["_chronicle"] as Array).append({"день": day, "вид": "state_stake", "что": "buyout" if buy else "sale", "доля": f,
		"count_value": float(q["amount"]), "country": country})


## The company buys back `fraction` of its shares from the free float with its own money and cancels them:
## every other holder's part grows (20.15 «выкуп акций»; also a defence against a hostile bid, 20.6).
## Returns what it paid, млн $ (0 — no float or no money).
static func buyback(db: Data, c: Dictionary, fraction: float, day: int, why: String) -> float:
	var e := db.econ(c)
	var f := minf(fraction, free_float(c) - 0.05)
	if e.is_empty() or f <= 0.002:
		return 0.0
	var cost := db.cap(c) * f * (1.0 + float((db.balance.get("stakes", {}) as Dictionary).get("premium", 0.1)))
	if float(e.get("money", 0.0)) < cost:
		return 0.0
	e["money"] = float(e["money"]) - cost
	var owners: Array = c.get("owners", [])
	_take_from(owners, FLOAT_KIND, f)
	for o in owners:
		(o as Dictionary)["доля"] = float((o as Dictionary).get("доля", 0.0)) / (1.0 - f)
	c["owners"] = owners.filter(func(o): return float((o as Dictionary).get("доля", 0.0)) > 0.00005)
	c["_owners_changed"] = true
	e["шок"] = float(e.get("шок", 0.0)) + log(1.0 + 0.5 * f)
	(c["_chronicle"] as Array).append({"день": day, "вид": "выкуп_акций", "что": why, "доля": f, "count_value": cost})
	return cost


static func free_float(c: Dictionary) -> float:
	var s := 0.0
	for o in c.get("owners", []):
		if o is Dictionary and str((o as Dictionary).get("type", "")) == FLOAT_KIND:
			s += float((o as Dictionary).get("доля", 0.0))
	return s


## The stake of one country's state in the company.
static func state_stake(c: Dictionary, country: String) -> float:
	var s := 0.0
	for o in c.get("owners", []):
		if o is Dictionary and str((o as Dictionary).get("type", "")) == STATE_KIND and str((o as Dictionary).get("country", "")) == country:
			s += float((o as Dictionary).get("доля", 0.0))
	return s


## The state holder the trade goes through: its biggest existing entry, or a new one (only when buying).
static func _state_holder(c: Dictionary, country: String, create: bool) -> Dictionary:
	var owners: Array = c.get("owners", [])
	var best: Dictionary = {}
	for o in owners:
		var od: Dictionary = o
		if str(od.get("type", "")) == STATE_KIND and str(od.get("country", "")) == country \
				and float(od.get("доля", 0.0)) >= float(best.get("доля", -1.0)):
			best = od
	if best.is_empty() and create:
		best = {"кто": {"ru": "Государство (%s)" % country, "en": "The state (%s)" % country}, "type": STATE_KIND,
			"country": country, "доля": 0.0}
		owners.append(best)
		c["owners"] = owners
	return best


static func _float_holder(owners: Array) -> Dictionary:
	for o in owners:
		if str((o as Dictionary).get("type", "")) == FLOAT_KIND:
			return o
	var h := {"кто": {"ru": "Частные акционеры и фонды", "en": "Free float and funds"}, "type": FLOAT_KIND, "доля": 0.0}
	owners.append(h)
	return h


static func _take_from(owners: Array, kind: String, amount: float) -> void:
	var left := amount
	for o in owners:
		var od: Dictionary = o
		if str(od.get("type", "")) != kind or left <= 0.0:
			continue
		var take := minf(left, float(od.get("доля", 0.0)))
		od["доля"] = float(od["доля"]) - take
		left -= take


## The company's type follows its own state's stake: over half — state, a real stake — mixed.
static func _retype(db: Data, c: Dictionary) -> void:
	var s := db.state_share(c)
	var kind := str(c.get("type", ""))
	if s > 0.5:
		c["type"] = "государственная"
	elif s >= 0.1:
		c["type"] = "смешанная"
	elif kind in ["государственная", "смешанная"]:
		c["type"] = "частная"


# ---------- save ----------

## Owner lists (and types) of the companies whose owners changed during the game — by the player or
## by debt (defaults and bailouts dilute the holders, debt.gd).
static func save_state(db: Data) -> Dictionary:
	var out := {}
	for item in db.companies:
		var c: Dictionary = item
		if bool(c.get("_owners_changed", false)):
			out[str(c["id"])] = {"owners": c.get("owners", []), "type": c.get("type", "")}
	return out


static func load_state(db: Data, state: Dictionary) -> void:
	for cid in state.keys():
		var c := db.company(str(cid))
		var saved: Variant = state[cid]
		if c.is_empty() or not (saved is Dictionary):
			continue
		var owners: Variant = (saved as Dictionary).get("owners")
		if owners is Array:
			c["owners"] = (owners as Array).duplicate(true)
			c["type"] = str((saved as Dictionary).get("type", c.get("type", "")))
			c["_owners_changed"] = true
