extends RefCounted
## Status frames of companies (ideas doc, section 17): a frame around the usual sector icon shows the company's
## place in the world. Five steps by the world rating (index): diamond 1–10, sapphire 11–30, gold 31–100,
## silver 101–300 and the leader of each country below that; no frame for the rest.
## Up only after 4 weeks in a row inside the new step, down only after 4 weeks below it with a 10 % margin
## (gold is lost below place 110) — no blinking at the borders. A change goes to the chronicle and the news.
##
## ONE drawing for every place a company is shown (draw()): the dossier, the list, the map, the countries'
## circles. All frames of one step pulse together from one clock (Time). Settings: «frames_fx» 2 — glow and
## animation, 1 — glow only, 0 — plain rings; «frames_on_map».

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const TIERS := ["", "silver", "gold", "sapphire", "diamond"]
const LIMITS := {"diamond": 10, "sapphire": 30, "gold": 100, "silver": 300}
const RING := {"silver": Color(0.80, 0.82, 0.88), "gold": Color(0.95, 0.78, 0.32), "sapphire": Color(0.30, 0.55, 1.0), "diamond": Color(0.60, 0.92, 1.0)}
const LAUREL := Color(0.93, 0.74, 0.25)
const PART_ALL := 0
const PART_STATIC := 1
const PART_FX := 2

static var fx := 2               # 2 glow + animation, 1 glow only, 0 rings only (setting «frames_fx»)
static var on_map := true        # setting «frames_on_map»
static var country_best: Dictionary = {}   # country -> [tier, company id] (the countries' circles)

var news: Array = []


# ---------- the steps ----------

static func rank(tier: String) -> int:
	return maxi(0, TIERS.find(tier))


## The step a place earns (margin 1.0) or keeps (margin 1.1 — the place it may slip to before losing it).
static func tier_for(place: int, country_leader: bool, margin: float) -> String:
	for t in ["diamond", "sapphire", "gold", "silver"]:
		if place <= int(round(float(LIMITS[t]) * margin)):
			return t
	return "silver" if country_leader else ""


static func of(c: Dictionary) -> String:
	return str(c.get("_frame", ""))


## Weekly, after the rating is recomputed.
func step(db: Data, day: int, player: String) -> void:
	news.clear()
	var best := {}
	for item in db.companies:
		var c: Dictionary = item
		var place := int(c.get("_world_place", 9999))
		var leader := int(c.get("_country_place", 99)) == 1
		var cur := of(c)
		if not c.has("_frame"):
			c["_frame"] = tier_for(place, leader, 1.0)   # the start: no waiting
			cur = of(c)
		else:
			var up := tier_for(place, leader, 1.0)
			var keep := tier_for(place, leader, 1.1)
			var want := cur
			if rank(up) > rank(cur):
				want = up
			elif rank(keep) < rank(cur):
				want = keep
			if want != cur and str(c.get("_frame_target", "")) == want:
				c["_frame_weeks"] = int(c.get("_frame_weeks", 0)) + db.dt
			elif want != cur:
				c["_frame_target"] = want
				c["_frame_weeks"] = db.dt
			else:
				c.erase("_frame_target")
				c.erase("_frame_weeks")
			if want != cur and int(c.get("_frame_weeks", 0)) >= 4:
				c["_frame"] = want
				c.erase("_frame_target")
				c.erase("_frame_weeks")
				_changed(c, cur, want, day, player)
				cur = want
		var country := str(c.get("_country", ""))
		if not cur.is_empty() and (not best.has(country) or rank(cur) > rank(str((best[country] as Array)[0])) \
				or (rank(cur) == rank(str((best[country] as Array)[0])) and place < int(db.company(str((best[country] as Array)[1])).get("_world_place", 9999)))):
			best[country] = [cur, str(c["id"])]
	country_best = best


## Companies without a frame get the one their place earns; the countries' best are found. No weeks counted.
static func init_missing(db: Data) -> void:
	var best := {}
	for item in db.companies:
		var c: Dictionary = item
		if not c.has("_frame"):
			c["_frame"] = tier_for(int(c.get("_world_place", 9999)), int(c.get("_country_place", 99)) == 1, 1.0)
		var cur := of(c)
		var country := str(c.get("_country", ""))
		if not cur.is_empty() and (not best.has(country) or rank(cur) > rank(str((best[country] as Array)[0]))):
			best[country] = [cur, str(c["id"])]
	country_best = best


func _changed(c: Dictionary, was: String, now: String, day: int, player: String) -> void:
	var up := rank(now) > rank(was)
	var entry := {"день": day, "вид": "рамка", "было": was, "стало": now, "up": up}
	(c["_chronicle"] as Array).append(entry)
	# The player's country: every change; the world: getting or losing sapphire and diamond.
	var mine := str(c.get("_country", "")) == player
	var loud := rank(now) >= rank("sapphire") or rank(was) >= rank("sapphire")
	if mine or loud:
		news.append({"c": c, "entry": entry, "tone": "good" if up else "bad", "size": 0.3 + 0.1 * float(maxi(rank(now), rank(was))), "big": loud})


## Saved: the frames and the weeks waited (the static data has none).
static func save_state(db: Data) -> Dictionary:
	var out := {}
	for item in db.companies:
		var c: Dictionary = item
		if c.has("_frame"):
			out[str(c["id"])] = [of(c), str(c.get("_frame_target", "")), int(c.get("_frame_weeks", 0))]
	return out


static func load_state(db: Data, state: Dictionary) -> void:
	for cid in state.keys():
		var c := db.company(str(cid))
		var v: Variant = state[cid]
		if c.is_empty() or not (v is Array) or (v as Array).size() < 3:
			continue
		c["_frame"] = str((v as Array)[0])
		if not str((v as Array)[1]).is_empty():
			c["_frame_target"] = str((v as Array)[1])
			c["_frame_weeks"] = int((v as Array)[2])


static func animated(tier: String) -> bool:
	return fx == 2 and rank(tier) >= rank("gold")


# ---------- drawing (one component everywhere) ----------

## The frame around an icon of radius r at `center` on any CanvasItem. part: PART_ALL (windows), PART_STATIC
## (the map's layer) or PART_FX (the map's light overlay, redrawn alone ~30 fps). The diamond and sapphire frames
## are fully animated, so with animation on they are drawn only by the overlay on the map.
static func draw(ci: CanvasItem, center: Vector2, r: float, tier: String, part: int = PART_ALL) -> void:
	if tier.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if tier == "diamond" or tier == "sapphire":
		var live := fx == 2
		if (part == PART_STATIC and live) or (part == PART_FX and not live):
			return
		var t := now if live else 0.0
		if tier == "diamond":
			_diamond(ci, center, r, t, live)
		else:
			_sapphire(ci, center, r, t, live)
		return
	var col: Color = RING[tier]
	var w := maxf(1.5, r * 0.16)
	if part != PART_FX:
		ci.draw_arc(center, r + w * 0.5, 0.0, TAU, 48, Color(0, 0, 0, 0.55), w + 2.0, true)
		ci.draw_arc(center, r + w * 0.5, 0.0, TAU, 48, col, w, true)
	if fx == 2 and part != PART_STATIC and tier == "gold":
		var phase := fmod(now, 8.0)
		if phase < 0.7:
			var a := -PI / 2.0 + TAU * phase / 0.7
			ci.draw_arc(center, r + w * 0.5, a, a + 0.55, 10, Color(1, 1, 1, 0.9 * (1.0 - phase / 0.7)), w, true)


## The silver and gold ring as a ready picture (the same ring the map drew with two antialiased 48-segment arcs at
## every redraw): computed once per tier and size (0.5 px steps), then one texture per badge. The centre of the
## picture is the badge's centre; draw it at center − size / 2.
static var _rings: Dictionary = {}


static func baked_ring(tier: String, r: float) -> Texture2D:
	if not RING.has(tier) or tier == "diamond" or tier == "sapphire":
		return null
	var rs := snappedf(r, 0.5)
	var key := "%s|%.1f" % [tier, rs]
	var t: Variant = _rings.get(key)
	if t is Texture2D:
		return t
	if _rings.size() > 400:
		_rings.clear()
	var col: Color = RING[tier]
	var w := maxf(1.5, rs * 0.16)
	var mid := rs + w * 0.5                      # the arcs' radius
	var reach := mid + (w + 2.0) * 0.5 + 1.5
	var n := int(ceil(reach * 2.0)) + 2
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := float(n) / 2.0
	for y in n:
		for x in n:
			var d := absf(Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length() - mid)
			var shade := clampf((w + 2.0) * 0.5 - d + 0.5, 0.0, 1.0) * 0.55   # the dark rim under the ring
			var ring := clampf(w * 0.5 - d + 0.5, 0.0, 1.0)
			var a := ring + shade * (1.0 - ring)
			if a <= 0.0:
				continue
			var rgb := Color(col.r, col.g, col.b) * (ring / a)
			img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))
	var tex := ImageTexture.create_from_image(img)
	_rings[key] = tex
	return tex


static func _dir(a: float) -> Vector2:
	return Vector2(cos(a), sin(a))


## Diamond: a faceted crystal hexagon lit from the upper left, a glint running over the facets, energy wisps
## below, twinkling sparks, golden Roman laurels on both sides that sway.
static func _diamond(ci: CanvasItem, c: Vector2, r: float, t: float, live: bool) -> void:
	var ro := r * 1.52
	var ri := r * 1.12
	var rm := (ro + ri) * 0.5
	var pulse := 0.75 + 0.25 * sin(TAU * t / 3.0) if live else 0.85
	# Glow behind everything.
	if fx >= 1:
		for i in 4:
			var rr := ro + r * 0.12 * float(i + 1)
			ci.draw_polyline(_hex(c, rr), Color(0.45, 0.85, 1.0, 0.22 * pulse * (1.0 - float(i) / 4.0)), r * 0.14, true)
	# Laurels behind the frame, swaying.
	_laurels(ci, c, ro, r, t, live)
	# Energy wisps fanning out below.
	if fx >= 1:
		for k in 6:
			var side := -1.0 if k % 2 == 0 else 1.0
			var spread := 0.35 + 0.18 * float(k / 2)
			var flick := 0.6 + 0.4 * sin(t * 5.0 + float(k) * 1.7) if live else 0.8
			var pts := PackedVector2Array()
			for j in 7:
				var u := float(j) / 6.0
				var x := side * (r * 0.15 + u * r * 1.7 * spread)
				var y := ro * 0.95 - u * u * r * 0.9 * (0.6 + spread) + sin(u * 3.0 + t * 2.0 + float(k)) * r * 0.05
				pts.append(c + Vector2(x, y))
			ci.draw_polyline(pts, Color(0.6, 0.95, 1.0, 0.55 * flick), maxf(1.0, r * 0.06), true)
	# The facets: an outer and an inner bevel on each of the six sides; the glint sweeps round every ~4 s.
	var light := Vector2(-0.55, -0.83)
	var sweep := -PI / 2.0 + TAU * fmod(t / 4.0, 1.0)
	var dark := Color(0.16, 0.36, 0.62)
	var bright := Color(0.94, 0.98, 1.0)
	for i in 6:
		var a0 := -PI / 2.0 + TAU * float(i) / 6.0
		var a1 := a0 + TAU / 6.0
		var mid := (a0 + a1) * 0.5
		var lit := _dir(mid).dot(light)
		var glint := pow(maxf(0.0, cos(angle_difference(mid, sweep))), 10.0) * 0.7 if live else 0.0
		var outer := dark.lerp(bright, clampf(0.55 + 0.45 * lit + glint, 0.0, 1.0))
		var inner := dark.lerp(bright, clampf(0.45 - 0.35 * lit + glint * 0.7, 0.0, 1.0))
		ci.draw_colored_polygon(PackedVector2Array([c + _dir(a0) * ro, c + _dir(a1) * ro, c + _dir(a1) * rm, c + _dir(a0) * rm]), outer)
		ci.draw_colored_polygon(PackedVector2Array([c + _dir(a0) * rm, c + _dir(a1) * rm, c + _dir(a1) * ri, c + _dir(a0) * ri]), inner)
	ci.draw_polyline(_hex(c, ro), Color(1, 1, 1, 0.9), maxf(1.0, r * 0.05), true)
	ci.draw_polyline(_hex(c, ri), Color(0.05, 0.15, 0.3, 0.9), maxf(1.0, r * 0.06), true)
	ci.draw_polyline(_hex(c, rm), Color(1, 1, 1, 0.25), 1.0, true)
	# Sparks around.
	if fx >= 1:
		for k in 8:
			var a := TAU * float(k) / 8.0 + 0.3
			var d := ro + r * (0.25 + 0.2 * float((k * 7) % 3))
			var tw := 0.5 + 0.5 * sin(t * 3.0 + float(k) * 2.3) if live else 0.6
			_spark(ci, c + _dir(a) * d, r * 0.12 * tw, Color(0.75, 0.95, 1.0, tw))


static func _hex(c: Vector2, rr: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 7:
		pts.append(c + _dir(-PI / 2.0 + TAU * float(i) / 6.0) * rr)
	return pts


static func _spark(ci: CanvasItem, p: Vector2, s: float, col: Color) -> void:
	if s <= 0.3:
		return
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 2.0), p + Vector2(s * 0.4, 0), p + Vector2(0, s * 2.0), p + Vector2(-s * 0.4, 0)]), col)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 2.0, 0), p + Vector2(0, s * 0.4), p + Vector2(s * 2.0, 0), p + Vector2(0, -s * 0.4)]), col)


## Sapphire: a blue crystal ring shaded like a tube, gold filigree and curls, crystal shards like wings on both
## sides, a crown with a gem on top and a gem below; a shimmer runs round the ring, the shards twinkle.
static func _sapphire(ci: CanvasItem, c: Vector2, r: float, t: float, live: bool) -> void:
	var ri := r * 1.1
	var ro := r * 1.4
	var pulse := 0.7 + 0.3 * sin(TAU * t / 3.0) if live else 0.8
	if fx >= 1:
		for i in 4:
			ci.draw_arc(c, ro + r * 0.13 * float(i + 1), 0.0, TAU, 40, Color(0.35, 0.55, 1.0, 0.2 * pulse * (1.0 - float(i) / 4.0)), r * 0.14, true)
	# Crystal shards — wings on both sides.
	for side_v in [-1.0, 1.0]:
		var side: float = side_v
		for k in 6:
			var u := float(k) / 5.0
			var ang := lerpf(0.68 * PI, 1.32 * PI, u)
			if side > 0.0:
				ang = PI - ang
			var tw := 0.65 + 0.35 * sin(t * 2.5 + float(k) * 1.3 + side) if live else 0.8
			var base := c + _dir(ang) * (ro - r * 0.05)
			var length := r * (0.55 - 0.25 * absf(u - 0.5))
			var tip := c + _dir(ang) * (ro + length)
			var nrm := _dir(ang + PI / 2.0) * r * 0.11
			ci.draw_colored_polygon(PackedVector2Array([base + nrm, c + _dir(ang) * (ro + length * 0.3) + nrm * 0.5, tip,
				c + _dir(ang) * (ro + length * 0.3) - nrm * 0.5, base - nrm]), Color(0.7, 0.85, 1.0, 0.75 * tw))
			ci.draw_line(base, tip, Color(1, 1, 1, 0.6 * tw), 1.0, true)
	# The ring: tube shading from dark blue at the edges to light in the middle.
	const bands := 6
	var bw := (ro - ri) / float(bands)
	for i in bands:
		var u := (float(i) + 0.5) / float(bands)
		var shade := sin(PI * u)
		ci.draw_arc(c, ri + bw * (float(i) + 0.5), 0.0, TAU, 56, Color(0.12, 0.22, 0.65).lerp(Color(0.62, 0.78, 1.0), shade), bw + 0.6, true)
	if live:
		var a := TAU * fmod(t / 5.0, 1.0)
		ci.draw_arc(c, (ri + ro) * 0.5, a, a + 0.9, 14, Color(1, 1, 1, 0.55), (ro - ri) * 0.6, true)
	# Gold filigree: the edges and four curls.
	var gold := Color(0.95, 0.76, 0.3)
	ci.draw_arc(c, ri, 0.0, TAU, 56, gold, maxf(1.0, r * 0.06), true)
	ci.draw_arc(c, ro, 0.0, TAU, 56, gold, maxf(1.0, r * 0.06), true)
	for k in 4:
		var a := PI / 4.0 + PI / 2.0 * float(k)
		var p := c + _dir(a) * (ro + r * 0.08)
		ci.draw_arc(p, r * 0.12, a, a + PI * 1.4, 10, gold, maxf(1.0, r * 0.05), true)
	# The crown on top and the gem below.
	var top := c + Vector2(0, -ro - r * 0.05)
	var cw := r * 0.42
	var ch := r * 0.32
	ci.draw_colored_polygon(PackedVector2Array([top + Vector2(-cw, 0), top + Vector2(-cw, -ch * 0.6), top + Vector2(-cw * 0.5, -ch * 0.25),
		top + Vector2(0, -ch), top + Vector2(cw * 0.5, -ch * 0.25), top + Vector2(cw, -ch * 0.6), top + Vector2(cw, 0)]), gold)
	ci.draw_circle(top + Vector2(0, -ch * 0.35), r * 0.08, Color(0.3, 0.55, 1.0))
	var bot := c + Vector2(0, ro + r * 0.02)
	var g := r * 0.13
	var gem := PackedVector2Array([bot + Vector2(0, -g), bot + Vector2(g * 0.8, 0), bot + Vector2(0, g * 1.4), bot + Vector2(-g * 0.8, 0)])
	ci.draw_colored_polygon(gem, Color(0.35, 0.6, 1.0))
	ci.draw_polyline(gem + PackedVector2Array([gem[0]]), gold, 1.0, true)


## Golden Roman laurel twigs on both sides of the diamond frame; each leaf sways a little (one clock for all).
static func _laurels(ci: CanvasItem, center: Vector2, from: float, r: float, t: float, live: bool) -> void:
	var rr := from + r * 0.12
	var length := r * 0.42
	var width := r * 0.16
	for side_v in [-1.0, 1.0]:
		var side: float = side_v
		var stem := PackedVector2Array()
		for k in 7:
			var a := lerpf(0.58 * PI, 1.18 * PI, float(k) / 6.0)
			if side > 0.0:
				a = PI - a
			stem.append(center + _dir(a) * (rr - r * 0.05))
		ci.draw_polyline(stem, Color(0.7, 0.5, 0.12), maxf(1.0, r * 0.05), true)
		for k in 6:
			var u := float(k) / 5.0
			var ang := lerpf(0.6 * PI, 1.18 * PI, u)
			if side > 0.0:
				ang = PI - ang
			var sway := 0.18 * sin(t * 1.8 + float(k) * 0.6 + side) if live else 0.0
			var pos := center + _dir(ang) * rr
			var dir := ang + (PI / 2.0 if side < 0.0 else -PI / 2.0) + side * 0.55 + sway
			_leaf(ci, pos + _dir(dir) * length * 0.35, dir, length * (1.0 - 0.2 * u), width)


static func _leaf(ci: CanvasItem, pos: Vector2, ang: float, length: float, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := TAU * float(i) / 10.0
		pts.append(pos + Vector2(cos(a) * length * 0.5, sin(a) * width * 0.5).rotated(ang))
	ci.draw_colored_polygon(pts, LAUREL)
	ci.draw_line(pos - _dir(ang) * length * 0.45, pos + _dir(ang) * length * 0.45, Color(1.0, 0.92, 0.6, 0.7), 1.0, true)
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.45, 0.32, 0.05, 0.8), 1.0, true)


## Why a company far down the world list has a frame: silver below place 300 is the leader of its country.
## tr: func(key without the mod's prefix) -> String. "" — the place itself explains the frame.
static func why_line(c: Dictionary, tr: Callable) -> String:
	if of(c) == "silver" and int(c.get("_world_place", 0)) > int(round(float(LIMITS["silver"]) * 1.1)):
		return " · " + str(tr.call("frame_why_leader")) % str(c.get("_country", ""))
	return ""


static func label_key(tier: String) -> String:
	return "frame_" + (tier if not tier.is_empty() else "none")


## Places to the next step (for the dossier's tooltip): 0 — already the top.
static func to_next(c: Dictionary) -> int:
	var place := int(c.get("_world_place", 9999))
	var cur := of(c)
	for t in ["silver", "gold", "sapphire", "diamond"]:
		if rank(t) > rank(cur):
			return maxi(0, place - int(LIMITS[t]))
	return 0


# ---------- the country's frame around a flag (the world rank, country_rank.gd) ----------
# The same family as the companies' frames, drawn around a rectangle: bronze and silver — plain edges, gold — a band
# with a running glint, sapphire — a crystal tube band in gold filigree with crystal wings, a crown and a gem,
# diamond — faceted crystal bevels lit from the upper left with a glint sweeping round, golden Roman laurels that
# sway on both sides, a diamond gem crown, energy wisps and sparks. One clock for all (Time).

const FLAG_TIERS := ["bronze", "silver", "gold", "sapphire", "diamond"]
const FLAG_RING := {"bronze": Color(0.80, 0.52, 0.32), "silver": Color(0.80, 0.83, 0.89), "gold": Color(0.96, 0.78, 0.32),
	"sapphire": Color(0.32, 0.58, 1.0), "diamond": Color(0.62, 0.94, 1.0)}


## How much room around the flag the frame takes (laurels, wings, crown), as a share of the flag's height.
static func flag_margin(tier: String) -> Vector4:
	match tier:
		"diamond":
			return Vector4(0.42, 0.42, 0.42, 0.34)   # left, top, right, bottom
		"sapphire":
			return Vector4(0.36, 0.36, 0.36, 0.26)
		"gold":
			return Vector4(0.1, 0.1, 0.1, 0.1)
	return Vector4(0.05, 0.05, 0.05, 0.05)


static func draw_flag(ci: CanvasItem, r: Rect2, tier: String) -> void:
	var live := fx == 2
	var t := Time.get_ticks_msec() / 1000.0 if live else 0.0
	var s := r.size.y
	match tier:
		"diamond":
			_flag_diamond(ci, r, s, t, live)
		"sapphire":
			_flag_sapphire(ci, r, s, t, live)
		"gold":
			var w := maxf(2.0, s * 0.07)
			ci.draw_rect(r.grow(w * 0.5 + 1.0), Color(0, 0, 0, 0.55), false, w + 2.0)
			ci.draw_rect(r.grow(w * 0.5), FLAG_RING["gold"], false, w)
			ci.draw_rect(r.grow(w), Color(1.0, 0.92, 0.6, 0.6), false, 1.0)
			if live:
				var per := 2.0 * (r.size.x + r.size.y)
				var phase := fmod(t, 6.0)
				if phase < 1.2:
					var p := _on_rect(r.grow(w * 0.5), per * phase / 1.2)
					ci.draw_circle(p, w * 0.9, Color(1, 1, 1, 0.85 * (1.0 - phase / 1.2)))
			for corner in _corners(r.grow(w * 0.5)):
				ci.draw_circle(corner, w * 0.7, Color(1.0, 0.86, 0.45))
		_:
			var col: Color = FLAG_RING.get(tier, FLAG_RING["bronze"])
			var w2 := maxf(1.5, s * 0.045)
			ci.draw_rect(r.grow(w2 * 0.5), col, false, w2)
			if tier == "silver":
				ci.draw_rect(r.grow(w2 * 1.8), Color(col, 0.55), false, 1.0)


static func _corners(r: Rect2) -> Array:
	return [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]


## A point at distance d along the rectangle's edge, clockwise from the top left.
static func _on_rect(r: Rect2, d: float) -> Vector2:
	var per := 2.0 * (r.size.x + r.size.y)
	d = fposmod(d, per)
	if d < r.size.x:
		return r.position + Vector2(d, 0)
	d -= r.size.x
	if d < r.size.y:
		return Vector2(r.end.x, r.position.y + d)
	d -= r.size.y
	if d < r.size.x:
		return Vector2(r.end.x - d, r.end.y)
	return Vector2(r.position.x, r.end.y - (d - r.size.x))


## Sapphire: a blue crystal band shaded like a tube, gold filigree edges and corner curls, crystal shards like
## wings on both sides, a gold crown with a sapphire on top and a gem below; a shimmer runs round, shards twinkle.
static func _flag_sapphire(ci: CanvasItem, r: Rect2, s: float, t: float, live: bool) -> void:
	var ri := r   # the band starts right at the flag's edge (a gap made the flag look smaller than its frame)
	var bw := s * 0.12
	var pulse := 0.7 + 0.3 * sin(TAU * t / 3.0) if live else 0.8
	if fx >= 1:
		for i in 4:
			ci.draw_rect(ri.grow(bw + s * 0.05 * float(i + 1)), Color(0.35, 0.55, 1.0, 0.18 * pulse * (1.0 - float(i) / 4.0)), false, s * 0.06)
	# Crystal wings: shards fanning out of the middle of each side.
	var cy := r.get_center().y
	for side_v in [-1.0, 1.0]:
		var side: float = side_v
		var root := Vector2(r.position.x - bw if side < 0.0 else r.end.x + bw, cy)
		for k in 5:
			var u := float(k) / 4.0
			var ang := lerpf(-0.75, 0.75, u)
			var dir := Vector2(side * cos(ang), sin(ang))
			var length := s * (0.42 - 0.18 * absf(u - 0.5) * 2.0)
			var tw := 0.65 + 0.35 * sin(t * 2.5 + float(k) * 1.3 + side) if live else 0.8
			var base := root + Vector2(0, (u - 0.5) * s * 0.5)
			var nrm := Vector2(-dir.y, dir.x) * s * 0.06
			var tip := base + dir * length
			ci.draw_colored_polygon(PackedVector2Array([base + nrm, base + dir * length * 0.35 + nrm * 0.6, tip,
				base + dir * length * 0.35 - nrm * 0.6, base - nrm]), Color(0.7, 0.85, 1.0, 0.8 * tw))
			ci.draw_line(base, tip, Color(1, 1, 1, 0.6 * tw), 1.0, true)
	# The band: tube shading from dark blue at the edges to light in the middle.
	const bands := 5
	for i in bands:
		var u2 := (float(i) + 0.5) / float(bands)
		var col := Color(0.12, 0.22, 0.65).lerp(Color(0.62, 0.78, 1.0), sin(PI * u2))
		ci.draw_rect(ri.grow(bw * u2), col, false, bw / float(bands) + 0.8)
	if live:
		var mid := ri.grow(bw * 0.5)
		var per := 2.0 * (mid.size.x + mid.size.y)
		var head := fmod(t / 5.0, 1.0) * per
		for j in 8:
			ci.draw_circle(_on_rect(mid, head - float(j) * s * 0.06), bw * 0.32 * (1.0 - float(j) / 8.0), Color(1, 1, 1, 0.5 * (1.0 - float(j) / 8.0)))
	# Gold filigree: the edges and a curl at each corner.
	var gold := Color(0.95, 0.76, 0.3)
	ci.draw_rect(ri, gold, false, maxf(1.0, s * 0.03))
	ci.draw_rect(ri.grow(bw), gold, false, maxf(1.0, s * 0.03))
	var cs := _corners(ri.grow(bw))
	for k in 4:
		var a := -PI * 3.0 / 4.0 + PI / 2.0 * float(k)
		ci.draw_arc((cs[k] as Vector2) + _dir(a) * s * 0.06, s * 0.07, a, a + PI * 1.4, 10, gold, maxf(1.0, s * 0.025), true)
	# The crown on top with a sapphire, a gem below.
	var top := Vector2(r.get_center().x, ri.position.y - bw - s * 0.01)
	var cw := s * 0.22
	var ch := s * 0.2
	ci.draw_colored_polygon(PackedVector2Array([top + Vector2(-cw, 0), top + Vector2(-cw, -ch * 0.6), top + Vector2(-cw * 0.5, -ch * 0.25),
		top + Vector2(0, -ch), top + Vector2(cw * 0.5, -ch * 0.25), top + Vector2(cw, -ch * 0.6), top + Vector2(cw, 0)]), gold)
	ci.draw_circle(top + Vector2(0, -ch * 0.35), s * 0.045, Color(0.3, 0.55, 1.0))
	var bot := Vector2(r.get_center().x, ri.end.y + bw)
	var g := s * 0.07
	var gem := PackedVector2Array([bot + Vector2(0, -g), bot + Vector2(g * 0.8, 0), bot + Vector2(0, g * 1.4), bot + Vector2(-g * 0.8, 0)])
	ci.draw_colored_polygon(gem, Color(0.35, 0.6, 1.0))
	ci.draw_polyline(gem + PackedVector2Array([gem[0]]), gold, 1.0, true)


## Diamond: faceted crystal bevels on the four sides lit from the upper left, a glint sweeping round every ~4 s,
## golden Roman laurels swaying on both sides, a diamond gem crown, energy wisps below and twinkling sparks.
static func _flag_diamond(ci: CanvasItem, r: Rect2, s: float, t: float, live: bool) -> void:
	var ri := r   # the inner bevel starts right at the flag's edge (no gap between the flag and the frame)
	var ro := r.grow(s * 0.17)
	var rm := r.grow(s * 0.1)
	var pulse := 0.75 + 0.25 * sin(TAU * t / 3.0) if live else 0.85
	if fx >= 1:
		for i in 4:
			ci.draw_rect(ro.grow(s * 0.06 * float(i + 1)), Color(0.45, 0.85, 1.0, 0.2 * pulse * (1.0 - float(i) / 4.0)), false, s * 0.07)
	_flag_laurels(ci, r, ro, s, t, live)
	# Energy wisps fanning out below.
	if fx >= 1:
		var c0 := Vector2(r.get_center().x, ro.end.y)
		for k in 6:
			var side := -1.0 if k % 2 == 0 else 1.0
			var spread := 0.35 + 0.18 * float(k / 2)
			var flick := 0.6 + 0.4 * sin(t * 5.0 + float(k) * 1.7) if live else 0.8
			var pts := PackedVector2Array()
			for j in 7:
				var u := float(j) / 6.0
				pts.append(c0 + Vector2(side * (s * 0.08 + u * s * 0.9 * spread), u * u * s * 0.18 + sin(u * 3.0 + t * 2.0 + float(k)) * s * 0.02))
			ci.draw_polyline(pts, Color(0.6, 0.95, 1.0, 0.5 * flick), maxf(1.0, s * 0.025), true)
	# The facets: outer and inner bevels on each side; the glint goes round.
	var light := Vector2(-0.55, -0.83)
	var sweep := -PI / 2.0 + TAU * fmod(t / 4.0, 1.0)
	var dark := Color(0.16, 0.36, 0.62)
	var bright := Color(0.94, 0.98, 1.0)
	var O := _corners(ro)
	var Mi := _corners(rm)
	var I := _corners(ri)
	var normals := [-PI / 2.0, 0.0, PI / 2.0, PI]   # top, right, bottom, left
	for k in 4:
		var k2 := (k + 1) % 4
		var nrm: float = normals[k]
		var lit := _dir(nrm).dot(light)
		var glint := pow(maxf(0.0, cos(angle_difference(nrm, sweep))), 8.0) * 0.75 if live else 0.0
		var outer := dark.lerp(bright, clampf(0.55 + 0.45 * lit + glint, 0.0, 1.0))
		var inner := dark.lerp(bright, clampf(0.45 - 0.35 * lit + glint * 0.7, 0.0, 1.0))
		ci.draw_colored_polygon(PackedVector2Array([O[k], O[k2], Mi[k2], Mi[k]]), outer)
		ci.draw_colored_polygon(PackedVector2Array([Mi[k], Mi[k2], I[k2], I[k]]), inner)
	ci.draw_rect(ro, Color(1, 1, 1, 0.9), false, maxf(1.0, s * 0.02))
	ci.draw_rect(ri.grow(maxf(1.0, s * 0.02) * 0.5), Color(0.05, 0.15, 0.3, 0.9), false, maxf(1.0, s * 0.02))
	for k in 4:
		ci.draw_line(O[k], I[k], Color(1, 1, 1, 0.35), 1.0, true)
	# A diamond gem crown on top.
	var top := Vector2(r.get_center().x, ro.position.y)
	var gw := s * 0.16
	var gh := s * 0.2
	var crown := PackedVector2Array([top + Vector2(-gw, -gh * 0.45), top + Vector2(-gw * 0.45, -gh), top + Vector2(gw * 0.45, -gh),
		top + Vector2(gw, -gh * 0.45), top + Vector2(0, gh * 0.25)])
	ci.draw_colored_polygon(crown, Color(0.78, 0.95, 1.0).lerp(Color(1, 1, 1), 0.3 * pulse))
	ci.draw_polyline(crown + PackedVector2Array([crown[0]]), Color(0.3, 0.6, 0.85), 1.0, true)
	ci.draw_line(top + Vector2(-gw, -gh * 0.45), top + Vector2(gw, -gh * 0.45), Color(1, 1, 1, 0.8), 1.0, true)
	# Sparks around.
	if fx >= 1:
		var pts2 := _corners(ro.grow(s * 0.1)) + [Vector2(r.get_center().x, ro.position.y - s * 0.32), Vector2(ro.position.x - s * 0.1, r.get_center().y),
			Vector2(ro.end.x + s * 0.1, r.get_center().y), Vector2(r.get_center().x, ro.end.y + s * 0.12)]
		for k in pts2.size():
			var tw := 0.5 + 0.5 * sin(t * 3.0 + float(k) * 2.3) if live else 0.6
			_spark(ci, pts2[k], s * 0.05 * tw, Color(0.75, 0.95, 1.0, tw))


## Golden Roman laurel branches rising along both sides of the flag from its lower corners, the leaves swaying (one
## clock). They start at the corners, not under the middle: nothing gold gathers below the flag's centre.
static func _flag_laurels(ci: CanvasItem, r: Rect2, ro: Rect2, s: float, t: float, live: bool) -> void:
	var length := s * 0.24
	var width := s * 0.09
	for side_v in [-1.0, 1.0]:
		var side: float = side_v
		var x_out := ro.position.x - s * 0.12 if side < 0.0 else ro.end.x + s * 0.12
		var p0 := Vector2((ro.position.x + s * 0.06) if side < 0.0 else (ro.end.x - s * 0.06), ro.end.y + s * 0.1)
		var p1 := Vector2(x_out + side * s * 0.06, ro.end.y)
		var p2 := Vector2(x_out, ro.position.y + s * 0.05)
		var stem := PackedVector2Array()
		for k in 13:
			var u := float(k) / 12.0
			stem.append(p0.lerp(p1, u).lerp(p1.lerp(p2, u), u))
		ci.draw_polyline(stem, Color(0.7, 0.5, 0.12), maxf(1.0, s * 0.025), true)
		for k in 8:
			var u2 := 0.22 + 0.73 * float(k) / 7.0
			var pos := p0.lerp(p1, u2).lerp(p1.lerp(p2, u2), u2)
			var nxt := p0.lerp(p1, u2 + 0.02).lerp(p1.lerp(p2, u2 + 0.02), u2 + 0.02)
			var along := (nxt - pos).angle()
			var sway := 0.18 * sin(t * 1.8 + float(k) * 0.6 + side) if live else 0.0
			for out_v in [-1.0, 1.0]:
				var out: float = out_v
				var dir := along + out * 0.7 + sway
				_leaf(ci, pos + _dir(dir) * length * 0.38, dir, length * (1.0 - 0.35 * u2), width)
		# The berry and the tie at the root.
		ci.draw_circle(p0, s * 0.03, Color(0.85, 0.65, 0.2))
