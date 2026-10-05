extends Node
## 3D buildings of the corporations on the game's map (ideas doc, section 12). The game's map is a flat picture of the
## world drawn over the scene, so the voxel models are not put on the globe: each model is photographed once by an
## isometric camera in a hidden render window (SubViewport, its own 3D world, a light) and the picture is kept; the
## map layer (map_layer.gd) draws these pictures at the companies' sites. One fixed camera scale for every model, so
## a tower stands taller than a warehouse. Pictures are made lazily — only the ones the map asks for, one or two a
## frame — and cached by (kind, height, colour, state, decoration).
##
## The model library (~10 models by the type of the site, built from data by Pax.voxel.model_mesh — no model files,
## no voxel component): штаб — a tower, 5 heights by market value; офис; завод with chimneys; нии with a dome;
## датацентр with cooling lights; промысел — a derrick; логистика with a crane; космодром with a rocket; руины; and
## a cube for anything else. States: кризис — dark windows; банкрот / заморожена — grey; руины.

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const WINDOW := "#ffe9a8"
const WINDOW_DARK := "#2f343c"
const ROOF := "#cfd6df"
const GREY := "#7c828c"
const PX := 256                  # the photo's side, px
const ORTHO := 64.0              # the camera sees this many voxels top to bottom — the same for every model
const PER_FRAME := 2

var _vp: SubViewport
var _cam: Camera3D
var _mi: MeshInstance3D
var _mat: StandardMaterial3D
var _pics: Dictionary = {}       # key -> {tex, anchor (px), top (px)}
var _queue: Array = []           # keys waiting: [key, data, size]
var _busy := false
var on_ready: Callable           # func() — new pictures are there (the map redraws)


func _ready() -> void:
	name = "PaxCorpBuildings"
	_vp = SubViewport.new()
	_vp.size = Vector2i(PX, PX)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.55
	env.environment = e
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = ORTHO
	_cam.near = 0.1
	_cam.far = 1000.0
	# Isometric: from the south-east, 30° above the ground; the model's base centre sits low in the picture.
	_cam.position = Vector3(1, 0.82, 1).normalized() * 200.0 + Vector3(0, ORTHO * 0.32, 0)
	_vp.add_child(_cam)
	_cam.look_at(Vector3(0, ORTHO * 0.32, 0), Vector3.UP)
	_mi = MeshInstance3D.new()
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.9
	_mi.material_override = _mat
	_vp.add_child(_mi)


func _process(_delta: float) -> void:
	if not _busy and not _queue.is_empty():
		_render_next()


## The picture of a building, or {} while it is being made (asked again on the next redraw).
func pic(kind: String, tier: int, color: String, state: String, deco: bool) -> Dictionary:
	var key := "%s|%d|%s|%s|%s" % [kind, tier, color, state, str(deco)]
	if _pics.has(key):
		return _pics[key]
	for q in _queue:
		if str((q as Array)[0]) == key:
			return {}
	_queue.append([key, model(kind, tier, color, state, deco, "")])
	return {}


func _render_next() -> void:
	_busy = true
	var n := 0
	while n < PER_FRAME and not _queue.is_empty():
		var q: Array = _queue.pop_front()
		var key := str(q[0])
		var data: Dictionary = q[1]
		var sz: Array = data["size"]
		var mesh: Mesh = Pax.voxel.model_mesh(data)
		_mi.mesh = mesh
		# The grid starts at its corner: move it so its base centre is at the origin.
		_mi.position = Vector3(-float(sz[0]) / 2.0, 0.0, -float(sz[2]) / 2.0)
		var anchor := _cam.unproject_position(Vector3.ZERO)
		var top := _cam.unproject_position(Vector3(0, float(sz[1]), 0))
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_instance_valid(_vp):
			return
		var img := _vp.get_texture().get_image()
		_pics[key] = {"tex": ImageTexture.create_from_image(img), "anchor": anchor, "top": top}
		n += 1
	_busy = false
	if on_ready.is_valid():
		on_ready.call()


## Which model a site gets: {kind, tier, state, deco}.
static func look_of(db: Data, c: Dictionary, p: Dictionary, index: int, tree_ref: Object) -> Dictionary:
	var e := db.econ(c)
	var kind := str(p.get("type", "office"))
	var status := str(p.get("_status", ""))
	var state := "норма"
	if status == "уничтожена":
		state = "руины"
	elif not status.is_empty():
		state = "frozen_f"
	elif not (e.get("банкротство", {}) as Dictionary).is_empty():
		state = "банкрот"
	elif int(e.get("ladder", 0)) >= 3 or (float(e.get("P", 0.0)) < 0.0 and float(e.get("money", 0.0)) < 0.0):
		state = "кризис"
	var tier := tier_of(db, c) if kind == "штаб" else 1
	var deco := kind == "штаб" and _decorated(c, tree_ref)
	return {"kind": kind if state != "руины" else "руины", "tier": tier, "state": state, "deco": deco,
		"strike": db.point_striking(c, index) and state != "руины"}


## The height step of a headquarters by the company's market value (5 steps).
static func tier_of(db: Data, c: Dictionary) -> int:
	var cap := db.cap(c)
	if cap >= 1e6:
		return 5
	if cap >= 2e5:
		return 4
	if cap >= 5e4:
		return 3
	if cap >= 1e4:
		return 2
	return 1


## A 3-GV node of the industry's tree open in the company's country — an antenna with a light on the headquarters.
static func _decorated(c: Dictionary, tree_ref: Object) -> bool:
	if tree_ref == null:
		return false
	var k := str(c.get("_country", "")) + "|" + str(c.get("sector", ""))
	var opened: Dictionary = (tree_ref.get("opened") as Dictionary).get(k, {})
	for id in opened.keys():
		var n: Dictionary = tree_ref.call("node", str(c.get("sector", "")), str(id))
		if int(n.get("price", 1)) >= 3:
			return true
	return false


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)


# ---------- the model library ----------

## The model's data (Pax.voxel format): palette 1 walls, 2 trim, 3 windows, 4 roof, 5 flag, 6 light.
static func model(kind: String, tier: int, color: String, state: String, deco: bool, flag: String) -> Dictionary:
	var wall := color
	var win := WINDOW
	if state == "кризис" or state == "frozen_f":
		win = WINDOW_DARK
	if state == "банкрот" or state == "frozen_f":
		wall = GREY
	var trim := Color.html(wall).darkened(0.35).to_html(false)
	var pal := [wall, "#" + trim, win, ROOF, flag if not flag.is_empty() else "#ffffff", "#ffd75a"]
	var s: Array = []
	var v: Array = []
	var size := [16, 16, 16]
	match kind:
		"штаб":
			var h := 10 + tier * 8
			size = [14, h + 10, 14]
			s.append(_box([3, 0, 3], [10, h, 10], 1))
			s.append(_box([2, 0, 2], [11, 2, 11], 2))
			for y in range(3, h - 1, 3):
				s.append(_box([3, y, 2], [10, y, 2], 3))
				s.append(_box([3, y, 11], [10, y, 11], 3))
				s.append(_box([2, y, 3], [2, y, 10], 3))
				s.append(_box([11, y, 3], [11, y, 10], 3))
			s.append(_box([4, h + 1, 4], [9, h + 1, 9], 4))
			if not flag.is_empty():
				s.append({"type": "line", "from": [9, h + 1, 9], "to": [9, h + 6, 9], "width": 1, "color": 4})
				s.append(_box([10, h + 4, 9], [12, h + 6, 9], 5))
			if deco:
				s.append({"type": "line", "from": [6, h + 1, 6], "to": [6, h + 9, 6], "width": 1, "color": 2})
				v.append([6, h + 9, 6, 6])
		"office":
			size = [16, 10, 12]
			s.append(_box([1, 0, 1], [14, 7, 10], 1))
			for y in [2, 5]:
				s.append(_box([1, y, 0], [14, y, 0], 3))
				s.append(_box([1, y, 11], [14, y, 11], 3))
			s.append(_box([2, 8, 2], [13, 8, 9], 4))
		"завод":
			size = [22, 18, 14]
			s.append(_box([1, 0, 1], [16, 6, 12], 1))
			s.append(_box([1, 7, 1], [16, 7, 12], 4))
			s.append({"type": "cylinder", "center": [18, 0, 4], "radius": 1.6, "height": 15, "color": 2})
			s.append({"type": "cylinder", "center": [18, 0, 9], "radius": 1.6, "height": 12, "color": 2})
			s.append(_box([2, 3, 0], [15, 3, 0], 3))
		"нии":
			size = [16, 14, 16]
			s.append(_box([1, 0, 1], [14, 5, 14], 1))
			s.append({"type": "sphere", "center": [8, 6, 8], "radius": 5, "color": 4})
			s.append(_box([1, 6, 1], [14, 6, 14], 2))
			s.append(_box([1, 2, 0], [14, 2, 0], 3))
		"датацентр":
			size = [24, 8, 10]
			s.append(_box([1, 0, 1], [22, 4, 8], 1))
			s.append(_box([1, 5, 1], [22, 5, 8], 4))
			for x in range(2, 22, 3):
				v.append([x, 3, 0, 6])
				v.append([x, 6, 4, 3])
		"промысел":
			size = [12, 24, 12]
			s.append(_box([1, 0, 1], [10, 1, 10], 2))
			s.append({"type": "line", "from": [2, 1, 2], "to": [6, 22, 6], "width": 1, "color": 1})
			s.append({"type": "line", "from": [10, 1, 2], "to": [6, 22, 6], "width": 1, "color": 1})
			s.append({"type": "line", "from": [2, 1, 10], "to": [6, 22, 6], "width": 1, "color": 1})
			s.append({"type": "line", "from": [10, 1, 10], "to": [6, 22, 6], "width": 1, "color": 1})
			for y in [6, 12, 17]:
				s.append(_box([3, y, 3], [9, y, 9], 2))
			v.append([6, 23, 6, 6])
		"logistics":
			size = [22, 16, 14]
			s.append(_box([1, 0, 1], [9, 5, 12], 1))
			s.append(_box([11, 0, 1], [19, 5, 12], 1))
			s.append(_box([1, 6, 1], [19, 6, 12], 4))
			s.append({"type": "line", "from": [20, 0, 6], "to": [20, 14, 6], "width": 1, "color": 2})
			s.append({"type": "line", "from": [12, 14, 6], "to": [21, 14, 6], "width": 1, "color": 2})
		"космодром":
			size = [18, 26, 18]
			s.append(_box([1, 0, 1], [16, 1, 16], 2))
			s.append({"type": "cylinder", "center": [9, 2, 9], "radius": 2.2, "height": 18, "color": 4})
			s.append({"type": "sphere", "center": [9, 20, 9], "radius": 2.2, "color": 1})
			s.append({"type": "line", "from": [13, 2, 9], "to": [13, 20, 9], "width": 1, "color": 2})
		"руины":
			size = [18, 6, 18]
			pal = ["#3a3330", "#5a524c", "#1d1a18", GREY, "#3a3330", "#ff7a2a"]
			s.append({"type": "torus", "center": [9, 0, 9], "radius": 7, "tube": 1.2, "color": 3})
			s.append(_box([4, 0, 5], [7, 3, 8], 2))
			s.append(_box([10, 0, 9], [12, 2, 12], 1))
			s.append(_box([8, 0, 4], [9, 4, 5], 2))
			v.append([6, 4, 6, 6])
		"дым":
			size = [12, 12, 12]
			pal = ["#9aa0a8", "#c3c8ce", "#80868e", "#9aa0a8", "#9aa0a8", "#9aa0a8"]
			s.append({"type": "sphere", "center": [5, 4, 5], "radius": 3.5, "color": 1})
			s.append({"type": "sphere", "center": [7, 7, 6], "radius": 3, "color": 2})
			s.append({"type": "sphere", "center": [5, 9, 7], "radius": 2.2, "color": 3})
		_:
			size = [8, 8, 8]
			s.append(_box([1, 0, 1], [6, 5, 6], 1))
	return {"size": size, "palette": pal, "shapes": s, "voxels": v}


static func _box(a: Array, b: Array, color: int) -> Dictionary:
	return {"type": "box", "from": a, "to": b, "color": color}
