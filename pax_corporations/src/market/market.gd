extends RefCounted
## Weekly share prices (section 20.2, stage 1 — no game events yet):
##   r = μ + σ·ε,  ε ~ N(0, 1),  P ← P·e^r,  |r| ≤ limit
## μ — the sector's yearly drift / 52, σ — the sector's weekly volatility.
## The random generator is saved with the game, so reloading does not re-roll the week.

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const BIG_MOVE := 0.08   # a weekly move this large goes into the company chronicle
const CHRONICLE_KEEP := 300

var week := 0
var _rng := RandomNumberGenerator.new()


func start_new() -> void:
	_rng.randomize()
	week = 0


func step(db: Data, day: int) -> void:
	var cfg: Dictionary = db.balance.get("price", {})
	var limit := float(cfg.get("restriction", 0.5))
	var keep := int(cfg.get("history_weeks", 520))
	var snow: Dictionary = cfg.get("snowball", {})
	var sector_stats := _sector_stats(db)
	for item in db.companies:
		var c: Dictionary = item
		var sector: Dictionary = db.sector_of(c)
		var sigma := float(sector.get("volatility", 0.03)) * db.cfx_c(c, "volatility")   # AI trading of the research trees
		# Fundamental drift: the price is pulled towards the fair value economy.gd builds from revenue and
		# profit, so staff, wages and strikes reach the share price; one-off shocks (strikes, layoffs) add on top.
		var e: Dictionary = db.econ(c)
		var dt := float(db.dt)   # weeks this step covers (a long time skip)
		var mu := float(sector.get("drift", 0.03)) / 52.0 * dt
		var shock := 0.0
		if not e.is_empty():
			var fair := float(e.get("fair", 0.0))
			if fair > 0.0:
				# The pull closes the same share of the gap per week; over dt weeks — 1 − (1 − k)^dt of it (no overshoot).
				mu = (1.0 - pow(1.0 - float(cfg.get("pull_to_fair", 0.03)), dt)) * log(fair / maxf(db.cap(c), 1e-6))
			# Snowball protection (20.19): diminishing returns of size above the sector's median, and a pull back
			# when the price is far above what the profit justifies against the sector.
			var st: Dictionary = sector_stats.get(str(c.get("sector", "")), {})
			var median := float(st.get("median", 0.0))
			if median > 0.0 and db.cap(c) > median:
				mu -= float(snow.get("diminishing_returns", 0.0005)) * log(db.cap(c) / median) * dt
			var pe := db.cap(c) / maxf(float(e.get("P", 0.0)), 1e-6) if float(e.get("P", 0.0)) > 0.0 else 0.0
			if pe > 0.0 and float(st.get("pe", 0.0)) > 0.0 and pe > 2.0 * float(st["pe"]):
				mu -= float(snow.get("mean_reversion", 0.003)) * dt
			shock = float(e.get("шок", 0.0))
			e["шок"] = 0.0
		# The weekly limit holds ordinary moves; one-off jolts (a crisis crash, a «shot») go past it (20.2).
		var r := clampf(mu + sigma * sqrt(dt) * _rng.randfn(0.0, 1.0), -limit, limit) + clampf(shock, -2.3, 1.1)
		var p := float(c["_price"]) * exp(r)
		c["_price"] = p
		var h: Array = c["_history"]
		h.append(p)
		while h.size() > keep:
			h.pop_front()
		var chron: Array = c["_chronicle"]
		if absf(r) >= BIG_MOVE:
			chron.append({"день": day, "вид": "price", "change": exp(r) - 1.0})
		# The chronicle keeps the latest entries only: long games must not grow the save and the week without end.
		if chron.size() > CHRONICLE_KEEP + 50:
			c["_chronicle"] = chron.slice(chron.size() - CHRONICLE_KEEP)
	week += 1


## Per sector: the median market cap and the median price/earnings of the profitable companies.
func _sector_stats(db: Data) -> Dictionary:
	var caps := {}
	var pes := {}
	for item in db.companies:
		var c: Dictionary = item
		var s := str(c.get("sector", ""))
		if not caps.has(s):
			caps[s] = []
			pes[s] = []
		(caps[s] as Array).append(db.cap(c))
		var p := float(db.econ(c).get("P", 0.0))
		if p > 0.0:
			(pes[s] as Array).append(db.cap(c) / p)
	var out := {}
	for s in caps.keys():
		var list: Array = caps[s]
		list.sort()
		var pe_list: Array = pes[s]
		pe_list.sort()   # the median: a few companies with a tiny profit must not set the norm
		out[s] = {"median": float(list[int(list.size() / 2.0)]) if not list.is_empty() else 0.0,
			"pe": float(pe_list[int(pe_list.size() / 2.0)]) if not pe_list.is_empty() else 0.0}
	return out


func save_state(db: Data) -> Dictionary:
	var prices := {}
	var chron := {}
	for item in db.companies:
		var c: Dictionary = item
		prices[str(c["id"])] = c["_history"]
		chron[str(c["id"])] = c["_chronicle"]
	# 64-bit generator state does not survive JSON floats, so it goes as text.
	return {"неделя": week, "зерно": str(_rng.seed), "состояние": str(_rng.state), "цены": prices, "хроника": chron}


func load_state(db: Data, state: Dictionary) -> void:
	week = int(state.get("неделя", 0))
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
	var prices: Dictionary = state.get("цены", {}) if state.get("цены") is Dictionary else {}
	var chron: Dictionary = state.get("хроника", {}) if state.get("хроника") is Dictionary else {}
	for item in db.companies:
		var c: Dictionary = item
		var cid := str(c["id"])
		var h: Variant = prices.get(cid)
		if h is Array and not (h as Array).is_empty():
			var arr: Array = []
			for v in h:
				arr.append(float(v))
			c["_history"] = arr
			c["_price"] = float(arr[arr.size() - 1])
		var ch: Variant = chron.get(cid)
		if ch is Array:
			c["_chronicle"] = (ch as Array).duplicate(true)
