extends RefCounted
## Unread counters on the bottom bar's buttons (a red circle with a number in the button's corner; hidden at 0):
##   «Корпорации» — the mod's unread letters + an unread «Сводка» after a time skip;
##   «Связи» — the game's unread letters of countries (each faction's «непрочитано») and organisations;
##   the projects (science) button — the game's unread science news (Main._новостей_науки);
##   the path button — new stages (Main._новые_этапы).
## The game's buttons are only decorated: a child Control is added to each; teardown() removes it.

const BADGE := "PaxCorpBadge"
const RED := Color(0.86, 0.2, 0.18)

var _buttons: Array = []         # Buttons that got a badge (to clean up)


## counts: [[Button, int], …]
func update(counts: Array) -> void:
	for pair in counts:
		var b: Variant = pair[0]
		if not is_instance_valid(b) or not (b is Button):
			continue
		_set_badge(b as Button, int(pair[1]))


func _set_badge(b: Button, n: int) -> void:
	var badge: PanelContainer = b.get_node_or_null(BADGE) as PanelContainer
	if n <= 0:
		if badge != null:
			badge.visible = false
		return
	if badge == null:
		badge = PanelContainer.new()
		badge.name = BADGE
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.z_index = 5
		var sb := StyleBoxFlat.new()
		sb.bg_color = RED
		sb.set_corner_radius_all(9)
		sb.border_color = Color(0, 0, 0, 0.6)
		sb.set_border_width_all(1)
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		badge.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.name = "N"
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(l)
		b.add_child(badge)
		_buttons.append(b)
	(badge.get_node("N") as Label).text = "99+" if n > 99 else str(n)
	badge.visible = true
	badge.reset_size()
	badge.position = Vector2(b.size.x - badge.size.x * 0.75, -badge.size.y * 0.35)


func teardown() -> void:
	for b in _buttons:
		if is_instance_valid(b):
			var badge: Node = (b as Node).get_node_or_null(BADGE)
			if badge != null:
				badge.queue_free()
	_buttons.clear()


# ---------- what is unread in the game ----------

## Unread letters of countries and organisations (the «Связи» window).
static func game_inbox(game: PaxGame) -> int:
	var n := 0
	for f in game.factions():
		if f is Dictionary:
			n += _count((f as Dictionary).get("непрочитано", 0))
	var orgs: Variant = game.main.get("организации")
	if orgs is Array:
		for o in orgs:
			if o is Dictionary:
				n += _count((o as Dictionary).get("непрочитано", 0))
	return n


static func _count(v: Variant) -> int:
	if v is bool:
		return 1 if v else 0
	if v is int or v is float:
		return maxi(0, int(v))
	if v is Array:
		return (v as Array).size()
	return 0


## A Main property with a count of new things (an int, a bool or an Array).
static func main_count(game: PaxGame, prop: String) -> int:
	return _count(game.main.get(prop))


## The bottom bar's button that shows `title` (a window added with game.add_window).
static func bar_button(game: PaxGame, title: String) -> Button:
	var bar: Variant = game.main.get("низ_кнопки")
	if not (is_instance_valid(bar) and bar is Node):
		return _find_button(game.main as Node, title.strip_edges(), 0)
	for ch in (bar as Node).get_children():
		if ch is Button and (ch as Button).text.strip_edges().contains(title.strip_edges()):
			return ch as Button
	# Windows of mods may sit in another bar: look through the HUD once (main.gd keeps the result).
	return _find_button(game.main as Node, title.strip_edges(), 0)


static func _find_button(n: Node, title: String, depth: int) -> Button:
	if n == null or depth > 8:
		return null
	for ch in n.get_children():
		if ch is Button and (ch as Button).text.strip_edges() == title:
			return ch as Button
		var found := _find_button(ch, title, depth + 1)
		if found != null:
			return found
	return null
