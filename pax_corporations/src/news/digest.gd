extends RefCounted
## Corporate summary for the player — one per time skip: what mattered among the player's country's and
## favourite companies (big moves, strikes, layoffs, threats and praise, the world crisis), who rose and who
## fell over the period, and what the companies paid into the treasury. Shown in the «Summary» tab of the
## window; the last reports are kept in the save.

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const KEEP := 12
const MAX_LINES := 10

var unread := false          # a new report the player has not opened yet
var reports: Array = []      # newest last: {с_дня, по_день, строки: [{id, entry, tone, size}], казна, лидеры}
var _current: Dictionary = {}


## A skip starts: remember prices so the period's leaders can be found.
func begin(db: Data, day: int) -> void:
	if not _current.is_empty():
		return
	var prices := {}
	for item in db.companies:
		var c: Dictionary = item
		prices[str(c["id"])] = db.price(c)
	_current = {"from_day": day, "rows": [], "treasury": 0.0, "цены": prices}


func add(item: Dictionary) -> void:
	if _current.is_empty():
		return
	var c: Dictionary = item.get("c", {})
	var lines: Array = _current["rows"]
	lines.append({"id": str(c.get("id", "")), "entry": item["entry"],
		"tone": str(item.get("tone", "neutral")), "size": float(item.get("size", 0.1))})
	# A skip of decades must not pile up tens of thousands of lines: keep the biggest when it grows.
	if lines.size() > 400:
		lines.sort_custom(func(a, b): return float(a["size"]) > float(b["size"]))
		_current["rows"] = lines.slice(0, 200)


func add_treasury(amount: float) -> void:
	if not _current.is_empty():
		_current["treasury"] = float(_current["treasury"]) + amount


## The skip is over: sort, keep the most important lines, find the leaders, file the report.
func close(db: Data, day: int, player: String, favorites: Dictionary) -> Dictionary:
	if _current.is_empty():
		return {}
	var rep := _current
	_current = {}
	rep["to_day"] = day
	var lines: Array = rep["rows"]
	lines.sort_custom(func(a, b): return float(a["size"]) > float(b["size"]))
	var crisis: Array = lines.filter(func(l): return str(l["id"]).is_empty())
	var rest: Array = lines.filter(func(l): return not str(l["id"]).is_empty())
	rep["rows"] = crisis + rest.slice(0, MAX_LINES - crisis.size())
	var moves: Array = []
	var before: Dictionary = rep["цены"]
	for item in db.companies:
		var c: Dictionary = item
		var cid := str(c["id"])
		var country := str(c.get("_country", ""))
		if not (country == player or favorites.has(cid) or favorites.has("страна:" + country)):
			continue
		var was := float(before.get(cid, 0.0))
		if was > 0.0:
			moves.append({"id": cid, "change": db.price(c) / was - 1.0})
	moves.sort_custom(func(a, b): return float(a["change"]) > float(b["change"]))
	rep["лидеры"] = moves
	rep.erase("цены")
	if (rep["rows"] as Array).is_empty() and moves.is_empty() and float(rep["treasury"]) == 0.0:
		return {}
	reports.append(rep)
	# A time skip (a month or more) leaves a badge on the «Corporations» button until the «Summary» tab is opened.
	if day - int(rep.get("from_day", day)) >= 28:
		unread = true
	while reports.size() > KEEP:
		reports.pop_front()
	return rep


func save_state() -> Array:
	var out: Array = []
	for r in reports:
		out.append(r)
	return out


func load_state(state: Variant) -> void:
	if state is Array:
		reports = (state as Array).duplicate(true)
