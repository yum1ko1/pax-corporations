extends RefCounted
## Workforce and money of every company, one step a week (sections 5, 9, 20.8, 20.15).
##
## People: the company needs D people for the work it has (D grows with demand). Up to D it hires —
## faster when it pays above the sector's market wage and people are content; people quit more when
## discontent or underpaid; above D, or while losing money, it lays people off.
## Wages: short of people and profitable → raises; profitable → follows wage inflation; losing → freezes.
## Satisfaction (0..1): wage against the market, company stability, recent layoffs, share price success,
## a running strike. It moves smoothly towards its target (20.13). Below 30% a site may strike (20.8).
## Money: revenue = potential (demand × price index) × (staff on hand / staff needed)^elasticity × strikes;
## profit = revenue × (1 − non-labour cost share) − payroll. The share price is pulled towards a fair value
## built from revenue and profit (market.gd), so people → revenue → profit → price.
##
## Everything lives in company["_ec"] (JSON-safe, saved with the game); the yearly figures the UI shows
## go to company["_fin"], which corp_data.fund() prefers over the static data.

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Parallel := preload("res://mods/pax_corporations/src/core/parallel.gd")
const HISTORY := 520
## Industries whose costs depend on power grids and utilities (departments.gd «издержки_пром»).
const INDUSTRY := ["metallurgy", "oil_gas", "auto_industry", "semiconductors", "строительство", "энергетика"]

var _rng := RandomNumberGenerator.new()


func start_new() -> void:
	_rng.randomize()


# ---------- initial state ----------

func init_all(db: Data) -> void:
	for item in db.companies:
		init_company(db, item)


func init_company(db: Data, c: Dictionary) -> void:
	if c.get("_ec") is Dictionary and not (c["_ec"] as Dictionary).is_empty():
		return
	var n0 := maxf(float(c.get("staff", 1.0)), 1.0)
	var w0 := float(c.get("wage", 1000.0))
	var r0 := maxf(db.fund(c, "выручка"), 1.0)
	var p0 := db.fund(c, "profit")
	var payroll0 := n0 * w0 * 12.0 / 1e6
	var shares: Array = []
	for p in c.get("sites", []):
		shares.append(float((p as Dictionary).get("staff", 0.0)) / n0 if p is Dictionary else 0.0)
	var e := {
		"N": n0, "W": w0, "H": -1.0, "D0": n0, "R0": r0, "P0": p0, "cap0": db.cap(c),
		"c_nl": clampf((r0 - p0 - payroll0) / r0, 0.0, 0.98),
		"payouts": clampf(db.fund(c, "dividends") / p0, 0.0, 1.0) if p0 > 0.0 else 0.0,
		"money": db.fund(c, "money"), "debt": db.fund(c, "debt"),
		"demand": 1.0, "цены": 1.0, "market_wage": market_wage(db, c), "site_shares": shares,
		"fired26": 0.0, "raised": 0.0, "шок": 0.0, "flows": [], "strikes": [],
		"headcount_history": [n0], "R": r0, "P": p0, "фот": payroll0, "fair": db.cap(c),
		"demand_money": r0, "offer": r0,   # until the first week: the dossier showed «demand $0 · load 0%»
	}
	c["_ec"] = e
	# A company just founded (founding.gd «_startup» weeks) is still being built: it starts with a part of its people
	# and work and reaches the planned size step by step (_ramp) — not the whole business on the first day.
	if c.has("_startup"):
		var r0s := clampf(float((db.goods.get("founding", {}) as Dictionary).get("startup_start", 0.08)), 0.01, 1.0)
		e["ramp"] = r0s
		e["ramp_weeks"] = maxi(1, int(c["_startup"]))
		e["N"] = maxf(1.0, n0 * r0s)
		e["R"] = r0 * r0s
		e["P"] = p0 * r0s
		e["demand_money"] = r0 * r0s
		e["offer"] = r0 * r0s
		c.erase("_startup")
	var target := _satisfaction_target(db, c, e, 0.0)
	var h := float(target["value"])
	e["H"] = h
	e["satisfaction_parts"] = target["parts"]
	# Start at the hiring/quitting balance: a company always has a few open posts, so the people who quit
	# in the first week are replaced. Without this every company shrinks in its first weeks.
	var cfg: Dictionary = db.balance.get("staff", {})
	var ratio := w0 / maxf(float(e["market_wage"]), 1.0)
	var quit_rate := float(cfg.get("exit_base", 0.0015)) * (1.0 + float(cfg.get("exit_discontent", 3.0)) * pow(1.0 - h, 2.0)) \
		/ clampf(ratio, 0.5, 2.0)
	var attract := clampf(ratio * ratio * (0.5 + h), 0.1, 3.0)
	var gap := clampf(quit_rate / (float(cfg.get("hiring_speed", 0.15)) * attract), 0.0, 0.2)
	e["D0"] = n0 / (1.0 - gap)
	e["нужно"] = e["D0"]
	e["vacancies"] = gap
	_publish(c, e)


## Demand for the company's work: its own (sector trend and noise) × the world's situation × what is left
## after a crisis × the fading effect of random events (the last three are set by events.gd).
static func demand_of(e: Dictionary) -> float:
	return float(e["demand"]) * float(e.get("climate_demand", 1.0)) * float(e.get("crisis_demand", 1.0)) \
		* float(e.get("event_demand", 1.0)) * float(e.get("market_demand", 1.0)) * float(e.get("tariff_demand", 1.0))   # tariffs, sanctions (arena.gd)


## The sector's market wage in the company's country, $ a month.
func market_wage(db: Data, c: Dictionary) -> float:
	var avg := float(db.country_info(str(c.get("_country", ""))).get("average_wage", 1000.0))
	return avg * float(db.sector_of(c).get("wage_premium", 1.0))


# ---------- weekly step ----------

## ctx: {"кризис": bool, "taxes": {country: rate}}. Returns what each country's treasury gets this week:
## {country: {"taxes": млн $, "dividends": млн $}} — taxes paid and dividends on the state's stake (20.15).
## Companies are independent here, so they are stepped on worker threads (parallel.gd): each chunk has its own
## RNG seeded from the saved one, every company writes only its own dictionaries; the treasury sums are
## added up afterwards on the main thread.
func step(db: Data, day: int, ctx: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary = db.balance.get("staff", {})
	var list: Array = db.companies
	for item in list:
		init_company(db, item)
	var base_seed := _rng.randi()
	var chunk := func(from: int, to: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = base_seed + from * 7919
		for i in range(from, to):
			var co: Dictionary = list[i]
			var ec: Dictionary = co["_ec"]
			ec["_payout"] = _step_company(db, co, ec, cfg, day, ctx, rng)
	Parallel.for_each(list.size(), chunk)
	var to_treasury := {}
	for item in list:
		var c: Dictionary = item
		var e: Dictionary = c["_ec"]
		var paid: Array = e["_payout"]
		e.erase("_payout")
		var country := str(c.get("_country", ""))
		var t: Dictionary = to_treasury.get(country, {"taxes": 0.0, "dividends": 0.0})
		t["taxes"] = float(t["taxes"]) + float(paid[0])
		t["dividends"] = float(t["dividends"]) + float(paid[1])
		to_treasury[country] = t
	return to_treasury


func _step_company(db: Data, c: Dictionary, e: Dictionary, cfg: Dictionary, day: int, ctx: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var infl := float(cfg.get("wage_inflation", 0.04))
	var sector := db.sector_of(c)

	# Demand for the company's work, and the people it takes.
	var drift := float(sector.get("drift", 0.03))
	# A step may cover several weeks of a long time skip (db.dt): drifts and inflation grow with it, noise with √dt.
	var dt := float(db.dt)
	e["demand"] = float(e["demand"]) * exp(drift * dt / 52.0 + float(cfg.get("demand_noise", 0.01)) * sqrt(dt) * rng.randfn(0.0, 1.0))
	var demand := demand_of(e)
	var ramp := _ramp(c, e, dt, day)
	# «План» — the posts the company keeps: restructuring in a loss cuts them, profit brings them back.
	var need := float(e["D0"]) * pow(demand, float(cfg.get("people_from_demand", 0.8))) * float(e.get("план", 1.0)) \
		* db.cfx_c(c, "headcount") * ramp   # automation of the research trees (tree.gd); a new company is still hiring
	e["market_wage"] = float(e["market_wage"]) * pow(1.0 + infl / 52.0, dt)
	# Prices grow with the same inflation as wages, so margins hold when nothing else changes.
	e["цены"] = float(e.get("цены", 1.0)) * pow(1.0 + infl / 52.0, dt)
	var n := float(e["N"])
	var w := float(e["W"])
	var ratio := w / maxf(float(e["market_wage"]), 1.0)
	var margin := float(e["P"]) / maxf(float(e["R"]), 1.0)

	# Strikes running.
	var striking := _step_strikes(db, c, e, cfg, day, rng)

	# Satisfaction moves towards its target.
	var target := _satisfaction_target(db, c, e, striking)
	var h := float(e["H"])
	h = float(target["value"]) if h < 0.0 else h + float(cfg.get("satisfaction_smoothing", 0.1)) * (float(target["value"]) - h)
	e["H"] = h
	e["satisfaction_parts"] = target["parts"]

	# People come and go.
	var country := str(c.get("_country", ""))
	var quit_rate := float(cfg.get("exit_base", 0.0015)) * (1.0 + float(cfg.get("exit_discontent", 3.0)) * pow(1.0 - h, 2.0)) \
		/ clampf(ratio, 0.5, 2.0) * db.dept(country, "exit", 1.0) \
		* db.labour(c, "exit", 1.0)   # good health care and labour laws — people stay (departments.gd, politics.gd)
	var quits := n * quit_rate
	var attract := clampf(ratio * ratio * (0.5 + h), 0.1, 3.0)
	var hires := maxf(0.0, need - n) * float(cfg.get("hiring_speed", 0.15)) * attract
	var fired := 0.0
	var cut := float(cfg.get("layoff_share", 0.015))
	var rs: Dictionary = cfg.get("restructuring", {})
	if n > need * (1.0 + float(cfg.get("surplus", 0.06))):
		fired = minf((n - need) * 0.25, n * cut)
	elif margin < float(cfg.get("loss_threshold", -0.03)):
		# Restructuring: the posts go together with the people (so the rest is not left short-handed) and
		# the other costs are squeezed too — a loss is a reason to get leaner, not to fall apart.
		fired = n * cut
		var plan := float(e.get("план", 1.0))
		e["план"] = maxf(float(rs.get("headcount_min", 0.7)), plan * (1.0 - cut))
		need *= float(e["план"]) / maxf(plan, 1e-6)
		var c_nl0 := float(e.get("c_nl0", e["c_nl"]))
		e["c_nl0"] = c_nl0
		e["c_nl"] = maxf(c_nl0 * float(rs.get("spending_min", 0.85)), float(e["c_nl"]) * (1.0 - float(rs.get("spending_per_week", 0.002))))
	if margin > 0.02 and float(e.get("план", 1.0)) < 1.0:
		e["план"] = minf(1.0, float(e["план"]) * (1.0 + float(rs.get("headcount_return", 0.002))))
	n = maxf(1.0, n + hires - quits - fired)
	e["N"] = n
	e["fired26"] = float(e["fired26"]) * (1.0 - 1.0 / 26.0) + fired
	var flows: Array = e["flows"]
	flows.append([hires, quits, fired])
	while flows.size() > 8:
		flows.pop_front()
	if fired >= n * 0.01:
		_chron(c, day, {"вид": "layoffs", "count_value": fired, "доля": fired / (n + fired)})
		e["шок"] = float(e["шок"]) + float(cfg.get("layoffs_shock", -0.02))
	elif hires - quits >= n * 0.02:
		_chron(c, day, {"вид": "набор", "count_value": hires - quits})

	# Wage policy.
	var vacancy := (need - n) / maxf(need, 1.0)
	if vacancy > float(cfg.get("vacancy_threshold", 0.03)) and margin > 0.05:
		var up := float(cfg.get("raise_on_vacancies", 0.004))
		w *= 1.0 + up
		e["raised"] = float(e["raised"]) + up
	elif margin > 0.0:
		w *= pow(1.0 + infl / 52.0, dt)
	# The cap stops endless raises; it never cuts a wage that was already above it.
	w = minf(w, maxf(float(e["W"]), float(e["market_wage"]) * 3.0))
	e["W"] = w
	if float(e["raised"]) >= 0.05:
		_chron(c, day, {"вид": "wage", "доля": float(e["raised"])})
		e["raised"] = 0.0

	# New strikes where people are worst off.
	_start_strikes(db, c, e, cfg, day, h, rng)

	# Money.
	# Education raises what people make (departments.gd).
	var potential := float(e["R0"]) * demand * float(e.get("цены", 1.0)) * db.dept(country, "производительность", 1.0) \
		* (1.0 + db.tree(c, "выручка", 0.0) + db.tree(c, "export", 0.0) * float(c.get("export", 0.3))) * (1.0 + db.tree(c, "производительность", 0.0)) \
		* db.cfx_c(c, "выручка_" + str(c.get("sector", ""))) \
		* _conditions(db, e) * ramp   # the industry tree; the research trees' discoveries; the country's conditions (conditions.gd); the build-up
	# Restructuring cuts posts, not the work: the plan does not reduce the potential.
	var on_hand := maxf(0.0, n - _striking_people(e))
	var labour := pow(minf(1.0, on_hand / maxf(0.97 * need, 1.0)), float(cfg.get("labour_elasticity", 0.6)))
	var revenue := potential * labour
	# For the dossier: what buyers want from the company and what its people can make (supply scales with
	# the staff at work: each worker makes potential / need), млн $ a year.
	e["demand_money"] = potential
	e["offer"] = potential * on_hand / maxf(0.97 * need, 1.0)
	var payroll := n * w * 12.0 / 1e6
	# Interest on the loans (debt.gd) comes out of the profit: more debt or a worse rating — less profit.
	# Roads (all) and utilities (industry) make the other costs cheaper or dearer (departments.gd).
	var cost_mult := db.dept(country, "издержки", 1.0) * (db.dept(country, "costs_industry", 1.0) if str(c.get("sector", "")) in INDUSTRY else 1.0) \
		* db.labour(c, "издержки", 1.0) * (1.0 + db.tree(c, "издержки", 0.0)) \
		* db.cfx_c(c, "издержки_" + str(c.get("sector", ""))) \
		* (1.0 + float(_ucfg(db).get("costs", 0.3)) * (0.5 - float(e.get("U", 0.5))))   # bad conditions cost more (conditions.gd)
	var profit := revenue * (1.0 + db.tree(c, "profit", 0.0) - float(e["c_nl"]) * cost_mult - float(e.get("extra_costs", 0.0))) - payroll - float(e.get("interest", 0.0))
	# «доп_расходы» (rivals.gd): advertising, a price-war discount, the cost of a corporate war — share of revenue.
	# Dividends (20.15): none at a loss, in an unstable company or in the bad stages of a world crisis.
	var stab := float(((c.get("_statuses", {}) as Dictionary).get("stability", {}) as Dictionary).get("value", 60.0)) / 100.0
	var pays := profit > 0.0 and stab >= 0.4 and not bool(ctx.get("кризис", false))
	var dividends := float(e["payouts"]) * profit if pays else 0.0
	# Taxes (9, 20.15): the country's rate on pre-tax profit; corruption hides up to half ("owes" vs "pays").
	var rate := clampf(float((ctx.get("taxes", {}) as Dictionary).get(str(c.get("_country", "")), float(cfg.get("tax_default", 0.2)))), 0.0, 0.9)
	var owes := maxf(profit, 0.0) * rate / (1.0 - rate)
	var k := float(((c.get("_statuses", {}) as Dictionary).get("corruption", {}) as Dictionary).get("value", 30.0)) / 100.0
	var tax := owes * (1.0 - 0.5 * k) * (1.0 + db.tree(c, "taxes", 0.0)) * db.cfx_c(c, "taxes_fee")
	e["tax_owed"] = owes
	e["tax_pays"] = tax
	e["dividends_now"] = dividends
	e["R"] = revenue
	e["P"] = profit
	e["фот"] = payroll
	e["money"] = float(e["money"]) + (profit - dividends) * dt / 52.0
	e["vacancies"] = maxf(vacancy, 0.0)
	e["нужно"] = need
	var p0 := float(e["P0"])
	var wr := float(cfg.get("revenue_weight", 0.4))
	# While it is being built the market values the plan (revenue and profit at full strength), not the first weeks.
	var full := 1.0 / ramp
	var earn := wr * revenue * full / float(e["R0"]) + (1.0 - wr) * maxf(profit * full, 0.05 * p0) / p0 if p0 > 0.0 \
		else revenue * full / float(e["R0"])
	e["fair"] = float(e["cap0"]) * maxf(earn, 0.02)
	var hist: Array = e["headcount_history"]
	hist.append(n)
	while hist.size() > HISTORY:
		hist.pop_front()
	if not (e.get("R_history") is Array):
		e["R_history"] = []
	var rh: Array = e["R_history"]
	rh.append(revenue)
	while rh.size() > 53:
		rh.pop_front()
	_publish(c, e)
	return [tax * dt / 52.0, db.state_take(c) * dividends * dt / 52.0]   # a front man's part too (orders.gd)


## The build-up of a new company, 0..1 (1 — built): grows evenly over its «ramp_weeks»; when done, a line in the
## chronicle. The non-labour costs grow with the work, so a half-built company is not drowned by them.
func _ramp(c: Dictionary, e: Dictionary, dt: float, day: int) -> float:
	if not e.has("ramp"):
		return 1.0
	var r := float(e["ramp"])
	var start := float(e.get("ramp_start", r))
	e["ramp_start"] = start
	r = minf(1.0, r + (1.0 - start) * dt / maxf(1.0, float(e.get("ramp_weeks", 26))))
	if r >= 1.0:
		e.erase("ramp")
		e.erase("ramp_start")
		e.erase("ramp_weeks")
		_chron(c, day, {"вид": "startup_done"})
		return 1.0
	e["ramp"] = r
	return r


## What the dossier and the rating read as the company's yearly figures.
func _publish(c: Dictionary, e: Dictionary) -> void:
	c["_fin"] = {"выручка": float(e["R"]), "profit": float(e["P"]), "money": float(e["money"]),
		"debt": float(e["debt"]), "фот": float(e["фот"]), "interest": float(e.get("interest", 0.0)),
		"dividends": float(e.get("dividends_now", float(e["payouts"]) * maxf(float(e["P"]), 0.0))),
		"taxes": float(e.get("tax_pays", 0.0)), "taxes_owed": float(e.get("tax_owed", 0.0))}


## Revenue from the conditions (conditions.gd): the slow level, blackouts and communication failures.
static func _conditions(db: Data, e: Dictionary) -> float:
	var cfg := _ucfg(db)
	return float(e.get("U_level", 1.0)) * (1.0 - float(cfg.get("blackout_output", 0.5)) * float(e.get("blackout", 0.0))) \
		* (1.0 - float(cfg.get("link_loss", 0.3)) * float(e.get("unlinked", 0.0)))


static func _ucfg(db: Data) -> Dictionary:
	return db.balance.get("условия", {})


# ---------- satisfaction ----------

## Target satisfaction 0..1 with its parts (for the tooltip), section 5.
func _satisfaction_target(db: Data, c: Dictionary, e: Dictionary, striking: float) -> Dictionary:
	var cfg: Dictionary = (db.balance.get("staff", {}) as Dictionary).get("satisfaction", {})
	var ratio := float(e["W"]) / maxf(float(e["market_wage"]), 1.0)
	var st: Dictionary = (c.get("_statuses", {}) as Dictionary).get("stability", {})
	var s := float(st.get("value", 60.0)) / 100.0
	var laid := float(e["fired26"]) / maxf(float(e["N"]), 1.0)
	var success := clampf(db.change(c, 26), -0.3, 0.3)
	var parts: Array = [
		["base", 0.5],
		["wage", float(cfg.get("wage", 0.6)) * (ratio - 1.0)],
		["stability", float(cfg.get("stability", 0.25)) * (s - 0.5)],
		["layoffs", -float(cfg.get("layoffs", 2.0)) * laid],
		["success", float(cfg.get("успех", 0.3)) * success],
	]
	if striking > 0.0:
		parts.append(["strike", -float(cfg.get("strike", 0.05))])
	var services := db.dept(str(c.get("_country", "")), "satisfaction", 0.0)   # health care, utilities (departments.gd)
	if absf(services) > 0.001:
		parts.append(["state", services])
	# Health care and security where the company works (conditions.gd).
	var cond: Dictionary = e.get("условия", {})
	if not cond.is_empty():
		var ucfg := _ucfg(db)
		var lift := float(ucfg.get("satisfaction_health", 0.2)) * (float(cond.get("здоровье", 0.5)) - 0.5) \
			+ float(ucfg.get("satisfaction_security", 0.1)) * (float(cond.get("security", 0.5)) - 0.5)
		if absf(lift) > 0.001:
			parts.append(["conditions", lift])
	var laws := db.labour(c, "satisfaction", 0.0)   # labour laws covering the industry (politics.gd)
	if absf(laws) > 0.001:
		parts.append(["labour_laws", laws])
	var v := 0.0
	for p in parts:
		v += float(p[1])
	return {"value": clampf(v, 0.02, 0.98), "parts": parts}


# ---------- strikes (20.8) ----------

func _start_strikes(db: Data, c: Dictionary, e: Dictionary, cfg: Dictionary, day: int, _h: float,
		rng: RandomNumberGenerator) -> void:
	var thr := float(cfg.get("strike_threshold", 0.3))
	# Labour laws: strong unions strike more readily, a strike ban makes it rare (politics.gd).
	var chance := float(cfg.get("strike_chance", 0.05)) * db.labour(c, "strikes", 1.0) * db.cfx_c(c, "strikes")   # 0 — automation: no strikes
	var weeks: Array = cfg.get("strike_weeks", [1, 4])
	var shares: Array = e["site_shares"]
	for i in shares.size():
		if is_striking(e, i):
			continue
		var hi := db.point_satisfaction(c, i)
		if hi >= thr:
			continue
		if rng.randf() < chance * pow((thr - hi) / thr, 2.0):
			var people := float(e["N"]) * float(shares[i])
			var strikes: Array = e["strikes"]
			strikes.append({"site": i, "weeks": rng.randi_range(int(weeks[0]), int(weeks[1])), "людей": people})
			_chron(c, day, {"вид": "strike", "site": i, "count_value": people})
			e["шок"] = float(e["шок"]) + float(cfg.get("strike_shock", -0.03))


## Advances running strikes; returns how many people are on strike this week.
func _step_strikes(_db: Data, c: Dictionary, e: Dictionary, cfg: Dictionary, day: int, rng: RandomNumberGenerator) -> float:
	var strikes: Array = e["strikes"]
	var left: Array = []
	for s in strikes:
		var sd: Dictionary = s
		sd["weeks"] = int(sd["weeks"]) - 1
		if int(sd["weeks"]) > 0:
			left.append(sd)
			continue
		if bool(sd.get("sabotage", false)):
			continue   # a sabotaged site (rivals.gd) simply starts again — nobody wins a raise
		if rng.randf() < float(cfg.get("concession_chance", 0.6)):
			var up := float(cfg.get("concession_markup", 0.03))
			e["W"] = float(e["W"]) * (1.0 + up)
			_chron(c, day, {"вид": "уступка", "site": int(sd["site"]), "доля": up})
		else:
			_chron(c, day, {"вид": "забастовка_конец", "site": int(sd["site"])})
	e["strikes"] = left
	return _striking_people(e)


func _striking_people(e: Dictionary) -> float:
	var total := 0.0
	for s in e["strikes"]:
		total += float((s as Dictionary).get("людей", 0.0))
	return total


func is_striking(e: Dictionary, index: int) -> bool:
	for s in e.get("strikes", []):
		if int((s as Dictionary).get("site", -1)) == index:
			return true
	return false


func _chron(c: Dictionary, day: int, entry: Dictionary) -> void:
	entry["день"] = day
	(c["_chronicle"] as Array).append(entry)


# ---------- save ----------

func save_state(db: Data) -> Dictionary:
	var out := {}
	for item in db.companies:
		var c: Dictionary = item
		if c.get("_ec") is Dictionary:
			out[str(c["id"])] = c["_ec"]
	return {"зерно": str(_rng.seed), "состояние": str(_rng.state), "companies": out}


func load_state(db: Data, state: Dictionary) -> void:
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
	var saved: Dictionary = state.get("companies", {}) if state.get("companies") is Dictionary else {}
	for item in db.companies:
		var c: Dictionary = item
		var e: Variant = saved.get(str(c["id"]))
		if e is Dictionary:
			c["_ec"] = (e as Dictionary).duplicate(true)
			_publish(c, c["_ec"])
	init_all(db)
