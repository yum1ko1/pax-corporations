extends RefCounted
## The mod's look — frosted glass (glass.gd blurs the game behind the window): translucent white-blue cards with
## thin light edges, a light-cyan accent (GOLD keeps its name: «the accent»), teal for growth and coral for falls,
## underlined tabs, a business typeface (the system's Segoe UI / Inter / Roboto / Arial), compact type.
## SOLID_* — the same tones opaque, for the game's own interface (hud_skin.gd) and drawings that need a solid ground.

const BG := Color(0.05, 0.09, 0.15, 0.28)      # the glass ground (over the blur)
const PANEL := Color(0.8, 0.9, 1.0, 0.07)      # a card
const PANEL2 := Color(0.8, 0.9, 1.0, 0.13)     # a raised card, a button
const LINE := Color(0.82, 0.92, 1.0, 0.22)     # thin light edges
const TEXT := Color(0.95, 0.97, 1.0)
const DIM := Color(0.72, 0.8, 0.9)
const GOLD := Color(0.48, 0.82, 1.0)           # the accent: light cyan
const UP := Color(0.45, 0.92, 0.82)
const DOWN := Color(1.0, 0.52, 0.5)
const BLUE := Color(0.6, 0.8, 1.0)
const INK := Color(0.075, 0.09, 0.115)         # opaque: donut holes, text on bright tags
const SOLID_BG := Color(0.075, 0.09, 0.115)
const SOLID_PANEL := Color(0.11, 0.13, 0.16)
const SOLID_PANEL2 := Color(0.145, 0.17, 0.205)
const SOLID_LINE := Color(0.24, 0.29, 0.35)
const TierLook := preload("res://mods/pax_corporations/src/shared/tier_look.gd")
const FONTS := ["Segoe UI", "Inter", "Roboto", "Helvetica Neue", "Arial"]
const FS := 13                                 # body type
const FS_SMALL := 11

static var _theme: Theme
static var accent := GOLD   # the theme's accent: the light cyan, or the colour of the country's world step


## A rounded box: fill, border (none when transparent), radius, inner margins (left, top, right, bottom).
static func box(fill: Color, border: Color = Color(0, 0, 0, 0), radius: int = 6, pad: Vector4 = Vector4(10, 6, 10, 6), bw: int = 1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = border
	b.set_border_width_all(bw if border.a > 0.0 else 0)
	b.set_corner_radius_all(radius)
	b.content_margin_left = pad.x
	b.content_margin_top = pad.y
	b.content_margin_right = pad.z
	b.content_margin_bottom = pad.w
	b.anti_aliasing = true
	return b


## Only a line under the box (a selected tab, a table header).
static func underline(col: Color, width: int, pad: Vector4) -> StyleBoxFlat:
	var b := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, pad)
	b.border_color = col
	b.border_width_bottom = width
	return b


## The business typeface, bold or regular (titles of cards and dialogs).
static func font(bold: bool = false) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(FONTS)
	f.font_weight = 700 if bold else 400
	return f


static func theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_fill(_theme)
	return _theme


## The world step of the player's country (country_rank.gd): the accent of buttons, tabs, bars and focus takes
## its colour; the theme is filled again in place, so every open window changes at once.
static func set_tier(tier: String) -> void:
	var a := TierLook.accent(tier, GOLD)
	if a == accent:
		return
	accent = a
	if _theme != null:
		_fill(_theme)


static func _fill(t: Theme) -> void:
	var f := SystemFont.new()   # a business typeface instead of the game's decorative one
	f.font_names = PackedStringArray(FONTS)
	t.default_font = f
	t.default_font_size = FS
	# Labels and text.
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", FS)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", FS)
	t.set_font_size("bold_font_size", "RichTextLabel", FS + 1)
	# Buttons: dark pills that light up under the mouse.
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, box(PANEL2, LINE, 6, Vector4(10, 4, 10, 4)))
		t.set_stylebox("hover", type, box(LINE, Color(accent, 0.5), 6, Vector4(10, 4, 10, 4)))
		t.set_stylebox("pressed", type, box(Color(accent, 0.16), accent, 6, Vector4(10, 4, 10, 4)))
		t.set_stylebox("hover_pressed", type, box(Color(accent, 0.22), accent, 6, Vector4(10, 4, 10, 4)))
		t.set_stylebox("disabled", type, box(PANEL, LINE, 6, Vector4(10, 4, 10, 4)))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, accent)
		t.set_color("font_hover_pressed_color", type, accent)
		t.set_color("font_disabled_color", type, Color(DIM, 0.6))
		t.set_font_size("font_size", type, FS)
	# «ExTab»: the exchange's top tabs — plain text, the chosen one bright with a yellow line under it.
	t.set_type_variation("ExTab", "Button")
	var tab_pad := Vector4(10, 6, 10, 6)
	t.set_stylebox("normal", "ExTab", underline(Color(0, 0, 0, 0), 2, tab_pad))
	t.set_stylebox("hover", "ExTab", underline(Color(DIM, 0.5), 2, tab_pad))
	t.set_stylebox("pressed", "ExTab", underline(accent, 2, tab_pad))
	t.set_stylebox("hover_pressed", "ExTab", underline(accent, 2, tab_pad))
	t.set_color("font_color", "ExTab", DIM)
	t.set_color("font_hover_color", "ExTab", TEXT)
	t.set_color("font_pressed_color", "ExTab", TEXT)
	t.set_color("font_hover_pressed_color", "ExTab", TEXT)
	# «ExPrimary»: the yellow action button.
	t.set_type_variation("ExPrimary", "Button")
	t.set_stylebox("normal", "ExPrimary", box(accent, Color(0, 0, 0, 0), 6, Vector4(12, 4, 12, 4)))
	t.set_stylebox("hover", "ExPrimary", box(accent.lightened(0.15), Color(0, 0, 0, 0), 6, Vector4(12, 4, 12, 4)))
	t.set_stylebox("pressed", "ExPrimary", box(accent.darkened(0.15), Color(0, 0, 0, 0), 6, Vector4(12, 4, 12, 4)))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		t.set_color(k, "ExPrimary", Color(0.08, 0.08, 0.08))
	# Panels, tabs of the dossier, popups, tooltips.
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 8, Vector4(10, 8, 10, 8)))
	t.set_stylebox("panel", "TabContainer", box(PANEL, LINE, 8, Vector4(4, 4, 4, 4)))
	t.set_stylebox("tab_selected", "TabContainer", underline(accent, 2, Vector4(12, 6, 12, 6)))
	t.set_stylebox("tab_unselected", "TabContainer", underline(Color(0, 0, 0, 0), 2, Vector4(12, 6, 12, 6)))
	t.set_stylebox("tab_hovered", "TabContainer", underline(Color(DIM, 0.5), 2, Vector4(12, 6, 12, 6)))
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabContainer", TEXT)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_font_size("font_size", "TabContainer", FS)
	# Popups and tooltips stand over other text: solid, never glass (glass let the text below show through).
	t.set_stylebox("panel", "PopupMenu", box(Color(SOLID_PANEL2, 0.98), SOLID_LINE, 6, Vector4(6, 6, 6, 6)))
	t.set_stylebox("hover", "PopupMenu", box(LINE, Color(0, 0, 0, 0), 4, Vector4(6, 2, 6, 2)))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", accent)
	var tip := box(Color(SOLID_BG, 0.98), SOLID_LINE, 6, Vector4(12, 8, 12, 8))
	tip.shadow_color = Color(0, 0, 0, 0.45)
	tip.shadow_size = 8
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", FS)
	# Separators, scroll bars, progress bars, sliders, inputs.
	var sep := StyleBoxLine.new()
	sep.color = LINE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 10)
	for sb_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_type, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 3, Vector4(2, 2, 2, 2)))
		t.set_stylebox("grabber", sb_type, box(LINE, Color(0, 0, 0, 0), 3, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber_highlight", sb_type, box(DIM, Color(0, 0, 0, 0), 3, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber_pressed", sb_type, box(accent, Color(0, 0, 0, 0), 3, Vector4(3, 3, 3, 3)))
	t.set_stylebox("background", "ProgressBar", box(PANEL2, Color(0, 0, 0, 0), 4, Vector4.ZERO))
	t.set_stylebox("fill", "ProgressBar", box(accent, Color(0, 0, 0, 0), 4, Vector4.ZERO))
	t.set_stylebox("slider", "HSlider", box(LINE, Color(0, 0, 0, 0), 3, Vector4(0, 2, 0, 2)))
	t.set_stylebox("grabber_area", "HSlider", box(accent, Color(0, 0, 0, 0), 3, Vector4(0, 2, 0, 2)))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(accent.lightened(0.2), Color(0, 0, 0, 0), 3, Vector4(0, 2, 0, 2)))
	for le in ["LineEdit", "TextEdit", "SpinBox"]:
		t.set_stylebox("normal", le, box(PANEL2, LINE, 6, Vector4(8, 4, 8, 4)))
		t.set_stylebox("focus", le, box(PANEL2, accent, 6, Vector4(8, 4, 8, 4)))
		t.set_color("font_color", le, TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())


## A coloured pill with text: green/red for a change, a tag, a status.
static func pill(text: String, col: Color, fs: int = FS_SMALL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(col, 0.14), Color(0, 0, 0, 0), 4, Vector4(6, 1, 6, 1)))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", fs)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## The colour of a change: green up, red down, grey flat.
static func tone(x: float, eps: float = 0.0005) -> Color:
	return UP if x > eps else (DOWN if x < -eps else DIM)


## A dark card (the body goes into the returned VBox).
static func card(parent: Control, title: String = "", accent: Color = Color(0, 0, 0, 0)) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PANEL, accent if accent.a > 0.0 else LINE, 8, Vector4(12, 8, 12, 10)))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	if not title.is_empty():
		v.add_child(caption(title))
	return v


## A small caps caption (a card or a column title).
static func caption(text: String, col: Color = DIM) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", FS_SMALL)
	return l


## A KPI tile: a dim caption over a big number, an optional coloured line under it.
static func kpi(title: String, value: String, col: Color = TEXT, sub: String = "", sub_col: Color = DIM) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PANEL, LINE, 8, Vector4(12, 6, 12, 8)))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	v.add_child(caption(title))
	var n := Label.new()
	n.text = value
	n.add_theme_color_override("font_color", col)
	n.add_theme_font_size_override("font_size", 18)
	v.add_child(n)
	if not sub.is_empty():
		var s := Label.new()
		s.text = sub
		s.add_theme_color_override("font_color", sub_col)
		s.add_theme_font_size_override("font_size", FS_SMALL)
		v.add_child(s)
	return p


## A flowing row of pills/chips that wraps onto new lines.
static func flow(sep: int = 6) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", 4)
	return f

## A button as the exchange's tab: styles set on the button itself (a theme variation reached it only after the
## first hover, while the game's window was still being themed).
static func as_tab(b: Button) -> void:
	var tab_pad := Vector4(10, 6, 10, 6)
	b.add_theme_stylebox_override("normal", underline(Color(0, 0, 0, 0), 2, tab_pad))
	b.add_theme_stylebox_override("hover", underline(Color(DIM, 0.5), 2, tab_pad))
	b.add_theme_stylebox_override("pressed", underline(GOLD, 2, tab_pad))
	b.add_theme_stylebox_override("hover_pressed", underline(GOLD, 2, tab_pad))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	b.add_theme_color_override("font_hover_pressed_color", TEXT)
	b.add_theme_font_size_override("font_size", FS)


## The yellow action button.
static func as_primary(b: Button) -> void:
	var pad := Vector4(12, 4, 12, 4)
	b.add_theme_stylebox_override("normal", box(GOLD, Color(0, 0, 0, 0), 6, pad))
	b.add_theme_stylebox_override("hover", box(GOLD.lightened(0.15), Color(0, 0, 0, 0), 6, pad))
	b.add_theme_stylebox_override("pressed", box(GOLD.darkened(0.15), Color(0, 0, 0, 0), 6, pad))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color(0.08, 0.08, 0.08))
	b.add_theme_font_size_override("font_size", FS)
