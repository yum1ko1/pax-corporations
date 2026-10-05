extends ColorRect
## The economic zones as districts (like Cities: Skylines): each union's territory is tinted in its colour and outlined
## along the borders of its member provinces, with a soft band inside the edge. Drawn by a shader on the GPU from the
## game's own province map — the texture of province numbers the political map draws with (found once in its
## material, the encoding checked on the provinces' label pixels from data/regions2.json) — and a small table
## «province number → zone colour» this layer fills. If the game's texture is not found, setup() fails and the
## map layer keeps its simple discs. Lives in the map's CanvasLayer right under the corporations' layer and moves
## with it every frame (the layer follows the map's icon layer, which the map moves while panning).

const SHADER := """
shader_type canvas_item;
uniform sampler2D ids : filter_nearest, repeat_enable;
uniform sampler2D lut : filter_nearest;
uniform vec2 origin;
uniform vec2 world = vec2(1.0);
uniform vec2 rect_size = vec2(1.0);
uniform int enc = 0;
uniform float line_px = 2.2;
uniform float band_px = 9.0;
varying vec2 local;

void vertex() {
	local = VERTEX;   // the rect's own pixels — the same space the layer's origin/world are measured in
}

int id_at(vec2 uv) {
	vec4 c = texture(ids, uv);
	if (enc == 1) { return int(round(c.r)); }
	return int(round(c.r * 255.0)) + 256 * int(round(c.g * 255.0));
}

vec4 zone_at(vec2 uv) {
	int id = id_at(uv);
	return texelFetch(lut, ivec2(id % 2048, id / 2048), 0);
}

void fragment() {
	vec2 px = local;
	vec2 uv = (px - origin) / world;
	if (uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0);
	} else {
		uv.x = fract(uv.x);
		vec4 z = zone_at(uv);
		if (z.a < 0.001) {
			COLOR = vec4(0.0);
		} else {
			vec2 d1 = vec2(line_px) / abs(world);
			vec2 d2 = vec2(band_px) / abs(world);
			bool edge = false;
			bool near = false;
			for (int i = 0; i < 8; i++) {
				float a = 0.785398 * float(i);
				vec2 dir = vec2(cos(a), sin(a));
				if (abs(zone_at(uv + dir * d1).a - z.a) > 0.001) { edge = true; }
				if (abs(zone_at(uv + dir * d2).a - z.a) > 0.001) { near = true; }
			}
			if (edge) {
				COLOR = vec4(mix(z.rgb, vec3(1.0), 0.25), 0.95);
			} else if (near) {
				COLOR = vec4(z.rgb, 0.36);
			} else {
				COLOR = vec4(z.rgb, 0.13);
			}
		}
	}
}
"""

var ok := false
var _mat: ShaderMaterial
var _lut: Image
var _lut_tex: ImageTexture


## Finds the game's province-number texture and checks how it is encoded. log: func(String).
func setup(map: CanvasLayer, log: Callable) -> bool:
	name = "PaxCorpZoneDistricts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)   # placed by the map layer each frame, on top of it exactly
	var meta: Variant = Pax.json("res://data/regions2.json", {})
	if not (meta is Dictionary):
		log.call("zones: no data/regions2.json")
		return false
	var w := int((meta as Dictionary).get("width", (meta as Dictionary).get("ширина", 0)))
	var h := int((meta as Dictionary).get("height", (meta as Dictionary).get("высота", 0)))
	var probes: Array = []
	for r in ((meta as Dictionary).get("regions", (meta as Dictionary).get("регионы", [])) as Array):
		var cap_v: Variant = (r as Dictionary).get("caption", (r as Dictionary).get("подпись")) if r is Dictionary else null
		if cap_v is Array and probes.size() < 12:
			var lab: Array = cap_v
			if int((r as Dictionary).get("id", 0)) % 97 == 3:
				probes.append([int((r as Dictionary)["id"]), Vector2(float(lab[0]), float(lab[1]))])
	var cands: Array = []
	var mat: Variant = map.get("мат")
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
		for u in (mat as ShaderMaterial).shader.get_shader_uniform_list():
			var v: Variant = (mat as ShaderMaterial).get_shader_parameter(str((u as Dictionary)["name"]))
			if v is Texture2D:
				cands.append([str((u as Dictionary)["name"]), v])
	for prop in map.get_property_list():
		var pn := str((prop as Dictionary)["name"])
		if pn.begins_with("текстур") or pn.contains("пров") or pn.contains("регион") 				or pn.contains("texture") or pn.contains("province") or pn.contains("region"):   # 0.24 English names
			var v2: Variant = map.get(pn)
			if v2 is Texture2D:
				cands.append([pn, v2])
	var lines: PackedStringArray = []
	for c in cands:
		var tex: Texture2D = c[1]
		var img := tex.get_image()
		if img == null or img.is_empty():
			lines.append("%s: no image" % str(c[0]))
			continue
		if img.is_compressed():
			lines.append("%s: compressed" % str(c[0]))
			continue
		var sz := img.get_size()
		for e in [0, 1]:
			var hits := 0
			for pr in probes:
				var at: Vector2 = pr[1]
				var p := Vector2i(int(at.x * float(sz.x) / maxf(float(w), 1.0)), int(at.y * float(sz.y) / maxf(float(h), 1.0)))
				if p.x < 0 or p.y < 0 or p.x >= sz.x or p.y >= sz.y:
					continue
				var col := img.get_pixelv(p)
				var id := roundi(col.r) if e == 1 else roundi(col.r * 255.0) + 256 * roundi(col.g * 255.0)
				if id == int(pr[0]):
					hits += 1
			lines.append("%s %dx%d fmt %d enc %d: %d/%d" % [str(c[0]), sz.x, sz.y, img.get_format(), e, hits, probes.size()])
			if probes.size() > 0 and hits * 10 >= probes.size() * 8:
				_build(tex, e)
				log.call("zones: districts from «%s» (%s)" % [str(c[0]), "; ".join(lines)])
				return true
	log.call("zones: the province texture was not found — the discs stay (%s)" % ("; ".join(lines) if not lines.is_empty() else "no textures"))
	return false


func _build(tex: Texture2D, e: int) -> void:
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_mat.set_shader_parameter("ids", tex)
	_mat.set_shader_parameter("enc", e)
	_lut = Image.create(2048, 1, false, Image.FORMAT_RGBA8)
	_lut_tex = ImageTexture.create_from_image(_lut)
	_mat.set_shader_parameter("lut", _lut_tex)
	material = _mat
	color = Color.WHITE
	ok = true


## The table: province number → its zone's colour (alpha carries the zone's number, so borders between two zones
## show too). owners — the map's province owners; zone_of — func(country) -> [index, Color] or [].
func fill(owners: Array, zone_of: Callable) -> void:
	if not ok:
		return
	_lut.fill(Color(0, 0, 0, 0))
	for pid in mini(owners.size(), 2048):
		var z: Array = zone_of.call(str(owners[pid]))
		if z.size() >= 2:
			var col: Color = z[1]
			_lut.set_pixel(pid, 0, Color(col.r, col.g, col.b, float(int(z[0]) + 1) / 255.0))
	_lut_tex.update(_lut)


## Where the world is on screen (the layer's own coordinates): uv → origin + world · uv.
func place(origin: Vector2, world: Vector2) -> void:
	if ok:
		_mat.set_shader_parameter("origin", origin)
		_mat.set_shader_parameter("world", world)
		_mat.set_shader_parameter("rect_size", size)
