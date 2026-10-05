extends RefCounted
## The might of countries, 0–100 — the country's world rank (Pax Corporations, country_rank.gd), Pax Corpface's
## «Связи» and the country choice. The game's «level» alone is development per person (it put Singapore first);
## might weighs what a country can bring to bear:
##   economy  — the country's budget, or, where the game gives none, people × level³;
##   army     — soldiers (people × fighters) × level (the quality of the arms);
##   people   — how many people it has;
##   nuclear  — a nuclear power gets a fixed share.
## Each part is taken as a square root of its share of the strongest (one giant no longer flattens everyone else),
## might = 100 × (W_ECON·economy + W_ARMY·army + W_PEOPLE·people + W_NUKE·nuclear).
## The great powers (MAJORS) are always among the first MAJOR_TOP places: when the formula puts one lower, it takes
## the place of the weakest ordinary country there.

const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")   # Main's methods, game 0.24

const W_ECON := 0.45
const W_ARMY := 0.25
const W_PEOPLE := 0.15
const W_NUKE := 0.15
const MAJORS := ["США", "Китай", "Россия", "Индия", "Германия", "Великобритания", "Франция", "Япония"]
const MAJOR_TOP := 15   # the sapphire step and above (country_rank.gd)


static func _econ(fd: Dictionary) -> float:
	var b: Variant = fd.get("budget")
	if (b is float or b is int) and float(b) > 0.0:
		return float(b)
	var lvl := maxf(float(fd.get("level", 1.0)), 0.1)
	return float(fd.get("humans", 0.0)) * lvl * lvl * lvl


static func _army(fd: Dictionary) -> float:
	return float(fd.get("humans", 0.0)) * clampf(float(fd.get("fighters", 0.0)), 0.0, 0.2) * maxf(float(fd.get("level", 1.0)), 0.1)


## Game 0.24 keeps the player's own country's people and money not in its faction record (only name, level,
## fighters…) but on the home planet: its resources («humans») and its treasury («yearly», the same scale as the
## other states' «budget»). Without them the player's country weighed nothing and always came out bronze.
static func _with_home(game: PaxGame, fd: Dictionary) -> Dictionary:
	if fd.has("humans") and fd.has("budget"):
		return fd
	var out := fd.duplicate()
	if not out.has("humans"):
		out["humans"] = float((game.resources(game.home_body()) as Dictionary).get("humans", 0.0))
	if not out.has("budget") and is_instance_valid(game.main):
		var tr: Variant = GameApi.call_main(game.main, "_казна_расклад", [game.home_body()])
		if tr is Dictionary:
			out["budget"] = float((tr as Dictionary).get("yearly", 0.0))
	return out


static func living_states(game: PaxGame) -> Array:
	var out: Array = []
	for f in game.factions():
		var fd: Dictionary = f
		if str(fd.get("name", "")).is_empty() or not bool(fd.get("polity", true)) or bool(fd.get("perished", false)):
			continue
		out.append(_with_home(game, fd) if bool(fd.get("ours", false)) else fd)
	return out


## Every living state's might and place: {name: {сила, место, экономика, army, nuclear, major}} — the player's
## country too (its record from game.player_faction() when the factions list leaves it out).
static func table(game: PaxGame) -> Dictionary:
	var states := living_states(game)
	var me: Dictionary = game.player_faction()
	var me_name := str(me.get("name", ""))
	if not me_name.is_empty() and not states.any(func(x: Variant) -> bool: return str((x as Dictionary).get("name", "")) == me_name):
		states.append(_with_home(game, me))
	var max_e := 1e-9
	var max_a := 1e-9
	var max_p := 1e-9
	for fd: Dictionary in states:
		max_e = maxf(max_e, _econ(fd))
		max_a = maxf(max_a, _army(fd))
		max_p = maxf(max_p, float(fd.get("humans", 0.0)))
	var rows: Array = []
	for fd: Dictionary in states:
		var e := sqrt(maxf(_econ(fd), 0.0) / max_e)
		var a := sqrt(maxf(_army(fd), 0.0) / max_a)
		var p := sqrt(maxf(float(fd.get("humans", 0.0)), 0.0) / max_p)
		var n := 1.0 if bool(fd.get("nuclear", false)) else 0.0
		var name := str(fd["name"])
		rows.append([name, 100.0 * (W_ECON * e + W_ARMY * a + W_PEOPLE * p + W_NUKE * n), e, a, n, MAJORS.has(name)])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) > float(y[1]))
	rows = _majors_up(rows)
	var out := {}
	for i in rows.size():
		var r: Array = rows[i]
		out[str(r[0])] = {"сила": float(r[1]), "место": i + 1, "экономика": float(r[2]) * 100.0, "army": float(r[3]) * 100.0,
			"nuclear": float(r[4]) > 0.0, "major": bool(r[5])}
	return out


## The great powers below MAJOR_TOP move up to its end, the weakest ordinary countries there move down after them.
static func _majors_up(rows: Array) -> Array:
	var top := mini(MAJOR_TOP, rows.size())
	var head: Array = rows.slice(0, top)
	var late: Array = rows.slice(top).filter(func(r: Array) -> bool: return bool(r[5]))
	if late.is_empty():
		return rows
	var pushed: Array = []
	var i := head.size() - 1
	while pushed.size() < late.size() and i >= 0:
		if not bool((head[i] as Array)[5]):
			pushed.push_front(head[i])
			head.remove_at(i)
		i -= 1
	var rest: Array = rows.slice(top).filter(func(r: Array) -> bool: return not bool(r[5]))
	return head + late + pushed + rest
