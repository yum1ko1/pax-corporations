extends RefCounted
## The mod's windows: building them, the links between the map and the main window, the tutorial's actions, the bar's badges.
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")   # Main's methods, 0.24 names
const Host := preload("res://mods/pax_corporations/main.gd")

var app: Host   # the host: its modules and data
var _button_search := 0.0


func _init(host: Host) -> void:
	app = host


## «State departments» — its own button in the bottom bar.
func _build_departments_window(game: PaxGame) -> void:
	app._dept_window = Host.DepartmentsWindow.new()
	app._dept_window.treasury_year = app.treasury_year
	app._dept_window.antitrust = app.antitrust
	app._dept_window.on_help = func(tour: String) -> void: app.tutorial.start(tour)
	app._dept_window.setup(app, game, app.db, app.departments, app.goods)
	app._dept_panel = game.add_window(app.tr_key("pax_corporations_dept_button"), app._dept_window, Vector2(740, 580))
	var dp := app._dept_panel
	(func() -> void: Host.Glass.apply(dp)).call_deferred()
	app._dept_panel.visibility_changed.connect(func() -> void:
		if is_instance_valid(app._dept_window) and app._dept_panel.is_visible_in_tree():
			app._dept_window.refresh())


## «Развитие»: a full-screen window over the map, opened by its own bottom button next to «Корпорации».
func _build_development(game: PaxGame) -> void:
	app._dev = Host.DevWindow.new()
	app._dev.setup(app, game, app.db, app.tree)
	app._dev.capabilities = app.capabilities
	app._dev.techlevel = app.techlevel
	app._dev.on_help = func(tour: String) -> void: app.tutorial.start(tour)
	app._dev.on_open_company = func(cid: String) -> void:
		if is_instance_valid(app._window):
			app._window.open_company(cid)
	var hud: Variant = game.hud_layer()
	if hud is Node:
		(hud as Node).add_child(app._dev)
	app._dev_button = game.add_bottom_button(app.tr_key("pax_corporations_dev_button"), func() -> void:
		_close_window()
		app._dev.toggle())
	app._dev_button.tooltip_text = app.tr_key("pax_corporations_dev_button_tip")
	# Right after the «Корпорации» button.
	var corp := Host.Badges.bar_button(game, app.tr_key("pax_corporations_button"))
	if corp != null and corp.get_parent() == app._dev_button.get_parent():
		app._dev_button.get_parent().move_child(app._dev_button, corp.get_index() + 1)


func _build_window(game: PaxGame, favs: Variant) -> void:
	app._window = Host.CorpWindow.new()
	app._window.on_show_on_map = _show_on_map
	app._window.on_show_point = _show_point
	app._window.events = app.events
	app._window.treasury_year = app.treasury_year
	app._window.digest = app.digest
	app._window.politics = app.politics
	app._window.goods = app.goods
	app._window.rivals = app.rivals
	app._window.on_ask_ai = app.ask_assistant
	app._window.on_found = app.found_company
	app._window.narrator = app.narrator
	app._window.on_close = _close_window
	app._window.on_found_preview = app.founding_preview
	app._window.on_pick_place = app.pick_place
	app._window.founding_info = app.founding_info
	app._window.ai_available = func() -> bool: return GameApi.has(app._game.main, "_спросить_помощника")
	app._window.on_trade = app.trade
	app._window.on_quote = app.quote_trade
	app._window.treasury_money = app.treasury_money
	app._window.letters = app.letters
	app._window.orders = app.orders
	app._window.arena = app.arena
	app._window.influence = app.influence
	app._window.on_write_head = app.write_head
	app._window.on_hud_skin = app.set_hud_skin
	app._window.on_buildings = app.set_buildings_3d
	app._window.investments = app.investments
	app._window.conditions = app.conditions
	app._window.capabilities = app.capabilities
	app._window.techlevel = app.techlevel
	app._window.lifecycle = app.lifecycle
	if favs is Array:
		for f in favs:
			app._window.favorites[str(f)] = true
	app._window.setup(app, game, app.db)
	app._drop_bar_buttons()   # leftovers of an earlier start (none normally)
	app._panel = game.add_window(app.tr_key("pax_corporations_button"), app._window, Vector2(800, 560))
	var wp := app._panel
	(func() -> void: Host.Glass.apply(wp)).call_deferred()
	app.log_info("window ready")
	app._window.panel = app._panel
	app._panel.visibility_changed.connect(func() -> void:
		if is_instance_valid(app._window) and app._panel.is_visible_in_tree():
			app._window.refresh())


## Where the corporations' layer draws: the game's political map while it is open, else the 3D Earth (play from
## orbit — the flat map closed or turned off), else the closed political map (another planet, the system).
func layer_target() -> CanvasLayer:
	var raw: Variant = app._game.main.get("полит_карта")
	var real: CanvasLayer = raw if raw is CanvasLayer else null
	if not is_instance_valid(app._globe):
		app._globe = Host.GlobeMap.new()
		app.add_child(app._globe)
	app._globe.setup(app._game, real)
	if real != null and real.visible:
		return real
	return app._globe if app._globe.wanted() else real


func _attach_layer() -> void:
	if is_instance_valid(app._layer):
		app._layer.detach()
	var target := layer_target()
	if target == null:
		app._layer = null
		return
	app._layer = Host.MapLayer.new()
	app._layer.on_background = _close_window
	app._layer.zones_on = bool(app.get_setting("zones_layer", false))
	app._layer.on_zone = app.open_zone
	if not app._layer.attach(app, app._game, app.db, _open_from_map, target):
		app._layer.queue_free()
		app._layer = null
	elif app.bank != null:
		app._layer.bank = app.bank
		app._layer.tree_ref = app.tree


## A click on the empty map closes the «Corporations» window (the bottom button still toggles it).
func _close_window() -> void:
	if not is_instance_valid(app._panel) or not app._panel.is_visible_in_tree():
		return
	if GameApi.has(app._game.main, "_переключить_окно"):
		GameApi.call_main(app._game.main, "_переключить_окно", [app._panel])
	if app._panel.is_visible_in_tree():
		app._panel.hide()


## A tutorial step opens its place and returns the control to outline (tutorial.gd).
func tutorial_action(what: String) -> Control:
	if not is_instance_valid(app._window):
		return null
	# The Development window: its parts (a tree, or the technologies map), shown full-screen over the map.
	if what.begins_with("dev:") or what.begins_with("techmap:"):
		_close_window()
		if not is_instance_valid(app._dev):
			return null
		var part := what.substr(what.find(":") + 1)
		if what.begins_with("techmap:"):
			app._dev.show_for_tutorial("map")
		elif part == "research":
			app._dev.show_for_tutorial("tree", "ии")
			return app._dev.tut_target("wallet")
		elif part == "techlevel":
			app._dev.show_for_tutorial("tree", "ии")
			return app._dev.tut_target("techlevel")
		elif part == "button":
			app._dev.visible = false
			return app._shown_button(app._dev_button)
		else:
			app._dev.show_for_tutorial("tree")
		if part == "open":
			return null   # the whole full-screen window: nothing to outline (a frame round the screen only blinks)
		return app._dev.tut_target(part)
	if is_instance_valid(app._dev):
		app._dev.visible = false
	# The Corporations list and the dossier.
	if what.begins_with("list:"):
		app._window.show_window()
		if app._window.tut_target("table") == null or what == "list:tabs" or not app._window.tut_target("table").is_visible_in_tree():
			app._window.select_tab("country")   # the window opens on its home: the lists first
		return app._window.tut_target(what.substr(5))
	if what.begins_with("dossier_ui:"):
		var cid0 := _tutorial_company()
		if cid0.is_empty():
			return null
		app._window.show_window()
		if app._window.tut_target("dtabs") == null or not app._window.tut_target("dtabs").is_visible_in_tree():
			app._window.open_company(cid0)
		var bits := what.substr(11).split(":")
		if bits[0] == "tabs":
			app._window.select_dossier_tab(int(bits[1]) if bits.size() > 1 else 0)
			return app._window.tut_target("dtabs")
		return app._window.tut_target(bits[0])
	# Pax Corpface's panel (a separate mod), when installed.
	if what == "corpface":
		_close_window()
		if Engine.has_meta("pax_corpface_panel"):
			var cf: Variant = Engine.get_meta("pax_corpface_panel")
			if cf is Control and is_instance_valid(cf):
				(cf as Control).visible = true
				return cf as Control
		return null
	# The state departments.
	if what.begins_with("dept:"):
		_close_window()
		if is_instance_valid(app._dept_panel) and not app._dept_panel.is_visible_in_tree() and GameApi.has(app._game.main, "_переключить_окно"):
			GameApi.call_main(app._game.main, "_переключить_окно", [app._dept_panel])
		return app._dept_window.tut_target(what.substr(5)) if is_instance_valid(app._dept_window) else null
	if what == "corp_button":
		_close_window()
		if not is_instance_valid(app._corp_button):
			app._corp_button = Host.Badges.bar_button(app._game, app.tr_key("pax_corporations_button"))
		return app._shown_button(app._corp_button)
	# Pax Corpface's new header (a separate mod), when it is on.
	if what == "corpface_hud":
		_close_window()
		if Engine.has_meta("pax_corpface_hud"):
			var hd: Variant = Engine.get_meta("pax_corpface_hud")
			if hd is Object and is_instance_valid(hd) and bool((hd as Object).get("active")):
				return ((hd as Object).get("tut") as Dictionary).get("dock") as Control
		return null
	# The home of the «Corporations» window (dashboard.gd).
	if what.begins_with("home:"):
		app._window.show_window()
		app._window.show_home()
		return app._window.home_target(what.substr(5))
	# A part of the «Zones» screen that is open now (its own mini tour: the window stays where it is).
	if what.begins_with("zone:"):
		return app._window.home_target(what.substr(5))
	if what.begins_with("tab:"):
		app._window.show_window()
		app._window.select_tab(what.substr(4))
		return app._window.tab_button(what.substr(4))
	if what.begins_with("dossier:"):
		var cid := _tutorial_company()
		if cid.is_empty():
			return null
		app._window.show_window()
		app._window.open_company(cid)
		app._window.select_dossier_tab(int(what.substr(8)))
		return null
	match what:
		"found", "help":
			app._window.show_window()
			app._window.select_tab("country")
			return app._window.found_button if what == "found" else app._window.tutorial_button
		"map":
			_close_window()
			_open_map()
			return null
		"departments":
			_close_window()
			if is_instance_valid(app._dept_panel) and not app._dept_panel.is_visible_in_tree() and GameApi.has(app._game.main, "_переключить_окно"):
				GameApi.call_main(app._game.main, "_переключить_окно", [app._dept_panel])
			return app._dept_panel
	return null


## The company the tutorial shows: the biggest of the player's country (else of the world).
func _tutorial_company() -> String:
	var best: Dictionary = {}
	for item in app.db.companies:
		var c: Dictionary = item
		var mine := str(c.get("_country", "")) == app._player_country()
		var best_mine := not best.is_empty() and str(best.get("_country", "")) == app._player_country()
		if best.is_empty() or (mine and not best_mine) or (mine == best_mine and app.db.cap(c) > app.db.cap(best)):
			best = c
	return str(best.get("id", ""))


## Unread counters on the bottom bar (badges.gd): the mod's letters and a new summary on «Corporations»; the game's
## unread letters on «Связи», science news on the projects button, new stages on the path button.
func _update_badges() -> void:
	if app.badges == null:
		return
	if not is_instance_valid(app._corp_button):
		app._corp_button = null
		_button_search -= 0.5
		if _button_search <= 0.0:
			_button_search = 5.0   # the HUD search is not cheap — at most every 5 s until the button is found
			app._corp_button = Host.Badges.bar_button(app._game, app.tr_key("pax_corporations_button"))
	var main: Object = app._game.main
	var counts: Array = []
	if app._corp_button != null:
		counts.append([app._corp_button, app.letters.unread() + (1 if app.digest.unread else 0)])
	counts.append([main.get("кнопка_связей"), Host.Badges.game_inbox(app._game)])
	counts.append([main.get("кнопка_проектов"), Host.Badges.main_count(app._game, "_новостей_науки")])
	counts.append([main.get("кнопка_пути"), Host.Badges.main_count(app._game, "_новые_этапы")])
	app.badges.update(counts)


func _open_from_map(cid: String) -> void:
	if is_instance_valid(app._window):
		app._window.open_company(cid)


func _show_on_map(cid: String) -> void:
	if _open_map():
		app._layer.focus_company(cid)


func _show_point(cid: String, point: Dictionary) -> void:
	if _open_map():
		app._layer.focus_point(cid, point)


func _open_map() -> bool:
	if not is_instance_valid(app._layer):
		return false
	if app._layer.map == app._globe and is_instance_valid(app._globe) and app._globe.visible:
		return true   # from orbit the globe is the map: it turns to the place instead
	var main: Object = app._game.main
	if GameApi.has(main, "_карта_открыта") and not bool(GameApi.call_main(main, "_карта_открыта")) and GameApi.has(main, "_переключить_карту"):
		GameApi.call_main(main, "_переключить_карту")
	return true
