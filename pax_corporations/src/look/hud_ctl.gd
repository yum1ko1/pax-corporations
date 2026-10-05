extends RefCounted
## The game's own interface around the mod: its skin (hud_skin.gd), Pax Corpface's menu, the game's hint hidden over our windows.
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const Host := preload("res://mods/pax_corporations/main.gd")

var app: Host   # the host: its modules and data


func _init(host: Host) -> void:
	app = host


## The ⚙ menu's «game interface in the mod's look».
func set_hud_skin(on: bool) -> void:
	app.set_setting("hud_skin", on)
	if not is_instance_valid(app.hud_skin):
		return
	if on and _corpface_interface():
		app.hud_skin.start()
	else:
		app.hud_skin.restore()


## The game's hover hint of a body (Main.подсказка — «Земля: единственное место, где точно есть жизнь») follows the
## mouse over the map under our window and covered the window's ✕: while a window of the mod is open it is hidden.
func _hide_game_hint() -> void:
	var open := (is_instance_valid(app._window) and app._window.is_visible_in_tree()) or (is_instance_valid(app._dept_window) and app._dept_window.is_visible_in_tree()) 		or (is_instance_valid(app._dev) and app._dev.visible)
	if not open:
		return
	for prop in ["подсказка", "подсказка_физики"]:
		var h: Variant = app._game.main.get(prop)
		if h is Control and is_instance_valid(h) and (h as Control).visible:
			(h as Control).visible = false
			(h as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


## A bar button as the player sees it: with Pax Corpface's new header the bottom bar is hidden and the button
## lives there as a proxy icon — the tutorial outlines that one.
func _shown_button(b: Button) -> Control:
	if is_instance_valid(b) and not b.is_visible_in_tree() and Engine.has_meta("pax_corpface_hud"):
		var hd: Variant = Engine.get_meta("pax_corpface_hud")
		if hd is Object and is_instance_valid(hd) and (hd as Object).has_method("proxy_of"):
			var p: Variant = (hd as Object).call("proxy_of", b)
			if p is Control and is_instance_valid(p):
				return p as Control
	return b


## Pax Corpface unloaded Pax Interface for its new header: the skin (off while Pax Interface was there) starts now.
func restart_hud_skin() -> void:
	if is_instance_valid(app.hud_skin) and bool(app.get_setting("hud_skin", true)):
		app.hud_skin.start.call_deferred()


## Pax Corpface's interface is off (or Corpface is gone): the game's menu goes back to the game's own look.
func stop_hud_skin() -> void:
	if is_instance_valid(app.hud_skin):
		app.hud_skin.restore()


## Pax Corpface's new interface stands now (the reskin of the game's menu belongs to it).
func _corpface_interface() -> bool:
	if not Engine.has_meta("pax_corpface_hud"):
		return false
	var hd: Variant = Engine.get_meta("pax_corpface_hud")
	return hd is Object and is_instance_valid(hd) and bool((hd as Object).get("active"))


## The «Corporations» window over the game's whole window area (a setting in its ⚙): its minimum size follows the
## area (right of Pax Corpface's column, below the header); off — the window's own size again.
func _fit_fullscreen() -> void:
	if not is_instance_valid(app._panel) or not app._panel.is_visible_in_tree() or app._game == null:
		return
	var want := Host.Glass.area(app._game.main) if bool(app.get_setting("fullscreen_window", true)) else Vector2(800, 560)
	if want == Vector2.ZERO:
		return
	if app._panel.custom_minimum_size.distance_to(want) > 2.0:
		app._panel.custom_minimum_size = want
