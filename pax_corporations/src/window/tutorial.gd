extends RefCounted
## The tutorials: a step-by-step tour in a small panel on the game's HUD; each step opens the place it talks about and
## outlines the button with a pulsing gold frame.
##   • «main» — the big tour of the whole mod: offered once at the start of a new game (it can be declined), always
##     available again from the 🎓 button of the Corporations and Development windows;
##   • a mini tour per window («list», «dossier», «departments», «dev», «techmap») — from the «?» in its corner: what
##     the window is for and what each part does, the parts outlined one by one.
## Texts: data/lang «pax_corporations_tut_<step>_title / _text».

## The steps and what each one opens (main.gd tutorial_action): "" — nothing.
const TOURS := {
	"main": [
		["intro", ""], ["button", "corp_button"], ["dash", "home:news"], ["lists", "tab:country"], ["world", "tab:world"], ["dossier", "dossier:0"],
		["statuses", "dossier:0"], ["conditions", "dossier:0"], ["head", "dossier:0"], ["shares", "dossier:1"], ["owners", "dossier:3"],
		["chronicle", "dossier:5"], ["markets", "tab:markets"], ["arena", "tab:arena"], ["caps", "tab:caps"], ["techlevel", "tab:tech"], ["letters", "tab:letters"],
		["summary", "tab:summary"], ["found", "found"], ["map", "map"], ["departments", "departments"], ["development", "dev:button"],
		["trees", "dev:open"], ["research", "dev:research"], ["techmap", "techmap:open"], ["newspaper", ""], ["corpface", "corpface"], ["corpface_hud", "corpface_hud"], ["orders", ""], ["orders2", ""], ["rank", ""], ["inc3d", ""],
		["life", ""], ["goals", ""], ["end", "help"],
	],
	"home": [
		["h_intro", "home:news"], ["h_top", "home:top"], ["h_market", "home:market"], ["h_deals", "home:deals"],
		["h_trends", "home:trends"], ["h_scope", "home:scope"], ["h_zones", "home:zones"],
	],
	"zones": [
		["z_intro", "zone:z_list"], ["z_kpi", "zone:z_kpi"], ["z_top", "zone:z_top"], ["z_sectors", "zone:z_sectors"],
		["z_rules", "zone:z_rules"], ["z_how", "zone:z_how"],
	],
	"list": [
		["l_intro", "list:tabs"], ["l_strip", "list:strip"], ["l_tools", "list:tools"], ["l_table", "list:table"], ["l_tabs2", "list:tabs"],
		["l_tech", "tab:tech"], ["l_found", "list:found"], ["l_gear", "list:gear"], ["l_big", "list:big"],
	],
	"dossier": [
		["d_head", "dossier_ui:head"], ["d_overview", "dossier_ui:tabs:0"], ["d_shares", "dossier_ui:tabs:1"], ["d_debt", "dossier_ui:tabs:2"],
		["d_owners", "dossier_ui:tabs:3"], ["d_assets", "dossier_ui:tabs:4"], ["d_chronicle", "dossier_ui:tabs:5"], ["d_map", "dossier_ui:map"],
		["d_back", "dossier_ui:back"],
	],
	"departments": [
		["p_intro", "dept:tiles"], ["p_advice", "dept:advice"], ["p_card", "dept:card"], ["p_slider", "dept:slider"],
		["p_antitrust", "dept:mood"], ["p_country", "dept:country"],
	],
	"dev": [
		["v_intro", "dev:open"], ["v_pick", "dev:pick"], ["v_wallet", "dev:wallet"], ["v_bar", "dev:bar"], ["v_advice", "dev:advice"],
		["v_nodes", "dev:open"], ["v_tech", "dev:open"], ["v_research", "dev:research"], ["v_level", "dev:techlevel"], ["v_map", "dev:mode"],
	],
	"techmap": [
		["m_intro", "techmap:open"], ["m_frames", "techmap:open"], ["m_nodes", "techmap:open"], ["m_click", "techmap:open"], ["m_buy", "techmap:open"],
		["m_back", "techmap:mode"],
	],
}
const GOLD := Color(0.95, 0.78, 0.32)

var mod: PaxMod
var game: PaxGame
var action: Callable             # func(what: String) -> Control — opens the place, returns what to outline (main.gd)
var _panel: PanelContainer
var _title: Label
var _text: RichTextLabel
var _count: Label
var _back: Button
var _next: Button
var _frame: Panel
var _offer: PanelContainer
var _step := 0
var _tour := "main"
var _target: Control = null      # the outlined part (the frame follows it)
var _target_scrolls: Array = []
var _token := 0                  # the step being placed (a newer step cancels the older one's placing)
var _steps: Array = []


func setup(m: PaxMod, g: PaxGame, action_cb: Callable) -> void:
	mod = m
	game = g
	action = action_cb


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


func _hud() -> CanvasLayer:
	return game.hud_layer() as CanvasLayer


func running() -> bool:
	return is_instance_valid(_panel)


# ---------- the offer at the start of a new game ----------

func offer() -> void:
	if is_instance_valid(_offer) or running() or bool(mod.get_setting("tutorial_done", false)):
		return
	var hud := _hud()
	if hud == null:
		return
	_offer = _box(Vector2(420, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_offer.add_child(v)
	v.add_child(_label(_t("tut_offer_title"), GOLD, 18))
	var text := _label(_t("tut_offer_text"), Color(1, 1, 1, 0.92), 14)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(390, 0)
	v.add_child(text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	row.add_child(_button(_t("tut_offer_yes"), func() -> void:
		_close_offer()
		start()))
	row.add_child(_button(_t("tut_offer_later"), func() -> void: _close_offer()))
	row.add_child(_button(_t("tut_offer_never"), func() -> void:
		mod.set_setting("tutorial_done", true)
		_close_offer()))
	hud.add_child(_offer)
	_place(_offer)


func _close_offer() -> void:
	if is_instance_valid(_offer):
		_offer.queue_free()
	_offer = null


# ---------- the tour ----------

## tour — «main» (the big one) or a window's mini tour.
func start(tour: String = "main") -> void:
	_close_offer()
	_tour = tour if TOURS.has(tour) else "main"
	_steps = TOURS[_tour]
	if not running():
		_build()
	_show(0)


func stop() -> void:
	_untrack()
	if is_instance_valid(_panel):
		_panel.queue_free()
	if is_instance_valid(_frame):
		_frame.queue_free()
	_panel = null
	_frame = null
	if _tour == "main":
		mod.set_setting("tutorial_done", true)


func _build() -> void:
	var hud := _hud()
	if hud == null:
		return
	_panel = _box(Vector2(460, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_title = _label("", GOLD, 17)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_count = _label("", Color(1, 1, 1, 0.55), 12)
	top.add_child(_count)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(430, 60)
	_text.add_theme_font_size_override("normal_font_size", 14)
	_text.add_theme_font_size_override("bold_font_size", 14)
	v.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_back = _button(_t("tut_back"), func() -> void: _show(_step - 1))
	row.add_child(_back)
	_next = _button(_t("tut_next"), func() -> void:
		if _step >= _steps.size() - 1:
			stop()
		else:
			_show(_step + 1))
	row.add_child(_next)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_button(_t("tut_close"), func() -> void: stop()))
	hud.add_child(_panel)
	_frame = Panel.new()
	_frame.z_index = 65   # over the full-screen Development window (z 40) too
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = GOLD
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	_frame.add_theme_stylebox_override("panel", sb)
	_frame.visible = false
	hud.add_child(_frame)
	var tw := _frame.create_tween().set_loops()
	tw.tween_property(_frame, "modulate:a", 0.35, 0.6)
	tw.tween_property(_frame, "modulate:a", 1.0, 0.6)


func _show(i: int) -> void:
	if not running():
		return
	_step = clampi(i, 0, _steps.size() - 1)
	var key := str(_steps[_step][0])
	_title.text = _t("tut_%s_title" % key)
	_text.text = _t("tut_%s_text" % key)
	_count.text = ("" if _tour == "main" else _t("tut_mini") + " · ") + "%d / %d" % [_step + 1, _steps.size()]
	_back.disabled = _step == 0
	_next.text = _t("tut_finish") if _step == _steps.size() - 1 else _t("tut_next")
	var target: Control = null
	var what := str(_steps[_step][1])
	if not what.is_empty() and action.is_valid():
		var got: Variant = action.call(what)
		if is_instance_valid(got) and got is Control:
			target = got as Control
	_outline(target)


## The gold frame around the control the step is about, and the panel beside it. The window first gets a couple of
## frames to rebuild and lay itself out; then every scrolled area around the part is scrolled so the part is in view;
## then the frame and the panel are put in place — the panel stays hidden until then, so it never jumps.
func _outline(target: Control) -> void:
	if not is_instance_valid(_frame):
		return
	_frame.visible = false
	_untrack()
	_token += 1
	var mine := _token
	if target == null:
		_panel.reset_size()
		_place(_panel)
		_panel.modulate.a = 1.0
		return
	_panel.modulate.a = 0.0
	var tree := game.main.get_tree()
	for i in 3:
		await tree.process_frame
	if mine != _token or not is_instance_valid(target) or not is_instance_valid(_frame):
		return
	var scrolls: Array = []
	var up := target.get_parent()
	while up != null:
		if up is ScrollContainer:
			scrolls.append(up)
		up = up.get_parent()
	# Innermost first: each area scrolls so the part's top is a little below its own top (or the part fits).
	for sc in scrolls:
		_scroll_to(sc as ScrollContainer, target)
		await tree.process_frame
	await tree.process_frame
	if mine != _token or not is_instance_valid(target) or not is_instance_valid(_frame) or not target.is_visible_in_tree():
		if is_instance_valid(_panel):
			_panel.modulate.a = 1.0
		return
	var r := _seen(target, scrolls)
	_put_frame(r)
	_place_beside(r, _window_rect(target))
	_panel.modulate.a = 1.0
	# The frame follows the part every frame — the player may scroll the window or move it.
	_target = target
	_target_scrolls = scrolls
	if not tree.process_frame.is_connected(_track):
		tree.process_frame.connect(_track)


## Only the part that is actually seen: clipped by the scroll areas around it and by the screen; a part scrolled
## out of sight — its scroll area.
func _seen(target: Control, scrolls: Array) -> Rect2:
	var r := target.get_global_rect()
	for sc in scrolls:
		if is_instance_valid(sc):
			r = r.intersection((sc as Control).get_global_rect())
	r = r.intersection(target.get_viewport_rect())
	if r.size.x < 4.0 or r.size.y < 4.0:
		var holder: Control = scrolls[0] if not scrolls.is_empty() and is_instance_valid(scrolls[0]) else null
		r = holder.get_global_rect().intersection(target.get_viewport_rect()) if holder != null else target.get_global_rect()
	return r


func _put_frame(r: Rect2) -> void:
	_frame.position = r.position - Vector2(5, 5)
	_frame.size = r.size + Vector2(10, 10)
	_frame.visible = true


func _track() -> void:
	if not is_instance_valid(_frame) or not is_instance_valid(_target) or not _target.is_visible_in_tree():
		if is_instance_valid(_frame) and _frame.visible and not is_instance_valid(_target):
			_frame.visible = false
		return
	_put_frame(_seen(_target, _target_scrolls))


func _untrack() -> void:
	_target = null
	_target_scrolls = []
	var tree := game.main.get_tree() if game != null and is_instance_valid(game.main) else null
	if tree != null and tree.process_frame.is_connected(_track):
		tree.process_frame.disconnect(_track)


## Scrolls the area so the part is seen: if it is below or above the visible band, its top goes to the band's top
## (a part taller than the band — its top, so the beginning is seen).
static func _scroll_to(sc: ScrollContainer, target: Control) -> void:
	if not is_instance_valid(sc) or not is_instance_valid(target):
		return
	var band := sc.get_global_rect()
	var r := target.get_global_rect()
	var dy := 0.0
	if r.position.y < band.position.y or r.end.y > band.end.y:
		dy = r.position.y - band.position.y - 8.0
	if absf(dy) > 0.5:
		sc.scroll_vertical = maxi(0, sc.scroll_vertical + int(dy))
	var dx := 0.0
	if r.position.x < band.position.x or r.end.x > band.end.x:
		dx = r.position.x - band.position.x - 8.0
	if absf(dx) > 0.5:
		sc.scroll_horizontal = maxi(0, sc.scroll_horizontal + int(dx))


## The window the part belongs to: its outermost control on the HUD layer (the game's window panel, or the mod's
## full-screen Development window).
func _window_rect(target: Control) -> Rect2:
	# The biggest ancestor that is still not the whole screen: the window itself. (The outermost one may be a
	# full-screen holder — «Pax Interface» gathers the whole HUD into one — which is not the window.)
	var view := target.get_viewport_rect().size
	var win: Control = target
	var n: Node = target.get_parent()
	while n != null and not (n is CanvasLayer):
		if n is Control:
			var r := (n as Control).get_global_rect()
			if r.size.x < view.x * 0.9 or r.size.y < view.y * 0.85:
				win = n as Control
			else:
				break
		n = n.get_parent()
	return win.get_global_rect()


## The panel beside the window — right, left, above or below, where it fits on the screen; a window that fills the
## screen (Development) — beside the outlined part instead. It never covers the outlined part.
func _place_beside(part: Rect2, win: Rect2) -> void:
	if not is_instance_valid(_panel):
		return
	_panel.reset_size()
	var view := _panel.get_viewport_rect()
	var sz := _panel.size
	const m := 12.0
	var screen := view.grow(-8.0)
	var big := win.size.x > view.size.x * 0.8 and win.size.y > view.size.y * 0.6
	var around := part if big else win
	var tries: Array = [
		Vector2(around.end.x + m, clampf(part.position.y, screen.position.y, screen.end.y - sz.y)),
		Vector2(around.position.x - sz.x - m, clampf(part.position.y, screen.position.y, screen.end.y - sz.y)),
		Vector2(clampf(part.position.x, screen.position.x, screen.end.x - sz.x), around.position.y - sz.y - m),
		Vector2(clampf(part.position.x, screen.position.x, screen.end.x - sz.x), around.end.y + m),
	]
	# Then beside the part itself, whatever the window.
	tries.append(Vector2(part.end.x + m, clampf(part.position.y, screen.position.y, screen.end.y - sz.y)))
	tries.append(Vector2(part.position.x - sz.x - m, clampf(part.position.y, screen.position.y, screen.end.y - sz.y)))
	tries.append(Vector2(clampf(part.position.x, screen.position.x, screen.end.x - sz.x), part.position.y - sz.y - m))
	tries.append(Vector2(clampf(part.position.x, screen.position.x, screen.end.x - sz.x), part.end.y + m))
	for p in tries:
		var r := Rect2(p, sz)
		if screen.encloses(r) and not r.intersects(part.grow(6.0)):
			_panel.position = p
			return
	# Nothing fits cleanly: the screen corner farthest from the part.
	var corners := [screen.position, Vector2(screen.end.x - sz.x, screen.position.y), Vector2(screen.position.x, screen.end.y - sz.y), screen.end - sz]
	var best: Vector2 = corners[0]
	for c in corners:
		if (Rect2(c, sz).get_center() - part.get_center()).length() > (Rect2(best, sz).get_center() - part.get_center()).length():
			best = c
	_panel.position = best


## Bottom-left, above the game's bottom bar.
func _place(c: Control) -> void:
	var view := c.get_viewport_rect().size
	c.reset_size()
	c.position = Vector2(16.0, maxf(16.0, view.y - c.size.y - 110.0))


func _box(min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	p.z_index = 66
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.96)
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func teardown() -> void:
	_untrack()
	_close_offer()
	if is_instance_valid(_panel):
		_panel.queue_free()
	if is_instance_valid(_frame):
		_frame.queue_free()
	_panel = null
	_frame = null
