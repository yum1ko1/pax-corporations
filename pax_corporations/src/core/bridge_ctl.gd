extends RefCounted
## What the other mods of the series read and call: Pax CorpInc3D's sites, Pax Corpface's rows and windows, the country's rank.
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const Host := preload("res://mods/pax_corporations/main.gd")

var app: Host   # the host: its modules and data


func _init(host: Host) -> void:
	app = host


## The buildings stand on the home planet's 3D node (they move with it); off by the ⚙ setting «3D-постройки».
func _build_buildings() -> void:
	if is_instance_valid(app.buildings):
		app.buildings.queue_free()
	app.buildings = null
	if is_instance_valid(app._layer):
		app._layer.bank = null
	app.bank = null
	# Pax CorpInc3D (a separate mod) on — its real 3D models stand on the map even with the voxel setting off.
	# The flat map keeps only the old voxel pictures (a setting); Pax CorpInc3D's models stand on the 3D Earth.
	if not app._active or not bool(app.get_setting("buildings_3d", false)):
		return
	app.buildings = Host.Buildings.new()
	app.add_child(app.buildings)   # its hidden render window photographs the voxel models for the map
	var redraw := func() -> void:
		if is_instance_valid(app._layer):
			app._layer.queue_redraw()
	app.buildings.on_ready = redraw
	var e := Host.BuildingBank.ext()
	if e != null:
		e.set("on_ready", redraw)
	app.bank = Host.BuildingBank.new()
	app.bank.voxel = app.buildings
	if is_instance_valid(app._layer):
		app._layer.bank = app.bank
		app._layer.tree_ref = app.tree
		app._layer.queue_redraw()


## Every site of every company for Pax CorpInc3D's 3D Earth: [{k kind, f frame, s sector, st state, lat, lon, c id}].
func sites_3d() -> Array:
	var out: Array = []
	for item in app.db.companies:
		var c: Dictionary = item
		var pts: Array = c.get("sites", [])
		for i in pts.size():
			if not (pts[i] is Dictionary):
				continue
			var p: Dictionary = pts[i]
			var look := Host.Buildings.look_of(app.db, c, p, i, app.tree)
			out.append({"k": str(look["kind"]), "f": Host.Frames.of(c), "s": str(c.get("sector", "")), "st": str(look["state"]),
				"lat": float(p.get("ш", 0.0)), "lon": float(p.get("д", 0.0)), "c": str(c["id"])})
	return out


## The point the flat map shows in its middle: Vector2(latitude, longitude), INF — no map (Pax CorpInc3D turns the
## globe's camera there when the map closes).
func map_center() -> Vector2:
	if not is_instance_valid(app._layer) or not is_instance_valid(app._layer.map) or not app._layer.map.visible:
		return Vector2.INF
	return app._layer.latlon_at(app._layer.get_viewport_rect().size / 2.0 - app._layer.global_position)


## Changes when the sites change (a new week's data).
func sites_version() -> int:
	return app.db.version


## Pax CorpInc3D was switched on or off (or came and went): the buildings are built anew.
func refresh_buildings() -> void:
	_build_buildings()


func set_buildings_3d(on: bool) -> void:
	app.set_setting("buildings_3d", on)
	_build_buildings()


## The mod's resources for Pax Corpface's panel (a separate mod; no dependency either way): [{id, имя, значение,
## показ, значок, подсказка}…]. Corpface samples «значение» daily for its arrow; «значок» is one of its icons.
## The country's world step for Pax Corpface's interface: [step, place] ("" — not counted yet).
func country_tier() -> Array:
	return [app.country_rank.tier, app.country_rank.place] if app.country_rank != null else ["", 0]


## Console demos (zz_corp_probe): «rank_anim up|down [step]», «rank_<step>».
func rank_demo(dir: String, to_tier: String) -> String:
	return app.country_rank.demo(dir, to_tier) if app.country_rank != null else "Pax Corporations: no world yet"


## The world's top states with their frames (Pax Corpface: a click on the rank line; console «rank_top»).
func open_country_top() -> void:
	if app.country_rank != null:
		app.country_rank.show_top()


## The country's frame drawn around a flag on any CanvasItem (Pax Corpface's column) — the companies' family.
func draw_flag_frame(ci: CanvasItem, r: Rect2, tier: String) -> void:
	Host.Frames.draw_flag(ci, r, tier)


## The room the frame needs around a flag, as a share of the flag's height: Vector4(left, top, right, bottom).
func flag_frame_margin(tier: String) -> Vector4:
	return Host.Frames.flag_margin(tier)


func rank_demo_to(to_tier: String) -> String:
	return app.country_rank.demo_to(to_tier) if app.country_rank != null else "Pax Corporations: no world yet"


func corpface_rows() -> Array:
	if not app._active or app.db == null:
		return []
	var me := app._player_country()
	var out: Array = []
	var t := func(k: String) -> String: return app.tr_key("pax_corporations_cf_" + k)
	var gv := app.tree.state_of(me)
	out.append({"id": "gw", "name": t.call("gv"), "value": float(gv.get("has_flag", 0)), "icon": "gv",
		"shown": "%d · %d%%" % [int(gv.get("has_flag", 0)), roundi(100.0 * float(gv.get("прогресс", 0.0)) / maxf(app.tree.threshold(int(gv.get("получено", 0))), 0.01))],
		"подсказка": t.call("gv_tip")})
	var no := app.tree.science_of(me)
	out.append({"id": "but_value", "name": t.call("no"), "value": float(no.get("has_flag", 0)), "icon": "no",
		"shown": "%d · %d%%" % [int(no.get("has_flag", 0)), roundi(100.0 * float(no.get("прогресс", 0.0)) / maxf(app.tree.threshold_for("ии", int(no.get("получено", 0))), 0.01))],
		"подсказка": t.call("no_tip")})
	var pr := float(app.arena.prestige.get(me, 0.0))
	out.append({"id": "prestige", "name": t.call("prestige"), "value": pr, "shown": "%d / 100" % roundi(pr), "icon": "prestige"})
	var top := 0
	var u_sum := 0.0
	var u_n := 0
	for item in app.db.companies:
		var c: Dictionary = item
		if str(c.get("_country", "")) != me:
			continue
		if int(c.get("_world_place", 999)) <= 100:
			top += 1
		var e := app.db.econ(c)
		if e.has("U"):
			u_sum += float(e["U"])
			u_n += 1
	out.append({"id": "top100", "name": t.call("top"), "value": float(top), "shown": str(top), "icon": "top"})
	var tax := float(app._paid_week.get("taxes", 0.0))
	out.append({"id": "taxes", "name": t.call("taxes"), "value": tax, "shown": app.db.money(tax) + t.call("per_week"), "icon": "taxes"})
	var div := float(app._paid_week.get("dividends", 0.0)) * 13.0
	out.append({"id": "dividends", "name": t.call("dividends"), "value": div, "shown": app.db.money(div) + t.call("per_quarter"), "icon": "dividends"})
	if u_n > 0:
		var u := 100.0 * u_sum / float(u_n)
		out.append({"id": "условия", "name": t.call("conditions"), "value": u, "shown": "%d / 100" % roundi(u), "icon": "conditions"})
	var best := -1.0
	var best_c: Dictionary = {}
	for kind in Host.TechLevel.TYPES:
		var bc := app.techlevel.best_of(me, str(kind))
		if not bc.is_empty() and app.techlevel.ratio(bc) > best:
			best = app.techlevel.ratio(bc)
			best_c = bc
	if not best_c.is_empty():
		out.append({"id": "tech_level", "name": t.call("tech"), "value": best * 100.0, "icon": "future",
			"shown": "%d · %s" % [roundi(best * 100.0), app.tr_key("pax_corporations_tl_step_" + app.techlevel.step_key(best_c))],
			"подсказка": t.call("tech_tip") % app.db.name_of(best_c)})
	var opened := 0
	var all: Array = app.capabilities.all()
	for cd in all:
		if app.capabilities.has(me, str((cd as Dictionary)["id"])):
			opened += 1
	out.append({"id": "будущее", "name": t.call("future"), "value": float(opened), "shown": "%d / %d" % [opened, all.size()], "icon": "future"})
	return out


## A click on one of them in Pax Corpface: the window of the mod about it.
func corpface_open(id: String) -> void:
	match id:
		"gw", "but_value":
			app._close_window()
			if is_instance_valid(app._dev):
				app._dev.show_for_tutorial("tree", "ии" if id == "but_value" else "")
		"будущее", "tech_level":
			app._close_window()
			if is_instance_valid(app._dev):
				app._dev.show_for_tutorial("map")
		_:
			if is_instance_valid(app._window):
				if is_instance_valid(app._dev):
					app._dev.visible = false
				app._window.show_window()
				app._window.select_tab("arena" if id == "prestige" else ("world" if id == "top100" else "country"))
