extends Node
## A country's card (Pax CorpInc3D: a click on a country on the 3D globe; main.open_country_card): a panel at the
## right of the screen, the globe stays in view. Dressed in the country's own world step (country_rank.gd: bronze …
## diamond — TierLook's frame, accent, shimmer; the flag in its step's frame): its place and might, its people, army
## and nuclear arms (might.gd), its companies — how many, their value and revenue, the five largest (a click — the
## dossier). ✕ or Esc closes it; another country replaces it.

const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")   # Main's methods, 0.24 names
const UiStyle := preload("res://mods/pax_corporations/src/look/ui_style.gd")
const TierLook := preload("res://mods/pax_corporations/src/shared/tier_look.gd")
const Might := preload("res://mods/pax_corporations/src/shared/might.gd")
const CountryRank := preload("res://mods/pax_corporations/src/world/country_rank.gd")
const WIDTH := 400.0

var app: Object                     # main.gd: tr_key, db, windows_ctl
var game: PaxGame
var country := ""
var _panel: PanelContainer


func setup(host: Object, g: PaxGame) -> void:
	app = host
	game = g
	name = "PaxCorpCountryCardCtl"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _tr(key: String) -> String:
	return str(app.call("tr_key", "pax_corporations_card_" + key))


func is_open() -> bool:
	return is_instance_valid(_panel)


func close() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	country = ""


func open(who: String) -> void:
	close()
	var layer: Variant = game.hud_layer() if game != null else null
	if who.is_empty() or not (layer is CanvasLayer):
		return
	var tb := Might.table(game)
	var row: Dictionary = tb.get(who, {})
	var place := int(row.get("место", 0))
	var step := CountryRank.tier_for(place, 1.0) if place > 0 else "bronze"
	var accent := CountryRank.color(step)
	var fd := _faction(who)
	country = who

	_panel = PanelContainer.new()
	_panel.name = "PaxCorpCountryCard"
	_panel.theme = UiStyle.theme()
	_panel.z_index = 80
	_panel.set_meta(&"pax_corp_skin_skip", true)
	var sb: StyleBoxFlat = TierLook.frame(step, Vector4(18, 14, 18, 16))
	if sb == null:
		sb = UiStyle.box(Color(UiStyle.SOLID_BG, 0.96), accent, 10, Vector4(18, 14, 18, 16))
	_panel.add_theme_stylebox_override("panel", sb)
	TierLook.shine(sb, step)
	TierLook.ensure_shimmer()
	var view := (layer as CanvasLayer).get_viewport().get_visible_rect().size
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.position = Vector2(view.x - WIDTH - 24.0, 150.0)
	(layer as CanvasLayer).add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)

	# The head: the flag in its step's frame, the name, the step; ✕.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var fl := CountryRank.FlagFrame.new()
	fl.setup(_flag(who), step, 0.6)
	fl.custom_minimum_size = Vector2(96, 60)
	fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(fl)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 2)
	head.add_child(tv)
	var title := Label.new()
	title.text = who
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_override("font", UiStyle.font(true))
	title.add_theme_font_size_override("font_size", 20)
	tv.add_child(title)
	var st := Label.new()
	st.text = str(app.call("tr_key", "pax_corporations_rank_" + step))
	st.add_theme_color_override("font_color", accent)
	st.add_theme_font_size_override("font_size", 13)
	tv.add_child(st)
	if str(game.player_faction().get("name", "")) == who:
		var ours := Label.new()
		ours.text = _tr("ours")
		ours.add_theme_color_override("font_color", UiStyle.DIM)
		ours.add_theme_font_size_override("font_size", 12)
		tv.add_child(ours)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(32, 28)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	x.pressed.connect(close)
	head.add_child(x)

	# The state: place and might, people, army, nuclear arms.
	_section(v, _tr("state"), accent)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	if place > 0:
		_row(grid, _tr("place"), _tr("place_of") % [place, tb.size()], accent)
		_row(grid, _tr("might"), "%d / 100" % roundi(float(row.get("сила", 0.0))), accent)
		_row(grid, _tr("economy"), "%d / 100" % roundi(float(row.get("экономика", 0.0))), Color.WHITE)
		_row(grid, _tr("army"), "%d / 100" % roundi(float(row.get("army", 0.0))), Color.WHITE)
	var humans := float(fd.get("humans", 0.0))
	if humans > 0.0:
		_row(grid, _tr("people"), _people(humans), Color.WHITE)
		var fighters := clampf(float(fd.get("fighters", 0.0)), 0.0, 1.0)
		if fighters > 0.0:
			_row(grid, _tr("soldiers"), _people(humans * fighters), Color.WHITE)
	if fd.has("level"):
		_row(grid, _tr("level"), "%.2f" % float(fd.get("level", 0.0)), Color.WHITE)
	if place > 0:
		_row(grid, _tr("nuclear"), _tr("yes") if bool(row.get("nuclear", false)) else _tr("no"), Color.WHITE)

	# The companies.
	var db: Object = app.get("db")
	var list: Array = []
	var cap := 0.0
	var revenue := 0.0
	if db != null:
		for item in db.get("companies"):
			var c: Dictionary = item
			if str(c.get("_country", "")) != who:
				continue
			list.append(c)
			cap += float(db.call("cap", c))
			revenue += float(db.call("fund", c, "выручка"))
	_section(v, _tr("companies"), accent)
	var g2 := GridContainer.new()
	g2.columns = 2
	g2.add_theme_constant_override("h_separation", 16)
	g2.add_theme_constant_override("v_separation", 4)
	v.add_child(g2)
	_row(g2, _tr("count"), "%d" % list.size(), Color.WHITE)
	if not list.is_empty():
		_row(g2, _tr("value"), str(db.call("money", cap)), accent)
		_row(g2, _tr("revenue"), str(db.call("money", revenue)), Color.WHITE)
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(db.call("cap", a)) > float(db.call("cap", b)))
		var top := Label.new()
		top.text = _tr("largest")
		top.add_theme_color_override("font_color", UiStyle.DIM)
		top.add_theme_font_size_override("font_size", 12)
		v.add_child(top)
		for i in mini(5, list.size()):
			var c: Dictionary = list[i]
			var b := Button.new()
			b.text = "%d. %s — %s" % [i + 1, str(db.call("name_of", c)), str(db.call("money", float(db.call("cap", c))))]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.focus_mode = Control.FOCUS_NONE
			b.flat = true
			b.tooltip_text = _tr("open_tip")
			var cid := str(c.get("id", ""))
			b.pressed.connect(func() -> void: app.call("open_company_3d", cid))
			v.add_child(b)
	else:
		var none := Label.new()
		none.text = _tr("none")
		none.add_theme_color_override("font_color", UiStyle.DIM)
		v.add_child(none)

	_panel.modulate.a = 0.0
	var tw := _panel.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.15)


## A country in numbers for other mods (Pax Corpface's «Держава»): {place, of, might, economy, army, step, nuclear,
## companies, cap, revenue, top: [[name, cap, id]…]} — money in the mod's own words (db.money); {} without data.
func summary(who: String) -> Dictionary:
	var out := {}
	var tb := Might.table(game)
	var row: Dictionary = tb.get(who, {})
	if not row.is_empty():
		var place := int(row.get("место", 0))
		out["place"] = place
		out["of"] = tb.size()
		out["might"] = float(row.get("сила", 0.0))
		out["economy"] = float(row.get("экономика", 0.0))
		out["army"] = float(row.get("army", 0.0))
		out["nuclear"] = bool(row.get("nuclear", false))
		out["step"] = CountryRank.tier_for(place, 1.0)
		out["step_name"] = str(app.call("tr_key", "pax_corporations_rank_" + str(out["step"])))
	var db: Object = app.get("db")
	if db != null:
		var list: Array = []
		var cap := 0.0
		var revenue := 0.0
		for item in db.get("companies"):
			var c: Dictionary = item
			if str(c.get("_country", "")) != who:
				continue
			list.append(c)
			cap += float(db.call("cap", c))
			revenue += float(db.call("fund", c, "выручка"))
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(db.call("cap", a)) > float(db.call("cap", b)))
		out["companies"] = list.size()
		out["cap"] = str(db.call("money", cap))
		out["revenue"] = str(db.call("money", revenue))
		var top: Array = []
		for i in mini(5, list.size()):
			var c: Dictionary = list[i]
			top.append([str(db.call("name_of", c)), str(db.call("money", float(db.call("cap", c)))), str(c.get("id", ""))])
		out["top"] = top
	return out


## Esc closes the card.
func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k != null and is_open() and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _faction(who: String) -> Dictionary:
	for f in Might.living_states(game):
		if str((f as Dictionary).get("name", "")) == who:
			return f
	var me: Dictionary = game.player_faction()
	if str(me.get("name", "")) == who:
		return Might._with_home(game, me)
	return {}


func _flag(who: String) -> Texture2D:
	var main: Object = game.main
	if GameApi.has(main, "_флаг_чей"):
		var tex: Variant = GameApi.call_main(main, "_флаг_чей", [who])
		if tex is Texture2D:
			return tex as Texture2D
	return null


static func _section(v: VBoxContainer, text: String, accent: Color) -> void:
	var sep := HSeparator.new()
	v.add_child(sep)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiStyle.font(true))
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", accent)
	v.add_child(l)


static func _row(grid: GridContainer, label: String, value: String, col: Color) -> void:
	var a := Label.new()
	a.text = label
	a.add_theme_color_override("font_color", UiStyle.DIM)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(a)
	var b := Label.new()
	b.text = value
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.add_theme_color_override("font_color", col)
	grid.add_child(b)


## People: «1,41 млрд» / «145 млн» / «820 тыс.» (the game's numbers are people).
func _people(n: float) -> String:
	if n >= 1e9:
		return _tr("bn") % (n / 1e9)
	if n >= 1e6:
		return _tr("mn") % (n / 1e6)
	return _tr("th") % (n / 1e3)
