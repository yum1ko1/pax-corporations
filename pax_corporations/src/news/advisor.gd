extends HBoxContainer
## The AI advisor: a round console face and a speech card — the mod's long explanations are his words, typed out
## letter by letter. A click on the card folds it into one line (and back); the fold is remembered per place
## («key»), and words already said are not typed anew when a window refreshes. Red when the news is bad.

const UiStyle := preload("res://mods/pax_corporations/src/look/ui_style.gd")

static var _folded: Dictionary = {}   # key -> true: the card is folded
static var _said: Dictionary = {}     # key -> the text said last (typed once)

var key := ""
var alarm := false
var _say: Label
var _typed := 1.0
var _avatar: Control
var _fold_mark: Label


## where — the place the advisor speaks in (his fold and his last words are kept under it); extra — e.g. a link
## button under the words.
func setup(mod: PaxMod, where: String, text: String, bad: bool = false, extra: Control = null) -> void:
	key = where
	alarm = bad
	_build(mod.tr_key("pax_corporations_advisor_name"), text, extra)


func _tone() -> Color:
	return UiStyle.DOWN if alarm else UiStyle.BLUE


func _build(who: String, text: String, extra: Control) -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_avatar = Control.new()
	_avatar.custom_minimum_size = Vector2(44, 44)
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_avatar.draw.connect(_draw_avatar)
	add_child(_avatar)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiStyle.box(Color(_tone(), 0.08), Color(_tone(), 0.55), 8, Vector4(12, 6, 12, 7)))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_folded[key] = not bool(_folded.get(key, false))
			_apply_fold())
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	top.add_child(UiStyle.caption(who, Color(_tone(), 0.95)))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	_fold_mark = UiStyle.caption("", UiStyle.DIM)
	top.add_child(_fold_mark)
	_say = Label.new()
	_say.text = text
	_say.add_theme_color_override("font_color", Color(1.0, 0.86, 0.86) if alarm else UiStyle.TEXT)
	_say.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_say.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_say.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	v.add_child(_say)
	if extra != null:
		v.add_child(extra)
	if str(_said.get(key, "")) != text:
		_said[key] = text
		_typed = 0.0
	_apply_fold()


func _apply_fold() -> void:
	var folded := bool(_folded.get(key, false))
	_fold_mark.text = "▸" if folded else "▾"
	_say.autowrap_mode = TextServer.AUTOWRAP_OFF if folded else TextServer.AUTOWRAP_WORD_SMART
	_say.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if folded else TextServer.OVERRUN_NO_TRIMMING
	_say.clip_text = folded
	_say.max_lines_visible = 1 if folded else -1
	if folded:
		_typed = 1.0
	_say.visible_ratio = _typed


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _typed < 1.0:
		_typed = minf(1.0, _typed + delta * 60.0 / maxf(float(_say.text.length()), 1.0))   # ~60 letters a second
		_say.visible_ratio = _typed
	_avatar.queue_redraw()


## A round console face with a scanning eye; rings pulse and the mouth moves while it speaks.
func _draw_avatar() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var tone := _tone()
	var c := _avatar.size / 2.0
	var r := minf(c.x, c.y) - 2.0
	if _typed < 1.0:
		var ph := fmod(now * 1.6, 1.0)
		_avatar.draw_arc(c, r * (0.8 + 0.25 * ph), 0.0, TAU, 32, Color(tone, 0.6 * (1.0 - ph)), 2.0, true)
	_avatar.draw_circle(c, r * 0.8, UiStyle.PANEL2)
	_avatar.draw_arc(c, r * 0.8, 0.0, TAU, 32, tone, 2.0, true)
	_avatar.draw_rect(Rect2(c + Vector2(-r * 0.5, -r * 0.16), Vector2(r, r * 0.32)), Color(tone, 0.18))
	var eye := c + Vector2(sin(now * 1.4) * r * 0.32, 0.0)
	var open := 0.15 if fmod(now, 4.0) < 0.12 else 1.0
	_avatar.draw_rect(Rect2(eye - Vector2(r * 0.12, r * 0.1 * open), Vector2(r * 0.24, r * 0.2 * open)), tone)
	var talk := 0.5 + 0.5 * absf(sin(now * 14.0)) if _typed < 1.0 else 0.2
	_avatar.draw_line(c + Vector2(-r * 0.2, r * 0.38), c + Vector2(r * 0.2, r * 0.38), Color(tone, 0.5 + 0.5 * talk), 1.0 + 2.0 * talk, true)
	_avatar.draw_line(c + Vector2(0, -r * 0.8), c + Vector2(0, -r * 1.0), tone, 2.0, true)
	if fmod(now, 1.0) < 0.5:
		_avatar.draw_circle(c + Vector2(0, -r * 1.0), 2.5, tone.lightened(0.3))
