extends HBoxContainer
## The technology level over a research tree (techlevel.gd, section 14.4): a horizontal scale from 0 to the world
## frontier with marks — the country's best company, the world leader (named), the world median; the step and the
## time («Catching up · behind ≈ 14 months» or «World leader · lead ≈ 5 months»); the hover — Q by factors and what
## holds it back most; a small chart of T and F over the last two years.

const UiStyle := preload("res://mods/pax_corporations/src/look/ui_style.gd")

var tl: Object                    # techlevel.gd
var db: Object
var mod: PaxMod
var company: Dictionary = {}
var kind := ""


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


func build(m: PaxMod, level: Object, data: Object, country: String, sector: String) -> void:
	mod = m
	tl = level
	db = data
	kind = sector
	company = tl.call("best_of", country, sector)
	add_theme_constant_override("separation", 12)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 8, Vector4(12, 6, 12, 8)))
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	card.add_child(v)
	if company.is_empty():
		v.add_child(_label(_t("tl_none"), UiStyle.DIM, 12))
		return
	var step := str(tl.call("step_key", company))
	var months := float(tl.call("months", company))
	var head := _label(_t("tl_title") % [str(db.call("name_of", company)), _t("tl_step_" + step),
		_t("tl_lead" if step == "leader" else "tl_behind") % months], _color(step), 13)
	v.add_child(head)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(300, 30)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.tooltip_text = _breakdown()
	bar.draw.connect(func() -> void: _draw_bar(bar))
	v.add_child(bar)
	var chart := Control.new()
	chart.custom_minimum_size = Vector2(170, 52)
	chart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chart.tooltip_text = _t("tl_chart_tip")
	chart.mouse_filter = Control.MOUSE_FILTER_STOP
	chart.draw.connect(func() -> void: _draw_chart(chart))
	add_child(chart)
	tooltip_text = bar.tooltip_text


func _label(text: String, col: Color, fs: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", fs)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _color(step: String) -> Color:
	match step:
		"leader":
			return UiStyle.GOLD
		"frontier":
			return UiStyle.UP
		"catching":
			return UiStyle.BLUE
		"behind":
			return Color(1.0, 0.6, 0.25)
	return UiStyle.DOWN


func _draw_bar(c: Control) -> void:
	var f := float(tl.call("frontier", kind))
	var font := c.get_theme_default_font()
	const y := 9.0
	var w := c.size.x
	c.draw_rect(Rect2(Vector2(0, y - 3), Vector2(w, 6)), UiStyle.PANEL2)
	# The steps' bands: far behind, behind, catching up, frontier.
	var x0 := 0.0
	for band in [[0.4, UiStyle.DOWN], [0.6, Color(1.0, 0.6, 0.25)], [0.8, UiStyle.BLUE], [1.0, UiStyle.UP]]:
		var x1 := w * float(band[0])
		c.draw_rect(Rect2(Vector2(x0, y - 3), Vector2(x1 - x0, 6)), Color(band[1] as Color, 0.25))
		x0 = x1
	var mine := float(tl.call("level", company)) / f
	c.draw_rect(Rect2(Vector2(0, y - 3), Vector2(w * clampf(mine, 0.0, 1.0), 6)), _color(str(tl.call("step_key", company))))
	var med := float(tl.call("median", kind)) / f
	c.draw_line(Vector2(w * med, y - 7), Vector2(w * med, y + 7), UiStyle.DIM, 2.0)
	c.draw_string(font, Vector2(clampf(w * med - 20.0, 0.0, w - 60.0), y + 20), _t("tl_median"), HORIZONTAL_ALIGNMENT_LEFT, 80, 10, UiStyle.DIM)
	var lead := db.call("company", str((tl.get("leaders") as Dictionary).get(kind, ""))) as Dictionary
	c.draw_line(Vector2(w - 1, y - 8), Vector2(w - 1, y + 8), UiStyle.GOLD, 2.0)
	if not lead.is_empty():
		c.draw_string(font, Vector2(w - 160, y + 20), "★ " + str(db.call("name_of", lead)), HORIZONTAL_ALIGNMENT_RIGHT, 158, 10, UiStyle.GOLD)
	c.draw_circle(Vector2(w * clampf(mine, 0.0, 1.0), y), 5.0, UiStyle.TEXT)


func _draw_chart(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(1, 1, 1, 0.04))
	var mine: Array = (tl.get("c_hist") as Dictionary).get(str(company.get("id", "")), [])
	var fr: Array = (tl.get("f_hist") as Dictionary).get(kind, [])
	if fr.size() < 2:
		c.draw_string(c.get_theme_default_font(), Vector2(6, c.size.y / 2.0 + 4), _t("tl_chart_wait"), HORIZONTAL_ALIGNMENT_LEFT, c.size.x - 12, 10, UiStyle.DIM)
		return
	var hi := 1.0
	var lo := INF
	for v in fr + mine:
		hi = maxf(hi, float(v))
		lo = minf(lo, float(v))
	lo = minf(lo, hi * 0.5)
	for pair in [[fr, UiStyle.GOLD], [mine, UiStyle.TEXT]]:
		var arr: Array = pair[0]
		if arr.size() < 2:
			continue
		var pts := PackedVector2Array()
		for i in arr.size():
			pts.append(Vector2(c.size.x * float(i) / float(arr.size() - 1), 4.0 + (c.size.y - 8.0) * (1.0 - (float(arr[i]) - lo) / maxf(hi - lo, 1e-6))))
		c.draw_polyline(pts, pair[1] as Color, 1.5, true)


## Q by its factors and what holds it back most.
func _breakdown() -> String:
	var p: Dictionary = (tl.get("parts") as Dictionary).get(str(company.get("id", "")), {})
	var f: Dictionary = p.get("factors", {})
	var lines: PackedStringArray = [_t("tl_q_title")]
	for k in ["research", "compute", "people", "money", "science"]:
		lines.append("  %s: %d%%" % [_t("tl_f_" + k), roundi(float(f.get(k, 0.0)) * 100.0)])
	if f.is_empty():
		lines.append(_t("tl_wait"))
	else:
		lines.append(_t("tl_brake") % _t("tl_brake_" + str(tl.call("brake", company))))
	lines.append(_t("tl_steps_tip"))
	return "\n".join(lines)
