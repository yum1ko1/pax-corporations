extends Control
## «Corporations» layer on the game's political map (section 18).
## Far away — only headquarters, sized by capitalisation, icon by the company's profile.
## Closer (zoom ≥ config) — every point of every company. A selected company shows all its points
## tied to the headquarters with thin lines, the rest is muted. Hover — a label; click — the dossier.
## Headquarters that overlap on screen (Moscow) fan out in a ring with leader lines to the real place;
## a crowd bigger than FAN_MAX folds into one marker with a counter and a scrollable drop-down list.
## The label and the drop-down live on their own canvas layer above the map's province card.
## The toggle sits next to the map's own «Borders» button.

const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")
const HqGroups := preload("res://mods/pax_corporations/src/map/hq_groups.gd")
const Log := preload("res://mods/pax_corporations/src/shared/log.gd")
const Zones := preload("res://mods/pax_corporations/src/zones/zones.gd")
const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const ZoneFx := preload("res://mods/pax_corporations/src/zones/zone_fx.gd")
const Frames := preload("res://mods/pax_corporations/src/companies/frames.gd")
const FAN_MAX := 7
const PULSE_TIME := 4.0
const TOP_LAYER := 110

var mod: PaxMod
var game: PaxGame
var db: Data
var map: CanvasLayer
var on_open: Callable           # func(company_id: String)
var on_background: Callable     # func() — a left click on the empty map
var selected := ""
## What the layer shows: MODE_OFF — nothing, MODE_HOME — the player's country only, MODE_WORLD — every company.
const MODE_OFF := 0
const MODE_HOME := 1
const MODE_WORLD := 2
var mode := MODE_WORLD

var _anchor: Control             # the map's own icon layer we follow
var _toggle: OptionButton
var _home := ""                  # the player's country, for MODE_HOME (read when the caches are rebuilt)
var _cache_mode := -1
var _cache_count := -1
var _top: CanvasLayer
var _tip: Control                # draws the hover label above everything on the map
var _menu: PopupMenu             # companies of a folded crowd
var _menu_ids: Array = []
var _hits: Array = []            # [{pos, r, id, point} | {pos, r, crowd: [ids]}] rebuilt every frame
var _hover: Dictionary = {}
var _pulse: Dictionary = {}      # {point, left}
var _owners_cache: Dictionary = {}   # extraction site name -> company id
var _last_sig: Array = []        # what the screen showed at the last redraw
# The layer as a picture while the map moves: the last drawing (its commands kept by the renderer) shifted and scaled
# with the map — nothing recomputed — and drawn anew once the map has stood still for «settle_s».
var _drawn_view: Array = []        # the map's corners [to_screen(0,0), to_screen(1,1)] at the last redraw
var _prev_view: Array = []
var _still := 0.0                  # seconds the map has not moved
var _pic_k := Vector2.ONE          # the picture's scale and shift from the last redraw to now
var _pic_off := Vector2.ZERO
# The badges' layout made on a worker thread (hq_groups.gd) for a view, kept for the views seen last.
var _layout_cache: Dictionary = {} # key -> groups
var _view_key: Array = []          # the key of the view drawn now
var _job: LayoutJob
var _job_sig: Array = []
var _blink := 0.0
var _since_draw := 0.0              # seconds since the last redraw (redraws throttled while the map moves)
var _strikes_on_screen := false
var _order: Array = []           # companies by capitalisation, largest first — re-sorted once a week
var _order_version := -1
var _pick: Callable              # pick mode: func(province_id, owner) — the next click on the map (founding)
# Projection: the map is a flat world picture, so uv → screen is origin + size × uv. Two calls to the map per
# redraw instead of one per company; checked against a third point, else every point goes through the map.
var _origin := Vector2.ZERO
var _world := Vector2.ONE        # the whole world's size on screen, px
var _linear := false
var _hq_uv: Dictionary = {}      # company id -> uv of its headquarters (rebuilt once a week)
var _countries: Array = []       # far view: [{name, uv, cap, n, slices: [[share, color, sector]]}]
var _cache_version := -1
var zones_on := false           # the economic zones' layer (zones.gd): members tinted, the zone's name opens its window
var on_zone: Callable            # func(zone_id) — open the zone's window (main.gd)
var _zone_cache: Array = []      # [{z, col, cells: [[uv, area]…], uv: label point}]
var _zone_sig := ""
var _zone_hits: Array = []       # [{rect, id}]
var _regions: Dictionary = {}    # province id -> [uv, area km²]
var _zone_box: CheckBox
var _zfx: ZoneFx                 # the zones as districts (zone_fx.gd), null until first shown
var _zfx_tried := false
var grouping := 0                # 0 — as is (companies gather into country circles when zoomed out), 1 — always circles
var _group_toggle: OptionButton
var _section: Control             # the «Корпорации» section in the game's layers window (removed whole on detach)
var _fx: Control                 # a light overlay with the frames' pulses and glints (redrawn alone, ~30 fps)
var _fx_items: Array = []
## 3D buildings (buildings.gd draws the voxel pictures): every site of every company of the world; the sites of one
## province stand around its centre as a little isometric city — the tallest towers in the middle.
var bank: Object = null          # buildings.gd, null — the buildings are switched off
var tree_ref: Object = null      # tree.gd (decorations)
var _city: Array = []            # [{cid, idx, uv, cell: Vector2i, look, color, flag}]
var _city_version := -1
var _cells: Array = []           # the spiral of iso cells (nearest to the centre first)
var _flags: Dictionary = {}      # country -> flag colour        # [[screen pos, radius, tier]] of the animated frames drawn this time
var _fx_clock := 0.0
var _frames_all := true          # zoomed in enough for every frame (else only sapphire and diamond)


## `target` — another map to draw on (globe_map.gd: the 3D Earth); the game's political map by default.
func attach(m: PaxMod, g: PaxGame, data: Data, open_cb: Callable, target: CanvasLayer = null) -> bool:
	mod = m
	game = g
	db = data
	on_open = open_cb
	var raw: Variant = target if target != null else g.main.get("полит_карта")
	if not (raw is CanvasLayer):
		return false
	map = raw
	if not map.has_method("to_screen"):
		m.log_warning("political map has no на_экран() — corporations layer disabled")
		return false
	name = "PaxCorporationsLayer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icons: Variant = map.get("icons_layer")
	var holder: Node = map
	if icons is Control and (icons as Control).get_parent() != null and not ((icons as Control).get_parent() is Container):
		_anchor = icons
		holder = _anchor.get_parent()
	holder.add_child(self)
	if _anchor != null:
		holder.move_child(self, _anchor.get_index() + 1)
	else:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# «layer_on» was the old on/off switch: on — the whole world, off — nothing.
	mode = clampi(int(m.get_setting("layer_mode", MODE_WORLD if bool(m.get_setting("layer_on", true)) else MODE_OFF)), MODE_OFF, MODE_WORLD)
	grouping = clampi(int(m.get_setting("map_grouping", 0)), 0, 1)
	_build_top()
	_add_toggle()
	return true


func set_mode(new_mode: int) -> void:
	mode = clampi(new_mode, MODE_OFF, MODE_WORLD)
	mod.set_setting("layer_mode", mode)
	if is_instance_valid(_toggle) and _toggle.selected != mode:
		_toggle.select(mode)
	if mode == MODE_OFF or (mode == MODE_HOME and selected != "" and not _shown(db.company(selected))):
		selected = ""
	queue_redraw()


## Is the company on the layer in the current mode?
func _shown(c: Dictionary) -> bool:
	if c.is_empty() or mode == MODE_OFF:
		return false
	return mode == MODE_WORLD or str(c.get("_country", "")) == _home_country()


func _home_country() -> String:
	if _home.is_empty() and game != null:
		_home = str(game.player_faction().get("name", ""))
	return _home


func set_zones(on: bool) -> void:
	zones_on = on
	mod.set_setting("zones_layer", on)
	if is_instance_valid(_zone_box) and _zone_box.button_pressed != on:
		_zone_box.set_pressed_no_signal(on)
	_zone_sig = ""
	queue_redraw()


func set_grouping(g: int) -> void:
	grouping = clampi(g, 0, 1)
	mod.set_setting("map_grouping", grouping)
	if is_instance_valid(_group_toggle) and _group_toggle.selected != grouping:
		_group_toggle.select(grouping)
	queue_redraw()


func detach() -> void:
	# The whole section goes, at once (out of the window, then freed): the next layer adds its own. Freeing only the
	# two lists left the title and the zones' box, the next layer saw the section there and the lists were gone.
	if is_instance_valid(_section):
		if _section.get_parent() != null:
			_section.get_parent().remove_child(_section)
		_section.queue_free()
	if is_instance_valid(_group_toggle):
		_group_toggle.queue_free()
	if is_instance_valid(_toggle):
		_toggle.queue_free()
	queue_free()


func is_attached_to(current_map: Variant) -> bool:
	return is_instance_valid(map) and current_map == map


func _build_top() -> void:
	_top = CanvasLayer.new()
	_top.layer = TOP_LAYER
	add_child(_top)
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.draw.connect(func() -> void:
		for it in _fx_items:
			Frames.draw(_fx, it[0] as Vector2, float(it[1]), str(it[2]), Frames.PART_FX))
	add_child(_fx)
	_tip = Control.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tip.draw.connect(_draw_tip)
	_top.add_child(_tip)
	_menu = PopupMenu.new()
	_menu.max_size = Vector2i(460, 420)   # taller lists scroll
	_menu.id_pressed.connect(func(i: int) -> void:
		if i >= 0 and i < _menu_ids.size():
			selected = str(_menu_ids[i])
			on_open.call(selected))
	_top.add_child(_menu)


## The switches live in the game's layers window (Tab): a «Корпорации» section — which companies (off / my country /
## the world) and how (as is / always the countries' circles). The window may be rebuilt, so the section is added
## whenever it is open without it.
func _add_toggle() -> void:
	_ensure_layers_section()


func _ensure_layers_section() -> void:
	var w: Variant = map.get("окно_слоёв")
	if not (is_instance_valid(w) and w is Control and (w as Control).is_visible_in_tree()):
		return
	if (w as Node).find_child("PaxCorporationsLayers", true, false) != null:
		return
	var box := _first_vbox(w as Node)
	if box == null:
		return
	var sec := VBoxContainer.new()
	sec.name = "PaxCorporationsLayers"
	sec.add_theme_constant_override("separation", 4)
	sec.add_child(HSeparator.new())
	var title := Label.new()
	title.text = mod.tr_key("pax_corporations_button")
	title.add_theme_color_override("font_color", Color(0.95, 0.78, 0.32))
	sec.add_child(title)
	_toggle = OptionButton.new()
	_toggle.tooltip_text = mod.tr_key("pax_corporations_layer_tip")
	_toggle.focus_mode = Control.FOCUS_NONE
	for key: String in ["pax_corporations_layer_off", "pax_corporations_layer_home", "pax_corporations_layer_world"]:
		_toggle.add_item(mod.tr_key(key))
	_toggle.select(mode)
	_toggle.item_selected.connect(func(i: int) -> void: set_mode(i))
	sec.add_child(_toggle)
	_group_toggle = OptionButton.new()
	_group_toggle.tooltip_text = mod.tr_key("pax_corporations_grouping_tip")
	_group_toggle.focus_mode = Control.FOCUS_NONE
	for key: String in ["pax_corporations_grouping_auto", "pax_corporations_grouping_countries"]:
		_group_toggle.add_item(mod.tr_key(key))
	_group_toggle.select(grouping)
	_group_toggle.item_selected.connect(func(i: int) -> void: set_grouping(i))
	sec.add_child(_group_toggle)
	_zone_box = CheckBox.new()
	_zone_box.text = mod.tr_key("pax_corporations_zones_layer")
	_zone_box.tooltip_text = mod.tr_key("pax_corporations_zones_layer_tip")
	_zone_box.focus_mode = Control.FOCUS_NONE
	_zone_box.button_pressed = zones_on
	_zone_box.toggled.connect(func(on: bool) -> void: set_zones(on))
	sec.add_child(_zone_box)
	box.add_child(sec)
	_section = sec


static func _first_vbox(n: Node) -> VBoxContainer:
	for ch in n.get_children():
		if ch is VBoxContainer:
			return ch
		var deeper := _first_vbox(ch)
		if deeper != null:
			return deeper
	return null


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	GameApi.perf("corporations.map_layer.process", t0)


func _process_body(delta: float) -> void:
	if not is_instance_valid(map):
		return
	_ensure_layers_section()
	if is_instance_valid(_anchor):
		position = _anchor.position
		size = _anchor.size
	else:
		# Over the globe (a CanvasLayer of its own, no icon layer to follow) the anchors gave no size: the layer was
		# 0 × 0, every headquarters counted as off the screen and nothing was drawn. The screen is its size.
		var view := get_viewport_rect().size
		if size != view or position != Vector2.ZERO:
			position = Vector2.ZERO
			size = view
	# The zones' districts move with the layer every frame (not only when it redraws), so they never slide off.
	if _zfx != null and _zfx.ok and _zfx.visible:
		_zfx.position = position
		_zfx.size = size
		_update_projection()
		_zfx.place(_origin, _world)
	_zone_labels()
	var want := (mode != MODE_OFF or bank != null or zones_on) and map.visible and bool(map.get("with_provinces")) and on_earth()
	if visible != want:
		visible = want
		_top.visible = want
		Log.info("map", "corporations layer %s on %s (mode %d, map shown %s, provinces %s, Earth %s)" % [
			"shown" if want else "hidden", map.name, mode, map.visible, map.get("with_provinces"), on_earth()])
		if not want and _zfx != null:
			_zfx.visible = false   # a sibling of the layer: it does not hide with it (the map of another body)
	if not _pulse.is_empty():
		_pulse["left"] = float(_pulse["left"]) - delta
		if float(_pulse["left"]) <= 0.0:
			_pulse = {}
	if visible:
		# Zoomed out the game's army chips and figurines (drawn above this layer) cover the companies' buttons and the
		# countries' circles: then the layer goes on top of them; close in («above_armies_below_zoom»), where the
		# sites show, the armies stay above the companies' marks.
		# Raised by its place among the map's drawing layers, not by z_index: a z_index lifted it over the game's
		# windows on the map too («Слои», the panels) — the icons covered the HUD.
		_raise(_far_view() or zoom() < float(_cfg().get("above_armies_below_zoom", 6.0)))
		# Our label replaces the map's plain white caption of the hovered extraction site.
		if _hover.has("site") and map.get("_промысел_наведён") != null:
			map.set("_промысел_наведён", -1)
		# Redraw only when something on screen changed: the map moved or zoomed, the hover, the selection,
		# a new week. Pulses and strike rings animate — those redraw on their own, strikes at ~15 fps.
		# On the globe the map's corners are the poles — they hardly move when the planet turns, and the layer never
		# redrew (its marks stayed where they were first drawn, mostly off the screen): there the camera is the signature.
		var sig := [map.call("to_screen", Vector2.ZERO, 0.0), map.call("to_screen", Vector2.ONE, 0.0), position, size, selected,
			str(_hover.get("pos", "")), db.version, _menu.visible,
			[map.get("_eye"), map.get("_basis"), map.get("зум")] if _globe() else null]
		_blink += delta
		var blink := _strikes_on_screen and _blink >= 1.0 / 15.0
		_since_draw += delta
		# While the map moves the marks are redrawn at most redraw_fps times a second (every frame cost a frame with
		# the whole world's companies); a still map — at once.
		var moving := sig != _last_sig and _since_draw < 1.0 / float(_cfg().get("redraw_fps", 30.0)) and _order.size() > 300
		var view: Array = [sig[0], sig[1]]
		if view != _prev_view:
			_still = 0.0
		else:
			_still += delta
		_prev_view = view
		var redraw_due := sig != _last_sig or not _pulse.is_empty() or blink
		_finish_layout()
		if _picture_ok() and view != _drawn_view and _still < float(_cfg().get("settle_s", 0.15)) and _fit_picture(view):
			pass   # the map moves: the last picture follows it, nothing is recomputed
		elif redraw_due and (not moving or _picture_ok()):
			var key := _layout_key(view)
			if _layout_cache.has(key) or not _threads() or _order.size() < 300 or _far_view() or mode == MODE_OFF:
				_commit(sig, view, key)
			elif _job == null:
				_request_layout(key, sig)   # the picture stays until the worker's layout is ready
		elif not _fx_items.is_empty() and Frames.fx == 2:
			# Only the frames' light overlay animates; the layer itself is not redrawn.
			_fx_clock += delta
			if _fx_clock >= 1.0 / 30.0:
				_fx_clock = 0.0
				_fx.queue_redraw()
		position += _pic_off   # the base was set from the map's anchor this frame
		scale = _pic_k


## The badges' layout on a worker thread (WorkerThreadPool): «key» — the view it was made for.
class LayoutJob extends RefCounted:
	var badges: Array
	var cell := 46.0
	var key: Array
	var task := -1
	var groups: Array = []

	func run() -> void:
		groups = HqGroups.layout(badges, cell)


func _picture_ok() -> bool:
	return _linear and not _globe() and not _drawn_view.is_empty() and bool(_cfg().get("move_as_picture", true))


## The shift and scale that carry the last drawing onto the map as it is now (the map is linear: uv → c0 + (c1 − c0)·uv).
func _fit_picture(view: Array) -> bool:
	if not (view[0] is Vector2 and view[1] is Vector2 and _drawn_view[0] is Vector2 and _drawn_view[1] is Vector2):
		return false
	var d0: Vector2 = _drawn_view[0]
	var dd: Vector2 = (_drawn_view[1] as Vector2) - d0
	var c0: Vector2 = view[0]
	var cc: Vector2 = (view[1] as Vector2) - c0
	if absf(dd.x) < 1.0 or absf(dd.y) < 1.0:
		return false
	var k := Vector2(cc.x / dd.x, cc.y / dd.y)
	if k.x < 0.125 or k.y < 0.125 or k.x > 8.0 or k.y > 8.0:
		return false
	var off := c0 - d0 * k
	if off.length() > size.length() * 3.0:
		return false   # wrapped round the world: drawn anew
	_pic_k = k
	_pic_off = off
	return true


func _threads() -> bool:
	return not Engine.has_meta(&"pax_threads") or bool(Engine.get_meta(&"pax_threads"))


## What the badges' layout depends on: the view, the layer's size, the data, the mode.
func _layout_key(view: Array) -> Array:
	return [view[0], view[1], size, db.version, _order.size(), mode, zoom()]


## Redrawn now: the picture back in place, the layout for this view.
func _commit(sig: Array, view: Array, key: Array) -> void:
	_last_sig = sig
	_drawn_view = view
	_view_key = key
	_pic_k = Vector2.ONE
	_pic_off = Vector2.ZERO
	_since_draw = 0.0
	_blink = 0.0
	queue_redraw()
	_tip.queue_redraw()
	_fx.queue_redraw()


func _request_layout(key: Array, sig: Array) -> void:
	_update_projection()
	var job := LayoutJob.new()
	job.badges = _badges(_order)
	job.cell = _layout_cell()
	job.key = key
	_job = job
	_job_sig = sig
	job.task = WorkerThreadPool.add_task(job.run, false, "pax_corporations map layout")


func _finish_layout() -> void:
	if _job == null or _job.task < 0 or not WorkerThreadPool.is_task_completed(_job.task):
		return
	WorkerThreadPool.wait_for_task_completion(_job.task)
	var job := _job
	_job = null
	if _layout_cache.size() >= 8:
		_layout_cache.erase(_layout_cache.keys()[0])
	_layout_cache[job.key] = job.groups
	if is_instance_valid(map):
		_update_projection()
		var view: Array = [map.call("to_screen", Vector2.ZERO, 0.0), map.call("to_screen", Vector2.ONE, 0.0)]
		if _layout_key(view) == job.key:
			_commit(_job_sig, view, job.key)


func _exit_tree() -> void:
	if _job != null and _job.task >= 0:
		WorkerThreadPool.wait_for_task_completion(_job.task)
		_job = null


# ---------- the economic zones' layer ----------

## The provinces of the zones' members (the map's owners × data/regions2.json), rebuilt when the owners change.
func _zone_cells() -> void:
	if _regions.is_empty():
		for r in Data.regions2():   # the map's own numbering
			if r is Dictionary:
				var rd: Dictionary = r
				_regions[int(rd.get("id", -1))] = [Data.uv_of({"ш": float(rd.get("ш", 0.0)), "д": float(rd.get("д", 0.0))}), float(rd.get("area", rd.get("площадь", 1000.0)))]
	var book: Variant = map.get("пров")
	var owners: Variant = ((book as Object).get("owner_of") if (book as Object).get("owner_of") != null else (book as Object).get("владелец")) if book is Object else null
	if not (owners is Array or owners is PackedStringArray):
		return
	var own: Array = Array(owners)
	var sig := "%d|%d|%d" % [own.size(), hash(str(own.slice(0, 400))), hash(str(Zones.state()))]   # owners or members changed
	if sig == _zone_sig:
		return
	_zone_sig = sig
	_zone_cache.clear()
	for z in Zones.all():
		var zd: Dictionary = z
		var members: Array = zd.get("members", [])
		var cells: Array = []
		var sum := Vector2.ZERO
		var w := 0.0
		for pid in own.size():
			if str(own[pid]) in members and _regions.has(pid):
				var cell: Array = _regions[pid]
				cells.append(cell)
				var a := sqrt(float(cell[1]))
				sum += (cell[0] as Vector2) * a
				w += a
		if not cells.is_empty():
			_zone_cache.append({"z": zd, "col": Zones.color_of(zd), "cells": cells, "uv": sum / w})
	if _zfx != null and _zfx.ok:
		var all := Zones.all()
		_zfx.fill(own, func(country: String) -> Array:
			var zs: Array = Zones.zones_of(country)
			if zs.is_empty():
				return []
			var pick: Dictionary = Zones.customs_union_of(country)
			if pick.is_empty():
				pick = zs[0]
			return [all.find(pick), Zones.color_of(pick)])


## In the zones' view the map's country names are hidden (only the unions' names stay); back when the view is off.
var _labels_hidden := false
var _labels_saved: Array = []     # the map's country names while hidden (given back as they were)


var _raised := false


## Above the armies' chips (the last drawing layer before the map's windows) or right over the icon layer.
func _raise(up: bool) -> void:
	if z_index != 0:
		z_index = 0
	var holder := get_parent()
	if holder == null or up == _raised:
		return
	_raised = up
	if not up:
		if _anchor != null and is_instance_valid(_anchor) and _anchor.get_parent() == holder:
			holder.move_child(self, _anchor.get_index() + 1)
		return
	# The first window or panel after the drawing layers: the layer goes right before it (or last when none).
	var at := holder.get_child_count() - 1
	for i in range(get_index() + 1, holder.get_child_count()):
		var ch := holder.get_child(i)
		if ch is Container or ch is Panel or ch is Window or ch is Button:
			at = i - 1
			break
	holder.move_child(self, at)


## The map's country names: «labels» since 0.24, «подписи» before.
func _labels_key() -> String:
	return "labels" if map.get("labels") is Array else "подписи"


func _redraw_map_layers() -> void:
	for cn in ["lines_layer", "icons_layer", "слой"]:
		var ci: Variant = map.get(cn)
		if ci is CanvasItem:
			(ci as CanvasItem).queue_redraw()


func _zone_labels() -> void:
	var hide := zones_on and _zfx != null and _zfx.ok and visible
	var key := _labels_key()
	if hide:
		var lab: Variant = map.get(key)
		if lab is Array and not (lab as Array).is_empty():
			_labels_saved = (lab as Array).duplicate()
			map.set(key, [])
			_redraw_map_layers()
		_labels_hidden = true
	elif _labels_hidden:
		_labels_hidden = false
		if map.has_method("_обновить_подписи"):
			map.call("_обновить_подписи")
		elif not _labels_saved.is_empty() and map.get(key) is Array and (map.get(key) as Array).is_empty():
			map.set(key, _labels_saved)
			_redraw_map_layers()
		_labels_saved = []


## Each member province — a soft disc of the zone's colour sized by its area; the zone's name in the middle.
func _draw_zones() -> void:
	if _zfx == null and not _zfx_tried and get_parent() != null:
		_zfx_tried = true
		_zfx = ZoneFx.new()
		get_parent().add_child(_zfx)
		get_parent().move_child(_zfx, get_index())
		if not _zfx.setup(map, func(s: String) -> void: mod.log_info(s)):
			_zfx.queue_free()
			_zfx = null
		else:
			_zone_sig = ""   # fill the districts' table now
	_zone_cells()
	var font := get_theme_default_font()
	var k := absf(_world.x) / 40075.0
	var lang := TranslationServer.get_locale().substr(0, 2)
	if _zfx != null:
		_zfx.visible = true
		_zfx.place(_origin, _world)
	# On Pax CorpInc3D's globe the members' land is tinted by the Earth's shader itself (Engine meta
	# «pax_corpinc3d_zones»): the soft discs are not drawn over it, only the names.
	var painted := _globe() and Engine.has_meta(&"pax_corpinc3d_zones") and bool(Engine.get_meta(&"pax_corpinc3d_zones"))
	for zc in (_zone_cache if _zfx == null and not painted else []):
		var col: Color = zc["col"]
		for cell in zc["cells"]:
			var s := _to_screen(cell[0])
			var r := maxf(2.0, sqrt(float(cell[1])) * k * 0.8)
			if s.x < -r or s.y < -r or s.x > size.x + r or s.y > size.y + r:
				continue
			draw_circle(s, r, Color(col, 0.2))
	for zc in _zone_cache:
		var col2: Color = zc["col"]
		var at := _to_screen(zc["uv"])
		var title := Zones.name_of(zc["z"], lang)
		const fs := 15
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var rect := Rect2(at - Vector2(tw / 2.0 + 10.0, 13.0), Vector2(tw + 20.0, 26.0))
		if not Rect2(Vector2.ZERO, size).intersects(rect):
			continue
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.08, 0.13, 0.82)
		sb.border_color = Color(col2, 0.95)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(13)
		draw_style_box(sb, rect)
		draw_string(font, rect.position + Vector2(10, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
		_zone_hits.append({"rect": rect, "id": str((zc["z"] as Dictionary).get("id", ""))})


## Drawn over the 3D Earth (globe_map.gd), not the flat map.
func _globe() -> bool:
	return is_instance_valid(map) and map.has_method("мир_на_экране")


## A point on the far side of the globe (globe_map.gd HIDDEN): no line is drawn to it.
static func _hidden(s: Vector2) -> bool:
	return s.x < -50000.0


func _screen(p: Dictionary) -> Vector2:
	return _to_screen(Data.uv_of(p))


func _to_screen(uv: Vector2) -> Vector2:
	return _origin + _world * uv if _linear else map.call("to_screen", uv, 0.0)


## The map's point under a position of this layer: Vector2(latitude, longitude) — the inverse of _to_screen.
func latlon_at(pos: Vector2) -> Vector2:
	if _globe():
		return map.call("широта_долгота", get_global_transform_with_canvas() * pos)
	_update_projection()
	if _world.x == 0.0 or _world.y == 0.0:
		return Vector2.INF
	var uv := (pos - _origin) / _world
	return Vector2(90.0 - clampf(uv.y, 0.0, 1.0) * 180.0, fposmod(uv.x, 1.0) * 360.0 - 180.0)


func _update_projection() -> void:
	if _globe():
		_world = map.call("мир_на_экране")
		_origin = Vector2.ZERO
		_linear = false
		return
	# Measured on a short step: the world map wraps at its edges, so two far points may land on different copies of
	# the world — the width then came out negative and the zones were drawn mirrored. The step whose width is
	# positive is taken (the seam can lie in one of them at most).
	var found := false
	for u: float in [0.25, 0.6, 0.85]:
		var a: Vector2 = map.call("to_screen", Vector2(u, 0.25), 0.0)
		var bx: Vector2 = map.call("to_screen", Vector2(u + 0.05, 0.25), 0.0)
		var by: Vector2 = map.call("to_screen", Vector2(u, 0.75), 0.0)
		var w := Vector2((bx.x - a.x) / 0.05, (by.y - a.y) / 0.5)
		if w.x > 0.0 and w.y != 0.0:
			_world = w
			_origin = a - w * Vector2(u, 0.25)
			found = true
			break
	if not found:
		var a2: Vector2 = map.call("to_screen", Vector2(0.25, 0.25), 0.0)
		var b2: Vector2 = map.call("to_screen", Vector2(0.75, 0.75), 0.0)
		_world = (b2 - a2) * 2.0
		_world.x = absf(_world.x)
		_origin = a2 - _world * 0.25
	_linear = true
	for probe in [Vector2(0.37, 0.61), Vector2(0.03, 0.5), Vector2(0.97, 0.5)]:
		var real: Vector2 = map.call("to_screen", probe, 0.0)
		if (real - (_origin + _world * (probe as Vector2))).length() > 1.5:
			_linear = false   # near the seam the map draws another copy — then every point asks the map
			break


func _hq_screen(c: Dictionary) -> Vector2:
	var cid := str(c["id"])
	if not _hq_uv.has(cid):
		_hq_uv[cid] = Data.uv_of(db.hq_of(c))
	return _to_screen(_hq_uv[cid])


## Level of detail: only when the map is zoomed almost all the way out (the whole world about as wide as the
## screen) do companies fold into one pie per country.
func _far_view() -> bool:
	if grouping == 1:
		return selected == ""   # always the countries' circles (a company shown on purpose still opens)
	var screen_w := maxf(size.x, 1.0)
	return absf(_world.x) > 1.0 and absf(_world.x) < screen_w * float(_cfg().get("countries_at_world_screens", 2.2)) and selected == ""


func _refresh_caches() -> void:
	if _cache_version == db.version and _cache_count == db.companies.size() and _cache_mode == mode:
		return
	_cache_version = db.version
	_cache_count = db.companies.size()
	_cache_mode = mode
	_home = ""
	_hq_uv.clear()
	# Only the companies of the current mode — fewer to sort, fan out and draw in «my country».
	_order = db.companies.filter(func(x: Dictionary) -> bool: return _shown(x))
	_order.sort_custom(func(a, b): return db.cap(a) > db.cap(b))
	# Countries: where their companies sit (weighted by √capitalisation) and their industries by capitalisation.
	var by: Dictionary = {}
	for item in _order:
		var c: Dictionary = item
		var name := str(c.get("_country", ""))
		if not by.has(name):
			by[name] = {"name": name, "uv": Vector2.ZERO, "w": 0.0, "cap": 0.0, "n": 0, "sec": {}}
		var d: Dictionary = by[name]
		var cap := maxf(db.cap(c), 0.0)
		var w := sqrt(cap) + 1.0
		d["uv"] = (d["uv"] as Vector2) + Data.uv_of(db.hq_of(c)) * w
		d["w"] = float(d["w"]) + w
		d["cap"] = float(d["cap"]) + cap
		d["n"] = int(d["n"]) + 1
		var sec := str(c.get("sector", ""))
		(d["sec"] as Dictionary)[sec] = float((d["sec"] as Dictionary).get(sec, 0.0)) + cap
	_countries.clear()
	for name in by.keys():
		var d: Dictionary = by[name]
		d["uv"] = (d["uv"] as Vector2) / maxf(float(d["w"]), 1e-6)
		var slices: Array = []
		for sec in (d["sec"] as Dictionary).keys():
			slices.append([float(d["sec"][sec]) / maxf(float(d["cap"]), 1e-6), db.sector_color(str(sec)), str(sec)])
		slices.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
		d["slices"] = slices
		_countries.append(d)
	_countries.sort_custom(func(a, b): return float(a["cap"]) > float(b["cap"]))


func _on_screen(s: Vector2) -> bool:
	return Rect2(Vector2(-40, -40), size + Vector2(80, 80)).has_point(s)


func _cfg() -> Dictionary:
	return db.balance.get("карта", {})


func _hq_radius(c: Dictionary) -> float:
	var cfg := _cfg()
	var t := sqrt(clampf(db.cap(c) / float(cfg.get("market_cap_max", 80000.0)), 0.0, 1.0))
	var r := lerpf(float(cfg.get("hq_min", 9.0)), float(cfg.get("hq_max", 22.0)), t)
	# The player's own companies start tiny — they still get a full badge, so they never look like a dot.
	return maxf(r, float(cfg.get("player_hq_min", 13.0))) if bool(c.get("made_by_player", false)) else r


func zoom() -> float:
	return float(map.get("зум"))


# ---------- drawing ----------

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_body()
	GameApi.perf("corporations.map_layer.draw", t0)


func _draw_body() -> void:
	_hits.clear()
	_fx_items.clear()
	var cfg := _cfg()
	var show_points := zoom() >= float(cfg.get("sites_from_zoom", 6.0))
	_strikes_on_screen = false
	_update_projection()
	_refresh_caches()
	_frames_all = zoom() >= float(_cfg().get("frames_all_from_zoom", 3.0))
	_zone_hits.clear()
	if zones_on:
		_draw_zones()
	elif _zfx != null:
		_zfx.visible = false
	_draw_city()
	# Real 3D buildings on screen: the companies' marks would cover them — only the chosen company keeps its marks.
	var city_on := _bld_px() > 0.0 and bank != null and bank.has_method("ext") and bank.call("ext") != null and bool((bank.call("ext") as Object).get("enabled"))
	if mode == MODE_OFF:
		return   # «Only 3D companies»: the buildings, no marks
	var order := _order
	if _far_view():
		_draw_countries()
		return
	var sites := _sites() if show_points or selected != "" else []
	_draw_site_links(sites)
	_draw_wars()
	for item in order:
		var c: Dictionary = item
		var cid := str(c["id"])
		if (show_points and selected == "" and not city_on) or cid == selected:
			_draw_points(c, cid == selected)   # each site and its line are culled on their own
	if not city_on:
		_draw_headquarters(order, show_points)
	_add_site_hits(sites)
	if not _pulse.is_empty():
		var s := _screen(_pulse["point"])
		var t := 1.0 - fmod(float(_pulse["left"]), 1.0)
		draw_arc(s, 8.0 + 22.0 * t, 0.0, TAU, 48, Color(1, 0.85, 0.35, 1.0 - t), 3.0, true)


# ---------- the 3D city ----------

## The size of a building's picture on screen, px (0 — too far away, nothing is drawn).
func _bld_px() -> float:
	if _globe():
		return 0.0   # on the globe the buildings are Pax CorpInc3D's real ones
	var w := absf(_world.x) / float(_cfg().get("buildings_divisor", 650.0))
	return minf(w, 220.0) if w >= float(_cfg().get("buildings_from_px", 36.0)) else 0.0


func _build_city() -> void:
	if _city_version == db.version and not _city.is_empty():
		return
	_city_version = db.version
	_city.clear()
	if _cells.is_empty():
		for i in range(-12, 13):
			for j in range(-12, 13):
				_cells.append(Vector2i(i, j))
		_cells.sort_custom(func(a, b): return Vector2(a).length() + 0.01 * atan2(float(a.y), float(a.x)) < Vector2(b).length() + 0.01 * atan2(float(b.y), float(b.x)))
	_flags.clear()
	for f in Pax.game.factions():
		var col: Variant = (f as Dictionary).get("colour")
		if col is Array and (col as Array).size() >= 3:
			_flags[str((f as Dictionary).get("name", ""))] = Color(float(col[0]), float(col[1]), float(col[2]))
	var by_prov := {}
	for item in db.companies:
		var c: Dictionary = item
		var pts: Array = c.get("sites", [])
		for i in pts.size():
			if not (pts[i] is Dictionary):
				continue
			var p: Dictionary = pts[i]
			var pid := int(p.get("province", 0))
			var look: Dictionary = bank.call("look_of", db, c, p, i, tree_ref)
			var list: Array = by_prov.get(pid, [])
			list.append({"cid": str(c["id"]), "idx": i, "uv": Data.uv_of(p), "look": look, "color": db.color_of(c), "cap": db.cap(c),
				"flag": _flags.get(str(c.get("_country", "")), Color.WHITE)})
			by_prov[pid] = list
	for pid in by_prov.keys():
		var list: Array = by_prov[pid]
		# The tallest in the middle: headquarters by height, then by market value.
		list.sort_custom(func(a, b): return int((a["look"] as Dictionary)["tier"]) * 1e12 + float(a["cap"]) > int((b["look"] as Dictionary)["tier"]) * 1e12 + float(b["cap"]))
		var centre: Vector2 = (list[0] as Dictionary)["uv"]
		for k in list.size():
			var e: Dictionary = list[k]
			e["uv"] = centre
			e["cell"] = _cells[mini(k, _cells.size() - 1)]
			_city.append(e)


func _draw_city() -> void:
	if bank == null:
		return
	var w := _bld_px()
	if w <= 0.0:
		return
	_build_city()
	var k := w / 256.0
	var step := w * 0.27
	# The map's view (Pax Corpface's isometric map): tilted — an isometric city, the pictures stand up out of the squashed
	# map; from above — a square grid of roofs.
	var mv: Variant = Engine.get_meta("pax_map_view") if Engine.has_meta("pax_map_view") else null
	var iso: bool = mv is Dictionary and bool((mv as Dictionary).get("iso", false))
	var tilt: float = float((mv as Dictionary).get("k", 1.0)) if iso else 1.0
	var ext := bank != null and bank.has_method("ext") and bank.call("ext") != null and bool((bank.call("ext") as Object).get("enabled"))
	if ext and not iso:
		step = w * 0.36
	var font := get_theme_default_font()
	var shown: Array = []
	for e in _city:
		var cell: Vector2i = e["cell"]
		var base := _to_screen(e["uv"]) + (Vector2(float(cell.x), float(cell.y)) * step if ext and not iso else \
			Vector2(float(cell.x - cell.y) * step, float(cell.x + cell.y) * step * 0.55 / tilt))
		if not _on_screen(base):
			continue
		shown.append([base, e])
	shown.sort_custom(func(a, b): return (a[0] as Vector2).y < (b[0] as Vector2).y)
	var t := Time.get_ticks_msec() / 1000.0
	for s in shown:
		var base: Vector2 = s[0]
		var e: Dictionary = s[1]
		var look: Dictionary = e["look"]
		var pic: Dictionary = bank.call("pic", str(look["kind"]), int(look["tier"]), "#" + (e["color"] as Color).to_html(false), str(look["state"]), bool(look["deco"]), str(look.get("frame", "")), str(look.get("sector", "")))
		if pic.is_empty():
			continue
		var anchor: Vector2 = pic["anchor"]
		var top: Vector2 = pic["top"]
		var rect := Rect2(base - anchor * k, Vector2(256, 256) * k)
		if tilt < 1.0:
			# Stand up out of the squashed map: the picture is stretched back by 1/tilt around its base.
			rect = Rect2(base - Vector2(anchor.x * k, anchor.y * k / tilt), Vector2(256.0 * k, 256.0 * k / tilt))
		var hov: bool = str(_hover.get("id", "")) == str(e["cid"]) and int(_hover.get("index", -1)) == int(e["idx"]) and _hover.has("rect")
		if hov:
			draw_circle(base, step * 1.1, Color(1.0, 0.85, 0.35, 0.35))
			draw_arc(base, step * 1.1, 0.0, TAU, 32, Color(1.0, 0.85, 0.35, 0.9), 2.0, true)
		draw_texture_rect(pic["tex"] as Texture2D, rect, false, Color(1.35, 1.3, 1.1) if hov else Color.WHITE)
		var top_s := base + (top - anchor) * k / Vector2(1.0, tilt)
		if str(look["kind"]) == "штаб" and not ext:
			# The owner country's flag on the roof.
			draw_line(top_s, top_s + Vector2(0, -step * 0.9), Color(0.9, 0.9, 0.9), 1.0, true)
			draw_rect(Rect2(top_s + Vector2(0, -step * 0.9), Vector2(step * 0.7, step * 0.4)), e["flag"] as Color)
		if bool(look["strike"]):
			_strikes_on_screen = true
			for i in 3:
				var ph := fmod(t * 0.6 + float(i) / 3.0, 1.0)
				draw_circle(top_s + Vector2(sin(t + float(i)) * step * 0.3, -step * (0.6 + 2.2 * ph)), step * (0.25 + 0.35 * ph), Color(0.6, 0.62, 0.66, 0.7 * (1.0 - ph)))
		var hit := Rect2(Vector2(base.x - step * 0.9, top_s.y - step * 0.3), Vector2(step * 1.8, base.y - top_s.y + step * 0.6))
		_hits.append({"rect": hit, "pos": base, "r": 0.0, "id": e["cid"], "point": (db.company(str(e["cid"])).get("sites", []) as Array)[int(e["idx"])] if not db.company(str(e["cid"])).is_empty() else {}, "index": e["idx"]})


func _draw_points(c: Dictionary, is_sel: bool) -> void:
	var dot_r := float(_cfg().get("site", 6.0))
	var col := db.color_of(c)
	var hq := db.hq_of(c)
	var hq_s := _hq_screen(c)
	var hq_on := _on_screen(hq_s)
	var pts: Array = c.get("sites", [])
	for i in pts.size():
		var p: Variant = pts[i]
		if not (p is Dictionary) or p == hq:
			continue
		var s := _screen(p)
		var on := _on_screen(s)
		if not on and not hq_on and not is_sel:
			continue   # neither end is visible — nothing to draw (LOD culling)
		if db.point_striking(c, i) and on:
			_strikes_on_screen = true
			var beat := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 250.0)
			draw_arc(s, dot_r + 5.0 + 2.0 * beat, 0.0, TAU, 24, Color(0.95, 0.3, 0.25, 0.6 + 0.4 * beat), 2.0, true)
		if not _hidden(hq_s) and not _hidden(s):
			draw_line(hq_s, s, Color(col.lightened(0.4), 0.7 if is_sel else 0.3), 1.5 if is_sel else 1.0, true)
		if not on:
			continue
		draw_circle(s, dot_r + 1.5, Color(0, 0, 0, 0.6))
		draw_circle(s, dot_r, col.lightened(0.15))
		if str((p as Dictionary).get("type", "")) == "промысел":
			var tex := db.icon_of(c)
			if tex != null:
				draw_texture_rect(tex, Rect2(s - Vector2(dot_r, dot_r) * 0.75, Vector2(dot_r, dot_r) * 1.5), false)
		_hits.append({"pos": s, "r": dot_r + 2.0, "id": str(c["id"]), "point": p, "index": i})


## The game's own extraction sites (the «Extraction» window) as the map draws them:
## [{pos, name, entry, owner}] where owner is the company id that runs the site ("" if none).
func _sites() -> Array:
	var raw: Variant = map.get("map_mines")
	if not (raw is Array):
		return []
	var owners := _site_owners()
	var out: Array = []
	for e in raw:
		if not (e is Dictionary) or not ((e as Dictionary).get("uv") is Vector2):
			continue
		var entry: Dictionary = e
		var site_name := str(entry.get("name", ""))
		var owner := str(owners.get(site_name, ""))
		if selected != "" and owner != selected:
			continue
		if owner != "" and not _shown(db.company(owner)):
			continue
		var s: Vector2 = _to_screen(entry["uv"])
		if _on_screen(s) or (owner != "" and _on_screen(_hq_screen(db.company(owner)))):
			out.append({"pos": s, "name": site_name, "entry": entry, "owner": owner})
	return out


func _site_owners() -> Dictionary:
	if _owners_cache.is_empty():
		for c in db.companies:
			for n in (c as Dictionary).get("промыслы", []):
				_owners_cache[str(n)] = str((c as Dictionary)["id"])
	return _owners_cache


## Corporate wars (rivals.gd): a pulsing red line between the two headquarters, crossed swords in the middle.
func _draw_wars() -> void:
	_strikes_on_screen = _strikes_on_screen or not db.wars.is_empty()
	var beat := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0)
	for w in db.wars:
		var a := db.company(str(w["a"]))
		var b := db.company(str(w["b"]))
		if a.is_empty() or b.is_empty() or not (_shown(a) or _shown(b)):
			continue
		var sa := _screen(db.hq_of(a))
		var sb := _screen(db.hq_of(b))
		if not (_on_screen(sa) or _on_screen(sb)) or _hidden(sa) or _hidden(sb):
			continue
		var dim := selected != "" and selected != str(w["a"]) and selected != str(w["b"])
		var alpha := (0.15 if dim else 0.45 + 0.4 * beat) * (0.6 + 0.4 * float(w.get("heat", 0.5)))
		draw_dashed_line(sa, sb, Color(0.95, 0.25, 0.2, alpha), 2.0 + 1.5 * float(w.get("heat", 0.5)), 8.0, true)
		if not dim:
			var mid := (sa + sb) / 2.0
			draw_circle(mid, 9.0, Color(0.15, 0.03, 0.03, 0.85))
			draw_string(get_theme_default_font(), mid + Vector2(-7, 5), "⚔", HORIZONTAL_ALIGNMENT_CENTER, 14, 13, Color(1, 0.4, 0.3, 0.6 + 0.4 * beat))


func _draw_site_links(sites: Array) -> void:
	for s in sites:
		var owner := str(s["owner"])
		if owner.is_empty():
			continue
		var c := db.company(owner)
		var hq_s := _screen(db.hq_of(c))
		var sel := owner == selected
		if not _hidden(hq_s):
			draw_line(hq_s, s["pos"] as Vector2, Color(db.color_of(c).lightened(0.4), 0.75 if sel else 0.4), 1.5 if sel else 1.0, true)
		draw_arc(s["pos"] as Vector2, 9.0, 0.0, TAU, 24, Color(db.color_of(c).lightened(0.4), 0.8), 1.5, true)


func _add_site_hits(sites: Array) -> void:
	for s in sites:
		if _on_screen(s["pos"] as Vector2):
			_hits.append({"pos": s["pos"], "r": 10.0, "site": s})


## Headquarters without overlaps. 1) Companies of one country whose badges touch form a group. 2) Groups of
## one country whose drawn shapes touch merge. 3) Groups of different countries that still touch are pushed
## apart, each keeping a thin leader line to where it really is. A group is drawn as a badge (1), a fan
## (2..FAN_MAX) or a cluster donut (more).
func _draw_headquarters(order: Array, labels: bool) -> void:
	# The layout made for this very view on a worker thread (_request_layout) — or, not ready, made here.
	var groups: Array = _layout_cache.get(_view_key, []) if _layout_cache.has(_view_key) else HqGroups.layout(_badges(order), _layout_cell())
	for g in groups:
		_draw_group(g, labels)


## The badges on the screen now: [{c, pos, r, country}] (the input of the layout).
func _badges(order: Array) -> Array:
	var out: Array = []
	for item in order:
		var c: Dictionary = item
		var s := _hq_screen(c)
		if not _on_screen(s):
			continue
		out.append({"c": c, "pos": s, "r": _hq_radius(c), "country": str(c.get("_country", ""))})
	return out


func _layout_cell() -> float:
	return 2.0 * float(_cfg().get("hq_max", 22.0)) + 2.0


func _draw_group(g: Dictionary, labels: bool) -> void:
	var items: Array = g["items"]
	var pos: Vector2 = g["pos"]
	var anchor: Vector2 = g["anchor"]
	if (pos - anchor).length() > 4.0:
		draw_line(anchor, pos, Color(1, 1, 1, 0.35), 1.0, true)
		draw_circle(anchor, 2.5, Color(1, 1, 1, 0.7))
	if items.size() == 1:
		_draw_hq(items[0]["c"], pos, float(items[0]["r"]), labels)
		return
	var maxr := float(g["maxr"])
	if items.size() > FAN_MAX:
		items.sort_custom(func(x, y): return db.cap(x["c"]) > db.cap(y["c"]))
		_draw_crowd(items, pos, maxr)
		return
	var radius := HqGroups.fan_radius(items, maxr)
	# The ring of the selected company stays lit and clickable — its neighbours are one click away.
	var has_selected := items.any(func(it): return str((it["c"] as Dictionary)["id"]) == selected)
	draw_circle(pos, radius + maxr + 3.0, Color(0, 0, 0, 0.14))
	for i in items.size():
		var it: Dictionary = items[i]
		var a := -PI / 2.0 + TAU * float(i) / float(items.size())
		var at := pos + Vector2(cos(a), sin(a)) * radius
		draw_line(it["pos"] as Vector2, at, Color(1, 1, 1, 0.3), 1.0, true)
		_draw_hq(it["c"], at, float(it["r"]), false, has_selected)   # names in a ring overlap — the hover label says it


func _draw_hq(c: Dictionary, s: Vector2, r: float, labels: bool, bright: bool = false) -> void:
	var cid := str(c["id"])
	var dim := selected != "" and cid != selected and not bright
	var a := 0.3 if dim else 1.0
	draw_circle(s, r + 2.0, Color(0, 0, 0, 0.6 * a))
	draw_circle(s, r, Color(db.color_of(c), a))
	if cid == selected:
		draw_arc(s, r + 4.0, 0.0, TAU, 40, Color(1, 0.85, 0.35), 2.0, true)
	elif bool(c.get("made_by_player", false)):
		draw_arc(s, r + 2.5, 0.0, TAU, 40, Color(0.95, 0.78, 0.32, 0.9 * a), 1.5, true)   # the player's own company
	_frame(s, r, Frames.of(c), dim)
	var tex := db.icon_of(c)
	if tex != null:
		# Small badges still get a readable icon (at least 14 px).
		var half := maxf(r * 0.62, 7.0)
		draw_texture_rect(tex, Rect2(s - Vector2(half, half), Vector2(half, half) * 2.0), false, Color(1, 1, 1, a))
	if dim:
		return
	_hits.append({"pos": s, "r": r + 2.0, "id": cid, "point": db.hq_of(c)})
	if labels:
		var font := get_theme_default_font()
		var fs := get_theme_default_font_size() - 2
		_label(db.name_of(c), s + Vector2(r + 4.0, 4.0), font, fs, Color(1, 1, 1, 0.95))


## The names on the map, shaped once (TextLine) and kept: draw_string shaped every name again at every redraw, twice
## (the outline and the text) — with the whole world's companies that was the most of a redraw. Key: text, size, font.
var _lines: Dictionary = {}


func _label_line(text: String, font: Font, fs: int) -> TextLine:
	var key := "%s|%d|%d" % [text, fs, font.get_instance_id()]
	var tl: Variant = _lines.get(key)
	if tl is TextLine:
		return tl
	if _lines.size() > 4000:
		_lines.clear()
	var line := TextLine.new()
	line.add_string(text, font, fs)
	_lines[key] = line
	return line


## A name with its dark outline (4 px), «at» on the baseline as draw_string had it.
func _label(text: String, at: Vector2, font: Font, fs: int, col: Color) -> void:
	var line := _label_line(text, font, fs)
	var top := at - Vector2(0.0, line.get_line_ascent())
	line.draw_outline(get_canvas_item(), top, 4, Color(0, 0, 0, 0.8))
	line.draw(get_canvas_item(), top, col)


## A status frame on the map (the same drawing as in the windows): far out only sapphire and diamond.
func _frame(s: Vector2, r: float, tier: String, dim: bool) -> void:
	if tier.is_empty() or not Frames.on_map or dim:
		return
	if not _frames_all and Frames.rank(tier) < Frames.rank("sapphire") and not _far_view():
		return
	var ring := Frames.baked_ring(tier, r)
	if ring != null:
		var half := Vector2(ring.get_size()) / 2.0
		draw_texture(ring, s - half)   # one ready picture instead of two arcs (frames.gd baked_ring)
	else:
		Frames.draw(self, s, r, tier, Frames.PART_STATIC)
	if Frames.animated(tier):
		_fx_items.append([s, r, tier])


## Too many companies in one place: a cluster — a ring split by the industries of the companies in it
## (by capitalisation), the number of companies in the middle, the three biggest icons along the bottom.
## A click opens the scrollable list.
func _draw_crowd(items: Array, center: Vector2, r: float) -> void:
	var caps: Dictionary = {}
	var total := 0.0
	var ids: Array = []
	for it in items:
		var c: Dictionary = it["c"]
		ids.append(str(c["id"]))
		var sec := str(c.get("sector", ""))
		var cap := maxf(db.cap(c), 1.0)
		caps[sec] = float(caps.get(sec, 0.0)) + cap
		total += cap
	var slices: Array = []
	for sec in caps.keys():
		slices.append([float(caps[sec]) / total, db.sector_color(str(sec))])
	slices.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var outer := r + 9.0
	_draw_donut(center, outer, outer - 6.0, slices, str(items.size()), 15, Color(0.95, 0.78, 0.32))
	# The biggest companies as small badges hanging on the ring's lower edge.
	var shown := mini(3, items.size())
	for i in shown:
		var c: Dictionary = items[i]["c"]
		var at := center + Vector2((float(i) - float(shown - 1) / 2.0) * 13.0, outer + 3.0)
		draw_circle(at, 7.0, Color(0, 0, 0, 0.7))
		draw_circle(at, 6.0, db.color_of(c))
		var tex := db.icon_of(c)
		if tex != null:
			draw_texture_rect(tex, Rect2(at - Vector2(4.5, 4.5), Vector2(9, 9)), false)
	_hits.append({"pos": center, "r": outer + 4.0, "crowd": ids})


## A donut chart: slices [[share, color], …] between two radii, a dark centre with a caption.
func _draw_donut(center: Vector2, outer: float, inner: float, slices: Array, caption: String, font_size: int, rim: Color) -> void:
	draw_circle(center + Vector2(2, 3), outer + 2.0, Color(0, 0, 0, 0.35))
	draw_circle(center, outer + 1.5, Color(0.04, 0.05, 0.07, 0.9))
	var start := -PI / 2.0
	for s in slices:
		var share := float(s[0])
		if share <= 0.0005:
			continue
		var end := start + TAU * share
		var pts := PackedVector2Array()
		var steps := maxi(2, int(48.0 * share))
		for k in steps + 1:
			var a := lerpf(start, end, float(k) / float(steps))
			pts.append(center + Vector2(cos(a), sin(a)) * outer)
		for k in range(steps, -1, -1):
			var a := lerpf(start, end, float(k) / float(steps))
			pts.append(center + Vector2(cos(a), sin(a)) * inner)
		draw_colored_polygon(pts, s[1] as Color)
		start = end
	draw_circle(center, inner - 0.5, Color(0.06, 0.07, 0.09, 0.95))
	draw_arc(center, outer + 1.5, 0.0, TAU, 48, Color(rim, 0.85), 1.5, true)
	if not caption.is_empty():
		var font := get_theme_default_font()
		var w := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, center + Vector2(-w / 2.0, font_size * 0.36), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.95))


## Far view: one donut per country — its industries by capitalisation, the number of companies inside,
## the size by the country's total capitalisation. A click brings the map close enough to see companies.
func _draw_countries() -> void:
	var cfg := _cfg()
	var max_cap := 1.0
	for d in _countries:
		max_cap = maxf(max_cap, float((d as Dictionary)["cap"]))
	var r_min := float(cfg.get("country_min", 11.0))
	var r_max := float(cfg.get("country_max", 30.0))
	var font := get_theme_default_font()
	# Neighbours (Benelux, the Baltics) would sit on each other — push the donuts apart, keep a leader line.
	var shown: Array = []
	for item in _countries:
		var d: Dictionary = item
		var s := _to_screen(d["uv"])
		if not _on_screen(s):
			continue
		var r := lerpf(r_min, r_max, sqrt(float(d["cap"]) / max_cap))
		shown.append({"d": d, "anchor": s, "pos": s, "R": r + 2.0, "r": r})
	HqGroups.push_apart(shown, 12)
	for g in shown:
		var d: Dictionary = g["d"]
		var s: Vector2 = g["pos"]
		var r := float(g["r"])
		if (s - (g["anchor"] as Vector2)).length() > 4.0:
			draw_line(g["anchor"], s, Color(1, 1, 1, 0.4), 1.0, true)
			draw_circle(g["anchor"], 2.5, Color(1, 1, 1, 0.8))
		var hovered := _hover.has("country") and str(_hover["country"]) == str(d["name"])
		_draw_donut(s, r, r * 0.58, d["slices"], str(int(d["n"])), int(clampf(r * 0.55, 9.0, 16.0)),
			Color(0.95, 0.78, 0.32) if hovered else Color(1, 1, 1, 0.5))
		# The circle gets the frame of the country's best company (frames.gd).
		var best: Array = Frames.country_best.get(str(d["name"]), [])
		if not best.is_empty():
			_frame(s, r + 1.5, str(best[0]), false)
		if r >= 18.0:
			var name := str(d["name"])
			var w := _label_line(name, font, 12).get_size().x
			_label(name, s + Vector2(-w / 2.0, r + 15.0), font, 12, Color(1, 1, 1, 0.9))
		_hits.append({"pos": s, "r": r + 2.0, "country": str(d["name"]), "uv": d["uv"]})


## Console «corp map»: what the level-of-detail switch sees now.
func debug_info() -> String:
	_update_projection()
	return "world on screen %.0f px, screen %.0f px, zoom %.2f, linear %s, countries view %s (below %.0f px)" % [
		absf(_world.x), size.x, zoom(), str(_linear), str(_far_view()), size.x * float(_cfg().get("countries_at_world_screens", 2.2))]


func _country(name: String) -> Dictionary:
	for d in _countries:
		if str((d as Dictionary)["name"]) == name:
			return d
	return {}


## Close in on a country from the far view: just past the zoom where companies unfold.
func _zoom_to_country(uv: Vector2) -> void:
	if not map.has_method("навести_на"):
		return
	var threshold := maxf(size.x, 1.0) * float(_cfg().get("countries_at_world_screens", 2.2))
	var want := zoom() * threshold * 2.5 / maxf(absf(_world.x), 1.0)
	map.call("навести_на", uv, maxf(want, zoom()))


## Which country runs a site: the game's full record in Main.промыслы has «чей».
func _site_country(site_name: String) -> String:
	var all: Variant = game.main.get("промыслы")
	if all is Array:
		for p in all:
			if p is Dictionary and str((p as Dictionary).get("name", "")) == site_name:
				return str((p as Dictionary).get("whose", ""))
	return ""


## The hover label, drawn by _tip on the top canvas layer (above the map's province card).
func _draw_tip() -> void:
	if _hover.is_empty() or not visible:
		return
	var font := _tip.get_theme_default_font()
	var fs := _tip.get_theme_default_font_size()
	var lines: Array = []
	var accent := Color(1, 1, 1)
	if _hover.has("site"):
		var s: Dictionary = _hover["site"]
		var entry: Dictionary = s["entry"]
		lines.append(str(s["name"]))
		var owner := db.company(str(s["owner"]))
		if not owner.is_empty():
			lines.append(mod.tr_key("pax_corporations_site_owner") % [db.name_of(owner), db.money(db.cap(owner))])
			accent = db.color_of(owner).lightened(0.3)
		else:
			accent = Color(0.7, 0.7, 0.7)
		var country := _site_country(str(s["name"]))
		if not country.is_empty():
			lines.append(mod.tr_key("pax_corporations_site_country") % country)
		var note := str(entry.get("подпись", ""))
		if not note.is_empty():
			lines.append(note)
	elif _hover.has("country"):
		var d := _country(str(_hover["country"]))
		if d.is_empty():
			return
		lines.append(str(d["name"]))
		lines.append(mod.tr_key("pax_corporations_map_country") % [int(d["n"]), db.money(float(d["cap"]))])
		for s in (d["slices"] as Array).slice(0, 6):
			lines.append("■ %s — %s" % [db.sector_name(str(s[2])), db.percent(float(s[0]))])
		var best: Array = Frames.country_best.get(str(d["name"]), [])
		if not best.is_empty():
			var bc := db.company(str(best[1]))
			if not bc.is_empty():
				lines.append(mod.tr_key("pax_corporations_frame_country_best") % [db.name_of(bc),
					mod.tr_key("pax_corporations_" + Frames.label_key(str(best[0]))), int(bc.get("_world_place", 0))])
		lines.append(mod.tr_key("pax_corporations_map_country_list" if grouping == 1 else "pax_corporations_map_country_click"))
		accent = Color(0.95, 0.78, 0.32)
	elif _hover.has("crowd"):
		var crowd: Array = _hover["crowd"]
		for cid in crowd.slice(0, 12):
			var c := db.company(str(cid))
			lines.append(db.name_of(c) + "  ·  " + db.money(db.cap(c)))
		if crowd.size() > 12:
			lines.append(mod.tr_key("pax_corporations_markets_rest") % (crowd.size() - 12))
		lines.push_front(mod.tr_key("pax_corporations_crowd") % crowd.size())
		accent = Color(0.95, 0.78, 0.32)
	else:
		var c := db.company(str(_hover["id"]))
		if c.is_empty():
			return
		var p: Dictionary = _hover["point"]
		lines.append(db.name_of(c) + "  ·  " + db.money(db.cap(c)))
		if not Frames.of(c).is_empty():
			lines.append(mod.tr_key("pax_corporations_frame_line") % [mod.tr_key("pax_corporations_" + Frames.label_key(Frames.of(c))), int(c.get("_world_place", 0))] + Frames.why_line(c, func(k: String) -> String: return mod.tr_key("pax_corporations_" + k)))
		lines.append(db.point_type_name(str(p.get("type", ""))) + ": " + db.text(p.get("name", "")))
		var idx := int(_hover.get("index", (c.get("sites", []) as Array).find(p)))
		if idx >= 0:
			lines.append(mod.tr_key("pax_corporations_employees_short") % db.people(db.point_staff(c, idx)))
			if db.point_striking(c, idx):
				lines.append("⚠ " + mod.tr_key("pax_corporations_on_strike"))
			elif not db.econ(c).is_empty():
				var h := db.point_satisfaction(c, idx)
				lines.append(mod.tr_key("pax_corporations_st_satisfaction") + ": " + mod.tr_key("pax_corporations_sat_level_%d" % clampi(int(h * 5.0), 0, 4)))
		accent = db.color_of(c).lightened(0.3)
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(str(l), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var at: Vector2 = get_global_transform_with_canvas() * (_hover["pos"] as Vector2) + Vector2(18, -10)
	var box := Rect2(at, Vector2(w + 16.0, lines.size() * (fs + 4.0) + 10.0))
	var screen := _tip.get_viewport_rect().size
	if box.end.x > screen.x:
		box.position.x -= box.size.x + 36.0
	if box.end.y > screen.y:
		box.position.y = screen.y - box.size.y - 4.0
	_tip.draw_rect(box, Color(0.06, 0.07, 0.09, 0.95))
	_tip.draw_rect(box, Color(accent, 0.8), false, 1.0)
	for i in lines.size():
		_tip.draw_string(font, box.position + Vector2(8, 6 + fs + i * (fs + 4.0)), str(lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1, 1, 1, 1.0 if i == 0 else 0.75))


# ---------- input ----------

## Pick mode (founding a company): the next left click on a province calls back with its id and its owner.
## The map shows the Earth. Other bodies (the Moon, Mars) have their own provinces and numbers since the game gave
## them a cut too — the companies, zones and sites are the Earth's, so the layer stays off there.
func on_earth() -> bool:
	if not is_instance_valid(map):
		return false
	var earth: Variant = map.get("_это_земля")
	return earth == null or bool(earth)


func pick_province(callback: Callable) -> void:
	_pick = callback
	if mode == MODE_OFF:
		set_mode(MODE_HOME)
	selected = ""


## The province under the cursor and who owns it: [id, owner] or [-1, ""].
func hovered_province() -> Array:
	if not on_earth():
		return [-1, ""]
	var pid: Variant = map.get("наведена")
	if pid == null or int(pid) < 0:
		return [-1, ""]
	return [int(pid), Data.owner_in(Data.province_owners(), int(pid))]


func _input(event: InputEvent) -> void:
	if _pick.is_valid() and event is InputEventMouseButton and (event as InputEventMouseButton).pressed and is_instance_valid(map) and map.visible:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			var cancel := _pick
			_pick = Callable()
			cancel.call(-1, "", Vector2.INF)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and _pointer_on_map() and on_earth():
			var hit := hovered_province()
			if int(hit[0]) >= 0:
				var cb := _pick
				_pick = Callable()
				cb.call(int(hit[0]), str(hit[1]), latlon_at(get_local_mouse_position()))
				get_viewport().set_input_as_handled()
				return
	if not visible or (is_instance_valid(_menu) and _menu.visible):
		return
	if event is InputEventMouseMotion:
		_hover = _hit_at(get_local_mouse_position()) if _pointer_on_map() else {}
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var at := get_local_mouse_position()
			for zh in _zone_hits:
				if ((zh as Dictionary)["rect"] as Rect2).has_point(at) and on_zone.is_valid() and _pointer_on_map():
					on_zone.call(str((zh as Dictionary)["id"]))
					get_viewport().set_input_as_handled()
					return
			var hit := _hit_at(get_local_mouse_position())
			if not _pointer_on_map():
				return
			if hit.is_empty():
				# A left click on the empty map leaves the company mode and closes the window;
				# the click itself still goes to the game (province selection).
				selected = ""
				if on_background.is_valid():
					on_background.call()
				return
			if hit.has("site"):
				var owner := str((hit["site"] as Dictionary)["owner"])
				if owner.is_empty():
					return   # a site nobody in the mod runs — the game handles the click
				selected = owner
				on_open.call(owner)
			elif hit.has("crowd"):
				_open_crowd(hit["crowd"])
			elif hit.has("country"):
				if grouping == 1:
					_open_country(str(hit["country"]))   # the circles stay — show the country's companies instead
				else:
					_zoom_to_country(hit["uv"])
			else:
				selected = str(hit["id"])
				on_open.call(selected)
			get_viewport().set_input_as_handled()


## «Always circles» mode: a click on a country's circle lists its companies, the biggest first.
func _open_country(country: String) -> void:
	var list: Array = _order.filter(func(x: Dictionary) -> bool: return str(x.get("_country", "")) == country)
	list.sort_custom(func(a, b): return db.cap(a) > db.cap(b))
	_open_crowd(list.map(func(x): return str(x["id"])))


func _open_crowd(ids: Array) -> void:
	_menu.clear()
	_menu_ids = ids.duplicate()
	for i in ids.size():
		var c := db.company(str(ids[i]))
		_menu.add_icon_item(db.icon_of(c), "%s  ·  %s" % [db.name_of(c), db.money(db.cap(c))], i)
		_menu.set_item_icon_modulate(i, db.color_of(c).lightened(0.5))
		_menu.set_item_icon_max_width(i, 18)
	_menu.reset_size()
	_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))
	_hover = {}


func _hit_at(at: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	var building: Dictionary = {}
	for h in _hits:
		if h.has("rect"):
			if (h["rect"] as Rect2).has_point(at):
				building = h   # drawn back to front: the last one under the cursor is the front one
			continue
		var d := (at - (h["pos"] as Vector2)).length()
		if d <= float(h["r"]) and d < best_d:
			best_d = d
			best = h
	return best if not best.is_empty() else building


## True when the cursor is over the map itself, not over a window or a button on top of it.
func _pointer_on_map() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if _globe():
		return bool(map.call("мышь_на_карте", hovered))
	if hovered == null:
		return true
	if not map.is_ancestor_of(hovered):
		return false
	var node: Node = hovered
	while node != null and node != map:
		if node is BaseButton or node is PanelContainer:
			return false
		node = node.get_parent()
	return true


# ---------- focus from the window ----------

## Centre the map on a company's headquarters and switch to its company mode.
func focus_company(cid: String) -> void:
	var c := db.company(cid)
	if not c.is_empty():
		focus_point(cid, db.hq_of(c))


## Centre the map on one point of a company, close enough to see its points, and make it pulse.
func focus_point(cid: String, point: Dictionary) -> void:
	if not is_instance_valid(map) or point.is_empty():
		return
	if not _shown(db.company(cid)):
		set_mode(MODE_WORLD)
	selected = cid
	var want := maxf(zoom(), float(_cfg().get("switch_zoom", 12.0)))
	if map.has_method("навести_на"):
		map.call("навести_на", Data.uv_of(point), want)
	_pulse = {"point": point, "left": PULSE_TIME}
