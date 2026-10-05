extends Control
## «Технологии нового времени» — a map in the «Развитие» window (capabilities.gd): the far-future technologies are
## scattered over the screen, each in a big animated frame, and the two tree nodes it needs (of two different
## industries) hang around it with links running into the frame. A ready node is lit and its link carries light; a
## click on a node sends the player to that industry's tree, where the node flashes for a few seconds (on_node).
## Drag to move the map, the wheel to zoom; hover for the description, its state and who would sell it.

const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")   # pictures (SVG), game 0.24
const UiStyle := preload("res://mods/pax_corporations/src/look/ui_style.gd")
const MIN_SCALE := 0.45           # below this the names stop being readable — then the canvas grows instead (pan)
const BOX := Vector2(190, 170)    # a technology's frame: the picture above, the name under it (virtual pixels)
const CHIP := Vector2(160, 44)    # a node's chip
## The two nodes hang below the frame, to the left and to the right, far enough for their links to show.
const NODE_OFF := Vector2(190.0 / 2.0 + 160.0 * 0.25 + 40.0, 170.0 / 2.0 + 44.0 / 2.0 + 50.0)

var caps: Object                  # capabilities.gd
var tree: Object                  # tree.gd
var db: Object                    # corp_data.gd
var mod: PaxMod
var country := ""
var on_node: Callable             # func(sector, node id) — open that tree and flash the node
var _layout: Dictionary = {}      # tech id -> {c: Vector2, nodes: [[sector, node, Vector2]…]} (virtual)
var _zoom := 1.0
var _pan := Vector2.ZERO
var _drag := false
var _moved := 0.0
var _hover := ""                  # "tech:<id>" or "node:<sector>|<id>"
var _clock := 0.0
var _now := 0.0
var _pics: Dictionary = {}
var _W := 3400.0                  # the invisible canvas the layout is made on (grows until everything fits)
var _H := 2000.0
var _base := 0.6                  # canvas → screen at zoom 1: the sizes the layout was made for
var _built_for := Vector2.ZERO    # the control size the layout was made for        # tech id -> Texture2D (config «картинка»)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= 1.0 / 30.0 and is_visible_in_tree():
		_clock = 0.0
		queue_redraw()


## The layout on an invisible canvas: the canvas is the control's size divided by the drawing scale; every
## technology goes to a random place (a fixed seed — the same map every time) where its frame, its two nodes and their
## links touch nothing placed before. If they do not all fit, the scale goes down (the canvas grows) — down to
## MIN_SCALE; below that the canvas keeps growing and the map is moved by dragging.
func _build() -> void:
	var view := size if size.x > 50.0 and size.y > 50.0 else Vector2(1600, 900)
	_built_for = size
	# Start from the scale the area suggests (each technology with its nodes takes about fw × fh), so only a step or
	# two are tried, not a dozen — the layout is made once per window size.
	var n := float((caps.call("all") as Array).size())
	var fw := 2.0 * NODE_OFF.x + CHIP.x + 28.0
	var fh := BOX.y / 2.0 + NODE_OFF.y + CHIP.y / 2.0 + 28.0
	var sc := clampf(sqrt(view.x * view.y / maxf(n * fw * fh * 1.3, 1.0)), MIN_SCALE, 0.9)
	var grow := 1.0
	while true:
		_W = view.x / sc * grow
		_H = view.y / sc * grow
		if _place_all():
			break
		if sc > MIN_SCALE + 0.001:
			sc = maxf(MIN_SCALE, sc - 0.04)
		else:
			grow *= 1.1
			if grow > 4.0:
				break
	_base = sc


## One attempt on the current canvas: true — everything placed without touching.
func _place_all() -> bool:
	_layout.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var placed: Array = []   # [centre, size]
	var links: Array = []    # [from, to]
	for item in caps.call("all"):
		var cd: Dictionary = item
		var groups: Array = cd.get("нужно", [])
		var best: Dictionary = {}
		for tries in 1500:
			var c := Vector2(rng.randf() * _W, rng.randf() * _H)
			var pts: Array = []
			for g in groups.size():
				var side := -1.0 if g % 2 == 0 else 1.0
				pts.append(c + Vector2(side * NODE_OFF.x * (1.0 + 0.3 * float(g / 2)), NODE_OFF.y))
			var els: Array = [[c, BOX]]
			for q in pts:
				els.append([q, CHIP])
			if _fits(els, pts, c, placed, links):
				best = {"c": c, "pts": pts, "els": els}
				break
		if best.is_empty():
			return false
		var nodes: Array = []
		for g in groups.size():
			var opt: Array = (groups[g] as Array)[0]
			nodes.append([str(opt[0]), str(opt[1]), (best["pts"] as Array)[g]])
			links.append([(best["pts"] as Array)[g], best["c"]])
		placed.append_array(best["els"])
		_layout[str(cd["id"])] = {"c": best["c"], "nodes": nodes}
	return true


func _fits(els: Array, pts: Array, c: Vector2, placed: Array, links: Array) -> bool:
	for el in els:
		var p: Vector2 = (el as Array)[0]
		var sz: Vector2 = (el as Array)[1]
		if p.x - sz.x / 2.0 < 10.0 or p.x + sz.x / 2.0 > _W - 10.0 or p.y - sz.y / 2.0 < 10.0 or p.y + sz.y / 2.0 > _H - 10.0:
			return false
		for q in placed:
			var qc: Vector2 = (q as Array)[0]
			var qs: Vector2 = (q as Array)[1]
			if absf(p.x - qc.x) < (sz.x + qs.x) / 2.0 + 14.0 and absf(p.y - qc.y) < (sz.y + qs.y) / 2.0 + 14.0:
				return false
		for l in links:
			if _cross((l as Array)[0], (l as Array)[1], p, sz):
				return false
	for q in pts:
		for o in placed:
			if _cross(q, c, (o as Array)[0], (o as Array)[1]):
				return false
	return true


## Does the segment a–b pass through the box (centre, size)?
static func _cross(a: Vector2, b: Vector2, centre: Vector2, sz: Vector2) -> bool:
	for k in range(1, 20):
		var x := a.lerp(b, float(k) / 20.0)
		if absf(x.x - centre.x) < sz.x / 2.0 and absf(x.y - centre.y) < sz.y / 2.0:
			return true
	return false


func _scale() -> float:
	return _base * _zoom


func _to_screen(p: Vector2) -> Vector2:
	var s := _scale()
	return (size - Vector2(_W, _H) * s) / 2.0 + _pan + p * s


func _draw() -> void:
	if caps == null or tree == null:
		return
	if _layout.is_empty() or (size - _built_for).length() > 40.0:
		_build()
	_now = Time.get_ticks_msec() / 1000.0
	var s := _scale()
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.045))
	# A faint starfield and grid: the map of the future.
	for i in 90:
		var x := fposmod(sin(float(i) * 3.1) * 9999.0, 1.0) * size.x
		var y := fposmod(sin(float(i) * 7.7) * 7777.0, 1.0) * size.y
		draw_circle(Vector2(x, y), 1.0, Color(1, 1, 1, 0.15 + 0.15 * sin(_now * 1.3 + float(i))))
	for id in _layout.keys():
		var lay: Dictionary = _layout[id]
		var cd: Dictionary = caps.call("cap", id)
		var st: Dictionary = caps.call("status", country, id)
		var col := _col(cd.get("colour"), UiStyle.GOLD)
		var c := _to_screen(lay["c"])
		# The links first: from each node into the frame; a ready node's link carries light.
		for nd in lay["nodes"]:
			var ok := _node_ok(str(nd[0]), str(nd[1]))
			var p := _to_screen(nd[2])
			var lc := Color(col, 0.8) if ok else Color(0.4, 0.45, 0.55, 0.35)
			draw_line(p, c, lc, (2.5 if ok else 1.5) * maxf(s, 0.5), true)
			if ok:
				var t := fmod(_now * 0.6 + p.x * 0.001, 1.0)
				draw_circle(p.lerp(c, t), 3.5 * maxf(s, 0.5), Color(1, 1, 1, 0.9))
		for nd in lay["nodes"]:
			_chip(str(nd[0]), str(nd[1]), _to_screen(nd[2]), s, font)
		_frame(id, cd, st, c, col, s, font)


func _col(v: Variant, fallback: Color) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return fallback


func _node_ok(sector: String, id: String) -> bool:
	return bool(tree.call("is_open", country, sector, id)) and not (tree.call("members", db, country, sector) as Array).is_empty()


## A node of an industry's tree: a chip with the industry's colour, ✓ when open.
func _chip(sector: String, id: String, p: Vector2, s: float, font: Font) -> void:
	var t: Dictionary = (tree.call("trees") as Dictionary).get(sector, {})
	var col := _col(t.get("colour"), UiStyle.BLUE)
	var nd: Dictionary = tree.call("node", sector, id)
	var ok := _node_ok(sector, id)
	var dev := int(tree.call("developing", country, sector, id)) >= 0
	var half := CHIP * s / 2.0
	var r := Rect2(p - half, half * 2.0)
	var hov := _hover == "node:" + sector + "|" + id
	draw_style_box(UiStyle.box(Color(col, 0.28) if ok else Color(0.06, 0.08, 0.12, 0.95), col if (ok or hov) else Color(col, 0.45), 6, Vector4.ZERO, 2 if hov else 1), r)
	var fs := maxi(9, int(12.0 * maxf(s, 0.55)))
	var label_text := ("✓ " if ok else ("⏳ " if dev else "")) + str(db.call("text", nd.get("name", id)))
	draw_string(font, r.position + Vector2(6, r.size.y * 0.42), label_text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10, fs, UiStyle.TEXT if ok else Color(1, 1, 1, 0.75))
	draw_string(font, r.position + Vector2(6, r.size.y * 0.85), str(db.call("sector_name", sector)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10, maxi(8, fs - 2), Color(col, 0.9))


## The technology: a big frame with its picture above and its name under it; open — gold, glowing, turning rays;
## learning — the state in gold; closed — a soft pulse. A light runs around the edge; the picture breathes.
func _frame(id: String, cd: Dictionary, st: Dictionary, c: Vector2, col: Color, s: float, font: Font) -> void:
	var half := BOX * s / 2.0
	var r := Rect2(c - half, half * 2.0)
	var open := bool(st["has_flag"])
	var how := str(st["как"])
	var hov := _hover == "tech:" + id
	var pulse := 0.5 + 0.5 * sin(_now * 2.2 + c.x * 0.01)
	if open:
		for k in 12:
			var a := TAU * float(k) / 12.0 + _now * 0.3
			draw_line(c + Vector2(cos(a), sin(a)) * half.x * 1.05, c + Vector2(cos(a), sin(a)) * half.x * (1.35 + 0.1 * pulse), Color(col, 0.35), 2.0, true)
		draw_style_box(UiStyle.box(Color(col, 0.08), Color(col, 0.35 * pulse), 16, Vector4.ZERO, 6), r.grow(8))
	else:
		draw_style_box(UiStyle.box(Color(0, 0, 0, 0), Color(col, 0.15 + 0.2 * pulse), 16, Vector4.ZERO, 2), r.grow(5 + 3 * pulse))
	draw_style_box(UiStyle.box(Color(0.05, 0.06, 0.1, 0.97), col if (open or hov) else Color(col, 0.55), 14, Vector4.ZERO, 3 if (open or hov) else 2), r)
	# A light runs around the frame's edge.
	var per := 2.0 * (r.size.x + r.size.y)
	var d := fmod(_now * 120.0 * maxf(s, 0.5), per)
	var q := r.position
	if d < r.size.x:
		q += Vector2(d, 0)
	elif d < r.size.x + r.size.y:
		q += Vector2(r.size.x, d - r.size.x)
	elif d < 2.0 * r.size.x + r.size.y:
		q += Vector2(r.size.x - (d - r.size.x - r.size.y), r.size.y)
	else:
		q += Vector2(0, r.size.y - (d - 2.0 * r.size.x - r.size.y))
	draw_circle(q, 3.0, Color(col.lightened(0.4), 0.9 if open else 0.5))
	# The picture: the upper part of the frame, tinted with the technology's colour, breathing.
	var tex := _pic(id, cd)
	var pic_h := r.size.y * 0.5
	if tex != null:
		var breathe := 1.0 + 0.04 * sin(_now * 1.8 + c.y * 0.01)
		var side := pic_h * breathe
		var pc := Vector2(c.x, r.position.y + r.size.y * 0.08 + pic_h / 2.0)
		if open:
			draw_circle(pc, side * 0.55, Color(col, 0.15 + 0.1 * pulse))
		draw_texture_rect(tex, Rect2(pc - Vector2(side, side) / 2.0, Vector2(side, side)), false, Color(col.lightened(0.25), 1.0 if open else 0.55))
	# The name under the picture and the state at the bottom, each in its own band, so they never overlap: the name
	# takes the biggest font that fits two lines in its band (one line when even the smallest font is too big); a frame
	# too small for both drops the state line (the frame's colour still tells it).
	var title := str(db.call("text", cd.get("name", id)))
	var box_w := r.size.x - 12.0
	var tag := _t("caps_" + (how if not how.is_empty() else "closed"))
	if how == "осваивается":
		tag = tag % int(st["weeks"])
	elif how == "куплена":
		tag = tag % str(st.get("from_value", ""))
	var tfs := clampi(int(12.0 * s / 0.6), 7, 14)
	var show_tag := r.size.y >= 70.0
	var name_top := r.position.y + r.size.y * 0.6
	var name_bottom := r.end.y - (float(tfs) + 8.0 if show_tag else 4.0)
	var room := maxf(name_bottom - name_top, 6.0)
	var fs := clampi(int(17.0 * s / 0.6), 6, 22)
	var lines := 2
	while fs > 6 and font.get_multiline_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, box_w, fs, lines).y > room:
		fs -= 1
	if font.get_multiline_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, box_w, fs, lines).y > room:
		lines = 1
	draw_multiline_string(font, Vector2(r.position.x + 6.0, name_top + float(fs)), title, HORIZONTAL_ALIGNMENT_CENTER, box_w, fs, lines, UiStyle.TEXT)
	if show_tag:
		var tc := UiStyle.UP if open else (UiStyle.GOLD if how == "осваивается" else UiStyle.DIM)
		draw_string(font, Vector2(r.position.x + 6.0, r.end.y - 6.0), tag, HORIZONTAL_ALIGNMENT_CENTER, box_w, tfs, tc)


func _pic(id: String, cd: Dictionary) -> Texture2D:
	if not _pics.has(id):
		var path := str(cd.get("picture", ""))
		_pics[id] = GameApi.picture(mod, path) if not path.is_empty() else null
	return _pics[id] as Texture2D


# ---------- input ----------

func _hit(at: Vector2) -> String:
	var s := _scale()
	for id in _layout.keys():
		var lay: Dictionary = _layout[id]
		for nd in lay["nodes"]:
			var half := CHIP * s / 2.0
			if Rect2(_to_screen(nd[2]) - half, half * 2.0).has_point(at):
				return "node:" + str(nd[0]) + "|" + str(nd[1])
	for id in _layout.keys():
		var half := BOX * s / 2.0
		if Rect2(_to_screen((_layout[id] as Dictionary)["c"]) - half, half * 2.0).has_point(at):
			return "tech:" + str(id)
	return ""


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var before := (mb.position - _to_screen(Vector2.ZERO)) / _scale()
				_zoom = clampf(_zoom * (1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12), 0.6, 3.0)
				_pan += mb.position - _to_screen(before)
				accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_moved = 0.0
			else:
				_drag = false
				if _moved < 6.0:
					var h := _hit(mb.position)
					if h.begins_with("node:") and on_node.is_valid():
						var parts := h.substr(5).split("|")
						on_node.call(parts[0], parts[1])
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if _drag:
			_pan += mm.relative
			_moved += mm.relative.length()
		var h := _hit(mm.position)
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h.begins_with("node:") else Control.CURSOR_ARROW


func _get_tooltip(at: Vector2) -> String:
	var h := _hit(at)
	if h.begins_with("tech:"):
		var id := h.substr(5)
		var cd: Dictionary = caps.call("cap", id)
		var st: Dictionary = caps.call("status", country, id)
		var lines: PackedStringArray = [str(db.call("text", cd.get("name", id))), str(db.call("text", cd.get("description", "")))]
		for n in st["what_missing"]:
			lines.append(("✓ " if bool((n as Array)[1]) else "✗ ") + str((n as Array)[0]))
		var sell: Array = st.get("sellers", [])
		if not sell.is_empty():
			lines.append(_t("caps_sellers") % [", ".join(PackedStringArray(sell)), str(db.call("text", cd.get("name", id))).to_lower(), sell[0]])
		return "\n".join(lines)
	if h.begins_with("node:"):
		var parts := h.substr(5).split("|")
		var nd: Dictionary = tree.call("node", parts[0], parts[1])
		return "%s — %s\n%s" % [str(db.call("sector_name", parts[0])), str(db.call("text", nd.get("name", ""))), _t("techmap_go")]
	return ""


## Fit the whole map back on the screen.
func reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
