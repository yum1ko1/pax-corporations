extends RefCounted
## Save compatibility. Every save keeps the mod version it was made with («мод»; saves before 3.0.0 have none).
## config/compat.json lists the versions whose global changes do not fit a world started on an older version —
## the incompatibility flags. A world saved before such a flag gets a warning when it is loaded: what changed and
## two ways — continue at one's own risk, or start the mod's data in this world anew (the world itself stays).
## After «continue» the next save carries the new version, so the warning is not repeated.
const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")

const WhatsNew := preload("res://mods/pax_corporations/src/shared/whatsnew.gd")
const WARN := Color(0.98, 0.55, 0.3)

var mod: PaxMod
var game: PaxGame
var on_reset: Callable          # func() — the mod's data in this world start anew
var _panel: PanelContainer


static func current(m: PaxMod) -> String:
	var manifest: Variant = GameApi.json(m, "mod.json", {})
	return str((manifest as Dictionary).get("version", "")) if manifest is Dictionary else ""


## The incompatibility flags newer than the version the world was saved with (oldest first). An empty state —
## a new world — has none.
static func flags_after(m: PaxMod, state: Dictionary) -> Array:
	if state.is_empty():
		return []
	var saved := str(state.get("mod_flag", "0"))
	var cfg: Variant = GameApi.json(m, "config/compat.json", {})
	var all: Array = (cfg as Dictionary).get("incompatible", []) if cfg is Dictionary else []
	var out: Array = []
	for f in all:
		if f is Dictionary and WhatsNew.newer(str((f as Dictionary).get("version", "0")), saved):
			out.append(f)
	return out


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


func is_open() -> bool:
	return is_instance_valid(_panel)


func show(m: PaxMod, g: PaxGame, flags: Array, saved: String) -> void:
	mod = m
	game = g
	var hud := game.hud_layer() as CanvasLayer
	if hud == null or flags.is_empty() or is_open():
		return
	_panel = PanelContainer.new()
	_panel.z_index = 70
	_panel.set_meta(&"pax_corp_skin_skip", true)
	_panel.set_meta(&"pax_interface_skip_skin", true)   # «Pax Interface» does not reskin our window
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.06, 0.97)
	sb.border_color = WARN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	var title := Label.new()
	title.text = "⚠  " + _t("compat_title")
	title.add_theme_color_override("font_color", WARN)
	title.add_theme_font_size_override("font_size", 20)
	v.add_child(title)
	var sub := Label.new()
	sub.text = _t("compat_sub") % [saved if saved != "0" else _t("compat_old"), current(m)]
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(640, 0)
	v.add_child(sub)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size = Vector2(640, 0)
	text.add_theme_font_size_override("normal_font_size", 14)
	var body := ""
	for f in flags:
		var fd: Dictionary = f
		body += "[b][color=#fa8c4d]%s[/color][/b]\n%s\n\n" % [str(fd.get("version", "")), _t(str(fd.get("что", "")))]
	text.text = body.strip_edges()
	v.add_child(text)
	var advice := Label.new()
	advice.text = _t("compat_advice")
	advice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	advice.custom_minimum_size = Vector2(640, 0)
	advice.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	v.add_child(advice)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var reset := Button.new()
	reset.text = _t("compat_reset")
	reset.focus_mode = Control.FOCUS_NONE
	reset.tooltip_text = _t("compat_reset_tip")
	reset.pressed.connect(func() -> void:
		teardown()
		if on_reset.is_valid():
			on_reset.call()
		game.toast(_t("compat_reset_done")))
	row.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var go := Button.new()
	go.text = _t("compat_continue")
	go.focus_mode = Control.FOCUS_NONE
	go.pressed.connect(teardown)
	row.add_child(go)
	hud.add_child(_panel)
	_panel.reset_size()
	var view := _panel.get_viewport_rect().size
	_panel.position = ((view - _panel.size) / 2.0).max(Vector2(8, 8))


func teardown() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
