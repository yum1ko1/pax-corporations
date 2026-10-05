extends Control
## The radial development tree of one industry in one country (tree.gd), drawn in the industry's style («чип» for
## IT: chips with pins and PCB traces). The root in the middle, four branches; along each branch: base → two
## middle nodes → three outer → the final at the tip. Hover — a tooltip with the node's description; with free
## GV the nodes that can be bought now get a light blue pulsing outline; a click asks to buy (main.gd).

const DevTree := preload("res://mods/pax_corporations/src/tech/tree.gd")
const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const BASE := Vector2(1300, 1340)
const R0 := 225.0
const R1 := 330.0
const R2 := 435.0
const R3 := 545.0
const RT := 140.0
const AVAIL := Color(0.55, 0.85, 1.0)
const SIDE_FROM := 80.0          # a side branch's name band along its axis: from the root's edge…
const SIDE_TO := 255.0           # …to before the middle nodes' labels

var tree: DevTree
var db: Data
var mod: PaxMod
var country := ""
var sector := ""
var on_pick: Callable            # func(node id)
var _pos: Dictionary = {}        # id -> [centre, half size] in the control's pixels
var _hover := ""
var _clock := 0.0
var capabilities: Object         # capabilities.gd: «Открывает: …» in a node's description
var _flash_id := ""              # a node to flash (sent here from the technologies map)
var _flash_until := 0.0
var _now := 0.0                  # seconds, one clock for every animation of the tree
var _node_open := false          # the node being drawn is open (its shape comes alive)
var _style := "чип"               # the industry's look: «чип» (IT), «нефть» (oil and gas), «энергия» (power)
# Moving and zooming, as on the technologies' map: the wheel zooms round the cursor, a drag moves the tree.
var _zoom := 1.0
var _pan := Vector2.ZERO
var _press := Vector2(-1, -1)      # where a button went down (a click is a press without a move)
var _dragged := false
var _view_of := ""                 # the industry the zoom and the move belong to (a new one starts whole)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true   # zoomed in, the tree stays inside its window
	tooltip_text = " "


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= 1.0 / 20.0 and is_visible_in_tree():
		_clock = 0.0
		queue_redraw()   # the outline of the nodes that can be bought pulses


func _scale() -> float:
	return minf(size.x / BASE.x, size.y / BASE.y) * _zoom


func _center() -> Vector2:
	return size / 2.0 + _pan


func _at(r: float, deg: float) -> Vector2:
	return _center() + Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg))) * r * _scale()


func _layout() -> void:
	_pos.clear()
	var t: Dictionary = tree.trees().get(sector, {})
	var s := _scale()
	_pos[str((t.get("root_node", {}) as Dictionary).get("id", "root"))] = [_center(), Vector2(66, 52) * s]
	for b in t.get("ветки", []):
		var a := float((b as Dictionary).get("угол", 0.0))
		for n in (b as Dictionary).get("nodes", []):
			var nd: Dictionary = n
			var at := Vector2.ZERO
			var half := 23.0
			match str(nd.get("место", "")):
				"founding":
					at = _at(R0, a)
					half = 25.0
				"левый_средний":
					at = _at(R1, a - 20.0)
				"правый_средний":
					at = _at(R1, a + 20.0)
				"левый":
					at = _at(R2, a - 29.0)
				"центр":
					at = _at(R2, a)
				"правый":
					at = _at(R2, a + 29.0)
				_:
					at = _at(R3, a)
					half = 32.0
			_pos[str(nd["id"])] = [at, Vector2(half, half) * s]


func _col(v: Variant, fallback: Color) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return fallback


func _draw() -> void:
	if tree == null or not tree.has_tree(sector):
		return
	if _view_of != sector:
		_view_of = sector
		_zoom = 1.0
		_pan = Vector2.ZERO
	_layout()
	var t: Dictionary = tree.trees()[sector]
	_style = str(t.get("стиль", "чип"))
	_now = Time.get_ticks_msec() / 1000.0
	var s := _scale()
	var font := get_theme_default_font()
	var oil := _style == "oil"
	var power := _style == "energy"
	var metal := _style == "металл"
	var silicon := _style == "кремний"
	var money := _style == "финансы"
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.04, 0.03) if oil else (Color(0.03, 0.03, 0.06) if power else (Color(0.045, 0.045, 0.05) if metal else (Color(0.02, 0.035, 0.06) if silicon else (Color(0.03, 0.045, 0.035) if money else Color(0.03, 0.045, 0.07))))))
	if STYLE_BG.has(_style):
		draw_rect(Rect2(Vector2.ZERO, size), STYLE_BG[_style])
	_backdrop(s)
	for r in [R0, R1, R2]:
		draw_arc(_center(), r * s, 0.0, TAU, 96, Color(0.2, 0.15, 0.08) if oil else (Color(0.16, 0.14, 0.26) if power else Color(0.11, 0.16, 0.23)), 1.0, true)
	var have_gv := int(tree.wallet(country, sector).get("has_flag", 0)) > 0   # GV or НО (research trees)
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * TAU / 1.6)
	var root_id := str((t.get("root_node", {}) as Dictionary).get("id", "root"))
	for b in t.get("ветки", []):
		var bd: Dictionary = b
		var col := _col(bd.get("colour"), Color.WHITE)
		var nodes: Array = bd.get("nodes", [])
		# Arrows: along the «требует» links.
		for n in nodes:
			var nd: Dictionary = n
			for req in nd.get("requires", [root_id]):
				var from := str(req)
				if not _pos.has(from):
					continue
				var on := tree.is_open(country, sector, from)
				_arrow((_pos[from] as Array)[0], (_pos[str(nd["id"])] as Array)[0], col, 0.85 if on else 0.35,
					((_pos[from] as Array)[1] as Vector2).x + 4.0 * s, ((_pos[str(nd["id"])] as Array)[1] as Vector2).x + 6.0 * s, s)
		for n in nodes:
			var nd: Dictionary = n
			var id := str(nd["id"])
			var st := 0
			if tree.is_open(country, sector, id):
				st = 2
			elif tree.developing(country, sector, id) >= 0:
				st = 3
			elif tree.can_buy(db, country, sector, id) in ["", "gv", "no"]:
				st = 1
			var avail := have_gv and tree.can_buy(db, country, sector, id).is_empty()
			_chip(id, nd, col, st, avail, pulse, bool(bd.get("технологии", false)), str(nd.get("место", "")) == "финал", font, s)
		_tag(db.text(bd.get("name", "")) + (" ★" if bool(bd.get("технологии", false)) else ""), float(bd.get("угол", 0.0)), col, font, s)
	# The root.
	var rc: Vector2 = (_pos[root_id] as Array)[0]
	var rh: Vector2 = (_pos[root_id] as Array)[1]
	var rcol := _col(t.get("colour"), Color(0.62, 0.91, 1.0))
	var r_open := tree.is_open(country, sector, root_id)
	var r_avail := have_gv and tree.can_buy(db, country, sector, root_id).is_empty()
	if r_avail:
		draw_rect(Rect2(rc - rh - Vector2(6, 6) * s, (rh + Vector2(6, 6) * s) * 2.0), Color(AVAIL, 0.5 * pulse), false, 3.0 * s)
	draw_rect(Rect2(rc - rh, rh * 2.0), Color(rcol, 0.33) if r_open else (Color(0.1, 0.07, 0.03) if oil else Color(0.06, 0.11, 0.17)))
	draw_rect(Rect2(rc - rh, rh * 2.0), rcol, false, 3.0 * s)
	if _emblem(rc + Vector2(0, -rh.y), rcol, s):
		pass
	elif money:
		_bank(rc + Vector2(0, -rh.y), 38.0 * s, rcol, s)
	elif silicon:
		_beam(rc + Vector2(0, -rh.y), 46.0 * s, rcol, s)
	elif metal:
		_anvil(rc + Vector2(0, -rh.y - 20.0 * s), 30.0 * s, rcol)
	elif power:
		_atom(rc + Vector2(0, -rh.y - 34.0 * s), 26.0 * s, rcol, s)
	elif oil:
		_derrick(rc + Vector2(0, -rh.y), rh.y * 1.3, rcol, s)
	else:
		_pins(rc, rh, rcol, s, 9)
	var fs := maxi(10, int(14.0 * s))
	_text_center(font, rc + Vector2(0, -6) * s, _t("tree_root_short"), fs, Color(0.9, 0.97, 1.0))
	_text_center(font, rc + Vector2(0, 26) * s, _cost_line(root_id, r_open), fs, rcol)
	if _hover == root_id:
		draw_rect(Rect2(rc - rh - Vector2(3, 3), rh * 2.0 + Vector2(6, 6)), Color(1, 1, 1, 0.6), false, 1.5)


func _cost_line(id: String, open: bool) -> String:
	if open:
		return "✓"
	var d := tree.developing(country, sector, id)
	if d >= 0:
		return _t("tree_dev_short") % maxi(0, (d - Pax.game.day()) / 7)
	return _t(_cost_key()) % int(tree.node(sector, id).get("price", 1))


## Light up a node for a few seconds (the technologies map sent the player here).
func flash(id: String) -> void:
	_flash_id = id
	_flash_until = Time.get_ticks_msec() / 1000.0 + 3.0


func _cost_key() -> String:
	return "tree_cost_no" if tree.currency(sector) == "but_value" else "tree_cost"


func _chip(id: String, nd: Dictionary, col: Color, st: int, avail: bool, pulse: float, tech: bool, fin: bool, font: Font, s: float) -> void:
	var c: Vector2 = (_pos[id] as Array)[0]
	var h: Vector2 = (_pos[id] as Array)[1]
	var dim := Color(0.23, 0.27, 0.33)
	var edge := col if st >= 1 else dim
	if avail:
		draw_rect(Rect2(c - h - Vector2(6, 6) * s, (h + Vector2(6, 6) * s) * 2.0), Color(AVAIL, 0.75 * pulse), false, 3.0 * s)
	var fill := Color(col, 0.35) if st == 2 else (Color(col, 0.15) if st == 3 else Color(0.05, 0.08, 0.13))
	_node_open = st == 2
	if id == _flash_id and _now < _flash_until:
		# Brought here from the technologies map: bright rings run outwards for a few seconds.
		for k in 3:
			var ph := fmod(_now * 1.4 + float(k) / 3.0, 1.0)
			var g := (h + Vector2(8, 8) * s) * (1.0 + 0.6 * ph)
			draw_rect(Rect2(c - g, g * 2.0), Color(1.0, 0.95, 0.5, 0.9 * (1.0 - ph)), false, 3.0 * s)
		draw_rect(Rect2(c - h - Vector2(5, 5) * s, (h + Vector2(5, 5) * s) * 2.0), Color(1.0, 0.95, 0.5), false, 4.0 * s)
	if _shape(c, h, fill, edge, (3.5 if fin else 2.5) * s):
		pass
	elif _style == "oil":
		_barrel(c, h, fill, edge, (3.5 if fin else 2.5) * s)
	elif _style == "финансы":
		_coin(c, h.x * 1.02, fill, edge, (3.5 if fin else 2.5) * s)
	elif _style == "кремний":
		_wafer(c, h.x * 1.05, fill, edge, (3.5 if fin else 2.5) * s)
	elif _style == "металл":
		_gear(c, h.x * 1.05, fill, edge, (3.5 if fin else 2.5) * s)
	elif _style == "energy":
		_cell(c, h.x * 1.12, fill, edge, (3.5 if fin else 2.5) * s, st)
	else:
		draw_rect(Rect2(c - h, h * 2.0), fill)
		draw_rect(Rect2(c - h, h * 2.0), edge, false, (3.5 if fin else 2.5) * s)
		_pins(c, h, edge, s, 3)
	if tech:
		var p := c + Vector2(h.x, -h.y)
		var g := 7.0 * s
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -g), p + Vector2(g, 0), p + Vector2(0, g), p + Vector2(-g, 0)]),
			Color(1.0, 0.88, 0.54) if st >= 2 else Color(0.35, 0.29, 0.13))
	var fs := maxi(10, int(14.0 * s))
	_text_center(font, c + Vector2(0, 5) * s, _cost_line(id, st == 2), fs, edge if st != 0 else Color(0.42, 0.46, 0.52))
	var name := db.text(nd.get("name", ""))
	if nd.has("on_the_way"):
		for via in (nd["on_the_way"] as Dictionary).keys():
			if tree.is_open(country, sector, str(via)):
				name = db.text(((nd["on_the_way"] as Dictionary)[via] as Dictionary).get("name", name))
	var lines := _wrap(name, 16)
	var ls := maxi(10, int(13.0 * s))
	for i in lines.size():
		_text_center(font, c + Vector2(0, h.y + (17.0 + 15.0 * float(i)) * s), str(lines[i]), ls,
			Color(0.9, 0.93, 0.97) if st >= 1 else Color(0.55, 0.59, 0.65))
	if st == 0 and tree.locked(country, sector, id):
		_padlock(c, h.x * 0.75, s)
	if _hover == id:
		draw_rect(Rect2(c - h - Vector2(3, 3), h * 2.0 + Vector2(6, 6)), Color(1, 1, 1, 0.6), false, 1.5)


## Finance style: a gold coin — a rim, an inner ring and milled edge marks.
func _coin(c: Vector2, r: float, fill: Color, edge: Color, w: float) -> void:
	draw_circle(c, r, fill)
	draw_arc(c, r, 0.0, TAU, 40, edge, w, true)
	draw_arc(c, r * 0.78, 0.0, TAU, 32, Color(edge, 0.7), maxf(1.0, w * 0.5), true)
	for i in 24:
		var a := TAU * float(i) / 24.0
		draw_line(c + Vector2(cos(a), sin(a)) * r * 0.86, c + Vector2(cos(a), sin(a)) * r * 0.95, Color(edge, 0.5), 1.0, true)
	if _node_open:
		# A glint sweeps across an open coin every few seconds.
		var ph := fmod(_now + c.x * 0.01, 3.0)
		if ph < 0.6:
			var x := lerpf(-r, r, ph / 0.6)
			draw_line(c + Vector2(x - r * 0.3, r * 0.6), c + Vector2(x + r * 0.3, -r * 0.6), Color(1, 1, 1, 0.55), maxf(1.5, w), true)


## Finance style: a classical bank front over the root — a pediment, four columns, steps.
func _bank(base: Vector2, w: float, col: Color, s: float) -> void:
	var h := w * 0.8
	var lw := maxf(1.5, 2.0 * s)
	draw_rect(Rect2(base + Vector2(-w, -h * 0.12), Vector2(w * 2.0, h * 0.12)), col)
	for i in 4:
		var x := lerpf(-w * 0.75, w * 0.75, float(i) / 3.0)
		draw_rect(Rect2(base + Vector2(x - w * 0.08, -h * 0.82), Vector2(w * 0.16, h * 0.7)), Color(col, 0.85))
	draw_rect(Rect2(base + Vector2(-w * 0.95, -h * 0.92), Vector2(w * 1.9, h * 0.1)), col)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-w, -h * 0.92), base + Vector2(0, -h * 1.35), base + Vector2(w, -h * 0.92)]), col)
	draw_line(base + Vector2(-w * 0.6, -h * 1.0), base + Vector2(w * 0.6, -h * 1.0), Color(0, 0, 0, 0.4), lw, true)


## Silicon style: a wafer — a disc with a flat notch and a grid of dies.
func _wafer(c: Vector2, r: float, fill: Color, edge: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var a := deg_to_rad(110.0) + TAU * 0.89 * float(i) / 40.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, edge, w, true)
	var cell := r * 0.34
	for gx in range(-2, 2):
		for gy in range(-2, 2):
			var q := c + Vector2(float(gx) + 0.1, float(gy) + 0.1) * cell
			if (q + Vector2(cell, cell) * 0.4 - c).length() < r * 0.78:
				draw_rect(Rect2(q, Vector2(cell, cell) * 0.8), Color(edge, 0.35), false, 1.0)


## Silicon style: a lithography beam over the root — a lens and light falling onto it.
func _beam(base: Vector2, hgt: float, col: Color, s: float) -> void:
	var lens := base + Vector2(0, -hgt)
	var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU / 2.5)
	draw_colored_polygon(PackedVector2Array([lens + Vector2(-12, 0) * s, lens + Vector2(12, 0) * s, base + Vector2(4, -2) * s, base + Vector2(-4, -2) * s]),
		Color(0.6, 0.4, 1.0, 0.25 + 0.25 * k))
	_ellipse(lens, 18.0 * s, 5.0 * s, col, maxf(1.5, 2.0 * s))
	draw_line(lens + Vector2(-18, -8) * s, lens + Vector2(18, -8) * s, col, maxf(1.5, 2.0 * s), true)


## Metal style: a cog — twelve teeth around a disc with a hub.
func _gear(c: Vector2, r: float, fill: Color, edge: Color, w: float) -> void:
	var pts := PackedVector2Array()
	const teeth := 12
	for i in teeth * 4 + 1:
		var a := TAU * float(i) / float(teeth * 4) + (_now * 0.8 if _node_open else 0.0)   # an open gear turns
		var k := i % 4
		var rr := r if k == 1 or k == 2 else r * 0.82
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts.slice(0, pts.size() - 1), fill)
	draw_polyline(pts, edge, w, true)
	draw_arc(c, r * 0.3, 0.0, TAU, 20, Color(edge, 0.7), maxf(1.0, w * 0.6), true)


## Metal style: an anvil over the root.
func _anvil(base: Vector2, w: float, col: Color) -> void:
	var top := PackedVector2Array([base + Vector2(-w, -w * 0.55), base + Vector2(w * 0.7, -w * 0.55), base + Vector2(w * 1.1, -w * 0.75),
		base + Vector2(w * 0.8, -w * 0.3), base + Vector2(w * 0.4, -w * 0.3), base + Vector2(w * 0.3, 0), base + Vector2(-w * 0.5, 0),
		base + Vector2(-w * 0.6, -w * 0.3), base + Vector2(-w, -w * 0.35)])
	draw_colored_polygon(top, col)
	draw_rect(Rect2(base + Vector2(-w * 0.7, 0), Vector2(w * 1.3, w * 0.18)), col.darkened(0.2))
	# Sparks fly off the anvil.
	for i in 5:
		var ph := fmod(_now * 1.3 + float(i) * 0.37, 1.0)
		var dir := Vector2(cos(-PI / 2.0 + (float(i) - 2.0) * 0.45), sin(-PI / 2.0 + (float(i) - 2.0) * 0.45))
		draw_circle(base + Vector2(0, -w * 0.55) + dir * w * 1.2 * ph, 2.0 * (1.0 - ph) + 0.5, Color(1.0, 0.7, 0.25, 1.0 - ph))


## Power style: a hexagonal energy cell with a glowing core (brighter when open).
func _cell(c: Vector2, r: float, fill: Color, edge: Color, w: float, st: int) -> void:
	var pts := PackedVector2Array()
	for i in 7:
		var a := PI / 6.0 + TAU * float(i) / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts.slice(0, 6), fill)
	draw_polyline(pts, edge, w, true)
	if st >= 2:
		var glow := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU / 2.0)
		draw_circle(c + Vector2(0, -r * 0.45), r * 0.18, Color(edge, 0.4 + 0.4 * glow))


## Power style: an atom over the root — a nucleus and three orbits.
func _atom(c: Vector2, r: float, col: Color, s: float) -> void:
	for k in 3:
		var a := TAU * float(k) / 3.0 + Time.get_ticks_msec() / 1000.0 * 0.3
		var pts := PackedVector2Array()
		for i in 33:
			var t := TAU * float(i) / 32.0
			var p := Vector2(cos(t) * r, sin(t) * r * 0.35).rotated(a)
			pts.append(c + p)
		draw_polyline(pts, Color(col, 0.85), maxf(1.0, 1.8 * s), true)
	draw_circle(c, r * 0.22, col)


## Oil style: a barrel — a body with hoops and an elliptic lid.
func _barrel(c: Vector2, h: Vector2, fill: Color, edge: Color, w: float) -> void:
	var body := Rect2(c - Vector2(h.x * 0.85, h.y), Vector2(h.x * 1.7, h.y * 2.0))
	draw_rect(body, fill)
	draw_rect(body, edge, false, w)
	for k in [-0.45, 0.45]:
		draw_line(Vector2(body.position.x, c.y + h.y * k), Vector2(body.end.x, c.y + h.y * k), Color(edge, 0.8), maxf(1.0, w * 0.6), true)
	_ellipse(Vector2(c.x, body.position.y), h.x * 0.85, h.y * 0.22, edge, w)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * float(i) / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, w, true)


## Oil style: a drilling derrick standing on the root.
func _derrick(base: Vector2, hgt: float, col: Color, s: float) -> void:
	var w := hgt * 0.45
	var top := base + Vector2(0, -hgt)
	var l := base + Vector2(-w, 0)
	var r := base + Vector2(w, 0)
	var lw := maxf(1.5, 2.5 * s)
	draw_line(l, top, col, lw, true)
	draw_line(r, top, col, lw, true)
	for k in 4:
		var t0 := float(k) / 4.0
		var t1 := float(k + 1) / 4.0
		draw_line(l.lerp(top, t0), r.lerp(top, t1), Color(col, 0.7), lw * 0.6, true)
		draw_line(r.lerp(top, t0), l.lerp(top, t1), Color(col, 0.7), lw * 0.6, true)
		draw_line(l.lerp(top, t1), r.lerp(top, t1), Color(col, 0.8), lw * 0.6, true)
	draw_circle(top, 3.0 * s, col)
	if fmod(_now, 1.2) < 0.6:
		draw_circle(top, 6.0 * s, Color(1.0, 0.3, 0.2, 0.8))   # the warning light on top blinks


## A padlock over a node closed by a choice in its branch.
func _padlock(c: Vector2, r: float, s: float) -> void:
	draw_rect(Rect2(c - Vector2(r, r) * 1.25, Vector2(r, r) * 2.5), Color(0.02, 0.03, 0.05, 0.75))
	var body := Rect2(c + Vector2(-r * 0.62, -r * 0.1), Vector2(r * 1.24, r * 0.95))
	var col := Color(0.86, 0.36, 0.33)
	draw_arc(c + Vector2(0, -r * 0.1), r * 0.42, PI, TAU, 18, col, maxf(2.0, 3.0 * s), true)
	draw_rect(body, col)
	draw_circle(body.get_center() + Vector2(0, -r * 0.08), r * 0.14, Color(0.15, 0.05, 0.05))
	draw_rect(Rect2(body.get_center() + Vector2(-r * 0.05, -r * 0.05), Vector2(r * 0.1, r * 0.3)), Color(0.15, 0.05, 0.05))


func _pins(c: Vector2, h: Vector2, col: Color, s: float, n: int) -> void:
	var step := (h.x * 2.0) / float(n + 1)
	for i in n:
		var o := -h.x + step * float(i + 1)
		draw_line(c + Vector2(o, -h.y), c + Vector2(o, -h.y - 6.0 * s), col, 2.0 * s)
		draw_line(c + Vector2(o, h.y), c + Vector2(o, h.y + 6.0 * s), col, 2.0 * s)
		var oy := (-h.y + (h.y * 2.0) / float(n + 1) * float(i + 1))
		draw_line(c + Vector2(-h.x, oy), c + Vector2(-h.x - 6.0 * s, oy), col, 2.0 * s)
		draw_line(c + Vector2(h.x, oy), c + Vector2(h.x + 6.0 * s, oy), col, 2.0 * s)


func _arrow(a: Vector2, b: Vector2, col: Color, alpha: float, ra: float, rb: float, s: float) -> void:
	var u := (b - a).normalized()
	var p0 := a + u * ra
	var p1 := b - u * rb
	var start := p0
	if _link(p0, p1, u, col, alpha, s):
		pass
	elif _style == "финансы":
		# A golden chain: links along the way.
		var lc := (p1 - p0).length()
		var kc := 0.0
		var odd := false
		while kc < lc - 14.0 * s:
			var q := p0 + u * (kc + 6.0 * s)
			var ang := u.angle()
			var rx := 6.0 * s
			var ry := (3.0 if not odd else 1.5) * s
			var pts := PackedVector2Array()
			for i in 13:
				var al := TAU * float(i) / 12.0
				pts.append(q + Vector2(cos(al) * rx, sin(al) * ry).rotated(ang))
			draw_polyline(pts, Color(col, alpha), 1.6 * s, true)
			kc += 10.0 * s
			odd = not odd
	elif _style == "кремний":
		# Gold bond wires: two thin parallel wires with bond pads at both ends.
		var nw := Vector2(-u.y, u.x)
		for off in [-2.5, 2.5]:
			draw_line(p0 + nw * off * s, p1 + nw * off * s, Color(0.95, 0.78, 0.35, alpha), 1.6 * s, true)
		draw_rect(Rect2(p0 - Vector2(4, 4) * s, Vector2(8, 8) * s), Color(0.95, 0.78, 0.35, alpha))
	elif _style == "металл":
		# A steel I-beam with rivets.
		var nb := Vector2(-u.y, u.x)
		draw_line(p0, p1, Color(0.12, 0.12, 0.14, alpha), 9.0 * s, true)
		draw_line(p0 + nb * 3.0 * s, p1 + nb * 3.0 * s, Color(col, alpha), 2.0 * s, true)
		draw_line(p0 - nb * 3.0 * s, p1 - nb * 3.0 * s, Color(col, alpha), 2.0 * s, true)
		var lb := (p1 - p0).length()
		var kb := 10.0 * s
		while kb < lb - 18.0 * s:
			draw_circle(p0 + u * kb, 1.6 * s, Color(col.lightened(0.3), alpha))
			kb += 22.0 * s
	elif _style == "energy":
		# A power line: a glowing wire with insulators along it and a current running towards the next node.
		var nn2 := Vector2(-u.y, u.x)
		draw_line(p0, p1, Color(col, alpha * 0.25), 7.0 * s, true)
		draw_line(p0, p1, Color(col.lightened(0.3), alpha), 2.0 * s, true)
		var len2 := (p1 - p0).length()
		var k := 0.0
		while k < len2 - 20.0 * s:
			var q := p0 + u * k
			draw_line(q - nn2 * 5.0 * s, q + nn2 * 5.0 * s, Color(col, alpha * 0.8), 2.0 * s, true)
			k += 34.0 * s
	elif _style == "oil":
		# A pipeline: a thick pipe with a light seam and flanges at both ends.
		var nn := Vector2(-u.y, u.x)
		draw_line(p0, p1, Color(0.08, 0.06, 0.04, alpha), 9.0 * s, true)
		draw_line(p0, p1, Color(col.darkened(0.35), alpha), 6.5 * s, true)
		draw_line(p0 + nn * 1.5 * s, p1 + nn * 1.5 * s, Color(col.lightened(0.3), alpha * 0.8), 1.5 * s, true)
		for q in [p0 + u * 4.0 * s, p1 - u * 18.0 * s]:
			draw_line(q - nn * 7.0 * s, q + nn * 7.0 * s, Color(col, alpha), 4.0 * s, true)
		p0 = p1 - u * 14.0 * s
	else:
		draw_line(p0, p1, Color(col, alpha), 3.0 * s, true)   # IT: a plain PCB trace
	if alpha > 0.6:
		_flow(start, p1, u, col, s)   # something flows along an opened path
	var n := Vector2(-u.y, u.x)
	draw_colored_polygon(PackedVector2Array([p1, p1 - u * 14.0 * s + n * 7.0 * s, p1 - u * 14.0 * s - n * 7.0 * s]), Color(col, alpha))


## The branch's name on its axis between the root and the first node. A side branch has only the gap between
## the root and the first node, so a long name goes on two lines and the font shrinks until it fits.
func _tag(text: String, deg: float, col: Color, font: Font, s: float) -> void:
	var side := absf(cos(deg_to_rad(deg))) > 0.5
	# A side branch: the free band above its arrow — from the root to past the first node, under the middle nodes.
	var room := (SIDE_TO - SIDE_FROM - 8.0) * s if side else 400.0 * s
	var fs := maxi(10, int(15.0 * s))
	var lines: Array = [text]
	while true:
		lines = [text]
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0 * s > room:
			lines = _split_two(text)
		var widest := 0.0
		for l in lines:
			widest = maxf(widest, font.get_string_size(str(l), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if widest + 16.0 * s <= room or fs <= 9:
			break
		fs -= 1
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(str(l), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	w += 16.0 * s
	var line_h := float(fs) + 3.0
	var hgt := line_h * float(lines.size()) + 10.0 * s
	var p := _at((SIDE_FROM + SIDE_TO) / 2.0 if side else RT, deg)
	if side:
		p.y -= 33.0 * s + hgt / 2.0   # just above the first node; the band above is free up to the next branch
	var box := Rect2(p - Vector2(w, hgt) / 2.0, Vector2(w, hgt))
	draw_rect(box, Color(0.04, 0.07, 0.13))
	draw_rect(box, col, false, 1.5 * s)
	for i in lines.size():
		var y := box.position.y + 5.0 * s + line_h * (float(i) + 1.0) - 3.0
		_text_center(font, Vector2(p.x, y), str(lines[i]), fs, col)


## Splits a name into two lines at the space closest to the middle.
static func _split_two(text: String) -> Array:
	var best := -1
	for i in text.length():
		if text[i] == " " and (best < 0 or absi(i - text.length() / 2) < absi(best - text.length() / 2)):
			best = i
	if best < 0:
		return [text]
	return [text.substr(0, best), text.substr(best + 1)]


func _text_center(font: Font, at: Vector2, text: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(font, at - Vector2(w / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
	draw_string(font, at - Vector2(w / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func _wrap(text: String, width: int) -> Array:
	var out: Array = []
	var line := ""
	for word in text.split(" ", false):
		if line.is_empty():
			line = word
		elif line.length() + 1 + word.length() <= width:
			line += " " + word
		else:
			out.append(line)
			line = word
	if not line.is_empty():
		out.append(line)
	return out


func _node_at(p: Vector2) -> String:
	for id in _pos.keys():
		var c: Vector2 = (_pos[id] as Array)[0]
		var h: Vector2 = (_pos[id] as Array)[1]
		if Rect2(c - h - Vector2(6, 6), h * 2.0 + Vector2(12, 12)).has_point(p):
			return str(id)
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press.x >= 0.0 and mm.button_mask != 0:
			if _dragged or mm.position.distance_to(_press) > 4.0:
				_dragged = true
				_pan += mm.relative
				_hover = ""
				queue_redraw()
			accept_event()
			return
		var id := _node_at(mm.position)
		if id != _hover:
			_hover = id
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var before := (mb.position - _center()) / _scale()   # the tree's point under the cursor stays there
			_zoom = clampf(_zoom * (1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12), 0.6, 4.0)
			_pan = mb.position - size / 2.0 - before * _scale()
			queue_redraw()
			accept_event()
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_press = mb.position
				_dragged = false
				if mb.double_click and mb.button_index != MOUSE_BUTTON_LEFT:
					_zoom = 1.0   # a double click with the right or middle button: the whole tree again
					_pan = Vector2.ZERO
					queue_redraw()
			else:
				var was_click := not _dragged and mb.button_index == MOUSE_BUTTON_LEFT
				_press = Vector2(-1, -1)
				_dragged = false
				if was_click:
					var id := _node_at(mb.position)
					if not id.is_empty() and on_pick.is_valid():
						on_pick.call(id)
			accept_event()


## The node's description under the cursor (Godot asks for it on hover).
func _get_tooltip(at: Vector2) -> String:
	var id := _node_at(at)
	if id.is_empty():
		return ""
	return describe(id)


func describe(id: String) -> String:
	var nd := tree.node(sector, id)
	var lines: PackedStringArray = []
	lines.append("%s — %s" % [db.text(nd.get("name", "")), _t(_cost_key()) % int(nd.get("price", 1))])
	var desc := db.text(nd.get("description", ""))
	if not desc.is_empty():
		lines.append(desc)
	if nd.has("on_the_way"):
		for via in (nd["on_the_way"] as Dictionary).keys():
			var p: Dictionary = (nd["on_the_way"] as Dictionary)[via]
			lines.append(_t("tree_via") % [db.text(tree.node(sector, str(via)).get("name", "")), db.text(p.get("name", ""))])
			for l in effect_lines(p.get("effects", {})):
				lines.append("   " + l)
	else:
		for l in effect_lines(nd.get("effects", {})):
			lines.append("• " + l)
	for l in mech_lines(nd.get("country", {})):
		lines.append("★ " + l)
	if bool(nd.get("технологии", false)):
		lines.append(_t("tree_tech_info") % int(nd.get("weeks", 26)))
	for l in _opens(id):
		lines.append(l)
	var why := tree.can_buy(db, country, sector, id)
	if tree.is_open(country, sector, id):
		lines.append(_t("tree_state_open"))
	elif tree.developing(country, sector, id) >= 0:
		lines.append(_t("tree_state_dev") % maxi(0, (tree.developing(country, sector, id) - Pax.game.day()) / 7))
	elif why.is_empty():
		lines.append(_t("tree_state_buy"))
	else:
		lines.append(_t("tree_why_" + why))
	return "\n".join(lines)


## The country-wide mechanics of a node (research trees): «забастовки −40%», «забастовки: отключены».
## The country capabilities this node opens (capabilities.gd): «Открывает: лазерное оружие» (+ «вместе с …»).
func _opens(id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if capabilities == null:
		return out
	for c in capabilities.call("all"):
		var cd: Dictionary = c
		var groups: Array = cd.get("нужно", [])
		var mine := false
		var others: PackedStringArray = []
		for g in groups:
			var in_group := false
			for opt in g:
				if str((opt as Array)[0]) == sector and str((opt as Array)[1]) == id:
					in_group = true
			if in_group:
				mine = true
			else:
				var names: PackedStringArray = []
				for opt in g:
					var nd: Dictionary = tree.node(str((opt as Array)[0]), str((opt as Array)[1]))
					names.append("%s «%s»" % [db.sector_name(str((opt as Array)[0])), db.text(nd.get("name", ""))])
				others.append(_t("cap_or").join(names))
		if mine:
			var line := "⚑ " + _t("tree_opens") % db.text(cd.get("name", ""))
			if not others.is_empty():
				line += " " + _t("tree_opens_with") % "; ".join(others)
			out.append(line)
	return out


func mech_lines(eff: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for k in eff.keys():
		var v := float(eff[k])
		var key := str(k)
		var what := ""
		if key.begins_with("выручка_") or key.begins_with("издержки_"):
			var sec := key.substr(key.find("_") + 1)
			what = _t("tree_mech_" + key.substr(0, key.find("_"))) % db.sector_name(sec)
		else:
			what = _t("tree_mech_" + key)
		var val := _t("tree_mech_off") if v <= 0.0 else ("+" if v >= 1.0 else "−") + db._num(absf(v - 1.0) * 100.0, 0) + "%"
		out.append("%s %s" % [what, val])
	return out


func effect_lines(eff: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for k in eff.keys():
		var v := float(eff[k])
		var key := str(k)
		var text := ""
		if key in DevTree.PERCENT:
			text = ("+" if v >= 0.0 else "−") + db._num(absf(v) * 100.0, 0) + "%"
		elif key in DevTree.MULT or key == "все":
			text = "×" + db._num(v, 1)
		else:
			text = ("+" if v >= 0.0 else "−") + str(roundi(absf(v)))
		out.append(_t("tree_eff_" + key) % text)
	return out


# ---------- the rest of the industries' looks (one function each: background, node, link, emblem) ----------

const STYLE_BG := {"ии": Color(0.035, 0.02, 0.07), "наука": Color(0.02, 0.05, 0.05), "космос": Color(0.008, 0.012, 0.035), "pharma": Color(0.03, 0.05, 0.06), "оборона": Color(0.04, 0.045, 0.035), "авиа": Color(0.025, 0.04, 0.07),
	"tourism": Color(0.03, 0.05, 0.05), "авто": Color(0.04, 0.04, 0.045), "retail": Color(0.05, 0.035, 0.04),
	"медиа": Color(0.04, 0.03, 0.06), "стройка": Color(0.05, 0.045, 0.03)}


## A node's shape for the newer styles; false — not one of them.
func _shape(c: Vector2, h: Vector2, fill: Color, edge: Color, w: float) -> bool:
	var r := h.x
	match _style:
		"ии":
			# A neuron: a round body with six dendrites; an open one fires — the dendrites pulse outwards.
			for k in 6:
				var a := TAU * float(k) / 6.0 + PI / 6.0
				var grow := 1.0 + (0.18 * (0.5 + 0.5 * sin(_now * 4.0 + float(k))) if _node_open else 0.0)
				draw_line(c + Vector2(cos(a), sin(a)) * r * 0.6, c + Vector2(cos(a), sin(a)) * r * 1.05 * grow, Color(edge, 0.8), maxf(1.0, w * 0.7), true)
				draw_circle(c + Vector2(cos(a), sin(a)) * r * 1.05 * grow, maxf(1.5, w * 0.9), edge)
			draw_circle(c, r * 0.68, fill)
			draw_arc(c, r * 0.68, 0.0, TAU, 32, edge, w, true)
			if _node_open:
				draw_circle(c, r * 0.3 * (0.8 + 0.2 * sin(_now * 6.0)), Color(1, 1, 1, 0.55))
		"наука":
			# A benzene ring: a hexagon with a circle inside; an open one's electrons run around the ring.
			var hex := PackedVector2Array()
			for k in 7:
				var a := TAU * float(k) / 6.0 - PI / 2.0
				hex.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(hex, fill)
			draw_polyline(hex, edge, w, true)
			draw_arc(c, r * 0.55, 0.0, TAU, 28, Color(edge, 0.7), maxf(1.0, w * 0.6), true)
			if _node_open:
				for k in 2:
					var a := _now * 2.5 + PI * float(k)
					draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.55, maxf(2.0, w), Color(1, 1, 1, 0.9))
		"космос":
			# A planet with a ring; an open one has a moon on its orbit.
			draw_circle(c, r * 0.72, fill)
			draw_arc(c, r * 0.72, 0.0, TAU, 32, edge, w, true)
			var ring := PackedVector2Array()
			for k in 41:
				var a := TAU * float(k) / 40.0
				ring.append(c + Vector2(cos(a) * r * 1.15, sin(a) * r * 0.32).rotated(-0.35))
			draw_polyline(ring, Color(edge, 0.8), maxf(1.0, w * 0.7), true)
			if _node_open:
				var a := _now * 1.2 + c.x * 0.01
				draw_circle(c + Vector2(cos(a) * r * 1.15, sin(a) * r * 0.32).rotated(-0.35), maxf(2.0, w * 1.1), Color(1, 1, 1, 0.95))
		"pharma":
			# A capsule lying across: two halves, one tinted.
			var cap_r := r * 0.55
			var half := r * 0.55
			var left := Rect2(c + Vector2(-half, -cap_r), Vector2(half, cap_r * 2.0))
			var right := Rect2(c + Vector2(0, -cap_r), Vector2(half, cap_r * 2.0))
			draw_rect(left, Color(edge, 0.35))
			draw_circle(c + Vector2(-half, 0), cap_r, Color(edge, 0.35))
			draw_rect(right, fill)
			draw_circle(c + Vector2(half, 0), cap_r, fill)
			draw_arc(c + Vector2(-half, 0), cap_r, PI / 2.0, PI * 1.5, 16, edge, w, true)
			draw_arc(c + Vector2(half, 0), cap_r, -PI / 2.0, PI / 2.0, 16, edge, w, true)
			draw_line(c + Vector2(-half, -cap_r), c + Vector2(half, -cap_r), edge, w, true)
			draw_line(c + Vector2(-half, cap_r), c + Vector2(half, cap_r), edge, w, true)
			draw_line(c + Vector2(0, -cap_r), c + Vector2(0, cap_r), Color(edge, 0.7), maxf(1.0, w * 0.5), true)
		"оборона":
			var pts := PackedVector2Array([c + Vector2(-r, -r * 0.85), c + Vector2(r, -r * 0.85), c + Vector2(r, r * 0.1),
				c + Vector2(0, r * 1.05), c + Vector2(-r, r * 0.1)])
			draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			draw_polyline(pts, edge, w, true)
			draw_line(c + Vector2(0, -r * 0.85), c + Vector2(0, r * 1.0), Color(edge, 0.45), maxf(1.0, w * 0.5), true)
		"авиа":
			draw_circle(c, r, fill)
			draw_arc(c, r, 0.0, TAU, 36, edge, w, true)
			draw_arc(c, r * 0.55, 0.0, TAU, 28, Color(edge, 0.6), maxf(1.0, w * 0.6), true)
			draw_line(c + Vector2(-r * 0.75, 0), c + Vector2(r * 0.75, 0), Color(edge, 0.6), maxf(1.0, w * 0.6), true)
		"tourism":
			# A map pin: a round head with a point below.
			var head := c + Vector2(0, -r * 0.2)
			var pin := PackedVector2Array()
			for i in 25:
				var a := PI * 0.8 - (PI * 1.6) * float(i) / 24.0 + PI
				pin.append(head + Vector2(cos(a), sin(a)) * r * 0.85)
			pin.append(c + Vector2(0, r * 1.05))
			draw_colored_polygon(pin, fill)
			pin.append(pin[0])
			draw_polyline(pin, edge, w, true)
			draw_arc(head, r * 0.32, 0.0, TAU, 18, Color(edge, 0.7), maxf(1.0, w * 0.6), true)
		"авто":
			draw_circle(c, r, Color(0.04, 0.04, 0.05))
			draw_arc(c, r * 0.9, 0.0, TAU, 36, edge, r * 0.2, true)
			draw_circle(c, r * 0.62, fill)
			for k in 5:
				var a := TAU * float(k) / 5.0 - PI / 2.0 + (_now * 2.0 if _node_open else 0.0)   # an open wheel turns
				draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.6, Color(edge, 0.7), maxf(1.0, w * 0.6), true)
			draw_circle(c, r * 0.16, edge)
		"retail":
			var body := PackedVector2Array([c + Vector2(-r * 0.85, -r * 0.45), c + Vector2(r * 0.85, -r * 0.45), c + Vector2(r * 0.7, r), c + Vector2(-r * 0.7, r)])
			draw_colored_polygon(body, fill)
			body.append(body[0])
			draw_polyline(body, edge, w, true)
			draw_arc(c + Vector2(0, -r * 0.45), r * 0.42, PI, TAU, 16, edge, w, true)
		"медиа":
			var scr := Rect2(c + Vector2(-r, -r * 0.7), Vector2(r * 2.0, r * 1.25))
			draw_rect(scr, fill)
			draw_rect(scr, edge, false, w)
			draw_line(c + Vector2(0, r * 0.55), c + Vector2(0, r * 0.85), edge, w, true)
			draw_line(c + Vector2(-r * 0.4, r * 0.88), c + Vector2(r * 0.4, r * 0.88), edge, w, true)
		"стройка":
			var blk := Rect2(c - Vector2(r, r * 0.8), Vector2(r * 2.0, r * 1.6))
			draw_rect(blk, fill)
			draw_rect(blk, edge, false, w)
			for k in 3:
				var y := blk.position.y + blk.size.y * float(k + 1) / 4.0
				draw_line(Vector2(blk.position.x, y), Vector2(blk.end.x, y), Color(edge, 0.45), 1.0, true)
				var x := blk.position.x + blk.size.x * (0.5 if k % 2 == 0 else 0.25)
				draw_line(Vector2(x, y - blk.size.y / 4.0), Vector2(x, y), Color(edge, 0.45), 1.0, true)
		_:
			return false
	return true


## A link for the newer styles; false — not one of them.
func _link(p0: Vector2, p1: Vector2, u: Vector2, col: Color, alpha: float, s: float) -> bool:
	var n := Vector2(-u.y, u.x)
	var length := (p1 - p0).length()
	var c := Color(col, alpha)
	match _style:
		"ии":
			# A synapse: a soft glow with beads of signal along it.
			draw_line(p0, p1, Color(col, alpha * 0.18), 7.0 * s, true)
			draw_line(p0, p1, Color(col, alpha * 0.8), 1.4 * s, true)
			var k := 8.0 * s + _phase(16.0 * s, 24.0 * s, alpha)
			while k < length - 12.0 * s:
				draw_circle(p0 + u * k, 1.6 * s, Color(col.lightened(0.4), alpha))
				k += 16.0 * s
		"наука":
			# A molecule chain: atoms of two sizes on a bond.
			draw_line(p0, p1, Color(col, alpha * 0.7), 2.0 * s, true)
			var k := 10.0 * s + _phase(22.0 * s, 14.0 * s, alpha)
			var big := true
			while k < length - 14.0 * s:
				draw_circle(p0 + u * k, (3.5 if big else 2.2) * s, Color(col.lightened(0.2), alpha))
				k += 11.0 * s
				big = not big
		"космос":
			# A trajectory: a thin dashed path with faint stars beside it.
			var k := _phase(14.0 * s, 20.0 * s, alpha)
			while k < length - 10.0 * s:
				draw_line(p0 + u * k, p0 + u * minf(k + 7.0 * s, length), Color(col, alpha * 0.9), 1.5 * s, true)
				k += 14.0 * s
			for i in 3:
				var q := p0 + u * length * (0.25 + 0.25 * float(i)) + n * (7.0 if i % 2 == 0 else -7.0) * s
				draw_circle(q, 1.0 * s, Color(1, 1, 1, alpha * (0.4 + 0.4 * sin(_now * 3.0 + float(i)))))
		"pharma":
			# A DNA double helix with rungs.
			var a := PackedVector2Array()
			var b := PackedVector2Array()
			var steps := maxi(8, int(length / (6.0 * s)))
			for i in steps + 1:
				var t := float(i) / float(steps)
				var wave := sin(t * length / (18.0 * s) * PI + (_now * 3.0 if alpha > 0.6 else 0.0)) * 5.0 * s   # the helix turns
				a.append(p0 + u * length * t + n * wave)
				b.append(p0 + u * length * t - n * wave)
				if i % 3 == 0:
					draw_line(a[a.size() - 1], b[b.size() - 1], Color(col, alpha * 0.5), 1.0, true)
			draw_polyline(a, c, 1.8 * s, true)
			draw_polyline(b, Color(col.lightened(0.3), alpha), 1.8 * s, true)
		"оборона":
			draw_line(p0, p1, Color(col, alpha * 0.6), 2.0 * s, true)
			var k := 12.0 * s + _phase(18.0 * s, 20.0 * s, alpha)
			while k < length - 16.0 * s:
				var q := p0 + u * k
				draw_line(q - u * 5.0 * s + n * 5.0 * s, q, c, 2.0 * s, true)
				draw_line(q - u * 5.0 * s - n * 5.0 * s, q, c, 2.0 * s, true)
				k += 18.0 * s
		"авиа":
			var k := _phase(14.0 * s, 16.0 * s, alpha)
			while k < length - 14.0 * s:
				draw_line(p0 + u * k, p0 + u * minf(k + 8.0 * s, length - 14.0 * s), c, 2.0 * s, true)
				k += 14.0 * s
		"tourism":
			var k := 4.0 * s + _phase(9.0 * s, 12.0 * s, alpha)
			while k < length - 12.0 * s:
				draw_circle(p0 + u * k, 2.2 * s, c)
				k += 9.0 * s
		"авто":
			draw_line(p0, p1, Color(0.08, 0.08, 0.09, alpha), 10.0 * s, true)
			draw_line(p0 + n * 4.5 * s, p1 + n * 4.5 * s, Color(col, alpha * 0.6), 1.0, true)
			draw_line(p0 - n * 4.5 * s, p1 - n * 4.5 * s, Color(col, alpha * 0.6), 1.0, true)
			var k := _phase(13.0 * s, 26.0 * s, alpha)
			while k < length - 14.0 * s:
				draw_line(p0 + u * k, p0 + u * (k + 6.0 * s), Color(1, 1, 1, alpha * 0.8), 1.5 * s, true)
				k += 13.0 * s
		"retail":
			draw_line(p0, p1, Color(col, alpha * 0.6), 2.0 * s, true)
			var k := 10.0 * s + _phase(20.0 * s, 18.0 * s, alpha)
			while k < length - 16.0 * s:
				var q := p0 + u * k
				draw_rect(Rect2(q - Vector2(3, 3) * s, Vector2(6, 6) * s), c)
				k += 20.0 * s
		"медиа":
			draw_line(p0, p1, Color(col, alpha * 0.7), 1.5 * s, true)
			var k := 14.0 * s + _phase(26.0 * s, 30.0 * s, alpha)
			while k < length - 18.0 * s:
				var q := p0 + u * k
				draw_arc(q, 5.0 * s, u.angle() - 0.8, u.angle() + 0.8, 8, c, 1.5 * s, true)
				draw_arc(q, 9.0 * s, u.angle() - 0.7, u.angle() + 0.7, 8, Color(col, alpha * 0.6), 1.2 * s, true)
				k += 26.0 * s
		"стройка":
			var a0 := p0 + n * 4.0 * s
			var b0 := p0 - n * 4.0 * s
			draw_line(a0, p1 + n * 4.0 * s, c, 1.6 * s, true)
			draw_line(b0, p1 - n * 4.0 * s, c, 1.6 * s, true)
			var k := 0.0
			var up := true
			while k < length - 12.0 * s:
				var k2 := minf(k + 10.0 * s, length)
				draw_line(p0 + u * k + n * (4.0 if up else -4.0) * s, p0 + u * k2 + n * (-4.0 if up else 4.0) * s, Color(col, alpha * 0.7), 1.0, true)
				k = k2
				up = not up
		_:
			return false
	return true


## The emblem over the root for the newer styles; false — not one of them.
func _emblem(base: Vector2, col: Color, s: float) -> bool:
	var e := base + Vector2(0, -32.0 * s)
	var r := 24.0 * s
	var lw := maxf(1.5, 2.2 * s)
	match _style:
		"ии":
			# A brain of nodes: an outer ring of neurons fires one after another round the centre.
			draw_arc(e, r, 0.0, TAU, 32, Color(col, 0.5), lw, true)
			for i in 8:
				var a := TAU * float(i) / 8.0
				var p := e + Vector2(cos(a), sin(a)) * r * 0.75
				draw_line(e, p, Color(col, 0.35), lw * 0.6, true)
				var fire := 1.0 - fmod(_now * 1.5 - float(i) / 8.0 + 8.0, 1.0)
				draw_circle(p, r * 0.13 * (1.0 + 0.5 * fire), Color(col.lightened(0.5 * fire), 0.6 + 0.4 * fire))
			draw_circle(e, r * 0.22, col)
		"наука":
			# A flask with bubbles rising.
			var neck := r * 0.25
			var flask := PackedVector2Array([e + Vector2(-neck, -r), e + Vector2(neck, -r), e + Vector2(neck, -r * 0.3), e + Vector2(r * 0.9, r * 0.8),
				e + Vector2(-r * 0.9, r * 0.8), e + Vector2(-neck, -r * 0.3)])
			draw_colored_polygon(PackedVector2Array([e + Vector2(-r * 0.62, r * 0.35), e + Vector2(r * 0.62, r * 0.35), e + Vector2(r * 0.9, r * 0.8), e + Vector2(-r * 0.9, r * 0.8)]), Color(col, 0.6))
			flask.append(flask[0])
			draw_polyline(flask, col, lw, true)
			for i in 4:
				var ph := fmod(_now * 0.7 + float(i) * 0.25, 1.0)
				draw_circle(e + Vector2(sin(float(i) * 2.1 + _now) * r * 0.2, lerpf(r * 0.6, -r * 1.1, ph)), r * 0.08 * (1.0 - ph * 0.5), Color(col.lightened(0.4), 1.0 - ph))
		"космос":
			# A rocket with a flickering flame and a satellite on orbit.
			var body := PackedVector2Array([e + Vector2(0, -r), e + Vector2(r * 0.3, -r * 0.4), e + Vector2(r * 0.3, r * 0.5), e + Vector2(-r * 0.3, r * 0.5), e + Vector2(-r * 0.3, -r * 0.4)])
			draw_colored_polygon(body, col)
			draw_colored_polygon(PackedVector2Array([e + Vector2(-r * 0.3, r * 0.1), e + Vector2(-r * 0.6, r * 0.6), e + Vector2(-r * 0.3, r * 0.5)]), col)
			draw_colored_polygon(PackedVector2Array([e + Vector2(r * 0.3, r * 0.1), e + Vector2(r * 0.6, r * 0.6), e + Vector2(r * 0.3, r * 0.5)]), col)
			var fl := r * (0.45 + 0.15 * sin(_now * 20.0))
			draw_colored_polygon(PackedVector2Array([e + Vector2(-r * 0.2, r * 0.5), e + Vector2(r * 0.2, r * 0.5), e + Vector2(0, r * 0.5 + fl)]), Color(1.0, 0.65, 0.2, 0.9))
			var a := _now * 0.9
			var sat := e + Vector2(cos(a) * r * 1.4, sin(a) * r * 0.5)
			draw_rect(Rect2(sat - Vector2(2, 2) * s, Vector2(4, 4) * s), Color(1, 1, 1, 0.9))
			draw_line(sat - Vector2(6, 0) * s, sat + Vector2(6, 0) * s, Color(col.lightened(0.4), 0.9), 1.5 * s)
		"pharma":
			draw_arc(e, r * (1.0 + 0.08 * sin(_now * 3.0)), 0.0, TAU, 32, Color(col, 0.35), lw * 2.0, true)   # a heartbeat
			draw_arc(e, r, 0.0, TAU, 32, col, lw, true)
			draw_rect(Rect2(e - Vector2(r * 0.18, r * 0.6), Vector2(r * 0.36, r * 1.2)), col)
			draw_rect(Rect2(e - Vector2(r * 0.6, r * 0.18), Vector2(r * 1.2, r * 0.36)), col)
		"оборона":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2.0 + TAU * float(i) / 10.0
				pts.append(e + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.42) * (1.0 + 0.06 * sin(_now * 2.0)))
			draw_colored_polygon(pts, col)
			if fmod(_now, 2.5) < 0.4:
				_twinkle(e + Vector2(r * 0.55, -r * 0.55), r * 0.35 * (1.0 - fmod(_now, 2.5) / 0.4))
		"авиа":
			draw_arc(e, r * 0.75, 0.0, TAU, 32, col, lw, true)
			for i in 4:
				var a := TAU * float(i) / 4.0 - PI / 2.0 + _now * 0.4   # the compass rose turns
				draw_colored_polygon(PackedVector2Array([e + Vector2(cos(a), sin(a)) * r, e + Vector2(cos(a + 0.4), sin(a + 0.4)) * r * 0.25,
					e + Vector2(cos(a - 0.4), sin(a - 0.4)) * r * 0.25]), col)
		"tourism":
			draw_arc(e, r, 0.0, TAU, 32, col, lw, true)
			draw_line(e + Vector2(-r, 0), e + Vector2(r, 0), col, lw * 0.7, true)
			for k in [-0.5, 0.5]:
				draw_line(e + Vector2(-r * 0.87, r * k), e + Vector2(r * 0.87, r * k), Color(col, 0.7), lw * 0.6, true)
			var mer := PackedVector2Array()
			for i in 21:
				var a := -PI / 2.0 + PI * float(i) / 20.0
				mer.append(e + Vector2(cos(a) * r * 0.45 * cos(_now * 0.8), sin(a) * r))   # the globe spins
			draw_polyline(mer, Color(col, 0.8), lw * 0.7, true)
			var mer2 := PackedVector2Array()
			for p in mer:
				mer2.append(Vector2(2.0 * e.x - p.x, p.y))
			draw_polyline(mer2, Color(col, 0.8), lw * 0.7, true)
		"авто":
			draw_arc(e, r, 0.0, TAU, 32, col, lw * 1.4, true)
			draw_circle(e, r * 0.2, col)
			for a in [PI / 2.0, PI * 1.17, -PI * 0.17]:
				var turn := float(a) + 0.35 * sin(_now * 1.2)   # the wheel steers left and right
				draw_line(e, e + Vector2(cos(turn), sin(turn)) * r, col, lw, true)
		"retail":
			var aw := Rect2(e + Vector2(-r * 1.2, -r * 0.4), Vector2(r * 2.4, r * 0.55))
			for i in 6:
				draw_rect(Rect2(aw.position + Vector2(aw.size.x * float(i) / 6.0, 0), Vector2(aw.size.x / 6.0, aw.size.y)),
					col if i % 2 == 0 else Color(1, 1, 1, 0.85))
			for i in 6:
				draw_arc(aw.position + Vector2(aw.size.x * (float(i) + 0.5) / 6.0, aw.size.y), aw.size.x / 12.0, 0.0, PI, 8, col, lw * 0.8, true)
		"медиа":
			draw_line(e + Vector2(0, r * 0.9), e + Vector2(0, -r * 0.3), col, lw, true)
			draw_line(e + Vector2(-r * 0.4, r * 0.9), e + Vector2(0, -r * 0.3), col, lw, true)
			draw_line(e + Vector2(r * 0.4, r * 0.9), e + Vector2(0, -r * 0.3), col, lw, true)
			var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU / 1.5)
			for i in 3:
				var rr := r * (0.35 + 0.28 * float(i))
				draw_arc(e + Vector2(0, -r * 0.3), rr, -PI * 0.85, -PI * 0.15, 12, Color(col, 0.4 + 0.5 * k * (1.0 - float(i) / 3.0)), lw * 0.8, true)
		"стройка":
			draw_line(e + Vector2(-r * 0.3, r), e + Vector2(-r * 0.3, -r), col, lw * 1.3, true)
			draw_line(e + Vector2(-r * 0.9, -r * 0.8), e + Vector2(r * 1.3, -r * 0.8), col, lw, true)
			var bob := r * 0.25 * sin(_now * 1.5)   # the hook goes up and down
			draw_line(e + Vector2(r * 1.0, -r * 0.8), e + Vector2(r * 1.0, -r * 0.1 + bob), Color(col, 0.8), lw * 0.6, true)
			draw_rect(Rect2(e + Vector2(r * 0.9, -r * 0.1 + bob), Vector2(r * 0.2, r * 0.2)), col)
			draw_rect(Rect2(e + Vector2(-r * 0.9, -r * 0.9), Vector2(r * 0.4, r * 0.3)), col)
		_:
			return false
	return true


# ---------- animation helpers ----------

## Where a moving pattern starts on an open link (it slides along; a closed link stands still).
func _phase(step: float, speed: float, alpha: float) -> float:
	return fmod(_now * speed, step) if alpha > 0.6 else 0.0


## A little star of light.
func _twinkle(p: Vector2, r: float) -> void:
	if r <= 0.5:
		return
	draw_line(p - Vector2(r, 0), p + Vector2(r, 0), Color(1, 1, 1, 0.9), 1.5, true)
	draw_line(p - Vector2(0, r), p + Vector2(0, r), Color(1, 1, 1, 0.9), 1.5, true)


## What runs along an opened path, by the industry: data packets (IT), current (power), an oil drop, a hot spark
## (metals), an electron (chips), a coin (finance), a pill, a tracer, a little plane, a traveller, a car, a parcel,
## a signal, a brick.
func _flow(p0: Vector2, p1: Vector2, u: Vector2, col: Color, s: float) -> void:
	var length := (p1 - p0).length()
	if length < 20.0 * s:
		return
	var speed := 70.0 * s
	for k in 2:
		var d := fmod(_now * speed + float(k) * length / 2.0 + p0.x * 0.37, length)
		var q := p0 + u * d
		var fade := clampf(minf(d, length - d) / (14.0 * s), 0.0, 1.0)
		match _style:
			"ии":
				draw_circle(q, 6.0 * s, Color(col, 0.25 * fade))
				draw_circle(q, 2.6 * s, Color(1, 1, 1, fade))
			"наука":
				draw_circle(q, 2.4 * s, Color(0.7, 1.0, 0.95, fade))
				draw_line(q, q - u * 9.0 * s, Color(col.lightened(0.3), 0.5 * fade), 1.5 * s, true)
			"космос":
				draw_line(q, q - u * 14.0 * s, Color(1.0, 0.75, 0.4, 0.6 * fade), 2.0 * s, true)   # a comet's tail
				draw_circle(q, 2.4 * s, Color(1, 1, 1, fade))
			"energy":
				draw_circle(q, 5.0 * s, Color(col, 0.3 * fade))
				draw_circle(q, 2.8 * s, Color(1, 1, 1, fade))
			"oil":
				draw_circle(q, 3.5 * s, Color(0.12, 0.08, 0.04, fade))
				draw_circle(q - Vector2(1, 1) * s, 1.2 * s, Color(1.0, 0.8, 0.4, fade))
			"металл":
				draw_circle(q, 2.5 * s, Color(1.0, 0.6, 0.2, fade))
				draw_line(q, q - u * 8.0 * s, Color(1.0, 0.45, 0.15, 0.6 * fade), 1.5 * s, true)
			"кремний":
				draw_circle(q, 2.2 * s, Color(0.7, 0.95, 1.0, fade))
			"финансы":
				draw_circle(q, 3.5 * s, Color(1.0, 0.85, 0.3, fade))
				draw_arc(q, 3.5 * s, 0.0, TAU, 10, Color(0.6, 0.45, 0.1, fade), 1.0, true)
			"pharma":
				draw_circle(q, 3.0 * s, Color(1, 1, 1, fade))
			"оборона":
				draw_line(q, q - u * 10.0 * s, Color(1.0, 0.9, 0.5, fade), 2.0 * s, true)
			"авиа":
				var n := Vector2(-u.y, u.x)
				draw_colored_polygon(PackedVector2Array([q + u * 6.0 * s, q - u * 4.0 * s + n * 5.0 * s, q - u * 2.0 * s, q - u * 4.0 * s - n * 5.0 * s]),
					Color(1, 1, 1, fade))
			"tourism":
				draw_circle(q, 3.2 * s, Color(1.0, 0.9, 0.6, fade))
			"авто":
				draw_rect(Rect2(q - Vector2(4, 2.5) * s, Vector2(8, 5) * s), Color(col.lightened(0.4), fade))
			"retail":
				draw_rect(Rect2(q - Vector2(3.5, 3.5) * s, Vector2(7, 7) * s), Color(1.0, 0.85, 0.6, fade))
			"медиа":
				draw_arc(q, 4.0 * s, 0.0, TAU, 12, Color(1, 1, 1, fade), 1.5 * s, true)
			"стройка":
				draw_rect(Rect2(q - Vector2(4, 2) * s, Vector2(8, 4) * s), Color(0.85, 0.45, 0.3, fade))
			_:
				draw_rect(Rect2(q - Vector2(2.5, 2.5) * s, Vector2(5, 5) * s), Color(0.8, 1.0, 1.0, fade))   # IT: a data packet


## The research styles' background: stars that twinkle (space), a faint network that flickers (AI), a lattice (science).
func _backdrop(s: float) -> void:
	match _style:
		"космос":
			for i in 140:
				var x := fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
				var y := fposmod(sin(float(i) * 78.233) * 12345.678, 1.0)
				var tw := 0.35 + 0.35 * sin(_now * (1.0 + fposmod(float(i) * 0.37, 2.0)) + float(i))
				draw_circle(Vector2(x * size.x, y * size.y), (0.8 if i % 7 else 1.6) * maxf(s, 0.6), Color(1, 1, 1, tw))
		"ии":
			for i in 40:
				var a := Vector2(fposmod(sin(float(i) * 3.17) * 1000.0, 1.0) * size.x, fposmod(sin(float(i) * 7.31) * 1000.0, 1.0) * size.y)
				var b := Vector2(fposmod(sin(float(i + 1) * 3.17) * 1000.0, 1.0) * size.x, fposmod(sin(float(i + 1) * 7.31) * 1000.0, 1.0) * size.y)
				draw_line(a, b, Color(0.55, 0.4, 1.0, 0.05), 1.0, true)
				draw_circle(a, 2.0 * maxf(s, 0.6), Color(0.6, 0.45, 1.0, 0.12 + 0.12 * sin(_now * 2.0 + float(i))))
		"наука":
			var step := 60.0 * maxf(s, 0.5)
			var row := 0
			var y := 0.0
			while y < size.y + step:
				var x := (step * 0.5 if row % 2 == 1 else 0.0)
				while x < size.x + step:
					draw_arc(Vector2(x, y), step * 0.3, 0.0, TAU, 6, Color(0.3, 0.85, 0.75, 0.05), 1.0)
					x += step
				y += step * 0.86
				row += 1
