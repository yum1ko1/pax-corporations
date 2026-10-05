extends RefCounted
## Small drawn controls for the dossier: price chart, ownership pie, company badge, status bar.

const Frames := preload("res://mods/pax_corporations/src/companies/frames.gd")
const UiStyle := preload("res://mods/pax_corporations/src/look/ui_style.gd")
const PIE_COLORS := [Color(0.24, 0.6, 1.0), Color(0.055, 0.796, 0.506), Color(0.61, 0.42, 1.0), Color(0.18, 0.77, 0.84),
	Color(1.0, 0.54, 0.24), Color(0.965, 0.275, 0.365), Color(0.85, 0.85, 0.4), Color(0.52, 0.56, 0.61)]


## Line chart of weekly values, the exchange way: dashed grid, a fading fill under the line, the high/low on the
## left and the last value in a coloured tag at the right edge.
class LineChart extends Control:
	var values: Array = []
	var line_color := UiStyle.GOLD
	var trend := false               # prices: the line is green when it rose over the chart, red when it fell
	var format_value: Callable
	var empty_text := ""

	func _init() -> void:
		custom_minimum_size = Vector2(0, 150)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(v: Array) -> void:
		values = v
		if trend and v.size() >= 2:
			line_color = UiStyle.UP if float(v.back()) >= float(v.front()) else UiStyle.DOWN
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var fs := UiStyle.FS_SMALL
		draw_style_box(UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 6, Vector4.ZERO), Rect2(Vector2.ZERO, size))
		if values.size() < 2:
			draw_string(font, Vector2(10, size.y / 2.0), empty_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20.0, fs, UiStyle.DIM)
			if values.size() == 1:
				draw_line(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5), line_color, 2.0)
			return
		var lo := float(values[0])
		var hi := lo
		for v in values:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		if hi - lo < 1e-9:
			hi = lo + 1.0
		var pad := 18.0
		var right := 74.0   # room for the last value's tag
		var w := maxf(10.0, size.x - right)
		var h := size.y - 2.0 * pad
		for i in 4:
			var gy := pad + h * float(i) / 3.0
			draw_dashed_line(Vector2(0, gy), Vector2(w, gy), Color(UiStyle.LINE, 0.9), 1.0, 4.0)
		var pts := PackedVector2Array()
		for i in values.size():
			var x := w * float(i) / float(values.size() - 1)
			var y := pad + h * (1.0 - (float(values[i]) - lo) / (hi - lo))
			pts.append(Vector2(x, y))
		# The fill fades downwards: a few bands of falling alpha.
		for band in 6:
			var k0 := float(band) / 6.0
			var k1 := float(band + 1) / 6.0
			var poly := PackedVector2Array()
			for q in pts:
				poly.append(Vector2(q.x, lerpf(q.y, size.y, k0)))
			for j in range(pts.size() - 1, -1, -1):
				poly.append(Vector2(pts[j].x, lerpf(pts[j].y, size.y, k1)))
			draw_colored_polygon(poly, Color(line_color, 0.16 * (1.0 - k0)))
		draw_polyline(pts, line_color, 2.0, true)
		var fmt := format_value if format_value.is_valid() else func(v: float) -> String: return str(v)
		draw_string(font, Vector2(6, pad - 4), str(fmt.call(hi)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiStyle.DIM)
		draw_string(font, Vector2(6, size.y - 4), str(fmt.call(lo)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiStyle.DIM)
		var last := pts[pts.size() - 1]
		draw_line(Vector2(0, last.y), Vector2(w, last.y), Color(line_color, 0.35), 1.0)
		draw_circle(last, 4.0, Color(line_color, 0.35))
		draw_circle(last, 2.5, line_color)
		var tag := str(fmt.call(float(values[values.size() - 1])))
		var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0
		var tag_rect := Rect2(Vector2(w + 4.0, last.y - 9.0), Vector2(minf(tw, right - 6.0), 18.0))
		draw_style_box(UiStyle.box(line_color, Color(0, 0, 0, 0), 3, Vector4.ZERO), tag_rect)
		draw_string(font, tag_rect.position + Vector2(5, 13), tag, HORIZONTAL_ALIGNMENT_LEFT, tag_rect.size.x - 6.0, fs, UiStyle.INK)


## A market or ownership donut, the exchange way: slices = [[share, color, name?], …] with thin gaps, it sweeps in
## when shown; under the mouse a slice lifts out and the centre shows its name and share (else the title/total).
class Pie extends Control:
	var slices: Array = []
	var center_title := ""           # the centre's caption when nothing is hovered (e.g. «volume»)
	var center_value := ""           # the centre's big text (e.g. the market's size)
	var _hover := -1
	var _born := -1.0

	func _init() -> void:
		custom_minimum_size = Vector2(150, 150)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _ready() -> void:
		_born = Time.get_ticks_msec() / 1000.0
		mouse_exited.connect(func() -> void:
			_hover = -1
			queue_redraw())

	func _process(_delta: float) -> void:
		if _sweep() < 1.0:
			queue_redraw()

	func _sweep() -> float:
		if _born < 0.0:
			return 1.0
		var k := clampf((Time.get_ticks_msec() / 1000.0 - _born) / 0.6, 0.0, 1.0)
		return 1.0 - pow(1.0 - k, 3.0)   # ease out

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			var d := (e as InputEventMouseMotion).position - size / 2.0
			var r := minf(size.x, size.y) / 2.0 - 6.0
			var was := _hover
			_hover = -1
			if d.length() <= r and d.length() >= r * 0.58:
				var a := fposmod(d.angle() + PI / 2.0, TAU) / TAU
				var acc := 0.0
				for i in slices.size():
					acc += float((slices[i] as Array)[0])
					if a <= acc:
						_hover = i
						break
			if _hover != was:
				queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 6.0
		var inner := r * 0.6
		var sweep := _sweep()
		var start := -PI / 2.0
		var gap := 0.025 if slices.size() > 1 else 0.0
		draw_circle(c, r, UiStyle.PANEL2)
		for i in slices.size():
			var s: Array = slices[i]
			var share := float(s[0])
			if share <= 0.0:
				continue
			var span := TAU * share * sweep
			var a0 := start + minf(gap, span * 0.3)
			var a1 := start + span - minf(gap, span * 0.3)
			var lift := 5.0 if i == _hover else 0.0
			var mid := (a0 + a1) / 2.0
			var off := Vector2(cos(mid), sin(mid)) * lift
			var col := s[1] as Color
			if _hover >= 0 and i != _hover:
				col = col.darkened(0.35)
			var steps := maxi(3, int(72.0 * share))
			var pts := PackedVector2Array()
			for k in steps + 1:
				var a := lerpf(a0, a1, float(k) / float(steps))
				pts.append(c + off + Vector2(cos(a), sin(a)) * (r + lift * 0.4))
			for k in range(steps, -1, -1):
				var a := lerpf(a0, a1, float(k) / float(steps))
				pts.append(c + off + Vector2(cos(a), sin(a)) * inner)
			if pts.size() >= 3:
				draw_colored_polygon(pts, col)
			start += span
		draw_circle(c, inner - 1.0, UiStyle.INK)
		draw_arc(c, inner - 1.0, 0.0, TAU, 48, UiStyle.LINE, 1.0, true)
		# The centre: the hovered slice, or the title and total.
		var font := get_theme_default_font()
		var top := center_title
		var big := center_value
		var big_col := UiStyle.TEXT
		if _hover >= 0:
			var hs: Array = slices[_hover]
			top = str(hs[2]) if hs.size() > 2 else ""
			big = "%.1f%%" % (float(hs[0]) * 100.0)
			big_col = hs[1] as Color
			# A dark sector (oil and gas…) on the dark centre could not be read: its colour lightened until it is.
			var lum := big_col.r * 0.3 + big_col.g * 0.59 + big_col.b * 0.11
			if lum < 0.55:
				big_col = big_col.lightened(clampf((0.55 - lum) / maxf(1.0 - lum, 0.01) + 0.15, 0.0, 0.85))
		var w := inner * 1.7
		var fs_big := int(clampf(inner * 0.34, 10.0, 22.0))
		var fs_top := int(clampf(inner * 0.2, 9.0, 12.0))
		if not top.is_empty():
			draw_string(font, c + Vector2(-w / 2.0, -fs_big * 0.45), top, HORIZONTAL_ALIGNMENT_CENTER, w, fs_top, UiStyle.DIM)
		if not big.is_empty():
			draw_string(font, c + Vector2(-w / 2.0, fs_big * 0.75), big, HORIZONTAL_ALIGNMENT_CENTER, w, fs_big, big_col)


## Round company badge: sector colour + icon.
class Badge extends Control:
	var color := Color.GRAY
	var icon: Texture2D
	var tier := ""                # status frame (frames.gd) — the same drawing as on the map
	var _clock := 0.0

	func _init(diameter: float = 28.0) -> void:
		custom_minimum_size = Vector2(diameter, diameter)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		set_process(Frames.animated(tier))

	func _process(delta: float) -> void:
		_clock += delta
		if _clock >= 1.0 / 30.0:
			_clock = 0.0
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		if tier == "diamond" or tier == "sapphire":
			r *= 0.5    # the crystal frame with wings, laurels and glow needs twice the icon's size
		elif not tier.is_empty():
			r *= 0.72   # room for the ring
		draw_circle(c, r, Color(0, 0, 0, 0.5))
		draw_circle(c, r - 1.5, color)
		if icon != null:
			var s := r * 1.2
			draw_texture_rect(icon, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false)
		Frames.draw(self, c, r, tier)


## Horizontal 0–100 bar.
class Bar extends Control:
	var value := 0.0
	var good_high := true

	func _init() -> void:
		custom_minimum_size = Vector2(120, 10)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rad := int(minf(size.y / 2.0, 4.0))
		draw_style_box(UiStyle.box(UiStyle.PANEL2, Color(0, 0, 0, 0), rad, Vector4.ZERO), Rect2(Vector2.ZERO, size))
		var t := clampf(value / 100.0, 0.0, 1.0)
		var goodness := t if good_high else 1.0 - t
		var col := UiStyle.DOWN.lerp(UiStyle.GOLD, clampf(goodness * 2.0, 0.0, 1.0)) if goodness < 0.5 else UiStyle.GOLD.lerp(UiStyle.UP, (goodness - 0.5) * 2.0)
		if t > 0.0:
			draw_style_box(UiStyle.box(col, Color(0, 0, 0, 0), rad, Vector4.ZERO), Rect2(Vector2.ZERO, Vector2(maxf(size.x * t, size.y), size.y)))
