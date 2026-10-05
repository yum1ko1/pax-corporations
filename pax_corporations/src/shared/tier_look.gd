extends RefCounted
## How the interface looks at each world step of the player's country (Pax Corporations decides the step,
## world/country_rank.gd; Pax Corporations' windows and Pax Corpface's header, column and windows wear it).
## Higher steps look richer: bronze — plain warm grey, thin edge; silver — cool steel; gold — dark warm glass, a gold
## edge, a soft glow; sapphire — deep blue glass, a brighter edge, a glow, a slow shimmer; diamond — black-cyan glass,
## the widest rounding, a strong glow and a prismatic shimmer of the edges.
## frame() makes a window's frame; shine() registers it for the shimmer (animated on the game's frames for this mod's
## registered frames). The current step is shared through Engine meta «pax_corpinc_tier».

const META := &"pax_corpinc_tier"
const TIERS := ["bronze", "silver", "gold", "sapphire", "diamond"]
## accent — buttons, tabs, focus, bars; fill — a window's glass; edge — the edge's strength; border — px;
## radius — corners; glow — the shadow's size in the accent colour; shimmer — 0 none … 1 strong; title — headings.
const LOOKS := {
	"bronze": {"accent": Color(0.86, 0.58, 0.36), "fill": Color(0.105, 0.10, 0.10, 0.95), "edge": 0.40, "border": 1,
		"radius": 6, "glow": 0, "shimmer": 0.0, "title": Color(0.96, 0.84, 0.74)},
	"silver": {"accent": Color(0.80, 0.86, 0.94), "fill": Color(0.085, 0.105, 0.135, 0.95), "edge": 0.45, "border": 1,
		"radius": 8, "glow": 6, "shimmer": 0.0, "title": Color(0.92, 0.95, 1.0)},
	"gold": {"accent": Color(0.97, 0.78, 0.32), "fill": Color(0.115, 0.10, 0.065, 0.95), "edge": 0.58, "border": 2,
		"radius": 10, "glow": 10, "shimmer": 0.0, "title": Color(1.0, 0.88, 0.58)},
	"sapphire": {"accent": Color(0.38, 0.64, 1.0), "fill": Color(0.05, 0.085, 0.19, 0.95), "edge": 0.66, "border": 2,
		"radius": 12, "glow": 14, "shimmer": 0.5, "title": Color(0.78, 0.88, 1.0)},
	"diamond": {"accent": Color(0.62, 0.95, 1.0), "fill": Color(0.035, 0.085, 0.11, 0.96), "edge": 0.78, "border": 2,
		"radius": 14, "glow": 18, "shimmer": 1.0, "title": Color(0.85, 1.0, 1.0)},
}

static var _shining: Array = []   # [WeakRef(StyleBoxFlat), base border colour, base shadow colour, shimmer, phase]
static var _ticking := false


## The look of a step; {} — no step yet (the mod's own look stays).
static func look(tier: String) -> Dictionary:
	return LOOKS.get(tier, {})


static func accent(tier: String, fallback: Color) -> Color:
	return (LOOKS[tier] as Dictionary)["accent"] if LOOKS.has(tier) else fallback


## A window's frame at the step (padding as given); null without a step.
static func frame(tier: String, pad: Vector4 = Vector4(14, 12, 14, 12)) -> StyleBoxFlat:
	if not LOOKS.has(tier):
		return null
	var lk: Dictionary = LOOKS[tier]
	var sb := StyleBoxFlat.new()
	sb.bg_color = lk["fill"]
	sb.border_color = Color(lk["accent"] as Color, float(lk["edge"]))
	sb.set_border_width_all(int(lk["border"]))
	sb.set_corner_radius_all(int(lk["radius"]))
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	sb.anti_aliasing = true
	if int(lk["glow"]) > 0:
		sb.shadow_color = Color(lk["accent"] as Color, 0.16 + 0.01 * float(lk["glow"]))
		sb.shadow_size = int(lk["glow"])
	else:
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 10
	shine(sb, tier)
	return sb


## The frame's edge shimmers at sapphire and diamond (nothing below).
static func shine(sb: StyleBoxFlat, tier: String) -> void:
	var s := float((LOOKS.get(tier, {}) as Dictionary).get("shimmer", 0.0))
	if s <= 0.0:
		return
	_shining = _shining.filter(func(e: Array) -> bool: return (e[0] as WeakRef).get_ref() != null)
	_shining.append([weakref(sb), sb.border_color, sb.shadow_color, s, randf() * TAU])
	ensure_shimmer()


## The shimmer runs on every frame of the game (once per mod; cheap — a few frames' colours).
static func ensure_shimmer() -> void:
	if _ticking:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_ticking = true
	tree.process_frame.connect(_tick)


## The mod unloads: the shimmer stops (the frames' last colours stay).
static func stop() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if _ticking and tree != null and tree.process_frame.is_connected(_tick):
		tree.process_frame.disconnect(_tick)
	_ticking = false
	_shining.clear()


static func _tick() -> void:
	if _shining.is_empty():
		return
	var t := float(Time.get_ticks_msec()) / 1000.0
	for e in _shining:
		var sb: Variant = (e[0] as WeakRef).get_ref()
		if sb == null:
			continue
		var s := float(e[3])
		var wave := 0.5 + 0.5 * sin(t * 1.6 + float(e[4]))
		var base: Color = e[1]
		var edge := base.lerp(Color(1, 1, 1, base.a), 0.35 * s * wave)
		if s >= 1.0:   # the diamond: the edge's hue drifts a little (a prism)
			edge = edge.lerp(Color.from_hsv(fposmod(t * 0.08 + float(e[4]), 1.0), 0.35, 1.0, base.a), 0.25 * wave)
		(sb as StyleBoxFlat).border_color = edge
		var glow: Color = e[2]
		(sb as StyleBoxFlat).shadow_color = Color(glow, glow.a * (0.7 + 0.6 * wave * s))


## The step the interface wears now (shared by the mods), "" — none yet.
static func current() -> String:
	var v: Variant = Engine.get_meta(META) if Engine.has_meta(META) else null
	return str((v as Dictionary).get("tier", "")) if v is Dictionary else ""


static func publish(tier: String, place: int) -> void:
	Engine.set_meta(META, {"tier": tier, "place": place})
