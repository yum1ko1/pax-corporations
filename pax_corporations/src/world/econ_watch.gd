extends RefCounted
## The economy watch: once a game year (and at the start) a snapshot of the corporate world — companies, revenue,
## profit, market value, debt, staff, wages, the share losing money, by country (the 15 biggest and the player's) and
## for the world; between snapshots — what happened (births, deaths, takeovers, breakups, wars, rescues, from the
## modules' counters). Each snapshot goes to the journal (category «econ», sent to the developer with it) and is
## kept in the save; «corp econ» in the console prints the table of all of them. It changes nothing in the game.

const MAX_SNAPSHOTS := 40
const TOP := 15

var snapshots: Array = []         # {day, date, world: {...}, countries: {country: {...}}, events: {...}}
var _next_day := -1
var _events_before: Dictionary = {}


func save_state() -> Dictionary:
	return {"snapshots": snapshots, "next_day": _next_day, "events_before": _events_before}


func load_state(st: Dictionary) -> void:
	snapshots = (st.get("snapshots", []) as Array).duplicate(true) if st.get("snapshots") is Array else []
	_next_day = int(st.get("next_day", -1))
	_events_before = (st.get("events_before", {}) as Dictionary).duplicate() if st.get("events_before") is Dictionary else {}


## Called every simulated week (scheduler, the last phase): a snapshot when a year has passed.
func week(db: Object, game: PaxGame, player: String, counters: Dictionary, log: Callable) -> void:
	var day := game.day()
	if _next_day >= 0 and day < _next_day:
		return
	_next_day = day + 364
	var snap := take(db, game, player, counters)
	snapshots.append(snap)
	if snapshots.size() > MAX_SNAPSHOTS:
		snapshots = snapshots.slice(snapshots.size() - MAX_SNAPSHOTS)
	for line in lines(snap, snapshots[snapshots.size() - 2] if snapshots.size() > 1 else {}):
		log.call(line)


## One snapshot of the corporate world.
func take(db: Object, game: PaxGame, player: String, counters: Dictionary, remember: bool = true) -> Dictionary:
	var by: Dictionary = {}
	var world := _empty()
	for item in db.get("companies"):
		var c: Dictionary = item
		var country := str(c.get("_country", ""))
		if not by.has(country):
			by[country] = _empty()
		for agg: Dictionary in [by[country], world]:
			var revenue := float(db.call("fund", c, "выручка"))
			var profit := float(db.call("fund", c, "profit"))
			agg["n"] = int(agg["n"]) + 1
			agg["revenue"] = float(agg["revenue"]) + revenue
			agg["profit"] = float(agg["profit"]) + profit
			agg["cap"] = float(agg["cap"]) + float(db.call("cap", c))
			agg["debt"] = float(agg["debt"]) + float(db.call("fund", c, "debt"))
			agg["staff"] = float(agg["staff"]) + float(db.call("staff", c))
			agg["payroll"] = float(agg["payroll"]) + float(db.call("staff", c)) * float(db.call("wage", c))
			agg["losing"] = int(agg["losing"]) + (1 if profit < 0.0 else 0)
			agg["state"] = int(agg["state"]) + (1 if float(db.call("state_share", c)) > 0.5 else 0)
	var names: Array = by.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return float((by[a] as Dictionary)["cap"]) > float((by[b] as Dictionary)["cap"]))
	var keep := {}
	for k in names.slice(0, TOP) + ([player] if by.has(player) else []):
		keep[k] = _finish(by[k])
	var events := {}
	for k in counters.keys():
		events[k] = int(counters[k]) - int(_events_before.get(k, 0))
	if remember:
		_events_before = counters.duplicate()
	return {"day": game.day(), "date": game.date_text(), "world": _finish(world), "countries": keep, "events": events,
		"player": player}


func _empty() -> Dictionary:
	return {"n": 0, "revenue": 0.0, "profit": 0.0, "cap": 0.0, "debt": 0.0, "staff": 0.0, "payroll": 0.0, "losing": 0, "state": 0}


func _finish(a: Dictionary) -> Dictionary:
	var out := a.duplicate()
	var n := maxi(1, int(a["n"]))
	out["margin"] = float(a["profit"]) / maxf(float(a["revenue"]), 1e-6)
	out["wage"] = float(a["payroll"]) / maxf(float(a["staff"]), 1e-6)
	out["losing_share"] = float(a["losing"]) / float(n)
	out["debt_to_revenue"] = float(a["debt"]) / maxf(float(a["revenue"]), 1e-6)
	return out


## The snapshot as journal lines, with the change since the previous one (×).
func lines(s: Dictionary, prev: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var w: Dictionary = s["world"]
	var pw: Dictionary = prev.get("world", {}) if not prev.is_empty() else {}
	out.append("%s · world: %d companies, revenue %s%s, profit %s (margin %.1f%%), cap %s%s, debt/revenue %.2f, staff %s, wage %.0f, losing %.0f%%, state-owned %d" % [
		str(s["date"]), int(w["n"]), _m(float(w["revenue"])), _x(w, pw, "revenue"), _m(float(w["profit"])), 100.0 * float(w["margin"]),
		_m(float(w["cap"])), _x(w, pw, "cap"), float(w["debt_to_revenue"]), _n(float(w["staff"])), float(w["wage"]),
		100.0 * float(w["losing_share"]), int(w["state"])])
	var ev: Dictionary = s["events"]
	if not ev.is_empty():
		var parts: PackedStringArray = []
		for k in ev.keys():
			if int(ev[k]) != 0:
				parts.append("%s %d" % [str(k), int(ev[k])])
		out.append("%s · the year's events: %s" % [str(s["date"]), ", ".join(parts) if not parts.is_empty() else "none"])
	var pc: Dictionary = prev.get("countries", {}) if not prev.is_empty() else {}
	for country in (s["countries"] as Dictionary).keys():
		var c: Dictionary = s["countries"][country]
		out.append("%s · %s%s: %d co., revenue %s%s, margin %.1f%%, cap %s%s, losing %.0f%%, wage %.0f" % [str(s["date"]), str(country),
			" (player)" if country == str(s["player"]) else "", int(c["n"]), _m(float(c["revenue"])), _x(c, pc.get(country, {}), "revenue"),
			100.0 * float(c["margin"]), _m(float(c["cap"])), _x(c, pc.get(country, {}), "cap"), 100.0 * float(c["losing_share"]), float(c["wage"])])
	return out


## Every snapshot so far as a table (the console).
func table() -> String:
	if snapshots.is_empty():
		return "no snapshots yet (the first comes at the first simulated week)"
	var out: PackedStringArray = ["date | companies | revenue | profit | margin | cap | debt/rev | losing | wage"]
	for s in snapshots:
		var w: Dictionary = (s as Dictionary)["world"]
		out.append("%s | %d | %s | %s | %.1f%% | %s | %.2f | %.0f%% | %.0f" % [str(s["date"]), int(w["n"]), _m(float(w["revenue"])),
			_m(float(w["profit"])), 100.0 * float(w["margin"]), _m(float(w["cap"])), float(w["debt_to_revenue"]),
			100.0 * float(w["losing_share"]), float(w["wage"])])
	return "\n".join(out)


static func _x(now: Dictionary, prev: Dictionary, key: String) -> String:
	if prev.is_empty() or float(prev.get(key, 0.0)) == 0.0:
		return ""
	return " ×%.2f" % (float(now[key]) / float(prev[key]))


static func _m(mln: float) -> String:
	return "%.2f trn" % (mln / 1e6) if absf(mln) >= 1e6 else ("%.1f bn" % (mln / 1e3) if absf(mln) >= 1e3 else "%.0f mln" % mln)


static func _n(x: float) -> String:
	return "%.1f mln" % (x / 1e6) if x >= 1e6 else "%.0f k" % (x / 1e3)
