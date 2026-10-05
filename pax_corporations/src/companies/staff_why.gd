extends Control
## «Почему так?» about a company's people — a modal card in the mod's design instead of a wall of text:
##   four tiles (satisfaction, pay against the market, who came and went in 4 weeks, strikes);
##   what makes the satisfaction (bars to the left and to the right of the base 50);
##   pay: the company against its industry's market and the country's average (bars), the wage policy;
##   people: who came, quit, was fired, and why; strikes and the sites close to one; the last weeks.
## It grows in, the bars fill one after another, the numbers count up. Esc, ✕ or a click outside close it.
## The numbers come from ui_window.staff_data() — the same as economy.gd uses.

const UiStyle := preload("res://mods/pax_corporations/src/look/ui_style.gd")
const Glass := preload("res://mods/pax_corporations/src/look/glass.gd")
const WheelGuard := preload("res://mods/pax_corporations/src/shared/wheel_guard.gd")

var _t: Callable          # func(key) -> String
var _ask_ai: Callable     # func() -> void, or none
var _people: Callable     # func(float) -> String: a count of people or money in words
var _card: PanelContainer
var _bars: Array = []     # [Control, target 0..1] — filled by the animation
var _counters: Array = [] # [Label, target, format Callable]
var _fill := 0.0


func open(layer: Node, data: Dictionary, t: Callable, ask_ai: Callable) -> void:
	_t = t
	_ask_ai = ask_ai
	name = "PaxCorpStaffWhy"
	set_meta(&"pax_corp_skin_skip", true)
	set_meta(&"pax_interface_skip_skin", true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 80
	theme = UiStyle.theme()
	layer.add_child(self)
	_build(data)
	var g := WheelGuard.new()
	g.whole = true
	add_child(g)
	_animate_in()


func _tr(key: String) -> String:
	return str(_t.call(key))


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if is_queued_for_deletion():
		return
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 0.0, 0.14)
	tw.tween_callback(queue_free)


func _build(d: Dictionary) -> void:
	_people = d["humans"]
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(760, 0)
	center.add_child(_card)
	Glass.apply(_card)
	var solid := StyleBoxFlat.new()
	solid.bg_color = Color(UiStyle.SOLID_BG, 0.97)
	solid.border_color = UiStyle.SOLID_LINE
	solid.set_border_width_all(1)
	solid.set_corner_radius_all(10)
	solid.set_content_margin_all(20)
	solid.shadow_color = Color(0, 0, 0, 0.5)
	solid.shadow_size = 18
	_card.add_theme_stylebox_override("panel", solid)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	_card.add_child(root)

	# The head.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	root.add_child(head)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	tv.add_child(_label(_tr("sw2_kicker").to_upper(), UiStyle.GOLD, 11))
	tv.add_child(_label(str(d["company"]), UiStyle.TEXT, 20))
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(34, 30)
	x.pressed.connect(close)
	head.add_child(x)

	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, mini(560, int(get_viewport_rect().size.y * 0.7)))
	root.add_child(sc)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)

	# Four tiles.
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 10)
	body.add_child(tiles)
	var h := float(d["satisfaction"])
	_tile(tiles, _tr("sw2_mood"), h * 100.0, func(v: float) -> String: return "%d%%" % roundi(v), str(d["satisfaction_word"]), _tone(h - 0.5))
	var ratio := float(d["wage_to_market"])
	_tile(tiles, _tr("sw2_pay"), ratio, func(v: float) -> String: return "×%s" % String.num(v, 2).replace(".", ","), _tr("sw2_pay_sub"), _tone(ratio - 1.0))
	var flow: Dictionary = d["поток"]
	var net := float(flow["arrived"]) - float(flow["left"]) - float(flow["fired"])
	_tile(tiles, _tr("sw2_flow"), net, func(v: float) -> String: return ("+" if v >= 0.0 else "−") + str(_people.call(absf(v))), _tr("sw2_flow_sub"), _tone(net))
	var strikes := int(d["strike_count"])
	_tile(tiles, _tr("sw2_strikes"), float(strikes), func(v: float) -> String: return "%d" % roundi(v), _tr("sw2_strikes_sub"), UiStyle.DOWN if strikes > 0 else UiStyle.UP)

	# What makes the satisfaction.
	var parts := _section(body, _tr("sw2_parts_title"), _tr("sw2_parts_hint"))
	var maxp := 1.0
	for p in d["parts"]:
		maxp = maxf(maxp, absf(float(p[1])))
	for p in d["parts"]:
		_diverging(parts, str(p[0]), float(p[1]), maxp, str(p[2]))

	# Pay.
	var pay := _section(body, _tr("sw2_pay_title"), "")
	var wages: Dictionary = d["wages"]
	var top := maxf(float(wages["company"]), maxf(float(wages["рынок"]), float(wages["country"])))
	for row in [["sw2_w_company", "company", UiStyle.GOLD], ["sw2_w_market", "рынок", UiStyle.BLUE], ["sw2_w_country", "country", UiStyle.DIM]]:
		_hbar(pay, _tr(str(row[0])), float(wages[str(row[1])]) / maxf(top, 1.0), "$" + str(_people.call(float(wages[str(row[1])]))), row[2] as Color)
	for line in d["wage_rows"]:
		pay.add_child(_wrap(str(line), UiStyle.DIM, 12))

	# People.
	var ppl := _section(body, _tr("sw2_people_title"), "")
	var topf := maxf(1.0, maxf(float(flow["arrived"]), maxf(float(flow["left"]), float(flow["fired"]))))
	_hbar(ppl, _tr("sw2_came"), float(flow["arrived"]) / topf, str(_people.call(float(flow["arrived"]))), UiStyle.UP)
	_hbar(ppl, _tr("sw2_quit"), float(flow["left"]) / topf, str(_people.call(float(flow["left"]))), UiStyle.BLUE)
	_hbar(ppl, _tr("sw2_fired"), float(flow["fired"]) / topf, str(_people.call(float(flow["fired"]))), UiStyle.DOWN)
	for line in d["people_rows"]:
		ppl.add_child(_wrap("• " + str(line), UiStyle.TEXT, 12))

	# Strikes and the sites close to one.
	var st := _section(body, _tr("sw2_strike_title"), "")
	for line in d["strike_rows"]:
		st.add_child(_wrap("• " + str(line), UiStyle.DOWN if strikes > 0 else UiStyle.TEXT, 12))
	st.add_child(_wrap(str(d["риск"]), UiStyle.DIM, 12))

	# The last weeks.
	var recent: Array = d["недавно"]
	if not recent.is_empty():
		var rc := _section(body, _tr("sw2_recent_title"), "")
		for line in recent:
			rc.add_child(_wrap("• " + str(line), UiStyle.TEXT, 12))

	# What it means + buttons.
	var eff := PanelContainer.new()
	eff.add_theme_stylebox_override("panel", UiStyle.box(Color(UiStyle.GOLD, 0.08), Color(UiStyle.GOLD, 0.35), 6, Vector4(12, 8, 12, 8)))
	body.add_child(eff)
	eff.add_child(_wrap(str(d["means"]), UiStyle.TEXT, 13))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	foot.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(foot)
	if _ask_ai.is_valid():
		var ai := Button.new()
		ai.text = "✦ " + _tr("staff_why_ai")
		ai.focus_mode = Control.FOCUS_NONE
		ai.pressed.connect(func() -> void:
			close()
			_ask_ai.call())
		foot.add_child(ai)
	var ok := Button.new()
	ok.text = _tr("staff_why_close")
	ok.theme_type_variation = &"ExPrimary"
	ok.focus_mode = Control.FOCUS_NONE
	ok.custom_minimum_size = Vector2(120, 32)
	ok.pressed.connect(close)
	foot.add_child(ok)


# ---------- parts ----------

static func _tone(x: float) -> Color:
	return UiStyle.UP if x > 0.02 else (UiStyle.DOWN if x < -0.02 else UiStyle.GOLD)


func _label(text: String, col: Color, fs: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", fs)
	return l


func _wrap(text: String, col: Color, fs: int) -> Label:
	var l := _label(text, col, fs)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(680, 0)
	return l


func _tile(row: HBoxContainer, title: String, value: float, fmt: Callable, sub: String, col: Color) -> void:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UiStyle.box(Color(1, 1, 1, 0.04), Color(col, 0.45), 8, Vector4(12, 10, 12, 10)))
	row.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	v.add_child(_label(title.to_upper(), UiStyle.DIM, 10))
	var num := _label(str(fmt.call(0.0)), col, 24)
	v.add_child(num)
	_counters.append([num, value, fmt])
	var s := _label(sub, UiStyle.DIM, 11)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(s)


func _section(parent: VBoxContainer, title: String, hint: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	parent.add_child(v)
	var hl := HBoxContainer.new()
	hl.add_theme_constant_override("separation", 8)
	v.add_child(hl)
	var bar := ColorRect.new()
	bar.color = UiStyle.GOLD
	bar.custom_minimum_size = Vector2(3, 16)
	hl.add_child(bar)
	hl.add_child(_label(title, UiStyle.TEXT, 15))
	if not hint.is_empty():
		v.add_child(_wrap(hint, UiStyle.DIM, 11))
	return v


## A part of the satisfaction: its name, a bar left (−) or right (+) of the middle, the points, the reason under it.
func _diverging(parent: VBoxContainer, name: String, pts: float, maxp: float, why: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var n := _label(name, UiStyle.TEXT, 13)
	n.custom_minimum_size = Vector2(200, 0)
	n.tooltip_text = why
	n.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(n)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(300, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.tooltip_text = why
	row.add_child(bar)
	var col := UiStyle.UP if pts >= 0.0 else UiStyle.DOWN
	var k := clampf(absf(pts) / maxf(maxp, 1.0), 0.0, 1.0)
	_bars.append([bar, k])
	bar.draw.connect(func() -> void:
		var hh := 8.0
		var y := (bar.size.y - hh) / 2.0
		var mid := bar.size.x / 2.0
		bar.draw_rect(Rect2(Vector2(0, y), Vector2(bar.size.x, hh)), Color(1, 1, 1, 0.06))
		var w := mid * k * _fill
		bar.draw_rect(Rect2(Vector2(mid if pts >= 0.0 else mid - w, y), Vector2(w, hh)), col)
		bar.draw_line(Vector2(mid, y - 3), Vector2(mid, y + hh + 3), Color(1, 1, 1, 0.45), 1.0))
	var val := _label(("+" if pts >= 0.0 else "−") + "%d" % roundi(absf(pts)), col, 13)
	val.custom_minimum_size = Vector2(44, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	var w2 := _label(why, UiStyle.DIM, 11)
	w2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w2.custom_minimum_size = Vector2(160, 0)
	row.add_child(w2)


func _hbar(parent: VBoxContainer, name: String, k: float, value: String, col: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var n := _label(name, UiStyle.TEXT, 13)
	n.custom_minimum_size = Vector2(200, 0)
	row.add_child(n)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(360, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var kk := clampf(k, 0.0, 1.0)
	_bars.append([bar, kk])
	bar.draw.connect(func() -> void:
		var hh := 8.0
		var y := (bar.size.y - hh) / 2.0
		bar.draw_rect(Rect2(Vector2(0, y), Vector2(bar.size.x, hh)), Color(1, 1, 1, 0.06))
		bar.draw_rect(Rect2(Vector2(0, y), Vector2(bar.size.x * kk * _fill, hh)), col))
	var val := _label(value, UiStyle.TEXT, 13)
	val.custom_minimum_size = Vector2(90, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)


# ---------- animation ----------

## The card grows in (pause-proof: the game may be paused), then the bars fill and the numbers count up.
func _animate_in() -> void:
	modulate.a = 0.0
	_card.pivot_offset = _card.size / 2.0
	_card.scale = Vector2(0.94, 0.94)
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var fill := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fill.tween_interval(0.12)
	fill.tween_method(_set_fill, 0.0, 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# The pivot needs the card's real size: one frame later.
	await get_tree().process_frame
	if is_instance_valid(_card):
		_card.pivot_offset = _card.size / 2.0


func _set_fill(x: float) -> void:
	_fill = x
	for b in _bars:
		if is_instance_valid(b[0]):
			(b[0] as Control).queue_redraw()
	for c in _counters:
		if is_instance_valid(c[0]):
			(c[0] as Label).text = str((c[2] as Callable).call(float(c[1]) * x))
