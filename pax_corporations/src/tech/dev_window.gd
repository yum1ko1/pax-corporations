extends Control
## «Развитие» — a full-screen window over the map (the bottom bar's button next to «Корпорации»): the country's
## «Гос вложения», the industry picker and the development tree (tree.gd, tree_view.gd) as large as the screen allows.
## Esc or ✕ closes it. Looks: ui_style.gd; the AI advisor speaks above the tree (advisor.gd).

const DevTree := preload("res://mods/pax_corporations/src/tech/tree.gd")
const TreeView := preload("res://mods/pax_corporations/src/tech/tree_view.gd")
const TechMap := preload("res://mods/pax_corporations/src/tech/tech_map.gd")
const TechLevelView := preload("res://mods/pax_corporations/src/tech/techlevel_view.gd")
const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const UiStyle := preload("res://mods/pax_corporations/src/look/ui_style.gd")
const Advisor := preload("res://mods/pax_corporations/src/news/advisor.gd")
const GOLD := UiStyle.GOLD
const DIM := UiStyle.DIM
const NO_COL := Color(0.4, 0.9, 1.0)   # «НО» — scientific discoveries

var mod: PaxMod
var game: PaxGame
var db: Data
var tree: DevTree
var on_open_company: Callable    # func(company id) — the dossier (closes this window)
var capabilities: Object         # capabilities.gd — «Открывает: …» on the nodes
var techlevel: Object            # techlevel.gd — the technology level over the research trees
var sector := "it"
var _frame: PanelContainer      # the header in a frame of the industry's colour
var _head: HBoxContainer
var _info: VBoxContainer
var _view: TreeView
var _map: TechMap                # «Технологии нового времени» (tech_map.gd)
var _mode := "tree"              # "tree" — an industry's tree; "map" — the technologies of the new time
var on_help: Callable            # func(tour) — the tutorials (tutorial.gd)
var _tut: Dictionary = {}


func setup(m: PaxMod, g: PaxGame, d: Data, t: DevTree) -> void:
	mod = m
	game = g
	db = d
	tree = t
	name = "PaxCorporationsDevelopment"
	set_meta(&"pax_covers_hud", true)   # full-screen: Pax Corpface hides its floating buttons (the chronicle's) under it
	theme = UiStyle.theme()
	set_meta(&"pax_corp_skin_skip", true)
	set_meta(&"pax_interface_skip_skin", true)   # «Pax Interface» does not reskin our window
	visible = false
	z_index = 40
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(UiStyle.BG, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 20
	v.offset_right = -20
	v.offset_top = 14
	v.offset_bottom = -90   # the game's bottom bar stays visible
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	_frame = PanelContainer.new()
	v.add_child(_frame)
	_head = HBoxContainer.new()
	_head.add_theme_constant_override("separation", 14)
	_frame.add_child(_head)
	_info = VBoxContainer.new()
	v.add_child(_info)
	_view = TreeView.new()
	_view.custom_minimum_size = Vector2(400, 400)
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.on_pick = _pick
	v.add_child(_view)
	_map = TechMap.new()
	_map.mod = mod
	_map.custom_minimum_size = Vector2(400, 400)
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.visible = false
	_map.on_node = func(s: String, id: String) -> void:
		# A node of the map: to its industry's tree, where it flashes for a few seconds.
		_mode = "tree"
		sector = s
		refresh()
		_view.flash(id)
	v.add_child(_map)


## The parts of this window a tutorial outlines (tutorial.gd), by name.
func tut_target(part: String) -> Control:
	var c: Variant = _tut.get(part)
	return c as Control if is_instance_valid(c) else null


## The tutorial puts the window in a mode and an industry (tutorial.gd through main.gd).
func show_for_tutorial(mode: String, sector_key: String = "") -> void:
	visible = true
	_mode = mode
	if not sector_key.is_empty():
		sector = sector_key
	refresh()


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()


func _label(text: String, color: Color, fs: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if fs > 0:
		l.add_theme_font_size_override("font_size", fs)
	return l


func refresh() -> void:
	if not visible or tree == null:
		return
	for ch in _head.get_children():
		ch.queue_free()
	for ch in _info.get_children():
		ch.queue_free()
	var me := str(game.player_faction().get("name", ""))
	var accent := _view._col((tree.trees().get(sector, {}) as Dictionary).get("colour"), GOLD)
	_frame.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, accent, 10, Vector4(18, 10, 12, 10), 2))
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -2)
	title.add_child(_label(_t("dev_title"), GOLD, 22))
	title.add_child(_label(_t("dev_sub") % db.sector_name(sector), Color(accent, 0.85), 12))
	_head.add_child(title)
	_head.add_child(_sep(accent))
	var pick := OptionButton.new()
	pick.focus_mode = Control.FOCUS_NONE
	pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var keys: Array = db.sectors.keys()
	for i in keys.size():
		var k := str(keys[i])
		pick.add_item(db.sector_name(k) + ("" if tree.has_tree(k) else "  · " + _t("tree_soon")), i)
		pick.set_item_disabled(i, not tree.has_tree(k))
		if k == sector:
			pick.select(i)
	pick.item_selected.connect(func(i: int) -> void:
		sector = str(keys[i])
		refresh())
	_head.add_child(pick)
	_tut["pick"] = pick
	var mode_btn := Button.new()
	mode_btn.text = _t("techmap_back") if _mode == "map" else "⚛ " + _t("techmap_open")
	mode_btn.focus_mode = Control.FOCUS_NONE
	mode_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_btn.tooltip_text = _t("techmap_tip")
	if _mode != "map":
		UiStyle.as_primary(mode_btn)
	mode_btn.pressed.connect(func() -> void:
		_mode = "tree" if _mode == "map" else "map"
		refresh())
	_head.add_child(mode_btn)
	_tut["mode"] = mode_btn
	_head.add_child(_sep(accent))
	# The tree's currency: «Гос вложения» (a gold chip with a diamond) or, for AI, science and space, «НО» —
	# scientific discoveries (a cyan chip with an atom), slower and only for those three trees.
	var research := tree.currency(sector) == "but_value"
	var g := tree.wallet(me, sector)
	var wallet := UiStyle.pill(("⚛  " + _t("tree_no") if research else "◆  " + _t("tree_gv")) % int(g["has_flag"]), NO_COL if research else GOLD, 18)
	_head.add_child(wallet)
	_tut["wallet"] = wallet
	wallet.tooltip_text = _breakdown(g, research)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(220, 8)
	bar.show_percentage = false
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("fill", UiStyle.box(accent, Color(0, 0, 0, 0), 4, Vector4.ZERO))
	var need := tree.threshold_for(sector, int(g.get("получено", 0)))
	bar.max_value = need
	bar.value = float(g.get("прогресс", 0.0))
	bar.tooltip_text = _breakdown(g, research)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP   # the tooltip needs the mouse
	_head.add_child(bar)
	_tut["bar"] = bar
	var nl := _label(_t("tree_next") % [db._num(float(g.get("прогресс", 0.0)), 1), db._num(need, 1)], DIM)
	nl.tooltip_text = bar.tooltip_text
	nl.mouse_filter = Control.MOUSE_FILTER_PASS
	_head.add_child(nl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(sp)
	for hb in [["?", "tut_mini_tip", "techmap" if _mode == "map" else "dev"], ["🎓", "tut_big_tip", "main"]]:
		var hbtn := Button.new()
		hbtn.text = str(hb[0])
		hbtn.tooltip_text = _t(str(hb[1]))
		hbtn.focus_mode = Control.FOCUS_NONE
		hbtn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tour := str(hb[2])
		hbtn.pressed.connect(func() -> void:
			if on_help.is_valid():
				on_help.call(tour))
		_head.add_child(hbtn)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.flat = true
	close.add_theme_font_size_override("font_size", 20)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: visible = false)
	_head.add_child(close)
	# The AI advisor: red news when the industry is empty, else the leader (a link) and how the tree works.
	var list := tree.members(db, me, sector)
	var alarm := list.is_empty()
	var text := _t("advisor_no_companies") % db.sector_name(sector) if alarm else _t("advisor_leader") % [db.sector_name(sector), list.size()]
	var link: Button = null
	if not alarm:
		var lead: Dictionary = list[0]
		var lid := str(lead["id"])
		link = Button.new()
		link.text = "→ " + db.name_of(lead)
		link.flat = true
		link.focus_mode = Control.FOCUS_NONE
		link.alignment = HORIZONTAL_ALIGNMENT_LEFT
		link.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		link.add_theme_color_override("font_color", GOLD)
		link.pressed.connect(func() -> void:
			visible = false
			if on_open_company.is_valid():
				on_open_company.call(lid))
	if _mode == "map":
		text = _t("techmap_hint")
		alarm = false
		link = null
	var adv := Advisor.new()
	if _mode == "map":
		adv.setup(mod, "techmap", text, false, null)
	else:
		adv.setup(mod, "dev_no" if research else "dev", text + "\n" + _t("tree_hint_no" if research else "tree_hint"), alarm, link)
	_info.add_child(adv)
	# Over a research tree (AI, science, space): where the country's best company stands in the world.
	if _mode == "tree" and techlevel != null and sector in ["ии", "наука", "космос"]:
		var lv := TechLevelView.new()
		lv.build(mod, techlevel, db, me, sector)
		_info.add_child(lv)
		_tut["techlevel"] = lv
	_tut["advice"] = adv
	_tut["tree"] = _view
	_tut["map"] = _map
	_view.tree = tree
	_view.db = db
	_view.mod = mod
	_view.country = me
	_view.sector = sector
	_view.capabilities = capabilities
	_view.queue_redraw()
	_view.visible = _mode == "tree"
	_map.visible = _mode == "map"
	_map.caps = capabilities
	_map.tree = tree
	_map.db = db
	_map.country = me


## A thin vertical divider in the header.
func _sep(col: Color) -> Control:
	var s := ColorRect.new()
	s.color = Color(col, 0.35)
	s.custom_minimum_size = Vector2(2, 34)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


## Where the points come from: every source with its share of this week (0 before the first week is counted).
func _breakdown(g: Dictionary, research: bool) -> String:
	var pre := "tree_no_" if research else "tree_gv_"
	var parts: Dictionary = g.get("breakdown", {})
	var keys: Array = ["выручка", "топ"] if research else ["рост", "top100", "stability", "новые", "bankruptcies", "investors"]
	for k in parts.keys():
		if not (k in keys):
			keys.append(k)
	var lines: PackedStringArray = [_t(pre + "week") % db._num(float(g.get("per_week", 0.0)), 2), _t("tree_sources")]
	for k in keys:
		var v := float(parts.get(k, 0.0))
		lines.append("  %s: %s" % [_t(pre + str(k)), ("+" if v >= 0.0 else "−") + db._num(absf(v), 2)])
	if parts.is_empty():
		lines.append(_t("tree_sources_wait"))
	lines.append(_t(pre + "total") % int(g.get("получено", 0)))
	return "
".join(lines)


## A click on a node: buy it after a confirmation, or say why not.
func _pick(id: String) -> void:
	var me := str(game.player_faction().get("name", ""))
	var why := tree.can_buy(db, me, sector, id)
	if not why.is_empty():
		game.toast(_t("tree_why_" + why))
		return
	var nd := tree.node(sector, id)
	var dlg := ConfirmationDialog.new()
	dlg.title = _t("tree_confirm_title")
	dlg.dialog_text = _t("tree_confirm_no" if tree.currency(sector) == "but_value" else "tree_confirm") % [int(nd.get("price", 1)), db.text(nd.get("name", "")), db.sector_name(sector)] + "\n\n" + _view.describe(id)
	dlg.ok_button_text = _t("tree_confirm_ok")
	dlg.confirmed.connect(func() -> void:
		if tree.buy(db, me, sector, id, game.day()):
			db.recompute()
			game.toast(_t("tree_bought") % db.text(nd.get("name", "")))
		refresh()
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()
