extends VBoxContainer
## «State departments» window, in the exchange look (ui_style.gd): KPI tiles of the money side (GDP, corporate
## income, the departments' bill, the balance, the treasury, the share of taxes), the AI advisor (how it works and
## warnings), a card per department — how much of the norm it gets (a slider), what it costs, its quality and where
## it heads, its effects as chips (the antimonopoly service also shows its mood towards the government) — then what
## the services do to the country's companies and how other countries' services compare. Built once; refresh()
## only rewrites the numbers, so a slider being dragged is not rebuilt under the mouse.

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Charts := preload("res://mods/pax_corporations/src/market/charts.gd")
const Departments := preload("res://mods/pax_corporations/src/state/departments.gd")
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")
const UiStyle := preload("res://mods/pax_corporations/src/look/ui_style.gd")
const Advisor := preload("res://mods/pax_corporations/src/news/advisor.gd")
const GOLD := UiStyle.GOLD
const DIM := UiStyle.DIM
const UP := UiStyle.UP
const DOWN := UiStyle.DOWN
const Antitrust := preload("res://mods/pax_corporations/src/state/antitrust.gd")
const EFFECT_ORDER := ["corruption", "satisfaction", "exit", "издержки", "costs_industry", "производительность", "security_forces", "antitrust"]
## Effects where a rise is bad for the companies (the chip turns red when it goes up).
const BAD_UP := ["corruption", "exit", "издержки", "costs_industry", "security_forces"]

var mod: PaxMod
var game: PaxGame
var db: Data
var deps: Departments
var goods: Goods
var treasury_year: Callable      # func() -> float — what companies pay into the treasury a year
var antitrust: Antitrust         # the antimonopoly service's mood towards the government

var _kpi: Dictionary = {}        # name -> [value label, sub label]
var _advice: VBoxContainer
var _advice_said := ""
var _rows: Dictionary = {}       # key -> {slider, pct, cost, bar, q, effects}
var _mood: Label
var _mood_bar: ProgressBar
var _mood_effect: Label
var _corr: HFlowContainer
var _country: HFlowContainer
var _best: VBoxContainer
var _worst: VBoxContainer
var _avg: Label
var on_help: Callable            # func(tour) — the tutorials (tutorial.gd)
var _tut: Dictionary = {}


func setup(m: PaxMod, g: PaxGame, data: Data, d: Departments, gd: Goods) -> void:
	mod = m
	game = g
	db = data
	deps = d
	goods = gd
	name = "PaxCorporationsDepartments"
	theme = UiStyle.theme()
	set_meta(&"pax_corp_skin_skip", true)
	set_meta(&"pax_interface_skip_skin", true)   # «Pax Interface» does not reskin our window
	custom_minimum_size = Vector2(700, 520)
	add_theme_constant_override("separation", 8)
	# The money side as KPI tiles.
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 6)
	add_child(tiles)
	_tut["tiles"] = tiles
	for k in ["gdp", "income", "spend", "balance", "treasury", "budget"]:
		tiles.add_child(_tile(k))
	var help := Button.new()
	help.text = "?"
	help.tooltip_text = _t("tut_mini_tip")
	help.focus_mode = Control.FOCUS_NONE
	help.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	help.pressed.connect(func() -> void:
		if on_help.is_valid():
			on_help.call("departments"))
	tiles.add_child(help)
	var room := Control.new()   # room for the window frame's ✕ in the corner: «?» stood right under it
	room.custom_minimum_size = Vector2(44, 0)
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tiles.add_child(room)
	_advice = VBoxContainer.new()
	add_child(_advice)
	_tut["advice"] = _advice
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	# Department cards, two in a row.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	list.add_child(grid)
	var all: Dictionary = db.departments.get("departments", {})
	for key in all.keys():
		var card := _dept_card(str(key), all[key])
		grid.add_child(card)
		if not _tut.has("card"):
			_tut["card"] = card
			_tut["slider"] = (_rows[str(key)] as Dictionary)["slider"]
	# The country: corruption and what the services do to its companies.
	var cv := UiStyle.card(list, _t("dept_card_country"))
	_tut["country"] = cv.get_parent()
	_corr = UiStyle.flow(6)
	cv.add_child(_corr)
	_country = UiStyle.flow(6)
	cv.add_child(_country)
	# Other countries' services: the best and the worst.
	var mv := UiStyle.card(list, _t("dept_card_compare"))
	_avg = _label("", UiStyle.TEXT)
	mv.add_child(_avg)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	mv.add_child(cols)
	_best = VBoxContainer.new()
	_best.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(_best)
	_worst = VBoxContainer.new()
	_worst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(_worst)
	refresh()


func _draw() -> void:
	draw_rect(Rect2(Vector2(-8, -8), size + Vector2(16, 16)), UiStyle.BG)


## Sets the theme anew once in the game's window, so every control picks it up at once (not on its first hover).
func _retheme() -> void:
	theme = null
	theme = UiStyle.theme()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == NOTIFICATION_ENTER_TREE:
		_retheme.call_deferred()


func _tile(k: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 8, Vector4(10, 5, 10, 6)))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.tooltip_text = _t("dept_kpi_" + k + "_tip")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	v.add_child(UiStyle.caption(_t("dept_kpi_" + k)))
	var val := _label("—", UiStyle.TEXT)
	val.add_theme_font_size_override("font_size", 16)
	v.add_child(val)
	var sub := _label("", DIM)
	sub.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
	v.add_child(sub)
	_kpi[k] = [val, sub]
	return p


func _set_kpi(k: String, value: String, col: Color = UiStyle.TEXT, sub: String = "") -> void:
	var pair: Array = _kpi[k]
	(pair[0] as Label).text = value
	(pair[0] as Label).add_theme_color_override("font_color", col)
	(pair[1] as Label).text = sub
	(pair[1] as Label).visible = not sub.is_empty()


func _dept_card(key: String, d: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 8, Vector4(12, 8, 12, 10)))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	var title := _label("%s %s" % [str(d.get("icon", "")), db.text(d.get("name", key))], GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.tooltip_text = db.text(d.get("description", ""))
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(title)
	var pct := _label("", UiStyle.TEXT)
	top.add_child(pct)
	var cost := _label("", DIM)
	cost.add_theme_font_size_override("font_size", UiStyle.FS_SMALL + 1)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(cost)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 200.0
	slider.step = 5.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = _t("dept_slider_tip")
	v.add_child(slider)
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 8)
	v.add_child(mid)
	var bar := Charts.Bar.new()
	bar.good_high = true
	bar.custom_minimum_size = Vector2(120, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(bar)
	var q := _label("", DIM)
	q.add_theme_font_size_override("font_size", UiStyle.FS_SMALL + 1)
	mid.add_child(q)
	var effects := UiStyle.flow(4)
	v.add_child(effects)
	if key == "antitrust":
		# The service's mood towards the government: a gauge, the zone and what it does in that zone.
		var mrow := HBoxContainer.new()
		mrow.add_theme_constant_override("separation", 8)
		v.add_child(mrow)
		_mood_bar = ProgressBar.new()
		_mood_bar.show_percentage = false
		_mood_bar.max_value = 100.0
		_mood_bar.custom_minimum_size = Vector2(100, 8)
		_mood_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_mood_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mrow.add_child(_mood_bar)
		_tut["mood"] = mrow
		_mood = _label("", UiStyle.TEXT)
		_mood.add_theme_font_size_override("font_size", UiStyle.FS_SMALL + 1)
		_mood.mouse_filter = Control.MOUSE_FILTER_PASS
		mrow.add_child(_mood)
		_mood_effect = _label("", DIM)
		_mood_effect.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
		_mood_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_mood_effect.max_lines_visible = 2
		_mood_effect.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_mood_effect.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(_mood_effect)
	slider.value = float(deps.funding.get(key, 0.5)) * 100.0
	slider.value_changed.connect(func(x: float) -> void:
		deps.funding[key] = x / 100.0
		refresh())
	_rows[key] = {"slider": slider, "pct": pct, "cost": cost, "bar": bar, "q": q, "effects": effects}
	return box


func refresh() -> void:
	if db == null or deps == null:
		return
	var player := str(game.player_faction().get("name", ""))
	var g := deps.budget(game, goods, player)
	var gdp_year := deps.gdp(game, goods, player)
	var all: Dictionary = db.departments.get("departments", {})
	var total := 0.0
	var k_now := db.country_corruption(player)
	for key in _rows.keys():
		var r: Dictionary = _rows[key]
		var f := float(deps.funding.get(key, 0.0))
		var slider: HSlider = r["slider"]
		if not is_equal_approx(slider.value, f * 100.0):
			slider.set_value_no_signal(f * 100.0)
		var year := f * deps.norm(db, str(key), g)
		total += year
		var pct: Label = r["pct"]
		pct.text = _t("dept_pct") % roundi(f * 100.0)
		pct.add_theme_color_override("font_color", GOLD if f > 1.0 else (DOWN if f < 0.5 else UiStyle.TEXT))
		(r["cost"] as Label).text = _t("dept_cost") % db.money(year)
		var q := float(deps.quality.get(key, 50.0))
		var target := deps.target_quality(deps.effective(db, f, k_now), k_now)
		(r["bar"] as Charts.Bar).value = q
		(r["bar"] as Control).queue_redraw()
		(r["q"] as Label).text = _t("dept_quality") % [roundi(q), roundi(target)]
		(r["q"] as Label).add_theme_color_override("font_color", UP if target > q + 1.0 else (DOWN if target < q - 1.0 else DIM))
		_effect_chips(r["effects"] as HFlowContainer, all.get(key, {}), (q - 50.0) / 50.0)
	var base_k_now := db.country_corruption_base(player)
	var income := float(treasury_year.call()) if treasury_year.is_valid() else 0.0
	var money := float(game.resources(game.home_body()).get("money", 0.0))
	_set_kpi("gdp", db.money(gdp_year), UiStyle.TEXT, _t("a_year_short"))
	_set_kpi("income", db.money(income), UP)
	_set_kpi("spend", db.money(total), DOWN if total > income else UiStyle.TEXT)
	_set_kpi("balance", ("+" if income >= total else "−") + db.money(absf(income - total)), UiStyle.tone(income - total, 0.0))
	_set_kpi("treasury", db.money(money), GOLD)
	_set_kpi("budget", db.percent(total / maxf(g, 1e-6)), UiStyle.TEXT, _t("dept_kpi_budget_sub") % db.money(g))
	# The advisor: how it works, or what is wrong now (red).
	var stolen := deps.theft(db, base_k_now)
	var warn: PackedStringArray = []
	if deps.short:
		warn.append(_t("dept_short").trim_prefix("⚠ "))
	if stolen > 0.0005:
		warn.append(_t("dept_theft").trim_prefix("⚠ ") % _signed_pct(stolen))
	var say := _t("advisor_dept_warn") % " ".join(warn) if not warn.is_empty() else _t("dept_intro")
	if say != _advice_said:
		_advice_said = say
		for ch in _advice.get_children():
			ch.queue_free()
		var a := Advisor.new()
		a.setup(mod, "dept_warn" if not warn.is_empty() else "dept", say, not warn.is_empty())
		_advice.add_child(a)
	# The country.
	var base_k := db.country_corruption_base(player)
	for ch in _corr.get_children():
		ch.queue_free()
	var corr := UiStyle.pill(_t("dept_corr") % [db.percent(base_k), db.percent(k_now)], UiStyle.tone(base_k - k_now, 0.0005), UiStyle.FS)
	corr.tooltip_text = _t("dept_country") % [db.percent(base_k), db.percent(k_now), _effects_line(db.dept_effects.get(player, {}))]
	_corr.add_child(corr)
	_country_chips(db.dept_effects.get(player, {}))
	if _mood != null and antitrust != null and antitrust.mood >= 0.0:
		var zone := "bad" if antitrust.bad(db) else ("good" if antitrust.good(db) else "normal")
		var zc := DOWN if zone == "bad" else (UP if zone == "good" else GOLD)
		_mood.text = _t("am_mood") % [roundi(antitrust.mood), _t("am_zone_" + zone)]
		_mood.add_theme_color_override("font_color", zc)
		_mood.tooltip_text = _mood_why()
		_mood_bar.value = antitrust.mood
		_mood_bar.add_theme_stylebox_override("fill", UiStyle.box(zc, Color(0, 0, 0, 0), 4, Vector4.ZERO))
		_mood_effect.text = _t("am_effect_" + zone)
		_mood_effect.tooltip_text = _mood_effect.text
	elif _mood != null:
		# No mood yet (the service forms its opinion in the first weeks).
		_mood.text = _t("am_mood_unknown")
		_mood.add_theme_color_override("font_color", DIM)
		_mood_bar.value = 50.0
		_mood_bar.add_theme_stylebox_override("fill", UiStyle.box(Color(DIM, 0.4), Color(0, 0, 0, 0), 4, Vector4.ZERO))
		_mood_effect.text = _t("am_mood_unknown_tip")
	_compare(player)


## A department's effects at its current quality as chips: green when they help the companies, red when they hurt.
func _effect_chips(box: HFlowContainer, d: Dictionary, k: float) -> void:
	for ch in box.get_children():
		ch.queue_free()
	var eff: Dictionary = d.get("effects", {})
	for what in eff.keys():
		var v := float(eff[what]) * k
		box.add_child(UiStyle.pill(_t("dept_eff_" + str(what)) % _signed_pct(v), _good_tone(str(what), v)))


func _country_chips(eff: Dictionary) -> void:
	for ch in _country.get_children():
		ch.queue_free()
	var any := false
	for what in EFFECT_ORDER:
		if not eff.has(what):
			continue
		var v := float(eff[what])
		var delta := v if what in ["corruption", "satisfaction"] else v - 1.0
		if absf(delta) >= 0.001:
			_country.add_child(UiStyle.pill(_t("dept_eff_" + what) % _signed_pct(delta), _good_tone(what, delta)))
			any = true
	if not any:
		_country.add_child(UiStyle.pill(_t("dept_eff_none"), DIM))


func _good_tone(what: String, v: float) -> Color:
	if absf(v) < 0.0005:
		return DIM
	var good := v < 0.0 if what in BAD_UP else v > 0.0
	return UP if good else DOWN


## Why the antimonopoly service feels so (the tooltip of its mood).
func _mood_why() -> String:
	var why: PackedStringArray = []
	for p in antitrust.parts:
		var v := float(p[1])
		if str(p[0]) != "base" and absf(v) >= 0.5:
			why.append("%s %s%d" % [_t("am_part_" + str(p[0])), "+" if v >= 0.0 else "−", roundi(absf(v))])
	return ", ".join(why)


func _effects_line(eff: Dictionary) -> String:
	var parts: PackedStringArray = []
	for what in EFFECT_ORDER:
		if not eff.has(what):
			continue
		var v := float(eff[what])
		var delta := v if what in ["corruption", "satisfaction"] else v - 1.0
		if absf(delta) >= 0.001:
			parts.append(_t("dept_eff_" + what) % _signed_pct(delta))
	return ", ".join(parts) if not parts.is_empty() else _t("dept_eff_none")


func _signed_pct(x: float) -> String:
	return ("+" if x >= 0.0 else "−") + db._num(absf(x) * 100.0, 1) + "%"


## The other countries' services: the best and the worst five, each with a bar of its level.
func _compare(player: String) -> void:
	var rows: Array = []
	for country in deps.ai_quality.keys():
		rows.append([str(country), float(deps.ai_quality[country])])
	rows.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	_avg.text = _t("dept_avg") % [player, roundi(deps.average_quality())]
	for box in [_best, _worst]:
		for ch in (box as VBoxContainer).get_children():
			ch.queue_free()
	_best.add_child(UiStyle.caption(_t("dept_best"), UP))
	_worst.add_child(UiStyle.caption(_t("dept_worst"), DOWN))
	for r in rows.slice(0, 5):
		_best.add_child(_level_row(str(r[0]), float(r[1])))
	for r in rows.slice(maxi(0, rows.size() - 5)):
		_worst.add_child(_level_row(str(r[0]), float(r[1])))


func _level_row(country: String, q: float) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var n := _label(country, UiStyle.TEXT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	h.add_child(n)
	var bar := Charts.Bar.new()
	bar.good_high = true
	bar.value = q
	bar.custom_minimum_size = Vector2(80, 6)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	var v := _label(str(roundi(q)), DIM)
	v.custom_minimum_size = Vector2(26, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return h


## The parts of this window a tutorial outlines (tutorial.gd), by name.
func tut_target(part: String) -> Control:
	var c: Variant = _tut.get(part)
	return c as Control if is_instance_valid(c) else null


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
