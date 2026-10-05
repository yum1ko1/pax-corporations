extends RefCounted
## The headquarters' badges grouped on the screen (the map's layer, map_layer.gd): those of one country that touch join a
## fan or a cluster, the groups that still overlap are pushed apart. Pure arithmetic on Dictionaries and Vector2 — no
## node, no scene: it runs on a worker thread (Job) as well as on the main one.

const FAN_MAX := 7


## The badges [{c, pos, r, country}] (on the screen already) → their groups, laid out.
static func layout(badges: Array, cell: float) -> Array:
	var groups: Array = []    # [{items: [{c, pos, r}], maxr, country, anchor, pos, R}]
	var grid: Dictionary = {}    # [country, x, y] -> [[item, group index]]
	for b in badges:
		var me: Dictionary = b
		var s: Vector2 = me["pos"]
		var r := float(me["r"])
		var country := str(me["country"])
		var kx := floori(s.x / cell)
		var ky := floori(s.y / cell)
		var best := -1
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for other in grid.get([country, kx + dx, ky + dy], []):
					var od: Dictionary = other[0]
					if (s - (od["pos"] as Vector2)).length() < r + float(od["r"]) + 2.0 and (best < 0 or int(other[1]) < best):
						best = int(other[1])
		if best < 0:
			best = groups.size()
			groups.append({"items": [me], "maxr": r, "country": country})
		else:
			var g: Dictionary = groups[best]
			(g["items"] as Array).append(me)
			g["maxr"] = maxf(float(g["maxr"]), r)
		var key := [country, kx, ky]
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append([me, best])
	for g in groups:
		group_shape(g)
	groups = merge_touching(groups)
	push_apart(groups, 10)
	return groups


## Where a group really is (the mean of its companies) and how big it is drawn (radius R).
static func group_shape(g: Dictionary) -> void:
	var items: Array = g["items"]
	var center := Vector2.ZERO
	var maxr := 0.0
	for it in items:
		center += it["pos"] as Vector2
		maxr = maxf(maxr, float(it["r"]))
	center /= float(items.size())
	g["anchor"] = center
	g["pos"] = center
	g["maxr"] = maxr
	if items.size() == 1:
		g["R"] = maxr + 2.0
	elif items.size() <= FAN_MAX:
		g["R"] = fan_radius(items, maxr) + maxr + 3.0
	else:
		g["R"] = maxr + 14.0


static func fan_radius(items: Array, maxr: float) -> float:
	var ring := 0.0
	for it in items:
		ring += 2.0 * float(it["r"]) + 5.0
	return maxf(maxr * 1.5, ring / TAU)


## Groups of the same country whose shapes overlap become one (a fan grows into a cluster). The candidates are
## looked up in a grid of the groups' size (comparing each group with every other was O(n²): with all the world's
## companies on screen the map dropped to no frames at all).
static func merge_touching(groups: Array) -> Array:
	for _pass in 3:
		var merged := false
		var cell := 8.0
		for g in groups:
			cell = maxf(cell, 2.0 * float((g as Dictionary)["R"]))
		cell = minf(cell, 400.0)
		var grid: Dictionary = {}    # Vector2i -> [alive groups]
		var alive: Array = []
		for g in groups:
			var gd: Dictionary = g
			var at: Vector2 = gd["anchor"]
			var key := Vector2i(floori(at.x / cell), floori(at.y / cell))
			var into: Dictionary = {}
			var reach := int(ceil((float(gd["R"]) * 2.0) / cell))
			for dx in range(-reach, reach + 1):
				for dy in range(-reach, reach + 1):
					for other in grid.get(key + Vector2i(dx, dy), []):
						var od: Dictionary = other
						if str(od["country"]) == str(gd["country"]) \
								and ((od["anchor"] as Vector2) - at).length() < float(od["R"]) + float(gd["R"]):
							into = od
							break
					if not into.is_empty():
						break
				if not into.is_empty():
					break
			if into.is_empty():
				alive.append(gd)
				if not grid.has(key):
					grid[key] = []
				(grid[key] as Array).append(gd)
			else:
				(into["items"] as Array).append_array(gd["items"])
				group_shape(into)
				merged = true
		groups = alive
		if not merged:
			break
	return groups


## Groups that still overlap (different countries) are nudged apart; smaller ones move more.
static func push_apart(groups: Array, passes: int) -> void:
	var n := groups.size()
	if n < 2:
		return
	var cell := 1.0
	for g in groups:
		cell = maxf(cell, 2.0 * float((g as Dictionary)["R"]))
	for _pass in passes:
		var grid: Dictionary = {}
		for i in n:
			var p: Vector2 = (groups[i] as Dictionary)["pos"]
			var key := Vector2i(floori(p.x / cell), floori(p.y / cell))
			if not grid.has(key):
				grid[key] = []
			(grid[key] as Array).append(i)
		var moved := false
		for i in n:
			var a: Dictionary = groups[i]
			var pa: Vector2 = a["pos"]
			var key := Vector2i(floori(pa.x / cell), floori(pa.y / cell))
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					for j in grid.get(key + Vector2i(dx, dy), []):
						if int(j) <= i:
							continue
						var b: Dictionary = groups[int(j)]
						var d: Vector2 = (b["pos"] as Vector2) - (a["pos"] as Vector2)
						var need := float(a["R"]) + float(b["R"]) + 3.0
						var dist := d.length()
						if dist >= need:
							continue
						var dir := d / dist if dist > 0.01 else Vector2.RIGHT.rotated(float(i * 7 + int(j)))
						var push := need - dist
						var wa := float(b["R"]) / (float(a["R"]) + float(b["R"]))
						a["pos"] = (a["pos"] as Vector2) - dir * push * wa
						b["pos"] = (b["pos"] as Vector2) + dir * push * (1.0 - wa)
						moved = true
		if not moved:
			break
