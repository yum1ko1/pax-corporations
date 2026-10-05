extends Node
## The game's own interface in the mod's look (ui_style.gd): panels, buttons, tabs, inputs, sliders, scroll bars,
## separators, progress bars, lists, tooltips and popup menus of the whole game — the HUD, its windows and menus.
## Reversible: every override replaced is remembered and put back on restore(). It changes neither layout nor
## callbacks: margins and sizes stay the game's, only colours, borders and corners change. Coloured (meaningful)
## fills and texts — factions, warnings — are kept. The mod's own windows (meta «pax_corp_skin_skip») are left
## alone, and so is everything when the «Pax Interface» mod already skins the game.

const UiStyle := preload("res://mods/pax_corporations/src/look/ui_style.gd")
const SKIP := &"pax_corp_skin_skip"
const BUTTON_STYLES: Array[StringName] = [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]

var _records: Dictionary = {}     # instance id -> {node: WeakRef, styles: {}, colors: {}}
var _active := false
var _root_theme: Theme             # the root window's theme before ours
var _root_set := false


func start() -> void:
	if _active or not is_inside_tree():
		return
	if _other_skin():
		return
	_active = true
	var tree := get_tree()
	if not tree.node_added.is_connected(_node_added):
		tree.node_added.connect(_node_added)
	# Tooltips and popup menus come from the root window's theme (the game's controls rarely carry their own).
	var root := tree.root
	_root_theme = root.theme
	var t := _root_theme.duplicate() as Theme if _root_theme != null else Theme.new()
	var tip := UiStyle.box(UiStyle.SOLID_PANEL2, UiStyle.SOLID_LINE, 6, Vector4(10, 6, 10, 6))
	t.set_stylebox(&"panel", &"TooltipPanel", tip)
	t.set_color(&"font_color", &"TooltipLabel", UiStyle.TEXT)
	t.set_stylebox(&"panel", &"PopupMenu", UiStyle.box(UiStyle.SOLID_PANEL2, UiStyle.SOLID_LINE, 6, Vector4(6, 6, 6, 6)))
	t.set_stylebox(&"hover", &"PopupMenu", UiStyle.box(Color(UiStyle.GOLD, 0.16), Color(0, 0, 0, 0), 4, Vector4(6, 2, 6, 2)))
	t.set_color(&"font_color", &"PopupMenu", UiStyle.TEXT)
	t.set_color(&"font_hover_color", &"PopupMenu", UiStyle.GOLD)
	root.theme = t
	_root_set = true
	_visit(root)


func restore() -> void:
	_active = false
	if is_inside_tree() and get_tree().node_added.is_connected(_node_added):
		get_tree().node_added.disconnect(_node_added)
	for id: Variant in _records.keys():
		var rec: Dictionary = _records[id]
		var c := (rec["node"] as WeakRef).get_ref() as Control
		if is_instance_valid(c):
			_put_back(c, rec)
	_records.clear()
	if _root_set and is_inside_tree():
		get_tree().root.theme = _root_theme
	_root_set = false


## Forgets the records of controls that are gone.
func _purge() -> void:
	for id: Variant in _records.keys():
		if not is_instance_valid((_records[id] as Dictionary)["node"].get_ref()):
			_records.erase(id)


func _exit_tree() -> void:
	restore()


## «Pax Interface» skins the game itself — two skins would fight over the same controls.
func _other_skin() -> bool:
	for n in get_tree().root.find_children("PaxInterfaceHUD", "", true, false):
		if is_instance_valid(n):
			return true
	return false


func _visit(node: Node) -> void:
	if node.has_meta(SKIP):
		return
	if node is Control:
		_skin(node as Control)
	for ch in node.get_children():
		_visit(ch)


func _node_added(node: Node) -> void:
	if _active and node is Control:
		_later.call_deferred(weakref(node))   # its creator sets its overrides right after adding it


func _later(ref: WeakRef) -> void:
	var c := ref.get_ref() as Control
	if _active and is_instance_valid(c) and c.is_inside_tree() and not _skipped(c):
		_skin(c)


func _skipped(node: Node) -> bool:
	var n := node
	while n != null:
		if n.has_meta(SKIP):
			return true
		n = n.get_parent()
	return false


func _skin(c: Control) -> void:
	var id := c.get_instance_id()
	if _records.has(id):
		return
	var rec := {"node": weakref(c), "styles": {}, "colors": {}}
	_records[id] = rec
	if _records.size() > 6000:
		_purge()
	if c is TextureButton or c is LinkButton:
		return
	if c is BaseButton:
		_button(c as BaseButton, rec)
	elif c is PanelContainer or c is Panel:
		var old := c.get_theme_stylebox(&"panel")
		if _solid(old):
			_put_style(c, rec, &"panel", _like(old, Color(UiStyle.SOLID_PANEL, maxf(_alpha(old), 0.94)), UiStyle.SOLID_LINE, 8))
	elif c is LineEdit or c is TextEdit:
		_put_style(c, rec, &"normal", _like(c.get_theme_stylebox(&"normal"), UiStyle.SOLID_PANEL2, UiStyle.SOLID_LINE, 6))
		_put_style(c, rec, &"focus", _like(c.get_theme_stylebox(&"focus"), Color(0, 0, 0, 0), UiStyle.GOLD, 6))
		_color(c, rec, &"caret_color", UiStyle.GOLD)
		_color(c, rec, &"selection_color", Color(UiStyle.GOLD, 0.3))
	elif c is TabContainer or c is TabBar:
		if c is TabContainer:
			var p := c.get_theme_stylebox(&"panel")
			if _solid(p):
				_put_style(c, rec, &"panel", _like(p, UiStyle.SOLID_PANEL, UiStyle.SOLID_LINE, 8))
		var pad := c.get_theme_stylebox(&"tab_selected")
		_put_style(c, rec, &"tab_selected", _under(pad, UiStyle.GOLD))
		_put_style(c, rec, &"tab_unselected", _under(c.get_theme_stylebox(&"tab_unselected"), Color(0, 0, 0, 0)))
		_put_style(c, rec, &"tab_hovered", _under(c.get_theme_stylebox(&"tab_hovered"), Color(UiStyle.DIM, 0.5)))
		_neutral(c, rec, &"font_selected_color", UiStyle.TEXT)
		_neutral(c, rec, &"font_unselected_color", UiStyle.DIM)
		_neutral(c, rec, &"font_hovered_color", UiStyle.TEXT)
	elif c is Slider:
		_put_style(c, rec, &"slider", _like(c.get_theme_stylebox(&"slider"), UiStyle.SOLID_LINE, Color(0, 0, 0, 0), 3))
		_put_style(c, rec, &"grabber_area", _like(c.get_theme_stylebox(&"grabber_area"), UiStyle.GOLD, Color(0, 0, 0, 0), 3))
		_put_style(c, rec, &"grabber_area_highlight", _like(c.get_theme_stylebox(&"grabber_area_highlight"), UiStyle.GOLD.lightened(0.2), Color(0, 0, 0, 0), 3))
	elif c is ScrollBar:
		_put_style(c, rec, &"scroll", _like(c.get_theme_stylebox(&"scroll"), Color(0, 0, 0, 0), Color(0, 0, 0, 0), 3))
		_put_style(c, rec, &"grabber", _like(c.get_theme_stylebox(&"grabber"), UiStyle.SOLID_LINE, Color(0, 0, 0, 0), 3))
		_put_style(c, rec, &"grabber_highlight", _like(c.get_theme_stylebox(&"grabber_highlight"), UiStyle.DIM, Color(0, 0, 0, 0), 3))
		_put_style(c, rec, &"grabber_pressed", _like(c.get_theme_stylebox(&"grabber_pressed"), UiStyle.GOLD, Color(0, 0, 0, 0), 3))
	elif c is HSeparator or c is VSeparator:
		var line := StyleBoxLine.new()
		line.color = UiStyle.SOLID_LINE
		line.thickness = 1
		line.vertical = c is VSeparator
		_put_style(c, rec, &"separator", line)
	elif c is ProgressBar:
		_put_style(c, rec, &"background", _like(c.get_theme_stylebox(&"background"), UiStyle.SOLID_PANEL2, Color(0, 0, 0, 0), 4))
		var fill := c.get_theme_stylebox(&"fill")
		if not _meaningful(fill):
			_put_style(c, rec, &"fill", _like(fill, UiStyle.GOLD, Color(0, 0, 0, 0), 4))
	elif c is Tree or c is ItemList:
		var p2 := c.get_theme_stylebox(&"panel")
		if _solid(p2):
			_put_style(c, rec, &"panel", _like(p2, UiStyle.SOLID_PANEL, UiStyle.SOLID_LINE, 6))
		_put_style(c, rec, &"selected", _like(c.get_theme_stylebox(&"selected"), Color(UiStyle.GOLD, 0.16), Color(UiStyle.GOLD, 0.6), 4))
		_put_style(c, rec, &"selected_focus", _like(c.get_theme_stylebox(&"selected_focus"), Color(UiStyle.GOLD, 0.2), UiStyle.GOLD, 4))
	if c is Label or c is LineEdit or c is TextEdit or c is Tree or c is ItemList:
		_neutral(c, rec, &"font_color", UiStyle.TEXT)
	elif c is RichTextLabel:
		_neutral(c, rec, &"default_color", UiStyle.TEXT)


## Buttons: dark pills, a yellow edge under the mouse, yellow-tinted when pressed or chosen. Flat buttons and
## buttons with a meaningful colour of their own keep their look; their text is still evened out.
func _button(b: BaseButton, rec: Dictionary) -> void:
	var normal := b.get_theme_stylebox(&"normal")
	var flat := b is Button and (b as Button).flat
	if not flat and _solid(normal) and not _meaningful(normal):
		_put_style(b, rec, &"normal", _like(normal, UiStyle.SOLID_PANEL2, UiStyle.SOLID_LINE, 6))
		_put_style(b, rec, &"hover", _like(normal, UiStyle.SOLID_LINE, Color(UiStyle.GOLD, 0.55), 6))
		_put_style(b, rec, &"pressed", _like(normal, Color(UiStyle.GOLD, 0.16), UiStyle.GOLD, 6))
		_put_style(b, rec, &"hover_pressed", _like(normal, Color(UiStyle.GOLD, 0.22), UiStyle.GOLD, 6))
		_put_style(b, rec, &"disabled", _like(normal, UiStyle.SOLID_PANEL, UiStyle.SOLID_LINE, 6))
		_put_style(b, rec, &"focus", StyleBoxEmpty.new())
	_neutral(b, rec, &"font_color", UiStyle.TEXT)
	_neutral(b, rec, &"font_hover_color", Color.WHITE)
	_neutral(b, rec, &"font_pressed_color", UiStyle.GOLD)
	_neutral(b, rec, &"font_hover_pressed_color", UiStyle.GOLD)
	_neutral(b, rec, &"font_disabled_color", Color(UiStyle.DIM, 0.6))


## A box that is actually drawn (not an empty layout box).
func _solid(sb: StyleBox) -> bool:
	if sb is StyleBoxFlat:
		var f := sb as StyleBoxFlat
		return f.draw_center and f.bg_color.a > 0.05 or (f.border_color.a > 0.05 and f.get_border_width_min() > 0)
	return sb is StyleBoxTexture


## A fill of its own colour (red, green, a faction's) — it means something, so it stays.
func _meaningful(sb: StyleBox) -> bool:
	if sb is StyleBoxFlat:
		var col := (sb as StyleBoxFlat).bg_color
		return col.s > 0.45 and col.v > 0.3 and col.a > 0.3
	return false


func _alpha(sb: StyleBox) -> float:
	return (sb as StyleBoxFlat).bg_color.a if sb is StyleBoxFlat else 1.0


## Our colours on the old box's margins (the layout stays the game's).
func _like(old: StyleBox, fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var b := UiStyle.box(fill, border, radius, Vector4.ZERO)
	if old != null:
		b.content_margin_left = old.get_margin(SIDE_LEFT)
		b.content_margin_right = old.get_margin(SIDE_RIGHT)
		b.content_margin_top = old.get_margin(SIDE_TOP)
		b.content_margin_bottom = old.get_margin(SIDE_BOTTOM)
	return b


## A tab: only a line under it.
func _under(old: StyleBox, col: Color) -> StyleBoxFlat:
	var b := _like(old, Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
	b.border_color = col
	b.border_width_bottom = 2
	return b


func _put_style(c: Control, rec: Dictionary, key: StringName, sb: StyleBox) -> void:
	var styles: Dictionary = rec["styles"]
	if not styles.has(key):
		styles[key] = [c.has_theme_stylebox_override(key), c.get_theme_stylebox(key) if c.has_theme_stylebox_override(key) else null]
	c.add_theme_stylebox_override(key, sb)


func _color(c: Control, rec: Dictionary, key: StringName, col: Color) -> void:
	var colors: Dictionary = rec["colors"]
	if not colors.has(key):
		colors[key] = [c.has_theme_color_override(key), c.get_theme_color(key)]
	c.add_theme_color_override(key, col)


## Only grey/white text is evened out; coloured text (warnings, factions, money) keeps its colour.
func _neutral(c: Control, rec: Dictionary, key: StringName, col: Color) -> void:
	var now := c.get_theme_color(key)
	if now.s < 0.3:
		_color(c, rec, key, Color(col, now.a if now.a < 1.0 else col.a))


func _put_back(c: Control, rec: Dictionary) -> void:
	var styles: Dictionary = rec["styles"]
	for key: Variant in styles.keys():
		var s: Array = styles[key]
		if bool(s[0]):
			c.add_theme_stylebox_override(key, s[1] as StyleBox)
		else:
			c.remove_theme_stylebox_override(key)
	var colors: Dictionary = rec["colors"]
	for key: Variant in colors.keys():
		var k: Array = colors[key]
		if bool(k[0]):
			c.add_theme_color_override(key, k[1] as Color)
		else:
			c.remove_theme_color_override(key)
