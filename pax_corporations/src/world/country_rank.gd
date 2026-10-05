extends Node
## The country's rank in the world (like the companies' frames in Pax Corporations): its place by might (might.gd)
## gives a step — бриллиант 1–5, сапфир 6–15, золото 16–35, серебро 36–70, бронза below. Pax Corporations decides the
## step and shows its change; the interface wears it when Pax Corpface is installed (its hud.apply_tier: the header's
## edge, the column's edge, the flag's frame, the own windows) — the step is handed over through Engine meta.
## Up at once when the place is inside the next step; down only below the step's limit with a 15 % margin (no blinking).
## A change waits until a skip is over, then a card asks «перейти на новый этап?» (or tells the country has slipped);
## on «go» — the animation: the big flag in its old frame grows, snaps small, a glow around the flag, the new frame, the new
## title; the interface takes the new step under the flash. Console (zz_corp_probe): rank_anim up|down [step],
## rank_<step> (rank_bronze … rank_diamond) — the way up to that step.

const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")   # Main's methods, 0.24 names
const UiStyle := preload("res://mods/pax_corporations/src/look/ui_style.gd")
const Glass := preload("res://mods/pax_corporations/src/look/glass.gd")
const TierLook := preload("res://mods/pax_corporations/src/shared/tier_look.gd")
const Might := preload("res://mods/pax_corporations/src/shared/might.gd")
const Frames := preload("res://mods/pax_corporations/src/companies/frames.gd")
const WheelGuard := preload("res://mods/pax_corporations/src/shared/wheel_guard.gd")
const TIERS := ["bronze", "silver", "gold", "sapphire", "diamond"]
const LIMITS := {"diamond": 5, "sapphire": 15, "gold": 35, "silver": 70}
const COLORS := {"bronze": Color(0.80, 0.52, 0.32), "silver": Color(0.80, 0.83, 0.89), "gold": Color(0.96, 0.78, 0.32),
	"sapphire": Color(0.32, 0.58, 1.0), "diamond": Color(0.62, 0.94, 1.0)}

var mod: Node
var game: PaxGame
var tier := ""                    # the step the interface wears
var place := 0                    # the country's place by might
var pending: Dictionary = {}      # {from, to, место, вверх} — waits for the player
var _week := -1
var _t := 0.0
var _card: Control
var _show: Control
var _demo_back := ""              # a console demo: the step to come back to


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _tr(key: String) -> String:
	return str(mod.call("tr_key", "pax_corporations_" + key))


static func rank_of(t: String) -> int:
	return maxi(0, TIERS.find(t))


static func color(t: String) -> Color:
	return COLORS.get(t, COLORS["bronze"])


## The step a place earns (margin 1.0) or keeps (margin 1.15).
static func tier_for(p: int, margin: float) -> String:
	for t in ["diamond", "sapphire", "gold", "silver"]:
		if p <= int(round(float(LIMITS[t]) * margin)):
			return t
	return "bronze"


func start(g: PaxGame) -> void:
	game = g
	_week = -1
	if not tier.is_empty():
		_apply(tier)   # a loaded save: the windows wear its step at once


func save_state() -> Dictionary:
	return {"ступень": tier, "место": place, "ждёт": pending}


func load_state(st: Dictionary) -> void:
	tier = str(st.get("ступень", ""))
	place = int(st.get("место", 0))
	pending = (st.get("ждёт", {}) as Dictionary).duplicate() if st.get("ждёт") is Dictionary else {}


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(game.main):
		return
	_t += delta
	if _t < 1.5:
		return
	_t = 0.0
	var week := floori(float(game.day()) / 7.0)
	if week != _week:
		_week = week
		_check()
	if not pending.is_empty() and not _skipping() and not is_instance_valid(_card) and not is_instance_valid(_show):
		_ask(pending)


func _skipping() -> bool:
	for flag in ["идёт_перемотка", "мотаем_до_события", "_прыжок_вперёд_машиной"]:
		var v: Variant = game.main.get(flag)
		if v is bool and v:
			return true
	return false


## The weekly place; a new step becomes a pending change (the first time — the step at once, no card).
func _check() -> void:
	var me := str(game.player_faction().get("name", ""))
	var tb := Might.table(game)
	if not tb.has(me):
		return
	place = int((tb[me] as Dictionary)["место"])
	var up := tier_for(place, 1.0)
	var keep := tier_for(place, 1.15)
	if tier.is_empty():
		tier = up
		_apply(tier)
		return
	var now := tier
	if rank_of(up) > rank_of(tier):
		now = up
	elif rank_of(keep) < rank_of(tier):
		now = keep
	var target := str(pending.get("to", tier))
	if now != target:
		pending = {} if now == tier else {"from": tier, "to": now, "место": place, "up": rank_of(now) > rank_of(tier)}
	elif not pending.is_empty():
		pending["место"] = place
	_apply(tier)


## The interface wears the step: Pax Corporations' windows (their glass and the theme's accent, tier_look.gd),
## Pax Corpface's hud (when installed), and the step is told to the other mods (Engine meta).
func _apply(t: String) -> void:
	UiStyle.set_tier(t)
	Glass.set_tier(t)
	TierLook.publish(t, place)
	if Engine.has_meta("pax_corpface_hud"):
		var hud: Variant = Engine.get_meta("pax_corpface_hud")
		if hud is Object and is_instance_valid(hud) and (hud as Object).has_method("apply_tier"):
			(hud as Object).call("apply_tier", t, place)


# ---------- the card ----------

func _ask(p: Dictionary) -> void:
	var layer: Variant = game.hud_layer()
	if not (layer is CanvasLayer):
		return
	var up := bool(p.get("up", true))
	var to := str(p["to"])
	var from := str(p["from"])
	_card = Control.new()
	_card.name = "PaxCorpfaceRankCard"
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.theme = UiStyle.theme()
	_card.z_index = 90
	(layer as CanvasLayer).add_child(_card)
	var wg := WheelGuard.new()
	wg.whole = true
	_card.add_child(wg)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	var sb := UiStyle.box(Color(UiStyle.SOLID_BG, 0.97), color(to), 10, Vector4(24, 20, 24, 20))
	sb.set_border_width_all(2)
	sb.shadow_color = Color(color(to), 0.35)
	sb.shadow_size = 18
	box.add_theme_stylebox_override("panel", sb)
	center.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var kicker := Label.new()
	kicker.text = _tr("rank_kicker_up" if up else "rank_kicker_down").to_upper()
	kicker.add_theme_color_override("font_color", color(to) if up else UiStyle.DOWN)
	kicker.add_theme_font_size_override("font_size", 12)
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(kicker)
	var help := Button.new()
	help.text = "?"
	help.tooltip_text = _tr("rank_help_tip")
	help.focus_mode = Control.FOCUS_NONE
	help.custom_minimum_size = Vector2(30, 26)
	head.add_child(help)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	var flag := FlagFrame.new()
	flag.setup(_flag_tex(), from, 1.0)
	flag.custom_minimum_size = Vector2(150, 104)
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(flag)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tv)
	var title := Label.new()
	title.text = _tr("rank_title_up" if up else "rank_title_down") % _tr("rank_" + to)
	title.add_theme_font_override("font", UiStyle.font(true))
	title.add_theme_font_size_override("font_size", 20)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(300, 0)
	tv.add_child(title)
	var text := Label.new()
	text.text = _tr("rank_text_up" if up else "rank_text_down") % [int(p.get("место", place)), _tr("rank_" + from), _tr("rank_" + to)]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(300, 0)
	text.add_theme_color_override("font_color", UiStyle.DIM)
	tv.add_child(text)
	var how := Label.new()
	how.text = _tr("rank_help")
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(460, 0)
	how.add_theme_font_size_override("font_size", 12)
	how.add_theme_color_override("font_color", UiStyle.DIM)
	how.visible = false
	v.add_child(how)
	help.pressed.connect(func() -> void: how.visible = not how.visible)
	var go := Button.new()
	go.text = _tr("rank_go_up" if up else "rank_go_down")
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(0, 38)
	go.add_theme_color_override("font_color", color(to) if up else UiStyle.TEXT)
	go.pressed.connect(func() -> void:
		_card.queue_free()
		pending = {}
		play(from, to, up))
	v.add_child(go)
	# No «world ranking» button on this card: it opened the ranking under the card (the ranking stays in the
	# column's step line and the console rank_top).
	box.pivot_offset = Vector2(260, 120)
	box.scale = Vector2(0.9, 0.9)
	_card.modulate.a = 0.0
	var tw := _card.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	tw.tween_property(_card, "modulate:a", 1.0, 0.2)
	tw.tween_property(box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _flag_tex() -> Texture2D:
	var main: Object = game.main
	if GameApi.has(main, "_флаг_чей"):
		var tex: Variant = GameApi.call_main(main, "_флаг_чей", [str(game.player_faction().get("name", ""))])
		if tex is Texture2D:
			return tex as Texture2D
	return null


# ---------- the animation ----------

## The big flag in the old frame grows, snaps small, a glow around the flag — under it the new frame and the new interface —
## and it settles; the new title, a pause, gone.
func play(from: String, to: String, up: bool) -> void:
	var layer: Variant = game.hud_layer()
	if not (layer is CanvasLayer):
		tier = to
		_apply(tier)
		return
	if is_instance_valid(_show):
		_show.queue_free()
	_show = Control.new()
	_show.name = "PaxCorpfaceRankShow"
	_show.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_show.mouse_filter = Control.MOUSE_FILTER_STOP
	_show.z_index = 95
	_show.theme = UiStyle.theme()
	(layer as CanvasLayer).add_child(_show)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_show.add_child(dim)
	var view := _show.get_viewport_rect().size
	var fsz := Vector2(420, 290)
	var flag := FlagFrame.new()
	flag.setup(_flag_tex(), from, 1.6)
	flag.size = fsz
	flag.position = (view - fsz) / 2.0 - Vector2(0, 40)
	flag.pivot_offset = fsz / 2.0
	_show.add_child(flag)
	var title := Label.new()
	title.text = _tr("rank_" + from)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UiStyle.font(true))
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", color(from))
	title.size = Vector2(view.x, 40)
	title.position = Vector2(0, flag.position.y + fsz.y + 30)
	_show.add_child(title)
	var sub := Label.new()
	sub.text = _tr("rank_show_up" if up else "rank_show_down") % place
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", UiStyle.DIM)
	sub.size = Vector2(view.x, 24)
	sub.position = Vector2(0, title.position.y + 44)
	sub.modulate.a = 0.0
	_show.add_child(sub)
	# The flash: a soft round glow in the new step's colour around the flag only — not a white screen (it blinded).
	var glow := Gradient.new()
	var tint: Color = color(to).lerp(Color(1, 1, 1), 0.45 if up else 0.2)
	glow.set_color(0, Color(tint, 0.85 if up else 0.5))
	glow.set_color(1, Color(tint, 0.0))
	glow.add_point(0.35, Color(tint, 0.45 if up else 0.25))
	var gt := GradientTexture2D.new()
	gt.gradient = glow
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var flash := TextureRect.new()
	flash.texture = gt
	flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flash.stretch_mode = TextureRect.STRETCH_SCALE
	var gsz := Vector2(fsz.x * 1.7, fsz.x * 1.7)
	flash.size = gsz
	flash.position = flag.position + fsz / 2.0 - gsz / 2.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.modulate.a = 0.0
	_show.add_child(flash)

	_show.modulate.a = 0.0
	flag.scale = Vector2(0.6, 0.6)
	var tw := _show.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_show, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(flag, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.45)
	# Grows…
	tw.tween_property(flag, "scale", Vector2(1.2, 1.2), 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# …snaps small…
	tw.tween_property(flag, "scale", Vector2(0.8, 0.8), 0.09).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	# …the flash: under it the new frame, the new title and the new interface.
	tw.tween_property(flash, "modulate:a", 1.0, 0.04)
	tw.tween_callback(func() -> void:
		flag.tier = to
		flag.rays = 1.0 if up else 0.0
		title.text = _tr("rank_" + to)
		title.add_theme_color_override("font_color", color(to))
		tier = to
		_apply(tier))
	tw.tween_property(flash, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(flag, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sub, "modulate:a", 1.0, 0.5)
	tw.parallel().tween_property(flag, "rays", 0.0, 1.6)
	tw.tween_interval(1.7)
	tw.tween_property(_show, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void:
		_show.queue_free()
		if not _demo_back.is_empty():
			var back := _demo_back
			_demo_back = ""
			get_tree().create_timer(4.0, true).timeout.connect(func() -> void:
				tier = back
				_apply(tier)))


## Console (zz_corp_probe «rank_anim up|down [step]», «rank_<step>»): the card and the animation without touching the
## real rank; the real step comes back 4 s after.
func demo(dir: String, to_tier: String) -> String:
	if game == null:
		return "no game"
	var cur := tier if not tier.is_empty() else "bronze"
	var up := dir != "down"
	var to := to_tier
	if not (to in TIERS):
		to = TIERS[clampi(rank_of(cur) + (1 if up else -1), 0, TIERS.size() - 1)]
		if to == cur:
			to = TIERS[clampi(rank_of(cur) + (-1 if up else 1), 0, TIERS.size() - 1)]
			up = not up
	_demo_back = cur
	if is_instance_valid(_card):
		_card.queue_free()
	_ask({"from": cur, "to": to, "место": place, "up": up})
	return "rank demo: %s → %s (%s), the real step %s comes back after" % [cur, to, "up" if up else "down", cur]


# ---------- the world's top ----------

var _top: Control


## The world's top states by might: place, flag in its frame, name, might, rank; the player's country marked.
## «?» explains the ranks. Esc, ✕ or a click outside close it.
func show_top() -> void:
	var layer: Variant = game.hud_layer() if game != null else null
	if not (layer is CanvasLayer) or is_instance_valid(_card) or is_instance_valid(_show):
		return   # never over the rank change's card or animation (it opened under them)
	if is_instance_valid(_top):
		_top.queue_free()
		_top = null
		return
	var me := str(game.player_faction().get("name", ""))
	var tb := Might.table(game)
	var rows: Array = tb.keys()
	rows.sort_custom(func(a, b): return int((tb[a] as Dictionary)["место"]) < int((tb[b] as Dictionary)["место"]))
	_top = Control.new()
	_top.name = "PaxCorpCountryTop"
	_top.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_top.mouse_filter = Control.MOUSE_FILTER_STOP
	_top.theme = UiStyle.theme()
	_top.z_index = 85
	_top.set_meta(&"pax_corp_skin_skip", true)
	(layer as CanvasLayer).add_child(_top)
	var wg := WheelGuard.new()
	wg.whole = true
	_top.add_child(wg)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and is_instance_valid(_top):
			_top.queue_free())
	_top.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(620, 0)
	var sb := UiStyle.box(Color(UiStyle.SOLID_BG, 0.97), UiStyle.SOLID_LINE, 10, Vector4(22, 18, 22, 18))
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	box.add_theme_stylebox_override("panel", sb)
	center.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	box.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var title := Label.new()
	title.text = _tr("rank_top_title")
	title.add_theme_font_override("font", UiStyle.font(true))
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var help := Button.new()
	help.text = "?"
	help.tooltip_text = _tr("rank_help_tip")
	help.focus_mode = Control.FOCUS_NONE
	help.custom_minimum_size = Vector2(32, 28)
	head.add_child(help)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(32, 28)
	x.pressed.connect(func() -> void:
		if is_instance_valid(_top):
			_top.queue_free())
	head.add_child(x)
	var how := Label.new()
	how.text = _tr("rank_help")
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(570, 0)
	how.add_theme_font_size_override("font_size", 12)
	how.add_theme_color_override("font_color", UiStyle.DIM)
	how.visible = false
	v.add_child(how)
	help.pressed.connect(func() -> void: how.visible = not how.visible)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, mini(560, int(_top.get_viewport_rect().size.y * 0.66)))
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var shown := 0
	for name in rows:
		var row: Dictionary = tb[name]
		var p := int(row["место"])
		var step := tier_for(p, 1.0)
		if str(name) == me and not tier.is_empty():
			step = tier
		var line := PanelContainer.new()
		var lsb := UiStyle.box(Color(color(step), 0.12) if str(name) == me else Color(1, 1, 1, 0.03), Color(color(step), 0.6) if str(name) == me else Color(0, 0, 0, 0), 6, Vector4(10, 4, 10, 4))
		line.add_theme_stylebox_override("panel", lsb)
		list.add_child(line)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		line.add_child(h)
		var num := Label.new()
		num.text = "%d" % p
		num.custom_minimum_size = Vector2(30, 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num.add_theme_color_override("font_color", color(step))
		num.add_theme_font_override("font", UiStyle.font(true))
		h.add_child(num)
		var fl := FlagFrame.new()
		fl.setup(_flag_of(str(name)), step, 0.5)
		fl.same_size = true
		fl.set_process(false)   # a still frame in the list (~190 rows redrawn every frame cost the game its frames)
		fl.custom_minimum_size = Vector2(86, 52)
		h.add_child(fl)
		var nm := Label.new()
		nm.text = str(name)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.add_theme_font_size_override("font_size", 14)
		h.add_child(nm)
		var st := Label.new()
		st.text = _tr("rank_" + step)
		st.custom_minimum_size = Vector2(170, 0)
		st.add_theme_color_override("font_color", color(step))
		st.add_theme_font_size_override("font_size", 12)
		h.add_child(st)
		var mt := Label.new()
		mt.text = "%d" % roundi(float(row["сила"]))
		mt.tooltip_text = _tr("rank_might_tip") % [roundi(float(row["экономика"])), roundi(float(row["army"])), _tr("rank_yes") if bool(row["nuclear"]) else _tr("rank_no")]
		mt.mouse_filter = Control.MOUSE_FILTER_PASS
		mt.custom_minimum_size = Vector2(40, 0)
		mt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(mt)
		shown += 1
	_top.modulate.a = 0.0
	var tw := _top.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_top, "modulate:a", 1.0, 0.18)


func _flag_of(country: String) -> Texture2D:
	var main: Object = game.main
	if GameApi.has(main, "_флаг_чей"):
		var tex: Variant = GameApi.call_main(main, "_флаг_чей", [country])
		if tex is Texture2D:
			return tex as Texture2D
	return null


func _unhandled_input(e: InputEvent) -> void:
	if is_instance_valid(_top) and e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).keycode == KEY_ESCAPE:
		_top.queue_free()
		get_viewport().set_input_as_handled()


# ---------- the frame ----------

## A flag in the frame of a step: a coloured edge, a glow (gold and above), gems in the corners (sapphire,
## diamond), a light running along the diamond; «rays» — the burst after the flash.
class FlagFrame extends Control:
	var tex: Texture2D
	var tier := "bronze"
	var thick := 1.0
	var rays := 0.0
	var same_size := false   # a list of countries: the flag sized for the widest frame, so every row's flag is equal
	var _clock := 0.0

	func setup(t: Texture2D, step: String, k: float) -> void:
		tex = t
		tier = step
		thick = k
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_clock += delta
		queue_redraw()

	func _draw() -> void:
		# Room for the frame (laurels, wings, crown) inside the control: the flag fills the rest.
		# The flag keeps 3:2 whatever the control's shape (a container may stretch it taller — the flag came out
		# square); the frame's margins are in flag heights.
		var m := Frames.flag_margin(tier)
		var fit := m
		if same_size:
			for t in TIERS:
				var o := Frames.flag_margin(t)
				fit = Vector4(maxf(fit.x, o.x), maxf(fit.y, o.y), maxf(fit.z, o.z), maxf(fit.w, o.w))
		var h := minf(size.y / (1.0 + fit.y + fit.w), size.x / (1.5 + fit.x + fit.z))
		var w := h * 1.5
		var top := (size.y - h * (1.0 + fit.y + fit.w)) / 2.0 + h * fit.y
		var r := Rect2(Vector2((size.x - w) / 2.0, top), Vector2(w, h))
		var col: Color = COLORS.get(tier, COLORS["bronze"])
		if rays > 0.01:
			var c := size / 2.0
			for i in 16:
				var a := TAU * float(i) / 16.0 + _clock * 0.4
				draw_line(c, c + Vector2(cos(a), sin(a)) * size.length() * (0.4 + 0.6 * rays), Color(col, 0.25 * rays), 6.0 * thick)
		draw_rect(r, Color(0, 0, 0, 0.5))
		if tex != null:
			draw_texture_rect(tex, r, false)
		else:
			draw_rect(r, Color(0.2, 0.25, 0.3))
		Frames.draw_flag(self, r, tier)

	static func _on_edge(r: Rect2, s: float, _per: float) -> Vector2:
		if s < r.size.x:
			return r.position + Vector2(s, 0)
		s -= r.size.x
		if s < r.size.y:
			return Vector2(r.end.x, r.position.y + s)
		s -= r.size.y
		if s < r.size.x:
			return Vector2(r.end.x - s, r.end.y)
		s -= r.size.x
		return Vector2(r.position.x, r.end.y - s)


## Console: the way up to a step — from the step below it (bronze: down from silver).
func demo_to(to_tier: String) -> String:
	if not (to_tier in TIERS):
		return "steps: " + ", ".join(PackedStringArray(TIERS))
	var i := TIERS.find(to_tier)
	var from: String = TIERS[i - 1] if i > 0 else TIERS[1]
	var real := tier if not tier.is_empty() else "bronze"
	_demo_back = real
	if is_instance_valid(_card):
		_card.queue_free()
	_ask({"from": from, "to": to_tier, "место": place, "up": i > 0})
	return "rank demo: %s → %s, the real step %s comes back after" % [from, to_tier, real]
