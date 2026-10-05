extends RefCounted
## Glass for the mod's windows (after the glass dashboard reference), without shaders: a deep blue translucent
## panel with a soft vertical light, a thin light edge and rounded corners; the mod's cards (ui_style.gd) are
## translucent white-blue on it. (5.0.10 blurred the screen with a shader — the game's experimental threaded
## renderer crashed on world load, so the blur is gone.)
## fullscreen: the «Corporations» window fills the game's whole window area (right of Pax Corpface's column,
## below the header) — a setting in the window's ⚙.

const FILL := Color(0.09, 0.15, 0.24, 0.94)
const EDGE := Color(0.85, 0.93, 1.0, 0.36)
const TierLook := preload("res://mods/pax_corporations/src/shared/tier_look.gd")

static var tier := ""             # the country's world step (country_rank.gd), "" — the mod's own blue glass
static var _panels: Array = []    # WeakRef of every glass window (a new step dresses them all)


static func apply(panel: Control) -> void:
	if not is_instance_valid(panel) or not (panel is PanelContainer) or panel.has_meta("pax_glass"):
		return
	panel.set_meta("pax_glass", true)
	_panels.append(weakref(panel))
	_dress(panel)


## A new world step: every glass window takes its look (and those made later).
static func set_tier(t: String) -> void:
	if t == tier:
		return
	tier = t
	_panels = _panels.filter(func(w: WeakRef) -> bool: return w.get_ref() != null)
	for w in _panels:
		_dress(w.get_ref() as Control)


static func _dress(panel: Control) -> void:
	var stepped := TierLook.frame(tier, Vector4(14, 12, 14, 12))
	if stepped != null:
		stepped.set_corner_radius_all(maxi(stepped.corner_radius_top_left, 12))
		panel.add_theme_stylebox_override("panel", stepped)
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = FILL
	sb.border_color = EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 14
	sb.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", sb)


## The window's minimum size = the game's window area (the parent of Main.низ_столб, inside its margins),
## never larger than the screen.
static func area(main: Object) -> Vector2:
	var col: Variant = main.get("низ_столб")
	if not (col is Control) or not ((col as Control).get_parent() is MarginContainer):
		return Vector2.ZERO
	var fr := (col as Control).get_parent() as MarginContainer
	var r := fr.get_global_rect()
	var m := Vector2(fr.get_theme_constant("margin_left") + fr.get_theme_constant("margin_right"),
		fr.get_theme_constant("margin_top") + fr.get_theme_constant("margin_bottom"))
	var view := fr.get_viewport_rect().size
	return (r.size - m - Vector2(16, 16)).clamp(Vector2(800, 560), (view - Vector2(40, 120)).max(Vector2(800, 560)))
