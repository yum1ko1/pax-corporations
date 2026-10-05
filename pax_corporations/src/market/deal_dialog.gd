extends Control
## «New terms of the deal»: the antimonopoly service approves a deal only with a condition (a fee for the harm to
## competition) — before anything is paid the player sees the new terms and decides. A dimmed screen, a glass card
## in the middle: the service's word, the terms (company, stake, price, the fee and its share, the total, the
## treasury after), «Accept the terms» / «Cancel the deal». Esc or a click outside — cancel.

const UiStyle := preload("res://mods/pax_corporations/src/look/ui_style.gd")
const Glass := preload("res://mods/pax_corporations/src/look/glass.gd")
const WheelGuard := preload("res://mods/pax_corporations/src/shared/wheel_guard.gd")

var _accept: Callable
var _decline: Callable
var _done := false


## rows: [[label, value, highlight?], …]
func open(layer: Node, title: String, intro: String, rows: Array, note: String, accept_text: String,
		decline_text: String, on_accept: Callable, on_decline: Callable) -> void:
	_accept = on_accept
	_decline = on_decline
	name = "PaxCorpDealDialog"
	set_meta(&"pax_corp_skin_skip", true)
	set_meta(&"pax_interface_skip_skin", true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	theme = UiStyle.theme()
	layer.add_child(self)
	_build(title, intro, rows, note, accept_text, decline_text)
	var g := WheelGuard.new()
	g.whole = true
	add_child(g)


func _build(title: String, intro: String, rows: Array, note: String, accept_text: String, decline_text: String) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_finish(false))
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(500, 0)
	center.add_child(card)
	Glass.apply(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	var mark := Label.new()
	mark.text = "🏛"
	mark.add_theme_font_size_override("font_size", 22)
	head.add_child(mark)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 17)
	t.add_theme_color_override("font_color", UiStyle.GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(t)
	var i := Label.new()
	i.text = intro
	i.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	i.custom_minimum_size = Vector2(470, 0)
	i.add_theme_color_override("font_color", UiStyle.TEXT)
	v.add_child(i)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	var gp := PanelContainer.new()
	gp.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 10, Vector4(14, 10, 14, 10)))
	gp.add_child(grid)
	v.add_child(gp)
	for r in rows:
		var ra: Array = r
		var hot := ra.size() > 2 and bool(ra[2])
		var k := Label.new()
		k.text = str(ra[0])
		k.add_theme_color_override("font_color", UiStyle.DIM)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(k)
		var val := Label.new()
		val.text = str(ra[1])
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.add_theme_color_override("font_color", UiStyle.DOWN if hot else UiStyle.TEXT)
		val.add_theme_font_size_override("font_size", 15 if hot else 13)
		grid.add_child(val)
	if not note.is_empty():
		var n := Label.new()
		n.text = note
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size = Vector2(470, 0)
		n.add_theme_font_size_override("font_size", 11)
		n.add_theme_color_override("font_color", UiStyle.DIM)
		v.add_child(n)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(bar)
	var no := Button.new()
	no.text = decline_text
	no.focus_mode = Control.FOCUS_NONE
	no.custom_minimum_size = Vector2(150, 34)
	no.pressed.connect(func() -> void: _finish(false))
	bar.add_child(no)
	var yes := Button.new()
	yes.text = accept_text
	yes.focus_mode = Control.FOCUS_NONE
	yes.custom_minimum_size = Vector2(180, 34)
	UiStyle.as_primary(yes)
	yes.pressed.connect(func() -> void: _finish(true))
	bar.add_child(yes)


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_finish(false)


func _finish(ok: bool) -> void:
	if _done:
		return
	_done = true
	var cb := _accept if ok else _decline
	queue_free()
	if cb.is_valid():
		cb.call()
