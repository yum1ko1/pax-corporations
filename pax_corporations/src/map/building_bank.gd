extends RefCounted
## The map layer's «bank» of building pictures: the real 3D models of Pax CorpInc3D (a separate mod, Engine meta
## «pax_corpinc3d») where it has one, the voxel pictures of buildings.gd for the rest (and when Pax CorpInc3D is
## off or absent). The look of a site (kind, height, state…) is buildings.gd's, plus the company's world frame.

const Buildings := preload("res://mods/pax_corporations/src/map/buildings.gd")
const Frames := preload("res://mods/pax_corporations/src/companies/frames.gd")
const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const META := &"pax_corpinc3d"

var voxel: Buildings             # may be null: then only the 3D models


## Pax CorpInc3D's pictures on the flat map — off since its 0.2: its models stand on the 3D Earth instead (they
## looked crooked on the flat map and climbed over the sea and the borders).
static func ext() -> Object:
	return null


static func ext_on() -> bool:
	var e := ext()
	return e != null and bool(e.get("enabled"))


func look_of(db: Data, c: Dictionary, p: Dictionary, index: int, tree_ref: Object) -> Dictionary:
	var look := Buildings.look_of(db, c, p, index, tree_ref)
	look["frame"] = Frames.of(c)
	look["sector"] = str(c.get("sector", ""))
	return look


func pic(kind: String, tier: int, color: String, state: String, deco: bool, frame: String = "", sector: String = "") -> Dictionary:
	var e := ext()
	if e != null:
		var r: Dictionary = e.call("pic", kind, frame, state, sector)
		if not r.has("нет"):
			return r
	if voxel != null and is_instance_valid(voxel):
		return voxel.pic(kind, tier, color, state, deco)
	return {}
