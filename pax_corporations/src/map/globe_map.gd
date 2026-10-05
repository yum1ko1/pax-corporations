extends CanvasLayer
## The corporations' layer (map_layer.gd) over the 3D Earth, for play from orbit with the flat map closed (or turned
## off): the same marks as on the political map — headquarters by capitalisation, points with their lines, the
## countries' circles when far, hover labels, clicks — drawn where those places are on the globe.
## It answers what map_layer asks the game's political map (Карта.gd): «to_screen» (a point of the map → the screen;
## the far side of the planet → HIDDEN), «зум» (the same scale: how many screen widths the whole world would take
## at the point under the camera), «наведена» (the province under the cursor), «навести_на» (turns the camera to a
## point). The game's sites, provinces and layers stay on its political map (`real`).
## Layer −1: over the 3D view, under the game's interface.

const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")   # Main's methods, 0.24 names
const HIDDEN := Vector2(-100000.0, -100000.0)

var game: PaxGame
var real: CanvasLayer               # the game's political map

# What map_layer reads from a map (the names are the game's).
var зум := 2.0
var наведена := 0
var with_provinces := true        # game 0.24 (was «с_провинциями»)
var _это_земля := true
var labels: Array = []            # game 0.24 (was «подписи»)
var icons_layer: Control = null   # the flat map's icon layer: none here, the layer covers the screen
var _промысел_наведён := -1
var окно_слоёв: Variant:            # the game's «Слои» window (over the globe Pax CorpInc3D moves it there)
	get:
		return real.get("окно_слоёв") if is_instance_valid(real) else null
var мат: ShaderMaterial = null      # zone_fx.gd draws on the flat map's shader only — on the globe the zones are circles
var пров: Variant:
	get:
		return real.get("пров") if is_instance_valid(real) else null
var map_mines: Array:             # game 0.24 (was «промыслы_карты»)
	get:
		var raw: Variant = real.get("map_mines") if is_instance_valid(real) else null
		return raw if raw is Array else []

# The view of this frame.
var _cam: Camera3D
var _centre := Vector3.ZERO
var _basis := Basis.IDENTITY        # the Earth's rotation (no scale)
var _r := 1.0
var _eye := Vector3.ZERO
var _mouse := Vector2(-1, -1)
var _px_per_rad := 1.0


func _init() -> void:
	name = "PaxCorporationsGlobe"
	layer = -1
	process_priority = 1002           # after the game's camera and Pax CorpInc3D's descent (1000): the marks where the camera really is
	visible = false


## The game and its political map (called again whenever they may have changed).
func setup(g: PaxGame, map: CanvasLayer) -> void:
	game = g
	real = map


## On the Earth, in orbit, and the flat map is closed.
func wanted() -> bool:
	if game == null or not is_instance_valid(game.main):
		return false
	if not (str(game.main.get("режим")) in ["body", "тело"]) or game.focused_body() != game.home_body():
		return false
	if is_instance_valid(real) and real.visible:
		return false
	return game.camera() != null and game.body_node(game.home_body()) != null


## The marks only from this «зум» on (the world's width in screens): far out, with the whole globe in view, the
## companies' icons covered it — the planet is shown clean (the 3D cities and their lights tell where they are).
const MARKS_FROM_ZOOM := 2.5


func _process(_delta: float) -> void:
	var on := wanted()
	if on:
		_measure()
	on = on and зум >= MARKS_FROM_ZOOM
	if visible != on:
		visible = on


func _measure() -> void:
	_cam = game.camera()
	var body := game.body_node(game.home_body())
	var xf := body.global_transform
	_centre = xf.origin
	_r = xf.basis.get_scale().x
	_basis = xf.basis.orthonormalized()
	_eye = _cam.global_position
	# The scale under the camera: the flat map's «зум» is the world's width in screen widths.
	var view := get_viewport().get_visible_rect().size
	var f := view.y * 0.5 / tan(deg_to_rad(_cam.fov) * 0.5)
	var height := maxf(_eye.distance_to(_centre) - _r, _r * 0.001)
	_px_per_rad = _r * f / height
	зум = TAU * _px_per_rad / maxf(view.x, 1.0)
	var m := get_viewport().get_mouse_position()
	if m != _mouse:
		_mouse = m
		наведена = _province_at(m)


## The world's size in px at the point under the camera (map_layer: «_world»), as on a flat map of this scale.
func мир_на_экране() -> Vector2:
	return Vector2(TAU * _px_per_rad, PI * _px_per_rad)


## A point of the map (u = longitude, v = latitude, as the game's maps) on the screen; HIDDEN on the far side.
func to_screen(uv: Vector2, _shift: float = 0.0) -> Vector2:
	if _cam == null:
		return HIDDEN
	var n := _basis * _dir(uv)
	var p := _centre + n * _r
	if n.dot(_eye - p) <= 0.0 or _cam.is_position_behind(p):
		return HIDDEN
	return _cam.unproject_position(p)


## The latitude and longitude under a point of the screen, Vector2.INF off the planet.
func широта_долгота(at: Vector2) -> Vector2:
	var d := _local_at(at)
	if d == Vector3.ZERO:
		return Vector2.INF
	return Vector2(rad_to_deg(asin(clampf(d.y, -1.0, 1.0))), rad_to_deg(atan2(d.x, d.z)))


## Turns the camera to a point of the map (the planet stays as it is) and comes as close as the flat map's «зум» would.
func навести_на(uv: Vector2, новый_зум: float = -1.0) -> void:
	var main: Object = game.main
	if _cam == null or main == null:
		return
	var n := _basis * _dir(uv)
	main.set("тангаж", asin(clampf(n.y, -1.0, 1.0)))
	main.set("камера_рыскание", atan2(n.x, n.z))
	if новый_зум > 0.0:
		var view := get_viewport().get_visible_rect().size
		var f := view.y * 0.5 / tan(deg_to_rad(_cam.fov) * 0.5)
		var px := новый_зум * view.x / TAU
		var dist := clampf(_r + _r * f / maxf(px, 1.0), _r * 1.25, _r * 6.0)
		main.set("цель_дист", minf(float(main.get("цель_дист")), dist))
	if GameApi.has(main, "_поставить_камеру"):
		GameApi.call_main(main, "_поставить_камеру")


## The cursor is over the planet, not over a window or a button.
func мышь_на_карте(hovered: Control) -> bool:
	if hovered == null:
		return true
	var node: Node = hovered
	while node != null:
		if node is BaseButton or node is PanelContainer or node is LineEdit or node is ScrollContainer:
			return false
		node = node.get_parent()
	# A full-screen catcher of the game's view lets the planet through.
	var r := hovered.get_global_rect()
	var view := get_viewport().get_visible_rect().size
	return r.size.x >= view.x * 0.9 and r.size.y >= view.y * 0.9


func _province_at(at: Vector2) -> int:
	var d := _local_at(at)
	var book: Variant = пров
	if d == Vector3.ZERO or not (book is Object) or not (book as Object).has_method("id_в"):
		return 0
	return int((book as Object).call("id_в", d))


## The Earth's own direction (radius 1) under a point of the screen, ZERO off the planet.
func _local_at(at: Vector2) -> Vector3:
	if _cam == null:
		return Vector3.ZERO
	var o := _cam.project_ray_origin(at)
	var k := _cam.project_ray_normal(at)
	var oc := o - _centre
	var b := oc.dot(k)
	var c := oc.dot(oc) - _r * _r
	var disc := b * b - c
	if disc < 0.0:
		return Vector3.ZERO
	var t := -b - sqrt(disc)
	if t < 0.0:
		return Vector3.ZERO
	return (_basis.inverse() * ((o + k * t - _centre) / _r)).normalized()


## The game's maps: u = atan2(x, z) / TAU + 0.5, v = acos(y) / PI (Карта.uv_точки).
static func _dir(uv: Vector2) -> Vector3:
	var lon := (uv.x - 0.5) * TAU
	var lat := PI * 0.5 - uv.y * PI
	return Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
