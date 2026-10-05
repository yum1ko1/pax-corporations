extends VBoxContainer
## The «Corporations» window (section 18): company lists (my country / world top-100 / favourites) with
## sorting, a sector filter and stars; a click opens the dossier with five tabs and the head's block.
## The window only shows things — there are no action buttons: the player acts with words.

const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")   # Main's methods, 0.24 names
const StaffWhy := preload("res://mods/pax_corporations/src/companies/staff_why.gd")
const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Dashboard := preload("res://mods/pax_corporations/src/window/dashboard.gd")
const Charts := preload("res://mods/pax_corporations/src/market/charts.gd")
const Events := preload("res://mods/pax_corporations/src/news/events.gd")
const Digest := preload("res://mods/pax_corporations/src/news/digest.gd")
const Politics := preload("res://mods/pax_corporations/src/state/politics.gd")
const TABS := ["country", "world", "favorites", "markets", "arena", "caps", "tech", "summary", "letters"]
const SORTS := ["index", "cap", "employees", "revenue"]
const COLUMNS := [["cap", 82], ["revenue", 82], ["employees", 78], ["index", 50], ["change", 58]]
const DOSSIER_TABS := ["overview", "shares", "debt", "owners", "assets", "chronicle"]
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")
const Rivals := preload("res://mods/pax_corporations/src/companies/rivals.gd")
const Letters := preload("res://mods/pax_corporations/src/news/letters.gd")
const Lifecycle := preload("res://mods/pax_corporations/src/companies/lifecycle.gd")
const Frames := preload("res://mods/pax_corporations/src/companies/frames.gd")
const DevTree := preload("res://mods/pax_corporations/src/tech/tree.gd")
const Orders := preload("res://mods/pax_corporations/src/state/orders.gd")
const Arena := preload("res://mods/pax_corporations/src/world/arena.gd")
const Influence := preload("res://mods/pax_corporations/src/state/influence.gd")
const Investments := preload("res://mods/pax_corporations/src/market/investments.gd")
const Conditions := preload("res://mods/pax_corporations/src/state/conditions.gd")
const Capabilities := preload("res://mods/pax_corporations/src/state/capabilities.gd")
const PIE_TOP := 7               # companies named in a market pie; the rest are summed
const STATUS_ROWS := [["trust", true], ["satisfaction", true], ["popularity", true], ["независимость", true], ["stability", true],
	["monopolism", false], ["corruption", false], ["экология", true]]
const PENDING_ROWS := []
const LIST_PAGE := 60            # rows built at once; «show more» adds a page (hundreds of rows are slow to build)
const CHRONICLE_ROWS := 120
const BUY_STEPS := [0.01, 0.05, 0.1]
const SELL_STEPS := [0.01, 0.05]
const UiStyle := preload("res://mods/pax_corporations/src/look/ui_style.gd")
const Advisor := preload("res://mods/pax_corporations/src/news/advisor.gd")
const GOLD := UiStyle.GOLD
const DIM := UiStyle.DIM
const UP := UiStyle.UP
const DOWN := UiStyle.DOWN

var mod: PaxMod
var game: PaxGame
var db: Data
var panel: Control
var on_show_on_map: Callable     # func(company_id: String)
var on_show_point: Callable      # func(company_id: String, point: Dictionary)
var events: Events
var digest: Digest
var politics: Politics
var treasury_year: Callable      # func() -> float, млн $ a year into the player's treasury
var goods: Goods
var rivals: Rivals
var letters: Letters          # the «Письма» tab (letters.gd)
var lifecycle: Lifecycle      # bankruptcy chances, former heads (lifecycle.gd)
var orders: Orders            # the player's running operations (orders.gd)
var tree: DevTree                # development trees of industries (tree.gd)
var arena: Arena              # prestige, dependencies, tariffs, conflicts (arena.gd)
var influence: Influence      # companies and elections, scandals (influence.gd)
var investments: Investments  # foreign investors (investments.gd)
var conditions: Conditions    # the country's conditions where the company works (conditions.gd)
var capabilities: Capabilities   # what the country can do thanks to its companies (capabilities.gd)
var techlevel: Object            # technology level of research companies (techlevel.gd)
var _mk_goods := ""              # the «Markets» tab: which goods and where ("" — the world)
var _mk_scope := "*"
var treasury_money: Callable   # func() -> float, млн $ in the player's treasury now
var on_trade: Callable           # func(company_id, fraction, buy) -> String — the state buys/sells shares at once
var on_found: Callable           # func(spec) -> String — found a company ("" or an error)
var on_close: Callable           # func() — close the window (main.gd)
var on_found_preview: Callable   # func(goods, capital, country) -> Dictionary — what the analysts expect
var on_pick_place: Callable      # func(done: Callable(place)) — pick the headquarters on the map
var founding_info: Callable      # func() -> Dictionary — state or person, money, default place
var _found: Dictionary = {}      # the founding dialog's state: {dlg, name, goods, desc, capital, place, preview, error, ask}
var on_ask_ai: Callable         # func(text) -> bool — hands a question to the game's AI assistant
var ai_available: Callable       # func() -> bool — the game has an assistant to ask
var on_quote: Callable          # func(company_id, fraction, buy) -> Dictionary — what that trade would be
var on_write_head: Callable     # func(company_id) — talk to the company's head (a game contact)
var on_tutorial: Callable       # func(tour) — start a tutorial (tutorial.gd): «main», «list», «dossier»
var _tut: Dictionary = {}        # name -> Control: the parts the tutorials outline
var on_hud_skin: Callable       # func(on) — the game's interface in the mod's look (hud_skin.gd)
var on_buildings: Callable      # func(on) — 3D buildings on the globe (buildings.gd)
var found_button: Button
var tutorial_button: Button
var _list_limit := LIST_PAGE
var favorites: Dictionary = {}

var _tab := "country"
var _sort := "index"
var _sector := ""
var _current := ""
var _dossier_tab := 0

var _list_view: VBoxContainer
var _tab_buttons: Dictionary = {}
var _tools: HBoxContainer        # the list's filters (sort, industry) — a second row, only for company lists
var _intro: VBoxContainer        # the advisor's words above a tab
var _sort_btn: OptionButton
var _sector_btn: OptionButton
var _hint: Control
var _list: VBoxContainer
var _news_box: VBoxContainer
var _dossier_view: VBoxContainer
var narrator: Object             # narrator.gd — the newspaper candidates for the home's news (main.gd)
var scope := "world"             # the home and its screens: "world" or "country" (the player's country only)
var chart_mode := "cap":         # the home's market chart: cap | state | share (kept between games)
	set(v):
		chart_mode = v
		if mod != null:
			mod.set_setting("dash_chart", v)
var _screen := "home"            # home | list (lists and the dossier) | market | news | deals
var _from := "top"               # the home tile the current screen was opened from (it folds back into it)
var _home: Dashboard
var _detail: VBoxContainer
var _expander: PanelContainer
var _expander_title: Label
var _animating := false
const SCREENS := {"top": "list", "market": "market", "news": "news", "deals": "deals", "zones": "zones"}
var zone_sel := ""               # the zone shown on the «Zones» screen


func setup(m: PaxMod, g: PaxGame, data: Data) -> void:
	mod = m
	game = g
	db = data
	name = "PaxCorporationsWindow"
	theme = UiStyle.theme()
	set_meta(&"pax_corp_skin_skip", true)   # our own look — the game skin (hud_skin.gd) leaves it
	set_meta(&"pax_interface_skip_skin", true)   # «Pax Interface» does not reskin our window
	custom_minimum_size = Vector2(780, 520)
	add_theme_constant_override("separation", 6)
	_tab = "country" if not _country_companies(_player_country()).is_empty() else "world"
	scope = str(mod.get_setting("dash_scope", "world"))
	chart_mode = str(mod.get_setting("dash_chart", "cap"))
	_home = Dashboard.new()
	_home.setup(self, db)
	add_child(_home)
	_detail = VBoxContainer.new()
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 10)
	_detail.visible = false
	add_child(_detail)
	_build_list_view()
	_dossier_view = VBoxContainer.new()
	_dossier_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dossier_view.visible = false
	add_child(_dossier_view)
	refresh()


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


## The exchange's dark background under the whole window (a bit past its edges, over the game's own panel).
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
		_retheme.call_deferred()   # the game's window was themed after us — take ours back at once


## The advisor says something above the current tab (advisor.gd); where — the place his fold is kept under.
func _advise(where: String, text: String, bad: bool = false, extra: Control = null) -> void:
	var a := Advisor.new()
	a.setup(mod, where, text, bad, extra)
	_intro.add_child(a)


func _player_country() -> String:
	return str(game.player_faction().get("name", ""))


func _country_companies(country: String) -> Array:
	return db.companies.filter(func(c): return str(c.get("_country", "")) == country)


# ---------- opening ----------

func open_company(cid: String) -> void:
	_screen = "list"
	_current = cid
	_dossier_tab = 0
	show_window()
	refresh()


## The tutorial opens a list tab or a dossier tab (tutorial.gd).
func select_tab(tab: String) -> void:
	_screen = "list"
	_current = ""
	_tab = tab
	_list_limit = LIST_PAGE
	refresh()


## The parts of this window a tutorial outlines (tutorial.gd), by name.
func tut_target(part: String) -> Control:
	var c: Variant = _tut.get(part)
	return c as Control if is_instance_valid(c) else null


func select_dossier_tab(index: int) -> void:
	_dossier_tab = index
	refresh()


func tab_button(tab: String) -> Button:
	return _tab_buttons.get(tab) as Button


func show_window() -> void:
	if not is_instance_valid(panel) or panel.is_visible_in_tree():
		return
	if GameApi.has(game.main, "_переключить_окно"):
		GameApi.call_main(game.main, "_переключить_окно", [panel])
	if not panel.is_visible_in_tree():
		panel.show()


func refresh() -> void:
	_home.visible = _screen == "home"
	_detail.visible = _screen in ["market", "news", "deals", "zones"]
	if _screen == "home" or _detail.visible:
		_list_view.visible = false
		_dossier_view.visible = false
		if _screen == "home":
			_home.build()
		else:
			for ch in _detail.get_children():
				_detail.remove_child(ch)
				ch.queue_free()
			_home.build_detail(_screen, _detail)
		return
	var dossier := not _current.is_empty() and not db.company(_current).is_empty()
	_list_view.visible = not dossier
	_dossier_view.visible = dossier
	if dossier:
		_fill_dossier()
	else:
		_fill_list()


# ---------- list ----------

func _build_list_view() -> void:
	_list_view = VBoxContainer.new()
	_list_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_view.add_theme_constant_override("separation", 6)
	add_child(_list_view)

	if not bool(mod.get_setting("hint_seen", false)):
		_hint = _hint_panel()
		_list_view.add_child(_hint)

	_news_box = VBoxContainer.new()
	_news_box.add_theme_constant_override("separation", 2)
	_list_view.add_child(_news_box)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	_list_view.add_child(bar)
	for t in TABS:
		var b := Button.new()
		b.toggle_mode = true
		UiStyle.as_tab(b)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			_tab = t
			_list_limit = LIST_PAGE
			refresh())
		bar.add_child(b)
		_tab_buttons[t] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var found := Button.new()
	found.text = "＋ " + _t("found_button")
	UiStyle.as_primary(found)
	found.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	found.tooltip_text = _t("found_button_tip")
	found.focus_mode = Control.FOCUS_NONE
	found.pressed.connect(func() -> void: open_founding())
	bar.add_child(found)
	found_button = found
	var help := Button.new()
	help.text = "?"
	help.tooltip_text = _t("tut_mini_tip")
	help.focus_mode = Control.FOCUS_NONE
	help.pressed.connect(func() -> void:
		if on_tutorial.is_valid():
			on_tutorial.call("list"))
	bar.add_child(help)
	tutorial_button = help
	var big := Button.new()
	big.text = "🎓"
	big.tooltip_text = _t("tut_big_tip")
	big.focus_mode = Control.FOCUS_NONE
	big.pressed.connect(func() -> void:
		if on_tutorial.is_valid():
			on_tutorial.call("main"))
	bar.add_child(big)
	# The tutorials on the left, far from ✕ — not pressed by chance when closing the window.
	bar.move_child(help, 0)
	bar.move_child(big, 1)
	_tut["big"] = big
	_tut["tabs"] = bar
	_tut["found"] = found
	# Settings of the status frames (frames.gd): glow and animation, glow only, plain; on the map or not.
	var gear := MenuButton.new()
	gear.text = "⚙"
	gear.tooltip_text = _t("frame_settings_tip")
	gear.flat = false
	_tut["gear"] = gear
	var pm := gear.get_popup()
	pm.add_radio_check_item(_t("frame_fx_2"), 2)
	pm.add_radio_check_item(_t("frame_fx_1"), 1)
	pm.add_radio_check_item(_t("frame_fx_0"), 0)
	pm.add_separator()
	pm.add_check_item(_t("frame_on_map"), 10)
	pm.add_separator()
	pm.add_check_item(_t("hud_skin_item"), 20)
	pm.add_check_item(_t("buildings_item"), 30)
	pm.add_check_item(_t("fullscreen_item"), 40)
	var sync := func() -> void:
		for i in 3:
			pm.set_item_checked(i, pm.get_item_id(i) == Frames.fx)
		pm.set_item_checked(pm.get_item_index(10), Frames.on_map)
		pm.set_item_checked(pm.get_item_index(20), bool(mod.get_setting("hud_skin", true)))
		pm.set_item_checked(pm.get_item_index(30), bool(mod.get_setting("buildings_3d", false)))
		pm.set_item_checked(pm.get_item_index(40), bool(mod.get_setting("fullscreen_window", true)))
	sync.call()
	pm.id_pressed.connect(func(id: int) -> void:
		if id == 40:
			mod.set_setting("fullscreen_window", not bool(mod.get_setting("fullscreen_window", true)))
			sync.call()
			return
		if id == 30:
			if on_buildings.is_valid():
				on_buildings.call(not bool(mod.get_setting("buildings_3d", false)))
			sync.call()
			return
		if id == 20:
			if on_hud_skin.is_valid():
				on_hud_skin.call(not bool(mod.get_setting("hud_skin", true)))
			sync.call()
			return
		if id == 10:
			Frames.on_map = not Frames.on_map
			mod.set_setting("frames_on_map", Frames.on_map)
		else:
			Frames.fx = id
			mod.set_setting("frames_fx", id)
		sync.call()
		db.version += 1   # the map redraws with the new look
		refresh())
	bar.add_child(gear)
	var close := Button.new()   # closes the window (the full-screen window has no game frame around it)
	close.text = "✕"
	close.tooltip_text = _t("close_window_tip")
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(34, 0)
	close.pressed.connect(func() -> void: close_screen())
	bar.add_child(close)
	_tut["close"] = close

	var line := ColorRect.new()   # the thin line under the tabs
	line.color = UiStyle.LINE
	line.custom_minimum_size = Vector2(0, 1)
	_list_view.add_child(line)
	_tools = HBoxContainer.new()
	_tools.add_theme_constant_override("separation", 6)
	_list_view.add_child(_tools)
	_tut["tools"] = _tools
	_tut["strip"] = _news_box
	_sort_btn = OptionButton.new()
	_sort_btn.focus_mode = Control.FOCUS_NONE
	for s in SORTS:
		_sort_btn.add_item(_t("sort_" + s))
	_sort_btn.item_selected.connect(func(i: int) -> void:
		_sort = SORTS[i]
		refresh())
	_tools.add_child(_sort_btn)

	_sector_btn = OptionButton.new()
	_sector_btn.focus_mode = Control.FOCUS_NONE
	_sector_btn.add_item(_t("all_sectors"))
	var keys: Array = db.sectors.keys()
	for k in keys:
		_sector_btn.add_item(db.sector_name(str(k)))
	_sector_btn.item_selected.connect(func(i: int) -> void:
		_sector = "" if i == 0 else str(keys[i - 1])
		refresh())
	_tools.add_child(_sector_btn)
	_intro = VBoxContainer.new()
	_list_view.add_child(_intro)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 380)
	_list_view.add_child(scroll)
	_list = VBoxContainer.new()
	_tut["table"] = _list
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)


func _hint_panel() -> Control:
	var x := Button.new()
	x.text = _t("advisor_got_it")
	x.focus_mode = Control.FOCUS_NONE
	x.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var a := Advisor.new()
	a.setup(mod, "hint", _t("hint"), false, x)
	x.pressed.connect(func() -> void:
		mod.set_setting("hint_seen", true)
		a.queue_free())
	return a


func _visible_companies() -> Array:
	var items: Array
	match _tab:
		"country":
			items = _country_companies(_player_country())
		"favorites":
			items = db.companies.filter(func(c): return favorites.has(str(c["id"])) or favorites.has("страна:" + str(c.get("_country", ""))))
		_:
			items = db.companies.duplicate()
	if not _sector.is_empty():
		items = items.filter(func(c): return str(c.get("sector", "")) == _sector)
	match _sort:
		"cap":
			items.sort_custom(func(a, b): return db.cap(a) > db.cap(b))
		"employees":
			items.sort_custom(func(a, b): return db.staff(a) > db.staff(b))
		"revenue":
			items.sort_custom(func(a, b): return db.fund(a, "выручка") > db.fund(b, "выручка"))
		_:
			items.sort_custom(func(a, b): return float(a.get("_index", 0.0)) > float(b.get("_index", 0.0)))
	if _tab == "world":
		items = items.slice(0, 100)
	return items


## Above the list: the world crisis (if any), «Market news» — rising and falling sectors (20.5),
## and what the country's companies pay into the player's treasury.
func _fill_news() -> void:
	for ch in _news_box.get_children():
		ch.queue_free()
	if events == null:
		return
	var stage := int(events.crisis.get("stage", 0))
	if stage > 0:
		var p := PanelContainer.new()
		var cc := DOWN if stage < 5 else UP
		p.add_theme_stylebox_override("panel", UiStyle.box(Color(cc, 0.1), Color(cc, 0.6), 6, Vector4(10, 5, 10, 5)))
		var l := _label("⚠ " + _t("crisis_banner_%d" % stage), cc)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.add_child(l)
		_news_box.add_child(p)
	if _tab == "summary":
		return
	# «Market news» follows the tab: my country — its sectors under its own situation and its companies;
	# the world — world sector trends and the world top; favourites — the favourites.
	var country := _player_country() if _tab == "country" else ""
	var title := _t("market_news_country") % country if _tab == "country" else _t("market_news_" + _tab)
	var mn := events.market_news(country) if _tab != "favorites" else {"up": [], "down": []}
	var up: PackedStringArray = []
	for k in mn["up"]:
		up.append(db.sector_name(str(k)))
	var down: PackedStringArray = []
	for k in mn["down"]:
		down.append(db.sector_name(str(k)))
	# One strip, like an exchange ticker: the title, sectors up/down as pills, the movers, the treasury.
	var h := UiStyle.flow(6)
	var cap := UiStyle.caption(title, GOLD)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(cap)
	for s in up:
		h.add_child(UiStyle.pill("▲ " + s, UP))
	for s in down:
		h.add_child(UiStyle.pill("▼ " + s, DOWN))
	if up.is_empty() and down.is_empty():
		h.add_child(UiStyle.pill(_t("sectors_calm"), DIM))
	for mv in _movers():
		var x := float(mv[1])
		var cid := str((mv[0] as Dictionary)["id"])
		var b := _chip("%s  %s" % [db.name_of(mv[0]), db.percent(x, true)], UP if x > 0.0 else DOWN, func() -> void: open_company(cid))
		b.tooltip_text = _t("movers") + " " + _t("change_4w")
		h.add_child(b)
	if treasury_year.is_valid() and _tab == "country":
		var year := float(treasury_year.call())
		if year > 0.0:
			var tp := UiStyle.pill("◆ " + _t("treasury_short") % db.money(year), GOLD)
			tp.tooltip_text = _t("treasury_line") % [_player_country(), db.money(year)] + "\n" + _t("treasury_tip")
			h.add_child(tp)
	_news_box.add_child(h)


var _summary_index := -1   # which report of digest.reports is shown; −1 — the latest


## The «Summary» tab: what mattered among the player's and favourite companies over one time skip.
func _fill_summary() -> void:
	if digest != null:
		digest.unread = false   # seen — the badge on the «Corporations» button goes (badges.gd)
	if digest == null or digest.reports.is_empty():
		_advise("summary", _t("summary_empty"))
		return
	var reps: Array = digest.reports
	var idx := reps.size() - 1 if _summary_index < 0 or _summary_index >= reps.size() else _summary_index
	var rep: Dictionary = reps[idx]

	var pick := OptionButton.new()
	pick.focus_mode = Control.FOCUS_NONE
	for i in range(reps.size() - 1, -1, -1):
		var r: Dictionary = reps[i]
		pick.add_item(_t("summary_period") % [_date_of(int(r.get("from_day", 0))), _date_of(int(r.get("to_day", 0)))], i)
	pick.select(reps.size() - 1 - idx)
	pick.item_selected.connect(func(i: int) -> void:
		_summary_index = pick.get_item_id(i)
		refresh())
	_list.add_child(pick)

	var money := float(rep.get("treasury", 0.0))
	if money > 0.0:
		_list.add_child(_label(_t("summary_treasury") % [_player_country(), db.money(money)], GOLD))

	var leaders: Array = rep.get("лидеры", [])
	if not leaders.is_empty():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.add_child(_label(_t("summary_leaders"), DIM))
		var shown: Array = leaders.slice(0, 3)
		for mv in leaders.slice(maxi(3, leaders.size() - 3), leaders.size()):
			if not shown.has(mv):
				shown.append(mv)
		for mv in shown:
			var c := db.company(str(mv["id"]))
			if c.is_empty():
				continue
			var x := float(mv["change"])
			var cid := str(mv["id"])
			h.add_child(_link("%s %s" % [db.name_of(c), db.percent(x, true)], UP if x > 0.0 else (DOWN if x < 0.0 else DIM),
				func() -> void: open_company(cid)))
		_list.add_child(h)

	_list.add_child(HSeparator.new())
	var lines: Array = rep.get("rows", [])
	if lines.is_empty():
		_list.add_child(_label(_t("summary_quiet"), DIM))
	for line in lines:
		var ld: Dictionary = line
		var c := db.company(str(ld.get("id", "")))
		var entry: Dictionary = ld.get("entry", {})
		var tone := str(ld.get("tone", "neutral"))
		var col := UP if tone == "good" else (DOWN if tone == "bad" else Color(1, 1, 1, 1))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		var when := _label(_date_of(int(entry.get("день", 0))), DIM)
		when.custom_minimum_size = Vector2(86, 0)
		row.add_child(when)
		if c.is_empty():
			row.add_child(_label(tr_market(), GOLD))
		else:
			var cid := str(c["id"])
			row.add_child(_link(db.name_of(c), GOLD, func() -> void: open_company(cid)))
		var text := _label(chron_text(c, entry), col)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)


## The «Арена» tab (arena.gd): the countries' prestige and what it does, who depends on whom, tariffs and sanctions,
## the latest conflicts. Orders change it: «пошлины 30% на сталь из Китая», «санкции против X», «украсть технологии у X».
func _fill_arena() -> void:
	if arena == null or arena.prestige.is_empty():
		_advise("arena", _t("arena_empty"))
		return
	var me := _player_country()
	var p := float(arena.prestige.get(me, 0.0))
	var p0 := float(arena.prestige0.get(me, p))
	_advise("arena", _t("arena_effects") % [db.percent(float(db.rate_shift.get(me, 0.0)), true), ("+" if p >= p0 else "−") + db._num(absf(p - p0) / 10.0, 1),
		db.money(arena.duties_year())] + "\n" + _t("arena_hint"))
	# The exchange's KPI tiles: prestige, place, change since the start.
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	tiles.add_child(UiStyle.kpi(_t("arena_kpi_prestige") % me, str(roundi(p)), GOLD))
	tiles.add_child(UiStyle.kpi(_t("arena_kpi_place"), "%d / %d" % [arena.place_of(me), arena.prestige.size()]))
	tiles.add_child(UiStyle.kpi(_t("arena_kpi_change"), ("+" if p >= p0 else "−") + str(roundi(absf(p - p0))), UiStyle.tone(p - p0, 0.5)))
	tiles.add_child(UiStyle.kpi(_t("arena_kpi_duties"), db.money(arena.duties_year())))
	_list.add_child(tiles)
	# The table of prestige: the top ten and the player.
	_list.add_child(_label(_t("arena_top"), GOLD))
	var rows: Array = arena.prestige.keys()
	rows.sort_custom(func(a, b): return float(arena.prestige[a]) > float(arena.prestige[b]))
	for i in rows.size():
		if i >= 10 and str(rows[i]) != me:
			continue
		var line := _label("%d. %s — %d" % [i + 1, str(rows[i]), roundi(float(arena.prestige[rows[i]]))], GOLD if str(rows[i]) == me else Color(1, 1, 1, 0.9))
		_list.add_child(line)
	_list.add_child(HSeparator.new())
	_list.add_child(_label(_t("arena_deps_in") % me, GOLD))
	if arena.deps_in.is_empty():
		_list.add_child(_label(_t("arena_none"), DIM))
	for d in arena.deps_in:
		var c := db.company(str(d["id"]))
		if c.is_empty():
			continue
		var cid := str(c["id"])
		_list.add_child(_link(_t("arena_dep_line") % [me, db.percent(float(d["доля"])), goods.goods_name(db, c), db.name_of(c), str(c.get("_country", ""))],
			Color(1, 1, 1, 0.9), func() -> void: open_company(cid)))
	_list.add_child(_label(_t("arena_deps_out") % me, GOLD))
	if arena.deps_out.is_empty():
		_list.add_child(_label(_t("arena_none"), DIM))
	for d in arena.deps_out:
		var c := db.company(str(d["id"]))
		if c.is_empty():
			continue
		var cid := str(c["id"])
		_list.add_child(_link(_t("arena_dep_line") % [str(d["country"]), db.percent(float(d["доля"])), goods.goods_name(db, c), db.name_of(c), me],
			Color(1, 1, 1, 0.9), func() -> void: open_company(cid)))
	_list.add_child(HSeparator.new())
	_list.add_child(_label(_t("arena_tariffs"), GOLD))
	if arena.tariffs.is_empty() and arena.sanctions.is_empty():
		_list.add_child(_label(_t("arena_none"), DIM))
	for t in arena.tariffs:
		var td: Dictionary = t
		var mine := str(td["from_value"]) == me
		var key := "arena_tariff_" + ("mine_" if mine else "theirs_") + str(td.get("вид", "tariffs"))
		_list.add_child(_label(_t(key) % [str(td["on_value"]) if mine else str(td["from_value"]), arena._goods_name(str(td["goods_key"])), db.percent(float(td["rate"]))],
			UP if mine else DOWN))
	for s in arena.sanctions:
		var c := db.company(str((s as Dictionary)["id"]))
		if not c.is_empty():
			_list.add_child(_label(_t("arena_sanction_line") % [db.name_of(c), str(c.get("_country", ""))], UP))
	if not arena.ops.is_empty():
		for op in arena.ops:
			var c := db.company(str((op as Dictionary)["id"]))
			_list.add_child(_label(_t("arena_spy_running") % [db.name_of(c) if not c.is_empty() else "", str(maxi(0, (int(op["until_day"]) - game.day()) / 7))], DIM))
	_fill_influence(me)
	_list.add_child(HSeparator.new())
	_list.add_child(_label(_t("arena_conflicts"), GOLD))
	if arena.conflicts.is_empty():
		_list.add_child(_label(_t("arena_none"), DIM))
	for i in range(arena.conflicts.size() - 1, maxi(-1, arena.conflicts.size() - 11), -1):
		var cf: Dictionary = arena.conflicts[i]
		var text := _t(str(cf["ключ"]))
		var args: Array = cf.get("args", [])
		var n := text.count("%s")
		var a := args.slice(0, n)
		while a.size() < n:
			a.append("")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_label(_date_of(int(cf.get("день", 0))), DIM))
		var l := _label(text % a if n > 0 else text, Color(1, 1, 1, 0.9))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		_list.add_child(row)


## «Техуровень» (techlevel.gd): three world ratings by T — AI companies, science corporations, space companies.
func _fill_tech() -> void:
	if techlevel == null:
		return
	_advise("tech", _t("tl_intro"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_list.add_child(row)
	for kind in ["ии", "наука", "космос"]:
		var card := UiStyle.card(row, db.sector_name(str(kind)))
		var list: Array = techlevel.call("members", str(kind))
		list.sort_custom(func(a, b): return float(techlevel.call("level", a)) > float(techlevel.call("level", b)))
		var f := float(techlevel.call("frontier", str(kind)))
		var mine := _player_country()
		for i in list.size():
			var c: Dictionary = list[i]
			var cid := str(c["id"])
			var r := HBoxContainer.new()
			r.add_theme_constant_override("separation", 6)
			card.add_child(r)
			var place := _label("%d" % (i + 1), DIM)
			place.custom_minimum_size = Vector2(18, 0)
			r.add_child(place)
			var name_b := _link(db.name_of(c), GOLD if str(c.get("_country", "")) == mine else UiStyle.TEXT, func() -> void: open_company(cid))
			name_b.clip_text = true
			name_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_b.tooltip_text = str(c.get("_country", ""))
			r.add_child(name_b)
			var bar := Charts.Bar.new()
			bar.value = 100.0 * float(techlevel.call("level", c)) / maxf(f, 1e-6)
			bar.custom_minimum_size = Vector2(60, 6)
			r.add_child(bar)
			var step := str(techlevel.call("step_key", c))
			r.add_child(UiStyle.pill(_t("tl_step_" + step), GOLD if step == "leader" else (UP if step == "frontier" else (UiStyle.BLUE if step == "catching" else DOWN))))


## «Возможности страны» (capabilities.gd): what the country can do thanks to its companies; for a closed one —
## what it lacks and who would sell it.
func _fill_caps() -> void:
	if capabilities == null:
		return
	var me := _player_country()
	var rows: Array = []
	for c in capabilities.all():
		var id := str((c as Dictionary)["id"])
		rows.append([id, capabilities.status(me, id)])
	rows.sort_custom(func(a, b): return int(bool((a[1] as Dictionary)["has_flag"])) > int(bool((b[1] as Dictionary)["has_flag"])))
	var open_n := rows.filter(func(r): return bool((r[1] as Dictionary)["has_flag"])).size()
	_advise("caps", _t("caps_intro") % [open_n, rows.size()])
	for r in rows:
		var id := str(r[0])
		var st: Dictionary = r[1]
		var how := str(st["как"])
		var col := UP if bool(st["has_flag"]) else (GOLD if how == "осваивается" else DOWN)
		var card := UiStyle.card(_list, "", Color(col, 0.45))
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		card.add_child(top)
		var name_l := _label(capabilities.name_of(id), UiStyle.TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_l)
		var tag := _t("caps_" + (how if not how.is_empty() else "closed"))
		if how == "осваивается":
			tag = tag % int(st["weeks"])
		elif how in ["куплена"]:
			tag = tag % str(st.get("from_value", ""))
		top.add_child(UiStyle.pill(tag, col))
		if not bool(st["has_flag"]) and how != "осваивается":
			var need := UiStyle.flow(4)
			for n in st["what_missing"]:
				need.add_child(UiStyle.pill(("✓ " if bool((n as Array)[1]) else "✗ ") + str((n as Array)[0]), UP if bool((n as Array)[1]) else DIM))
			card.add_child(need)
			var sell: Array = st["sellers"]
			if not sell.is_empty():
				var s := _label(_t("caps_sellers") % [", ".join(PackedStringArray(sell)), capabilities.name_of(id).to_lower(), sell[0]], DIM)
				s.add_theme_font_size_override("font_size", UiStyle.FS_SMALL + 1)
				s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				card.add_child(s)


## Companies and the player's elections (20.17) and the latest corruption scandals (20.9) — part of the «Арена» tab.
func _fill_influence(me: String) -> void:
	if influence == null:
		return
	_list.add_child(HSeparator.new())
	_list.add_child(_label(_t("infl_title") % me, GOLD))
	var n := influence.national
	var p: Dictionary = influence.parts
	var line := _label(_t("infl_national") % [("+" if n >= 0.0 else "−") + db._num(absf(n), 1),
		_pts(float(p.get("workers", 0.0))), _pts(float(p.get("sponsorship", 0.0))), _pts(float(p.get("media", 0.0))),
		db.percent(float(p.get("business", 0.0)), true)], UP if n > 0.05 else (DOWN if n < -0.05 else Color(1, 1, 1, 0.9)))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_size_override("font_size", UiStyle.FS_SMALL + 1)
	_list.add_child(line)
	var rows: Array = []
	for pid in influence.provinces.keys():
		rows.append([int(pid), float(influence.provinces[pid])])
	rows.sort_custom(func(a, b): return absf(float(a[1])) > absf(float(b[1])))
	var shown: PackedStringArray = []
	for r in rows.slice(0, 6):
		if absf(float(r[1])) >= 0.05:
			shown.append("%s %s" % [db.province_name(int(r[0])), _pts(float(r[1]))])
	if not shown.is_empty():
		var pl := _label(_t("infl_provinces") % ", ".join(shown), DIM)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(pl)
	var f := _label(_t("infl_forces") % (", ".join(PackedStringArray(influence.forces_found)) if not influence.forces_found.is_empty() else _t("infl_no_forces")), DIM)
	f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(f)
	_list.add_child(_label(_t("infl_scandals"), GOLD))
	# Only the scandals of the player's country belong here (the world's are in the news).
	var own_scandals: Array = influence.scandals.filter(func(s): return str((s as Dictionary).get("country", "")) == me)
	if own_scandals.is_empty():
		_list.add_child(_label(_t("arena_none"), DIM))
	for i in range(own_scandals.size() - 1, maxi(-1, own_scandals.size() - 7), -1):
		var s: Dictionary = own_scandals[i]
		var c := db.company(str(s["id"]))
		if c.is_empty():
			continue
		var cid := str(c["id"])
		_list.add_child(_link("%s — %s (%s), %s" % [_date_of(int(s["день"])), db.name_of(c), str(s["country"]), _t("infl_fine") % db.money(float(s["fine"]))],
			Color(1, 1, 1, 0.9), func() -> void: open_company(cid)))


func _pts(x: float) -> String:
	return ("+" if x >= 0.0 else "−") + db._num(absf(x), 1)


## The «Письма» tab: letters of company heads and the antimonopoly service, newest first; offers can be
## accepted or declined until their deadline (letters.gd). Opening the tab marks everything as read.
func _fill_letters() -> void:
	# The player's orders still running (orders.gd): what, against whom, how many weeks left.
	if orders != null and not orders.ops.is_empty():
		var box := VBoxContainer.new()
		box.add_child(_label(_t("ord_running"), GOLD))
		for line in orders.operations_text():
			box.add_child(_label("  • " + line, Color(1, 1, 1, 0.9)))
		_list.add_child(box)
		_list.add_child(HSeparator.new())
	if letters == null or letters.letters.is_empty():
		_advise("letters", _t("letters_empty"))
		return
	_advise("letters", _t("letters_intro"))
	for i in range(letters.letters.size() - 1, -1, -1):
		_list.add_child(_letter_card(letters.letters[i]))
	if letters.unread() > 0:
		letters.mark_read()
		(_tab_buttons["letters"] as Button).text = _t("tab_letters")


func _letter_card(l: Dictionary) -> Control:
	var unread := not bool(l.get("read_flag", false))
	var pending := str(l.get("status", "")) == "ждёт"
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(Color(GOLD, 0.07) if pending else UiStyle.PANEL, GOLD if unread else UiStyle.LINE, 8, Vector4(12, 8, 12, 8)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	top.add_child(_label(_date_of(int(l.get("день", 0))), DIM))
	var cid := str(l.get("from_value", ""))
	var company := str(l.get("company", ""))
	if not cid.is_empty() and not db.company(cid).is_empty():
		top.add_child(_link(company, GOLD, func() -> void: open_company(cid)))
	else:
		top.add_child(_label(company, GOLD))
	var who := str(l.get("name", ""))
	var role := str(l.get("роль", ""))
	if not role.is_empty():
		who += ", " + _t("role_" + role).to_lower()
	var country := str(l.get("country", ""))
	if not country.is_empty() and country != _player_country():
		who += " · " + country
	var w := _label(who, DIM)
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(w)
	if unread:
		top.add_child(_label("● " + _t("letters_new_mark"), GOLD))
	var text := _label(str(l.get("текст", "")), Color(1, 1, 1, 0.95))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(text)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	v.add_child(bottom)
	var n := int(l["number"])
	if pending:
		var offer: Dictionary = l.get("offer", {})
		var yes := Button.new()
		yes.text = _t("letters_accept")
		yes.focus_mode = Control.FOCUS_NONE
		var tip := _t("letters_offer_" + str(offer.get("вид", "")))
		yes.tooltip_text = tip % db.money(float(offer.get("amount", 0.0))) if tip.contains("%s") else tip
		yes.pressed.connect(func() -> void:
			var msg := letters.accept(n)
			if not msg.is_empty():
				game.toast(msg)
			refresh())
		bottom.add_child(yes)
		var no := Button.new()
		no.text = _t("letters_decline")
		no.focus_mode = Control.FOCUS_NONE
		no.pressed.connect(func() -> void:
			var msg := letters.decline(n)
			if not msg.is_empty():
				game.toast(msg)
			refresh())
		bottom.add_child(no)
		if bool(offer.get("bargain", false)):
			var bargain := Button.new()
			bargain.text = _t("letters_haggle")
			bargain.focus_mode = Control.FOCUS_NONE
			bargain.tooltip_text = _t("letters_haggle_tip")
			bargain.pressed.connect(func() -> void:
				var msg := letters.haggle(n)
				if not msg.is_empty():
					game.toast(msg)
				refresh())
			bottom.add_child(bargain)
		bottom.add_child(_label(_t("letters_until") % _date_of(int(l.get("срок", 0))), DIM))
	elif str(l.get("status", "")) != "письмо":
		var st := str(l["status"])
		bottom.add_child(_label(_t("letters_status_" + st), UP if st == "принято" else DIM))
	# Talk to the head in the game's own conversation, when the head is one of the game's contacts.
	if on_write_head.is_valid() and not cid.is_empty() and not db.company(cid).is_empty():
		var talk := Button.new()
		talk.text = _t("letters_talk")
		talk.focus_mode = Control.FOCUS_NONE
		talk.pressed.connect(func() -> void: on_write_head.call(cid))
		bottom.add_child(talk)
	return p


## What a company is angry about, in words: a law by name, taxes, the military course, corruption…
func grievance_text(key: String) -> String:
	if key.begins_with("law:"):
		return _t("grievance_law") % key.substr(4)
	return _t("grievance_" + key) if not key.is_empty() else _t("grievance_")


func tr_market() -> String:
	return _t("market_title")


## Biggest movers of the tab's companies over 4 weeks: two up, two down — [[company, change], …].
func _movers() -> Array:
	var tab_items := _visible_companies()
	var moves: Array = []
	for item in tab_items:
		moves.append([item, db.change(item, 4)])
	moves.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	var out: Array = []
	for mv in moves.slice(0, 2):
		if float(mv[1]) > 0.005:
			out.append(mv)
	var rev := moves.duplicate()
	rev.reverse()
	for mv in rev.slice(0, 2):
		if float(mv[1]) < -0.005 and not out.has(mv):
			out.append(mv)
	return out


func _fill_list() -> void:
	_fill_news()
	for t in TABS:
		var b: Button = _tab_buttons[t]
		b.button_pressed = t == _tab
		b.text = _t("tab_" + t) if t != "country" else _t("tab_country") % _player_country()
		if t == "letters" and letters != null and letters.unread() > 0:
			b.text += " (%d)" % letters.unread()
		if t == "summary" and digest != null and digest.unread and _tab != "summary":
			b.text += " •"
	_sort_btn.select(SORTS.find(_sort))
	_tools.visible = not (_tab in ["summary", "markets", "letters", "arena", "caps", "tech", "development"])
	for ch in _list.get_children():
		ch.queue_free()
	for ch in _intro.get_children():
		ch.queue_free()
	if _tab == "summary":
		_fill_summary()
		return
	if _tab == "markets":
		_fill_markets()
		return
	if _tab == "letters":
		_fill_letters()
		return
	if _tab == "arena":
		_fill_arena()
		return
	if _tab == "caps":
		_fill_caps()
		return
	if _tab == "tech":
		_fill_tech()
		return
	var items := _visible_companies()
	if items.is_empty():
		_advise("empty_" + _tab, _t("empty_" + _tab))
		return
	_list.add_child(_header_row())
	for i in mini(items.size(), _list_limit):
		_list.add_child(_row(items[i], i + 1))
	if items.size() > _list_limit:
		var more := Button.new()
		more.text = _t("show_more") % (items.size() - _list_limit)
		more.focus_mode = Control.FOCUS_NONE
		more.pressed.connect(func() -> void:
			_list_limit += LIST_PAGE
			refresh())
		_list.add_child(more)


## Column captions above the list; the column the list is sorted by is gold.
func _header_row() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var lead := Control.new()
	lead.custom_minimum_size = Vector2(34 + 8 + 28, 0)
	h.add_child(lead)
	var n := UiStyle.caption(_t("col_name"))
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	for col in COLUMNS:
		var key := str(col[0])
		var l := UiStyle.caption(_t("col_" + key), GOLD if key == _sort else DIM)
		if key == "index":
			l.tooltip_text = _t("idx_col_tip")
			l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.custom_minimum_size = Vector2(float(col[1]), 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(l)
	var star := Control.new()
	star.custom_minimum_size = Vector2(32, 0)
	h.add_child(star)
	return h


func _cell(c: Dictionary, key: String) -> String:
	match key:
		"cap":
			return db.money(db.cap(c))
		"revenue":
			return db.money(db.fund(c, "выручка"))
		"employees":
			return db.people(db.staff(c))
		"index":
			return db._num(float(c.get("_index", 0.0)), 1)
	return ""


func _row(c: Dictionary, rank: int) -> Control:
	var cid := str(c["id"])
	var p := PanelContainer.new()
	# Exchange rows: zebra stripes, a lighter row and a coloured edge under the mouse.
	var normal := UiStyle.box(UiStyle.PANEL if rank % 2 == 1 else UiStyle.BG, Color(UiStyle.LINE, 0.8), 4, Vector4(8, 3, 8, 3))   # its own thin edge, before and after a hover
	var hover := UiStyle.box(UiStyle.PANEL2, Color(db.color_of(c).lightened(0.3), 0.6), 4, Vector4(8, 3, 8, 3))
	p.add_theme_stylebox_override("panel", normal)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.mouse_entered.connect(func() -> void: p.add_theme_stylebox_override("panel", hover))
	p.mouse_exited.connect(func() -> void: p.add_theme_stylebox_override("panel", normal))
	p.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			open_company(cid))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)

	var num := _label("%d" % rank, DIM)
	num.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
	num.custom_minimum_size = Vector2(34, 0)
	h.add_child(num)
	h.add_child(_badge(c, 28.0))
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_theme_constant_override("separation", 0)
	h.add_child(names)
	names.add_child(_label(db.name_of(c)))
	var sub := _label("%s · %s" % [db.sector_name(str(c.get("sector", ""))), str(c.get("_country", ""))], DIM)
	sub.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
	names.add_child(sub)

	for col in COLUMNS:
		var key := str(col[0])
		var cell: Label
		if key == "change":
			var ch := db.change(c, 4)
			if on_ask_ai.is_valid() and bool(ai_available.call()):
				# A click on the change offers the game's AI assistant to explain it.
				var b := _chip(db.percent(ch, true), UP if ch > 0.0 else (DOWN if ch < 0.0 else DIM), func() -> void: _offer_ai(c))
				b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
				b.custom_minimum_size = Vector2(float(col[1]), 0)
				b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				b.tooltip_text = _t("ai_cell_tip")
				h.add_child(b)
				continue
			var pc := UiStyle.pill(db.percent(ch, true), UP if ch > 0.0 else (DOWN if ch < 0.0 else DIM), UiStyle.FS)
			pc.custom_minimum_size = Vector2(float(col[1]), 0)
			h.add_child(pc)
			continue
		cell = _label(_cell(c, key), GOLD if key == _sort else Color(1, 1, 1, 1))
		if key == "index":
			cell.tooltip_text = db.index_tip(c)
			cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.custom_minimum_size = Vector2(float(col[1]), 0)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(cell)
	h.add_child(_star(cid))
	return p


func _star(key: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.text = "★" if favorites.has(key) else "☆"
	b.add_theme_color_override("font_color", GOLD if favorites.has(key) else DIM)
	b.tooltip_text = _t("favorite_tip")
	b.pressed.connect(func() -> void:
		if favorites.has(key):
			favorites.erase(key)
		else:
			favorites[key] = true
		refresh())
	return b


# ---------- dossier ----------

func _fill_dossier() -> void:
	for ch in _dossier_view.get_children():
		ch.queue_free()
	var c := db.company(_current)

	var top := HBoxContainer.new()
	_dossier_view.add_child(top)
	var back := Button.new()
	back.text = "← " + _t("back")
	back.flat = true
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func() -> void:
		_current = ""
		refresh())
	top.add_child(back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var map_btn := Button.new()
	map_btn.text = "🗺 " + _t("show_on_map")
	map_btn.focus_mode = Control.FOCUS_NONE
	map_btn.pressed.connect(func() -> void: on_show_on_map.call(_current))
	top.add_child(map_btn)
	top.add_child(_star(_current))
	var dhelp := Button.new()
	dhelp.text = "?"
	dhelp.tooltip_text = _t("tut_mini_tip")
	dhelp.focus_mode = Control.FOCUS_NONE
	dhelp.pressed.connect(func() -> void:
		if on_tutorial.is_valid():
			on_tutorial.call("dossier"))
	top.add_child(dhelp)
	var dclose := Button.new()   # the dossier had no way out but «← To the list»: ✕ closes the window at once
	dclose.text = "✕"
	dclose.tooltip_text = _t("close_window_tip")
	dclose.focus_mode = Control.FOCUS_NONE
	dclose.custom_minimum_size = Vector2(34, 0)
	dclose.pressed.connect(close_window)
	top.add_child(dclose)
	_tut["back"] = back
	_tut["map"] = map_btn

	var head_card := PanelContainer.new()
	head_card.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, Color(db.color_of(c), 0.5), 8, Vector4(12, 8, 12, 8)))
	_dossier_view.add_child(head_card)
	_tut["head"] = head_card
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head_card.add_child(head)
	head.add_child(_badge(c, 52.0))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	var title := _label(db.name_of(c))
	title.add_theme_font_size_override("font_size", 22)
	info.add_child(title)
	var tags := UiStyle.flow(6)
	for tag in [db.sector_name(str(c.get("sector", ""))), str(c.get("_country", "")), _t("type_" + str(c.get("type", ""))), _t("founded") % int(c.get("founded", 0))]:
		tags.add_child(UiStyle.pill(str(tag), DIM))
	info.add_child(tags)
	# The ticker: price, its 4-week change, capitalisation.
	var tick := HBoxContainer.new()
	tick.add_theme_constant_override("separation", 10)
	var price := _label(db.money_price(db.price(c)), UiStyle.tone(db.change(c, 4)))
	price.add_theme_font_size_override("font_size", 20)
	tick.add_child(price)
	tick.add_child(UiStyle.pill(db.percent(db.change(c, 4), true), UiStyle.tone(db.change(c, 4)), UiStyle.FS))
	var capl := _label(_t("market_cap_short") % db.money(db.cap(c)), DIM)
	capl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.add_child(capl)
	info.add_child(tick)
	if not Frames.of(c).is_empty():
		var st := _label(_frame_text(c), Frames.RING[Frames.of(c)])
		st.tooltip_text = _frame_next(c)
		st.mouse_filter = Control.MOUSE_FILTER_PASS
		info.add_child(st)
	# The description is kept to two lines; the whole text is in the tooltip.
	var desc := _label(db.text(c.get("description", "")), DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(300, 0)
	desc.max_lines_visible = 2
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.add_theme_font_size_override("font_size", UiStyle.FS_SMALL + 1)
	desc.tooltip_text = db.text(c.get("description", ""))
	desc.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(desc)
	head.add_child(_leader_block(c))

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, 320)
	_dossier_view.add_child(tabs)
	_tut["dtabs"] = tabs
	tabs.add_child(_scroll(_tab_overview(c)))
	tabs.add_child(_scroll(_tab_shares(c)))
	tabs.add_child(_scroll(_tab_debt(c)))
	tabs.add_child(_scroll(_tab_owners(c)))
	tabs.add_child(_scroll(_tab_assets(c)))
	tabs.add_child(_scroll(_tab_chronicle(c)))
	for i in DOSSIER_TABS.size():
		tabs.set_tab_title(i, _t("dtab_" + DOSSIER_TABS[i]))
	tabs.current_tab = _dossier_tab
	tabs.tab_changed.connect(func(i: int) -> void: _dossier_tab = i)


func _leader_block(c: Dictionary) -> Control:
	var lead: Dictionary = c.get("глава", {})
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL2, UiStyle.LINE, 8, Vector4(10, 6, 10, 6)))
	p.custom_minimum_size = Vector2(210, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	row.add_child(_portrait(db.text(lead.get("name", "")), db.color_of(c)))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	row.add_child(names)
	# The head's name is a link: a click makes them a contact of the game and opens a conversation (main.gd).
	var cid := str(c["id"])
	if on_write_head.is_valid() and not db.text(lead.get("name", "")).is_empty():
		var link := _link("✉ " + db.text(lead.get("name", "")), Color(1, 1, 1, 0.95), func() -> void: on_write_head.call(cid))
		link.tooltip_text = _t("head_write_tip")
		names.add_child(link)
	else:
		names.add_child(_label(db.text(lead.get("name", "—"))))
	names.add_child(_label(_t("role_" + str(lead.get("роль", ""))), GOLD))
	var year := int(game.date().get("year", 2026))
	var bits: PackedStringArray = []
	var owns := float(lead.get("доля", 0.0))
	if owns > 0.0:
		bits.append(_t("owns") % db.percent(owns))
	bits.append(_t("head_since") % int(lead.get("с_года", 0)))
	var small := _label(" · ".join(bits), DIM)
	small.add_theme_font_size_override("font_size", 12)
	v.add_child(small)
	if lead.has("born_year"):
		var age := _label(_t("age") % (year - int(lead["born_year"])), DIM)
		age.add_theme_font_size_override("font_size", 12)
		v.add_child(age)
	if politics != null and politics.heads_added(str(c["id"])):
		var contact := _label("💬 " + _t("head_contact"), UP)
		contact.add_theme_font_size_override("font_size", 12)
		contact.tooltip_text = _t("head_contact_tip")
		contact.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(contact)
	p.tooltip_text = db.text(lead.get("характер", ""))
	return p


func _tab_overview(c: Dictionary) -> Control:
	var v := _vbox(_t("dtab_overview"))
	var places := _label(_t("places") % [int(c.get("_world_place", 0)), int(c.get("_country_place", 0)),
		str(c.get("_country", "")), db._num(float(c.get("_index", 0.0)), 1)], GOLD)
	places.tooltip_text = db.index_tip(c)
	places.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(places)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	v.add_child(grid)
	var st: Dictionary = c.get("_statuses", {})
	for row in STATUS_ROWS:
		var key := str(row[0])
		var s: Dictionary = st.get(key, {})
		if s.is_empty():
			# Trust is counted only for the player's country — only it has laws and taxes in the game.
			grid.add_child(_label(_t("st_" + key), DIM))
			grid.add_child(_label("—", DIM))
			grid.add_child(_label(_t("only_player_country"), DIM))
			continue
		var val := float(s.get("value", 0.0))
		var name_l := _label(_t("st_" + key))
		name_l.tooltip_text = _parts_text(s.get("parts", []), "")
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(name_l)
		var bar := Charts.Bar.new()
		bar.value = val
		bar.good_high = bool(row[1])
		bar.custom_minimum_size = Vector2(160, 10)
		grid.add_child(bar)
		var val_l := _label("%d · %s" % [roundi(val), _level_word(val)], DIM)
		val_l.tooltip_text = name_l.tooltip_text
		val_l.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(val_l)
	for key in PENDING_ROWS:
		grid.add_child(_label(_t("st_" + key), DIM))
		grid.add_child(_label("—", DIM))
		grid.add_child(_label(_t("stage2"), DIM))

	var rung := int(db.econ(c).get("ladder", 0))
	if rung > 0:
		var ladder := _label("⚠ " + _t("ladder_now") % [rung, _t("ladder_%d" % rung)], DOWN)
		ladder.tooltip_text = _t("ladder_tip")
		ladder.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(ladder)

	_conditions_block(v, c)
	_situation_block(v, c)
	_market_block(v, c)

	var br: Dictionary = c.get("_breakup", {})
	var brl := _label(_t("breakup") % db._num(float(br.get("value", 0.0)), 1), GOLD)
	v.add_child(brl)
	var parts := _label(_parts_text(br.get("parts", []), "%"), DIM)
	parts.add_theme_font_size_override("font_size", 12)
	v.add_child(parts)

	v.add_child(HSeparator.new())
	_people_block(v, c)
	var est: Array = c.get("оценка", [])
	if not est.is_empty():
		var e := _label("⚠ " + _t("estimate") % ", ".join(PackedStringArray(est)), DIM)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.add_theme_font_size_override("font_size", 12)
		v.add_child(e)
	return v


## «Условия работы» (conditions.gd): the index U and the seven conditions as bars, the main problem highlighted,
## failures (blackout, no communication, fighting) as red pills.
func _conditions_block(v: VBoxContainer, c: Dictionary) -> void:
	var e := db.econ(c)
	var cond: Dictionary = e.get("условия", {})
	if conditions == null or cond.is_empty():
		return
	var u := float(e.get("U", 0.5))
	var card := UiStyle.card(v, _t("cond_title"), Color(UiStyle.tone(u - 0.5, 0.05), 0.5))
	var top := UiStyle.flow(6)
	card.add_child(top)
	var idx := UiStyle.pill(_t("cond_index") % roundi(u * 100.0), UiStyle.tone(u - 0.5, 0.05), UiStyle.FS)
	idx.tooltip_text = _t("cond_index_tip")
	top.add_child(idx)
	var lvl := float(e.get("U_level", 1.0))
	top.add_child(UiStyle.pill(_t("cond_level") % db.percent(lvl - 1.0, true), UiStyle.tone(lvl - 1.0, 0.002)))
	var worst := conditions.main_problem(c)
	top.add_child(UiStyle.pill(_t("cond_main") % _t("cond_v_" + worst), DOWN if float(cond.get(worst, 0.5)) < 0.4 else GOLD))
	for key in [["blackout", "cond_blackout"], ["unlinked", "cond_mute"], ["in_battles", "cond_fight"]]:
		if float(e.get(str(key[0]), 0.0)) > 0.0:
			top.add_child(UiStyle.pill("⚠ " + _t(str(key[1])) % db.percent(float(e[str(key[0])])), DOWN))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	card.add_child(grid)
	var w := conditions.weights(str(c.get("sector", "")))
	for vname in Conditions.VARS:
		var x := float(cond.get(vname, 0.5))
		var name_l := _label(_t("cond_v_" + vname), GOLD if vname == worst else UiStyle.TEXT)
		name_l.add_theme_font_size_override("font_size", UiStyle.FS_SMALL + 1)
		name_l.tooltip_text = _t("cond_v_" + vname + "_tip")
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(name_l)
		var bar := Charts.Bar.new()
		bar.value = x * 100.0
		bar.custom_minimum_size = Vector2(110, 7)
		grid.add_child(bar)
		var val := _label(str(roundi(x * 100.0)), DIM)
		val.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
		grid.add_child(val)
		var wl := _label(_t("cond_weight") % roundi(float(w.get(vname, 0.0)) * 100.0), DIM)
		wl.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
		grid.add_child(wl)


## How the world's events press on the company this week: each event × the sector's sensitivity (7, 20.2).
func _situation_block(v: VBoxContainer, c: Dictionary) -> void:
	var ex: Dictionary = c.get("_climate", {})
	var parts: Dictionary = ex.get("parts", {})
	v.add_child(HSeparator.new())
	var total := float(ex.get("total", 0.0))
	var head := _label(_t("situation") % _signed(total), UP if total > 0.05 else (DOWN if total < -0.05 else GOLD))
	head.tooltip_text = _t("situation_tip")
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(head)
	if parts.is_empty():
		v.add_child(_label(_t("situation_calm"), DIM))
		return
	for ev in parts.keys():
		var x := float(parts[ev])
		v.add_child(_label("   %s  %s" % [_signed(x), _t("event_" + str(ev))], UP if x > 0.0 else DOWN))
	var trend := 0.0
	if events != null:
		trend = float(events.trends.get(str(c.get("sector", "")), 0.0))
	if absf(trend) > 0.01:
		v.add_child(_label(_t("sector_trend") % [db.sector_name(str(c.get("sector", ""))), _signed(trend)], DIM))


## The company's goods and markets: demand from people (population × consumption × wealth), the company's
## shares by popularity, and demand against what its staff can make.
func _market_block(v: VBoxContainer, c: Dictionary) -> void:
	var e := db.econ(c)
	if goods == null or e.is_empty() or not e.has("market_home"):
		return
	v.add_child(HSeparator.new())
	var head := _label(_t("market_title") % goods.goods_name(db, c), GOLD)
	head.tooltip_text = _t("market_tip")
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(head)
	var country := str(c.get("_country", ""))
	var info: Dictionary = goods.country_info(country)
	var home_volume := float(goods.pool_volume.get(goods.home_pool(c), 0.0))
	var world_volume := float(goods.pool_volume.get(goods.world_pool(c), 0.0))
	var home := _label(_t("market_home") % [country, db.money(home_volume), db.percent(float(e.get("home_share_mod", 0.0)))])
	if not info.is_empty():
		home.tooltip_text = _t("market_home_tip") % [db.people(float(info["humans"])), db._num(float(info["богатство"]), 2)]
		home.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(home)
	v.add_child(_label(_t("market_world") % [db.money(world_volume), db.percent(float(e.get("world_share_mod", 0.0))),
		db.percent(goods.export_share(db, c))]))
	var want := float(e.get("demand_money", 0.0))
	var can := float(e.get("offer", want))
	var used := minf(want, can) / maxf(can, 1e-6)
	var sd := _label(_t("market_supply") % [db.money(want), db.money(can), db.percent(used)],
		DOWN if can < 0.95 * want else (GOLD if can > 1.1 * want else Color(1, 1, 1, 1)))
	sd.tooltip_text = _t("market_supply_tip")
	sd.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(sd)
	if e.has("ramp"):
		# A new company is still being built (economy.gd _ramp): how far, and when it works at full strength.
		var r := float(e["ramp"])
		var start := float(e.get("ramp_start", r))
		var left := ceili((1.0 - r) / maxf(1.0 - start, 1e-6) * float(e.get("ramp_weeks", 26)))
		var bl := _label(_t("market_startup") % [db.percent(r), str(left)], GOLD)
		bl.tooltip_text = _t("market_startup_tip")
		bl.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(bl)
	var m := float(e.get("market_demand", 1.0))
	v.add_child(_label(_t("market_effect") % db.percent(m - 1.0, true), UP if m > 1.01 else (DOWN if m < 0.99 else DIM)))
	var pies := HBoxContainer.new()
	pies.add_theme_constant_override("separation", 18)
	v.add_child(pies)
	pies.add_child(_share_pie(goods.home_pool(c), str(c["id"]), _t("home_pie") % country, home_volume, 190.0))
	pies.add_child(_share_pie(goods.world_pool(c), str(c["id"]), _t("world_pie"), world_volume, 190.0))
	_rivals_block(v, c)


## A market as a pie with its legend: the biggest companies by name (the given one in gold), the rest of
## the list summed, and the producers outside the list. Legend names open the dossier.
func _share_pie(pool: String, highlight: String, title: String, volume: float, diameter: float) -> Control:
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 8, Vector4(12, 8, 12, 10)))
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	outer.add_child(box)
	box.add_child(UiStyle.caption(title, GOLD))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	box.add_child(h)
	var pie := Charts.Pie.new()
	pie.custom_minimum_size = Vector2(diameter, diameter)
	pie.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(pie)
	var legend := VBoxContainer.new()
	legend.add_theme_constant_override("separation", 1)
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(legend)
	var rows: Array = goods.pool_shares(db, pool) if goods != null else []
	var slices: Array = []
	var rest := 0.0
	var rest_n := 0
	var shown := 0
	for r in rows:
		var cid := str(r[0])
		var share := float(r[1])
		if cid.is_empty():
			continue
		if shown >= PIE_TOP and cid != highlight:
			rest += share
			rest_n += 1
			continue
		var comp := db.company(cid)
		# Distinct colours slice by slice (companies of one goods share a profile colour); ours is gold.
		var col: Color = GOLD if cid == highlight else Charts.PIE_COLORS[shown % Charts.PIE_COLORS.size()]
		slices.append([share, col, db.name_of(comp)])
		legend.add_child(_legend_row(col, db.name_of(comp), share, cid, cid == highlight))
		shown += 1
	if rest > 0.0:
		slices.append([rest, Color(0.33, 0.36, 0.41), _t("markets_rest") % rest_n])
		legend.add_child(_legend_row(Color(0.33, 0.36, 0.41), _t("markets_rest") % rest_n, rest, "", false))
	if rows.is_empty():
		legend.add_child(_label(_t("markets_empty"), DIM))
	pie.slices = slices
	pie.center_title = _t("pie_volume")
	pie.center_value = db.money(volume) if volume > 0.0 else ""
	return outer


func _legend_row(col: Color, text: String, share: float, cid: String, bold: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var sw := Control.new()
	sw.custom_minimum_size = Vector2(10, 10)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.draw.connect(func() -> void: sw.draw_circle(sw.size / 2.0, 4.5, col))
	row.add_child(sw)
	var name_ctl: Control
	if cid.is_empty():
		name_ctl = _label(text, DIM)
	else:
		var b := _link(text, GOLD if bold else UiStyle.TEXT, func() -> void: open_company(cid))
		b.clip_text = true
		name_ctl = b
	name_ctl.add_theme_font_size_override("font_size", UiStyle.FS_SMALL + 1)
	name_ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_ctl)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(50, 4)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.draw.connect(func() -> void:
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), UiStyle.PANEL2)
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * clampf(share, 0.0, 1.0), bar.size.y)), col))
	row.add_child(bar)
	var pct := _label(db.percent(share), GOLD if bold else UiStyle.TEXT)
	pct.add_theme_font_size_override("font_size", UiStyle.FS_SMALL + 1)
	pct.custom_minimum_size = Vector2(48, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	return row


## Stage 3 in the dossier: the parent, running corporate wars, the rivals it is in tension with.
func _rivals_block(v: VBoxContainer, c: Dictionary) -> void:
	if rivals == null:
		return
	var cid := str(c["id"])
	v.add_child(HSeparator.new())
	var head := _label(_t("rivals_title") + " · " + _t("aggression") % db.percent(rivals.aggression(db, c)), GOLD)
	head.tooltip_text = _t("rivals_tip")
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(head)
	var any := false
	var parent := Rivals.parent_of(c)
	if not parent.is_empty() and not db.company(parent).is_empty():
		v.add_child(_link(_t("rivals_parent") % [db.name_of(db.company(parent)), db.percent(Rivals.stake_of(c, parent))], GOLD,
			func() -> void: open_company(parent)))
		any = true
	var origin := str(c.get("split_from", ""))
	if not origin.is_empty() and not db.company(origin).is_empty():
		v.add_child(_link(_t("rivals_from") % db.name_of(db.company(origin)), DIM, func() -> void: open_company(origin)))
	for w in rivals.wars_of(cid):
		var other := str(w["b"]) if str(w["a"]) == cid else str(w["a"])
		v.add_child(_link(_t("rivals_war") % [db.name_of(db.company(other)), int(w["weeks"]), db.percent(float(w["heat"]))], DOWN,
			func() -> void: open_company(other)))
		any = true
	var hot: Array = []
	for k in rivals.tension.keys():
		var ids := str(k).split("|")
		if cid in ids and float(rivals.tension[k]) >= 0.2:
			hot.append([ids[1] if ids[0] == cid else ids[0], float(rivals.tension[k])])
	hot.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	for pair in hot.slice(0, 3):
		var other := str(pair[0])
		var level := clampf(float(pair[1]) / float((db.balance.get("competition", {}) as Dictionary).get("war_threshold", 1.0)), 0.0, 1.0)
		v.add_child(_link(_t("rivals_tension") % [db.name_of(db.company(other)), db.percent(level)], DOWN.lerp(GOLD, 1.0 - level),
			func() -> void: open_company(other)))
		any = true
	if not any:
		v.add_child(_label(_t("rivals_none"), DIM))


# ---------- the «Markets» tab ----------

## One market as a pie (a goods, the world or one country), the running corporate wars, the latest deals.
func _fill_markets() -> void:
	if goods == null:
		return
	var keys: Array = (db.goods.get("goods", {}) as Dictionary).keys()
	if _mk_goods.is_empty() or not (_mk_goods in keys):
		_mk_goods = str(keys[0]) if not keys.is_empty() else ""
	if _mk_scope == "*":
		_mk_scope = ""
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	_list.add_child(bar)
	var gsel := OptionButton.new()
	gsel.focus_mode = Control.FOCUS_NONE
	for i in keys.size():
		gsel.add_item(db.text(((db.goods["goods"] as Dictionary)[keys[i]] as Dictionary).get("name", keys[i])))
		if str(keys[i]) == _mk_goods:
			gsel.select(i)
	gsel.item_selected.connect(func(i: int) -> void:
		_mk_goods = str(keys[i])
		refresh())
	bar.add_child(gsel)
	var scopes: Array = [""]
	for country in db.countries.keys():
		if goods.members.has("дом|%s|%s" % [_mk_goods, str(country)]):
			scopes.append(str(country))
	if not (_mk_scope in scopes):
		_mk_scope = ""
	var ssel := OptionButton.new()
	ssel.focus_mode = Control.FOCUS_NONE
	for i in scopes.size():
		ssel.add_item(_t("markets_world") if str(scopes[i]).is_empty() else str(scopes[i]))
		if str(scopes[i]) == _mk_scope:
			ssel.select(i)
	ssel.item_selected.connect(func(i: int) -> void:
		_mk_scope = str(scopes[i])
		refresh())
	bar.add_child(ssel)
	var pool := "мир|" + _mk_goods if _mk_scope.is_empty() else "дом|%s|%s" % [_mk_goods, _mk_scope]
	var volume := float(goods.pool_volume.get(pool, 0.0))
	_list.add_child(_share_pie(pool, "", gsel.get_item_text(gsel.selected) + " — " + ssel.get_item_text(ssel.selected), volume, 180.0))

	_list.add_child(HSeparator.new())
	var st: Dictionary = rivals.stats if rivals != null else {}
	var totals := _label(_t("stage3_totals") % [int(st.get("войн", 0)), int(st.get("поглощений", 0)),
		int(st.get("распадов", 0)) + int(st.get("разделов", 0)), int(st.get("forbidden", 0)), int(st.get("силовое", 0))], DIM)
	totals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(totals)
	_list.add_child(_label(_t("wars_now"), GOLD))
	if rivals == null or rivals.wars.is_empty():
		_list.add_child(_label(_t("wars_none"), DIM))
	else:
		for w in rivals.wars:
			var a := str(w["a"])
			var b := str(w["b"])
			var row := HBoxContainer.new()
			row.add_child(_link("⚔ " + db.name_of(db.company(a)), DOWN, func() -> void: open_company(a)))
			row.add_child(_label("—", DIM))
			row.add_child(_link(db.name_of(db.company(b)), DOWN, func() -> void: open_company(b)))
			row.add_child(_label(_t("war_info") % [int(w["weeks"]), db.percent(float(w["heat"]))], DIM))
			_list.add_child(row)
	_list.add_child(_label(_t("deals_title"), GOLD))
	if rivals == null or rivals.deals.is_empty():
		_list.add_child(_label(_t("deals_none"), DIM))
	else:
		for i in range(rivals.deals.size() - 1, maxi(-1, rivals.deals.size() - 13), -1):
			var d: Dictionary = rivals.deals[i]
			var a := str(d["a"])
			var b := str(d["b"])
			var text := _t("deal_" + str(d["вид"])) % [_date_of(int(d["день"])), _name_of_id(a), db.percent(float(d["доля"])), _name_of_id(b)]
			_list.add_child(_link(text, Color(1, 1, 1, 0.9), func() -> void: open_company(b)))


func _signed(x: float) -> String:
	return ("+" if x >= 0.0 else "−") + db._num(absf(x), 2)


## Staff now, who came and went over the last 4 weeks, wages against the market and the country,
## strikes, and the staff chart (section 5).
func _people_block(v: VBoxContainer, c: Dictionary) -> void:
	var e := db.econ(c)
	var n := db.staff(c)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	title_row.add_child(_label(_t("people_title"), GOLD))
	if not e.is_empty():
		var why := Button.new()
		why.text = "ⓘ " + _t("staff_why")
		why.tooltip_text = _t("staff_why_tip")
		why.focus_mode = Control.FOCUS_NONE
		why.pressed.connect(func() -> void: _explain_staff(c))
		title_row.add_child(why)
	v.add_child(title_row)
	v.add_child(_label(_t("employees") % [db.people(n), _points_count(c)]))
	if e.is_empty():
		v.add_child(_label(_t("salary") % db.people(db.wage(c))))
		return
	var came := 0.0
	var left := 0.0
	var fired := 0.0
	var flows: Array = e.get("flows", [])
	for i in range(maxi(0, flows.size() - 4), flows.size()):
		came += float(flows[i][0])
		left += float(flows[i][1])
		fired += float(flows[i][2])
	var net := came - left - fired
	var flow_l := _label(_t("flows") % [("+" if net >= 0.0 else "−") + db.people(absf(net)), db.people(came),
		db.people(left), db.people(fired)], UP if net > 0.0 else (DOWN if net < 0.0 else DIM))
	flow_l.tooltip_text = _t("flows_tip")
	flow_l.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(flow_l)
	v.add_child(_label(_t("need") % [db.people(float(e.get("нужно", n))), db.percent(float(e.get("vacancies", 0.0)))], DIM))
	var w := db.wage(c)
	var market := float(e.get("market_wage", w))
	var avg := float(db.country_info(str(c.get("_country", ""))).get("average_wage", 1000.0))
	var wage_l := _label(_t("salary_live") % [db.people(w), db._num(w / maxf(market, 1.0), 2), db._num(w / maxf(avg, 1.0), 2)])
	wage_l.tooltip_text = _t("salary_tip") % [db.people(market), db.people(avg)]
	wage_l.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(wage_l)
	v.add_child(_label(_t("payroll") % db.money(db.fund(c, "фот")), DIM))
	var strikes: Array = e.get("strikes", [])
	if not strikes.is_empty():
		var people := 0.0
		for s in strikes:
			people += float((s as Dictionary).get("людей", 0.0))
		v.add_child(_label("⚠ " + _t("strikes_now") % [db.people(people), strikes.size()], DOWN))
	var chart := Charts.LineChart.new()
	chart.custom_minimum_size = Vector2(0, 90)
	chart.line_color = Color(0.55, 0.8, 0.95)
	chart.format_value = func(x: float) -> String: return db.people(x)
	chart.empty_text = _t("chart_empty")
	chart.set_values(e.get("headcount_history", []))
	v.add_child(chart)


func _tab_shares(c: Dictionary) -> Control:
	var v := _vbox(_t("dtab_shares"))
	var chart := Charts.LineChart.new()
	chart.trend = true
	chart.format_value = func(x: float) -> String: return db.money_price(x)
	chart.empty_text = _t("chart_empty")
	chart.set_values(db.history(c))
	v.add_child(chart)
	var rating := str(c.get("_rating", "—"))
	var pairs: Array = [
		["share_price", db.money_price(db.price(c))],
		["market_cap", db.money(db.cap(c))],
		["change_4w", db.percent(db.change(c, 4), true), UiStyle.tone(db.change(c, 4))],
		["change_start", db.percent(db.change(c, 100000), true), UiStyle.tone(db.change(c, 100000))],
		["credit_rating", "%s  (Q = %s)" % [rating, db._num(float(c.get("_q", 0.0)), 2)]],
		["volatility", db.percent(db.volatility(c)) + " " + _t("per_week")],
		["revenue", db.money(db.fund(c, "выручка"))],
		["profit", db.money(db.fund(c, "profit")), UiStyle.tone(db.fund(c, "profit"), 0.0)],
		["dividends", db.money(db.fund(c, "dividends"))],
		["payroll_short", db.money(db.fund(c, "фот"))],
		["debt", db.money(db.fund(c, "debt"))],
		["cash", db.money(db.fund(c, "money"))],
		["taxes", _t("taxes_value") % [db.money(db.fund(c, "taxes")), db.money(db.fund(c, "taxes_owed"))]],
	]
	if lifecycle != null:
		# The yearly bankruptcy chance (20.3) — or the procedure already running.
		var proc: Dictionary = db.econ(c).get("банкротство", {})
		if not proc.is_empty():
			pairs.append(["bankruptcy", _t("bankruptcy_running") % int(proc.get("weeks", 0))])
		elif float(db.econ(c).get("P", 0.0)) >= 0.0 and float(db.econ(c).get("money", 0.0)) >= 0.0:
			pairs.append(["bankruptcy", _t("bankruptcy_safe")])
		else:
			var b := lifecycle.bankruptcy_chance(db, c, events != null and events.crisis_on())
			pairs.append(["bankruptcy", db.percent(float(b["value"])) + " " + _t("per_year"), DOWN if float(b["value"]) > 0.1 else UiStyle.TEXT])
	v.add_child(_tiles(pairs))
	return v


## Figures as the exchange's KPI tiles, four in a row: [caption key, value, colour?].
func _tiles(pairs: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for pr in pairs:
		var pa: Array = pr
		var tile := UiStyle.kpi(_t(str(pa[0])), str(pa[1]), pa[2] if pa.size() > 2 else UiStyle.TEXT)
		tile.tooltip_text = str(pa[1])
		grid.add_child(tile)
	return grid


## Debt and creditors (section 9): total, load, rating and rate, interest, the next big payment, the loans.
func _tab_debt(c: Dictionary) -> Control:
	var v := _vbox(_t("dtab_debt"))
	var e := db.econ(c)
	var debt := db.fund(c, "debt")
	var rev := maxf(db.fund(c, "выручка"), 1.0)
	var loans: Array = e.get("loans", [])
	if debt <= 0.0 and loans.is_empty():
		var why := _t("debt_bank") if str(c.get("sector", "")) == "banks" else _t("debt_none")
		var a := Advisor.new()
		a.setup(mod, "debt_none", why)
		v.add_child(a)
		return v
	var rate := float(e.get("rate", 0.0))
	var leverage := debt / rev
	var pairs: Array = [
		["debt", db.money(debt)],
		["debt_load", db._num(leverage, 2) + "× " + _t("of_revenue"), DOWN if leverage > 2.0 else UiStyle.TEXT],
		["credit_rating", str(c.get("_rating", "—"))],
		["debt_rate", db.percent(rate) + " " + _t("a_year")],
		["debt_interest", db.money(db.fund(c, "interest")) + " " + _t("a_year")],
		["cash", db.money(db.fund(c, "money"))],
	]
	var next := _next_payment(loans)
	if not next.is_empty():
		pairs.append(["debt_next", "%s · %s" % [db.money(float(next["amount"])), _date_of(int(next["repayment"]))]])
	v.add_child(_tiles(pairs))
	var hist: Array = e.get("debt_history", [])
	if hist.size() >= 2:
		var chart := Charts.LineChart.new()
		chart.custom_minimum_size = Vector2(0, 90)
		chart.line_color = Color(0.95, 0.45, 0.35)
		chart.format_value = func(x: float) -> String: return db.money(x)
		chart.set_values(hist)
		v.add_child(chart)

	v.add_child(HSeparator.new())
	v.add_child(_label(_t("debt_loans"), GOLD))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	for cap in [["debt_lender", 0], ["debt_amount", 90], ["debt_rate_short", 70], ["debt_due", 90]]:
		var hl := _label(_t(str(cap[0])), DIM)
		hl.add_theme_font_size_override("font_size", 12)
		if int(cap[1]) > 0:
			hl.custom_minimum_size = Vector2(float(cap[1]), 0)
			hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(hl)
	v.add_child(head)
	var sorted := loans.duplicate()
	sorted.sort_custom(func(a, b): return int(a["repayment"]) < int(b["repayment"]))
	for loan in sorted:
		var ld: Dictionary = loan
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		var who := db.text(ld.get("creditor", "")) + "  ·  " + _t("lender_" + str(ld.get("вид", "")))
		var bank_id := str(ld.get("company", ""))
		var name_ctl: Control
		if not bank_id.is_empty() and not db.company(bank_id).is_empty():
			name_ctl = _link(who, GOLD, func() -> void: open_company(bank_id))
		else:
			name_ctl = _label(who)
		name_ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_ctl)
		for cell in [[db.money(float(ld["amount"])), 90], [db.percent(float(ld["rate"])) + ("~" if bool(ld.get("floating", false)) else ""), 70],
				[_date_of(int(ld["repayment"])), 90]]:
			var cl := _label(str(cell[0]))
			cl.custom_minimum_size = Vector2(float(cell[1]), 0)
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(cl)
	var note := Advisor.new()
	note.setup(mod, "debt_note", _t("debt_note"))
	v.add_child(note)
	return v


## The biggest payment within the next year, else the nearest one.
func _next_payment(loans: Array) -> Dictionary:
	var soon := game.day() + 365
	var best: Dictionary = {}
	for loan in loans:
		var ld: Dictionary = loan
		if int(ld["repayment"]) <= soon and float(ld["amount"]) > float(best.get("amount", -1.0)):
			best = ld
	if best.is_empty():
		for loan in loans:
			if best.is_empty() or int(loan["repayment"]) < int(best["repayment"]):
				best = loan
	return best


func _tab_owners(c: Dictionary) -> Control:
	var v := _vbox(_t("dtab_owners"))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	var pie := Charts.Pie.new()
	pie.custom_minimum_size = Vector2(210, 210)
	h.add_child(pie)
	var legend := VBoxContainer.new()
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(legend)
	var slices: Array = []
	var owners: Array = c.get("owners", [])
	for i in owners.size():
		if not (owners[i] is Dictionary):
			continue
		var o: Dictionary = owners[i]
		var share := float(o.get("доля", 0.0))
		var col: Color = Charts.PIE_COLORS[i % Charts.PIE_COLORS.size()]
		slices.append([share, col, db.text(o.get("кто", ""))])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		legend.add_child(row)
		var sw := ColorRect.new()
		sw.color = col
		sw.custom_minimum_size = Vector2(12, 12)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sw)
		var who := _label(db.text(o.get("кто", "")))
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(who)
		row.add_child(_label(db.percent(share)))
		var tag := ""
		if share > 0.5:
			tag = _t("control")
		elif share > 0.25:
			tag = _t("blocking")
		if not tag.is_empty():
			row.add_child(_label(tag, GOLD))
		var kind := _label(_t("holder_" + str(o.get("type", ""))), DIM)
		kind.add_theme_font_size_override("font_size", 12)
		legend.add_child(kind)
	pie.slices = slices
	pie.center_title = _t("pie_owners")
	pie.center_value = str(owners.size())
	var ind: Dictionary = (c.get("_statuses", {}) as Dictionary).get("независимость", {})
	v.add_child(_label(_t("st_независимость") + ": %d" % roundi(float(ind.get("value", 0.0))), GOLD))
	_investors_block(v, c)
	if on_trade.is_valid():
		_stake_block(v, c)
	return v


## Foreign investors of the company (investments.gd): who, how much, what they bring, their rights, the risk.
func _investors_block(v: VBoxContainer, c: Dictionary) -> void:
	if investments == null:
		return
	var list: Array = investments.describe(c)
	if list.is_empty():
		return
	var card := UiStyle.card(v, _t("inv_title"), Color(UiStyle.BLUE, 0.5))
	for item in list:
		var d: Dictionary = item
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var who := _label("%s · %s" % [str(d["country"]), db.percent(float(d["доля"]))], UiStyle.TEXT)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(who)
		row.add_child(UiStyle.pill(_t("inv_brings_" + str(d["profile"])), UiStyle.BLUE))
		row.add_child(UiStyle.pill(_t("inv_right_" + str(d["права"])), GOLD if str(d["права"]) != "control" else DOWN))
		row.add_child(UiStyle.pill("E %s" % db._num(float(d["E"]), 2), UP))
		var rel := float(d["relations"])
		var risk := UiStyle.pill(_t("inv_frozen_tag") if bool(d["frozen_n"]) else _t("inv_rel") % roundi(rel * 100.0),
			DIM if bool(d["frozen_n"]) else (DOWN if rel < 0.4 else UP))
		risk.tooltip_text = _t("inv_rel_tip")
		row.add_child(risk)
	var a := Advisor.new()
	a.setup(mod, "investors", _t("inv_advice"))
	card.add_child(a)


## The player's state buys or sells a block of shares right away — works on pause too (section 6).
func _stake_block(v: VBoxContainer, c: Dictionary) -> void:
	var cid := str(c["id"])
	var country := _player_country()
	var mine := 0.0
	var free := 0.0
	for o in c.get("owners", []):
		var od: Dictionary = o
		if str(od.get("type", "")) == "polity" and str(od.get("country", "")) == country:
			mine += float(od.get("доля", 0.0))
		elif str(od.get("type", "")) == "частные":
			free += float(od.get("доля", 0.0))
	v.add_child(HSeparator.new())
	var head := _label(_t("stake_title") % [country, db.percent(mine)], GOLD)
	v.add_child(head)
	var money := float(treasury_money.call()) if treasury_money.is_valid() else 0.0
	var info := _label(_t("stake_info") % [db.percent(free), db.money_price(db.price(c)), db.money(money)], DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)
	var buys := HBoxContainer.new()
	buys.add_theme_constant_override("separation", 6)
	v.add_child(buys)
	for f in BUY_STEPS:
		buys.add_child(_trade_button(cid, float(f), true, _t("stake_buy") % db.percent(float(f))))
	if mine <= 0.5:
		buys.add_child(_trade_button(cid, 0.5001 - mine, true, _t("stake_buy_control")))
	var sells := HBoxContainer.new()
	sells.add_theme_constant_override("separation", 6)
	v.add_child(sells)
	for f in SELL_STEPS:
		sells.add_child(_trade_button(cid, float(f), false, _t("stake_sell") % db.percent(float(f))))
	sells.add_child(_trade_button(cid, mine, false, _t("stake_sell_all")))
	var hint := Advisor.new()
	hint.setup(mod, "stake_hint", _t("stake_hint"))
	v.add_child(hint)


func _trade_button(cid: String, fraction: float, buy: bool, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var side := UP if buy else DOWN
	b.add_theme_stylebox_override("normal", UiStyle.box(Color(side, 0.16), Color(side, 0.5), 6, Vector4(10, 4, 10, 4)))
	b.add_theme_stylebox_override("hover", UiStyle.box(Color(side, 0.3), side, 6, Vector4(10, 4, 10, 4)))
	b.add_theme_color_override("font_color", side.lightened(0.2))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	var q: Dictionary = on_quote.call(cid, fraction, buy)
	if bool(q.get("ok", false)):
		b.tooltip_text = _t("stake_tip_" + ("buy" if buy else "sell")) % [db.percent(float(q["доля"])), db.money(float(q["amount"])),
			db.percent(absf(float(q["premium"])))]
	else:
		b.disabled = true
		b.tooltip_text = _t(str(q.get("why", "stake_nothing"))) + (" (%s)" % db.money(float(q["amount"])) if float(q.get("amount", 0.0)) > 0.0 else "")
	b.pressed.connect(func() -> void:
		on_trade.call(cid, fraction, buy)
		_dossier_tab = DOSSIER_TABS.find("owners")
		refresh())
	return b


func _tab_assets(c: Dictionary) -> Control:
	var v := _vbox(_t("dtab_assets"))
	for p in c.get("sites", []):
		if not (p is Dictionary):
			continue
		var pd: Dictionary = p
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var kind := _label(db.point_type_name(str(pd.get("type", ""))), GOLD if str(pd.get("type", "")) == "штаб" else DIM)
		kind.custom_minimum_size = Vector2(150, 0)
		row.add_child(kind)
		var place := VBoxContainer.new()
		place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		place.add_theme_constant_override("separation", 0)
		row.add_child(place)
		var cid := str(c["id"])
		var go := func() -> void: on_show_point.call(cid, pd)
		var addr := _link(db.text(pd.get("name", "")), Color(1, 1, 1, 1), go)
		addr.tooltip_text = _t("go_to_point")
		place.add_child(addr)
		var prov := _link("📍 " + db.province_name(int(pd.get("province", 0))), DIM, go)
		prov.add_theme_font_size_override("font_size", 12)
		prov.tooltip_text = _t("go_to_point")
		place.add_child(prov)
		var idx := (c.get("sites", []) as Array).find(p)
		var stats := VBoxContainer.new()
		stats.add_theme_constant_override("separation", 0)
		row.add_child(stats)
		var people := _label(db.people(db.point_staff(c, idx)) + " " + _t("people_short"), DIM)
		people.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats.add_child(people)
		if conditions != null:
			var dots := HBoxContainer.new()
			dots.add_theme_constant_override("separation", 4)
			var owner := Data.owner_in(Data.province_owners(), int(pd.get("province", -1)))
			var where := owner if db.countries.has(owner) else str(c.get("_country", ""))
			for vname in Conditions.LOCAL:
				var x := conditions.at(vname, int(pd.get("province", -1)), where)
				var col := UP if x >= 0.6 else (GOLD if x >= 0.3 else DOWN)
				var dot := UiStyle.pill(_t("cond_short_" + vname), col)
				dot.tooltip_text = "%s: %d" % [_t("cond_v_" + vname), roundi(x * 100.0)]
				dots.add_child(dot)
			place.add_child(dots)
		var e := db.econ(c)
		if not e.is_empty():
			var h := db.point_satisfaction(c, idx)
			var mood: Label
			if db.point_striking(c, idx):
				mood = _label("⚠ " + _t("on_strike"), DOWN)
			else:
				mood = _label(_t("sat_level_%d" % clampi(int(h * 5.0), 0, 4)), DOWN.lerp(UP, h))
			mood.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			mood.add_theme_font_size_override("font_size", 12)
			stats.add_child(mood)
	var sites: Array = c.get("промыслы", [])
	if not sites.is_empty():
		v.add_child(HSeparator.new())
		v.add_child(_label(_t("extraction_linked"), GOLD))
		for s in sites:
			v.add_child(_label("⛏ " + str(s)))
	var subs: Array = db.companies.filter(func(o): return _owns(o, str(c["id"])))
	if not subs.is_empty():
		v.add_child(HSeparator.new())
		v.add_child(_label(_t("subsidiaries"), GOLD))
		for s in subs:
			var b := Button.new()
			b.flat = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.focus_mode = Control.FOCUS_NONE
			b.text = "→ " + db.name_of(s)
			var sid := str(s["id"])
			b.pressed.connect(func() -> void: open_company(sid))
			v.add_child(b)
	return v


func _owns(o: Dictionary, parent_id: String) -> bool:
	for h in o.get("owners", []):
		if h is Dictionary and str((h as Dictionary).get("company", "")) == parent_id and float((h as Dictionary).get("доля", 0.0)) > 0.5:
			return true
	return false


func _tab_chronicle(c: Dictionary) -> Control:
	var v := _vbox(_t("dtab_chronicle"))
	var entries: Array = c.get("_chronicle", [])
	for i in range(entries.size() - 1, maxi(-1, entries.size() - 1 - CHRONICLE_ROWS), -1):
		var e: Dictionary = entries[i]
		var when := _date_of(int(e.get("день", 0)))
		var text := chron_text(c, e)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		var d := _label(when, DIM)
		d.custom_minimum_size = Vector2(90, 0)
		row.add_child(d)
		row.add_child(_label(text))
	var lead: Dictionary = c.get("глава", {})
	v.add_child(_label(_t("chron_head") % [int(lead.get("с_года", 0)), db.text(lead.get("name", ""))], DIM))
	for past in c.get("former_heads", []):
		# Heads replaced during the game (lifecycle.gd).
		var pd: Dictionary = past
		v.add_child(_label(_t("chron_past_head") % [db.text(pd.get("name", "")), _date_of(int(pd.get("until_day", 0))),
			_t("head_why_" + str(pd.get("почему", "")))], DIM))
	v.add_child(_label(_t("chron_founded") % int(c.get("founded", 0)), DIM))
	return v


## One chronicle line in the player's language (entries keep numbers and site indexes, not text).
func chron_text(c: Dictionary, e: Dictionary) -> String:
	if e.has("ии"):
		return str(e["ии"])   # the game's AI explained it (narrator.gd)
	var pts: Array = c.get("sites", [])
	var i := int(e.get("site", -1))
	var place := db.text((pts[i] as Dictionary).get("name", "")) if i >= 0 and i < pts.size() else ""
	var n := db.people(float(e.get("count_value", 0.0)))
	var share := db.percent(float(e.get("доля", 0.0)))
	match str(e.get("вид", "")):
		"price":
			var x := float(e.get("change", 0.0))
			return (_t("chron_up") if x > 0.0 else _t("chron_down")) % db.percent(absf(x))
		"strike":
			return _t("chron_strike") % [place, n]
		"забастовка_конец":
			return _t("chron_strike_end") % place
		"уступка":
			return _t("chron_concession") % [place, share]
		"layoffs":
			return _t("chron_layoffs") % [n, share]
		"набор":
			return _t("chron_hiring") % n
		"wage":
			return _t("chron_raise") % share
		"событие":
			# «Shares rose 12%: a large state contract» — what changed, how much, why (20.4).
			var up := bool(e.get("up", true))
			var what := _t("ev_%s_%s" % [str(e.get("что", "price")), "up" if up else "down"]) % share
			var why := _t(str(e.get("reason", "")))
			var line := "%s: %s" % [what, why]
			return ("🚀 " + line) if bool(e.get("shot", false)) else line
		"кризис":
			return _t("crisis_stage_%d" % int(e.get("stage", 0)))
		"ladder":
			var rung := int(e.get("ступень", 1))
			var why := grievance_text(str(e.get("grudge", "")))
			if rung in [4, 5]:
				return _t("chron_ladder_%d" % rung) % [n, why]
			return _t("chron_ladder_%d" % rung) % why
		"лестница_мир":
			return _t("chron_ladder_peace")
		"debt":
			var amount := db.money(float(e.get("count_value", 0.0)))
			var rate := db.percent(float(e.get("rate", 0.0)))
			var lender := db.text(e.get("creditor", ""))
			match str(e.get("что", "")):
				"рефинансирование", "срочный_кредит", "invest_loan":
					return _t("chron_debt_" + str(e["что"])) % [amount, rate]
				"дефолт":
					return _t("chron_debt_дефолт") % [amount, lender, share]
				"state_aid":
					var s := _t("chron_debt_state_aid") % amount
					return s + (_t("chron_debt_for_shares") % share if float(e.get("доля", 0.0)) > 0.0 else "")
				"owner_repaid", "write_off":
					return _t("chron_debt_" + str(e["что"])) % [lender, amount]
				"revaluation":
					return _t("chron_debt_revaluation") % [amount, share]
				_:
					return _t("chron_debt_" + str(e.get("что", ""))) % amount
		"похвала":
			return _t("chron_praise")
		"трудовой_закон":
			return _t("chron_labour_law") % [str(e.get("текст", "")), share]
		"приказ":
			# The player's orders (orders.gd).
			var what := str(e.get("что", ""))
			var money := db.money(float(e.get("count_value", 0.0)))
			match what:
				"nationalisation", "taxes":
					return _t("chron_ord_" + what) % money
				"confiscation", "rescue":
					return _t("chron_ord_" + what) % [share, money]
				"схема_успех":
					return _t("chron_ord_схема_успех") % str(e.get("name", ""))
				"дело":
					return _t("chron_ord_дело") % str(e.get("name", ""))
				_:
					return _t("chron_ord_" + what)
		"выкуп_акций":
			return _t("chron_buyback_" + str(e.get("что", "buyout"))) % [share, db.money(float(e.get("count_value", 0.0)))]
		"банкротство":
			match str(e.get("что", "")):
				"управляющий":
					return _t("chron_bankrupt_start") % int(e.get("weeks", 12))
				"продана":
					return _t("chron_bankrupt_sold") % [_name_of_id(str(e.get("rival", ""))), db.money(float(e.get("count_value", 0.0)))]
				"санация":
					return _t("chron_bankrupt_rescue") % db.money(float(e.get("count_value", 0.0)))
				_:
					return _t("chron_bankrupt_" + str(e.get("что", "")))
		"birth":
			return _t("chron_born_" + str(e.get("что", "обычно"))) % db.money(float(e.get("count_value", 0.0)))
		"слияние":
			var other := _name_of_id(str(e.get("rival", "")))
			return _t("chron_merge_" + str(e.get("что", ""))) % other
		"переезд":
			if str(e.get("что", "")) == "штаб":
				return _t("chron_moved_hq") % [str(e.get("откуда", "")), str(e.get("country", ""))]
			return _t("chron_moved_site") % [place, str(e.get("country", ""))]
		"смена_главы":
			return _t("chron_new_head") % [str(e.get("name", "")), _t("role_" + str(e.get("роль", ""))).to_lower(), _t("head_why_" + str(e.get("что", "")))]
		"война_страны":
			var what := str(e.get("что", ""))
			if what in ["frozen_f", "конфискована", "уничтожена", "возврат"]:
				return _t("chron_war_site_" + what) % [place, str(e.get("country", ""))]
			return _t("chron_war_hq_" + what) % str(e.get("country", ""))
		"antitrust":
			if str(e.get("что", "")) == "section":
				return _t("chron_am_split") % _name_of_id(str(e.get("rival", "")))
			return _t("chron_am_fine") % db.money(float(e.get("count_value", 0.0)))
		"переименование":
			return _t("chron_renamed") % [str(e.get("old_value", "")), str(e.get("новое", ""))]
		"ipo":
			return _t("chron_ipo") % [share, db.money(float(e.get("count_value", 0.0)))]
		"tree":
			match str(e.get("что", "")):
				"технология":
					return _t("chron_tree_tech") % str(e.get("текст", ""))
				"kickback":
					return _t("chron_tree_rollback") % str(e.get("текст", ""))
				"переезд":
					return _t("chron_tree_moved") % [str(e.get("country", "")), str(e.get("текст", ""))]
				_:
					return _t("chron_tree_node" if not bool(e.get("технология", false)) else "chron_tree_dev") % str(e.get("текст", ""))
		"возможность":
			return _t("chron_cap_" + str(e.get("что", "открыта"))) % str(e.get("текст", ""))
		"ии_событие":
			return str(e.get("текст", ""))
		"business_reaction":
			return _t("chron_business_tense") % [int(e.get("count_value", 0)), int(e.get("отрасль", 0)), maxi(1, roundi(absf(float(e.get("доля", 0.0))) * 100.0))]
		"tech_level":
			if str(e.get("что", "")) == "leader":
				return _t("chron_tl_leader") % db.sector_name(str(e.get("type", "")))
			return _t("chron_tl_step") % _t("tl_step_" + str(e.get("что", "")))
		"условия":
			var what := str(e.get("что", ""))
			if what in ["лучше", "хуже"]:
				if e.has("reason"):
					# «Энергия, Подмосковье: 18 → 45 — похоже, запустили новую ЛЭП; акции +6%»
					var dir := "up" if int(e.get("стало", 0)) >= int(e.get("было", 0)) else "down"
					return _t("chron_cond_cause") % [_t("cond_v_" + str(e["reason"])), str(e.get("province", "")), int(e.get("было", 0)), int(e.get("стало", 0)),
						_t("cond_cause_" + str(e["reason"]) + "_" + dir), db.percent(float(e.get("shares", 0.0)), true)]
				return _t("chron_cond_" + what) % [db.percent(absf(float(e.get("count_value", 0.0)))), _t("cond_v_" + str(e.get("main_flag", "roads"))).to_lower()]
			if what.begins_with("конец_"):
				return _t("chron_cond_end_" + what.substr(6))
			return _t("chron_cond_" + what) % place
		"рамка":
			var now_t := _t(Frames.label_key(str(e.get("стало", ""))))
			var was_t := _t(Frames.label_key(str(e.get("было", ""))))
			return _t("chron_frame_up") % now_t if bool(e.get("up", true)) else _t("chron_frame_down") % [was_t, now_t]
		"scandal":
			var who := str(e.get("name", ""))
			return _t("chron_scandal") % db.money(float(e.get("count_value", 0.0))) + (_t("chron_scandal_resigned") % who if not who.is_empty() else "")
		"arena":
			if str(e.get("что", "")) == "санкции":
				return _t("chron_arena_sanctions") % str(e.get("country", ""))
			return _t("chron_arena_spy_gain") % _name_of_id(str(e.get("rival", "")))
		"письмо":
			if str(e.get("что", "")) == "завод":
				return _t("chron_letter_завод") % [db.money(float(e.get("count_value", 0.0))), str(e.get("country", ""))]
			return _t("chron_letter_" + str(e.get("что", ""))) % db.money(float(e.get("count_value", 0.0)))
		"state_stake":
			return _t("chron_stake_" + ("buy" if str(e.get("что", "")) == "buyout" else "sell")) % [
				str(e.get("country", "")), share, db.money(float(e.get("count_value", 0.0)))]
		"founding":
			return _t("chron_founded_by_player") % db.money(float(e.get("count_value", 0.0)))
		"startup_done":
			return _t("chron_startup_done")
		"state_goal":
			# What a state decided (state_goals.gd), from this company's side: it gains or loses by it.
			var target := str(e.get("goods", ""))
			var goods_name := db.text((((db.goods.get("goods", {}) as Dictionary).get(target, {}) as Dictionary).get("name", target))) if not target.is_empty() else ""
			var line := _t("goal_%s_%s" % [str(e.get("что", "")), "up" if bool(e.get("mine_up", true)) else "down"])
			return line % ([str(e.get("country", "")), goods_name].slice(0, line.count("%s")))
		"expansion":
			if str(e.get("что", "")) == "start":
				return _t("chron_expansion_start") % [db.money(float(e.get("count_value", 0.0))), str(int(e.get("weeks", 0)))]
			if not place.is_empty():
				return _t("chron_expansion_site") % [db.money(float(e.get("count_value", 0.0))), share, place]
			return _t("chron_expansion_done") % [db.money(float(e.get("count_value", 0.0))), share]
		"competition":
			# Stage 3 (rivals.gd): a move against a rival, told from both sides.
			var rival := _name_of_id(str(e.get("rival", "")))
			var what := str(e.get("что", ""))
			var money := db.money(float(e.get("count_value", 0.0)))
			if bool(e.get("против", false)):
				match what:
					"переманивание":
						return _t("chron_comp_against_переманивание") % [rival, n]
					"иск":
						return _t("chron_comp_against_иск") % [rival, money]
					_:
						return _t("chron_comp_against_" + what) % rival
			match what:
				"реклама":
					return _t("chron_comp_реклама")
				"переманивание":
					return _t("chron_comp_переманивание") % [n, rival]
				_:
					return _t("chron_comp_" + what) % rival
		"война":
			match str(e.get("что", "")):
				"начало":
					return _t("chron_war_start") % _name_of_id(str(e.get("rival", "")))
				"конец":
					return _t("chron_war_end") % [_name_of_id(str(e.get("rival", ""))), int(e.get("weeks", 0))]
				_:
					return _t("chron_war_diplomacy") % str(e.get("country", ""))
		"takeover":
			var rival := _name_of_id(str(e.get("rival", "")))
			var tail := (_t("ma_control") if bool(e.get("control", false)) else "") + (_t("ma_hostile") if bool(e.get("hostile", false)) else "")
			match str(e.get("что", "")):
				"купила":
					return _t("chron_ma_bought") % [share, rival, db.money(float(e.get("count_value", 0.0)))] + tail
				"куплена":
					return _t("chron_ma_sold") % [rival, share, db.money(float(e.get("count_value", 0.0)))] + tail
				"ban":
					return _t("chron_ma_banned") % rival
				"запрет_власти":
					return _t("chron_ma_banned_state") % [str(e.get("country", "")), rival]
				"рыцарь_перебил":
					return _t("chron_ma_knight_beat") % [rival, _name_of_id(str(e.get("knight", "")))]
				"белый_рыцарь":
					return _t("chron_ma_white_knight") % [rival, share, db.money(float(e.get("count_value", 0.0)))]
				"repelled":
					return _t("chron_ma_repelled") % rival
				_:
					return _t("chron_ma_banned_target") % rival
		"breakup":
			var other := _name_of_id(str(e.get("rival", "")))
			match str(e.get("что", "")):
				"новая":
					return _t("chron_split_new") % [other, share]
				"antitrust":
					return _t("chron_split_regulator") % [share, other]
				_:
					return _t("chron_split") % [share, other]
	return str(e.get("текст", ""))


# ---------- why the staff are the way they are ----------

## A window that explains the company's people: satisfaction and its parts, wages and the wage policy,
## who came and went and why, layoffs and restructuring, strikes and the sites at risk, what rivals did.
## Everything is read from the same numbers economy.gd uses (config «сотрудники»).
func _explain_staff(c: Dictionary) -> void:
	var layer: Variant = game.hud_layer() if game != null else null
	var host: Node = layer as Node if layer is Node else self
	var ask := Callable()
	if on_ask_ai.is_valid() and ai_available.is_valid() and bool(ai_available.call()):
		var text := staff_explanation(c)
		ask = func() -> void: on_ask_ai.call(_t("staff_ai_q") % [db.name_of(c), str(c.get("_country", ""))] + "\n" + _strip_bbcode(text))
	var w := StaffWhy.new()
	w.open(host, staff_data(c), _t, ask)


## The numbers of «Почему так?» for staff_why.gd — the same that economy.gd uses (config «сотрудники»).
func staff_data(c: Dictionary) -> Dictionary:
	var e := db.econ(c)
	var cfg: Dictionary = db.balance.get("staff", {})
	var n := float(e.get("N", 0.0))
	var h := float(e.get("H", 0.5))
	var w := float(e.get("W", 0.0))
	var market := maxf(float(e.get("market_wage", 1.0)), 1.0)
	var avg := float(db.country_info(str(c.get("_country", ""))).get("average_wage", 1000.0))
	var ratio := w / market
	var margin := float(e.get("P", 0.0)) / maxf(float(e.get("R", 1.0)), 1.0)
	var need := float(e.get("нужно", n))
	var vacancy := (need - n) / maxf(need, 1.0)
	var parts: Array = []
	for p in e.get("satisfaction_parts", []):
		var key := str(p[0])
		if key == "base":
			continue
		var val := float(p[1]) * 100.0
		parts.append([_t("sat_" + key).capitalize(), val, _t("sw_part_" + key + ("_up" if val >= 0.0 else "_down"))])
	var pay_lines: PackedStringArray = [_t("sw_wage_market") % [db.people(market), db.sector_name(str(c.get("sector", "")))]]
	if vacancy > float(cfg.get("vacancy_threshold", 0.03)) and margin > 0.05:
		pay_lines.append(_t("sw_policy_raise") % [db.percent(vacancy), db.percent(float(cfg.get("raise_on_vacancies", 0.004)))])
	elif margin > 0.0:
		pay_lines.append(_t("sw_policy_index") % db.percent(float(cfg.get("wage_inflation", 0.04))))
	else:
		pay_lines.append(_t("sw_policy_freeze"))
	if w >= market * 3.0:
		pay_lines.append(_t("sw_policy_cap"))
	var came := 0.0
	var left := 0.0
	var fired := 0.0
	var flows: Array = e.get("flows", [])
	for i in range(maxi(0, flows.size() - 4), flows.size()):
		came += float(flows[i][0])
		left += float(flows[i][1])
		fired += float(flows[i][2])
	var people_lines: PackedStringArray = []
	var quit_week := float(cfg.get("exit_base", 0.0015)) * (1.0 + float(cfg.get("exit_discontent", 3.0)) * pow(1.0 - h, 2.0)) / clampf(ratio, 0.5, 2.0)
	people_lines.append(_t("sw_quits") % [db.percent(quit_week * 52.0), _t("sw_quits_why_" + ("pay" if ratio < 0.9 else ("mood" if h < 0.45 else "normal")))])
	if vacancy > 0.005:
		var attract := clampf(ratio * ratio * (0.5 + h), 0.1, 3.0)
		people_lines.append(_t("sw_vacancies") % [db.people(need - n), db.percent(vacancy), _t("sw_attract_" + ("good" if attract >= 1.0 else "poor"))])
	elif n > need * (1.0 + float(cfg.get("surplus", 0.06))):
		people_lines.append(_t("sw_excess") % db.people(n - need))
	else:
		people_lines.append(_t("sw_balanced"))
	if margin < float(cfg.get("loss_threshold", -0.03)):
		people_lines.append(_t("sw_loss") % [db.percent(margin), db.percent(float(cfg.get("layoff_share", 0.015)))])
	if float(e.get("план", 1.0)) < 0.999:
		people_lines.append(_t("sw_plan") % db.percent(1.0 - float(e.get("план", 1.0))))
	var demand_m := float(e.get("market_demand", 1.0)) * float(e.get("crisis_demand", 1.0)) * float(e.get("event_demand", 1.0)) * float(e.get("climate_demand", 1.0))
	if absf(demand_m - 1.0) > 0.03:
		people_lines.append(_t("sw_demand_" + ("up" if demand_m > 1.0 else "down")) % db.percent(demand_m - 1.0, true))
	var thr := float(cfg.get("strike_threshold", 0.3))
	var strikes: Array = e.get("strikes", [])
	var pts: Array = c.get("sites", [])
	var strike_lines: PackedStringArray = []
	if strikes.is_empty():
		strike_lines.append(_t("sw_strikes_none"))
	for s in strikes:
		var sd: Dictionary = s
		var i := int(sd.get("site", -1))
		var place := db.text((pts[i] as Dictionary).get("name", "")) if i >= 0 and i < pts.size() else "?"
		strike_lines.append(_t("sw_strike_" + ("sabotage" if bool(sd.get("sabotage", false)) else "site")) % [place, db.people(float(sd.get("людей", 0.0))), int(sd.get("weeks", 0))])
	var risky: PackedStringArray = []
	for i in pts.size():
		var hs := db.point_satisfaction(c, i)
		if hs < thr + 0.1:
			risky.append("%s (%s)" % [db.text((pts[i] as Dictionary).get("name", "")), db.percent(hs)])
	var recent: Array = []
	var chron: Array = c.get("_chronicle", [])
	for i in range(chron.size() - 1, -1, -1):
		var entry: Dictionary = chron[i]
		if int(entry.get("день", 0)) < game.day() - 56 or recent.size() >= 8:
			break
		var kind := str(entry.get("вид", ""))
		if kind in ["layoffs", "набор", "wage", "strike", "забастовка_конец", "уступка", "ladder"] \
				or (kind == "competition" and str(entry.get("что", "")) in ["переманивание", "силовое"]):
			recent.append(chron_text(c, entry))
	var pop_q := 0.0
	for p in e.get("popularity_parts", []):
		if str(p[0]) == "quality":
			pop_q = float(p[1])
	return {"company": db.name_of(c), "satisfaction": h, "satisfaction_word": _t("sat_level_%d" % clampi(int(h * 5.0), 0, 4)),
		"wage_to_market": ratio, "поток": {"arrived": came, "left": left, "fired": fired}, "strike_count": strikes.size(),
		"parts": parts, "wages": {"company": w, "рынок": market, "country": avg}, "wage_rows": pay_lines,
		"people_rows": people_lines, "strike_rows": strike_lines,
		"риск": _t("sw_risk") % [db.percent(thr), ", ".join(risky)] if not risky.is_empty() else _t("sw_risk_none") % db.percent(thr),
		"недавно": recent,
		"means": _t("sw_effect") % [_signed_pts(pop_q), db.percent(minf(1.0, float(e.get("offer", 1.0)) / maxf(float(e.get("demand_money", 1.0)), 1e-6)))],
		"humans": func(x: float) -> String: return db.people(x)}


func staff_explanation(c: Dictionary) -> String:
	var e := db.econ(c)
	var cfg: Dictionary = db.balance.get("staff", {})
	var out: PackedStringArray = []
	var n := float(e.get("N", 0.0))
	var h := float(e.get("H", 0.5))
	var w := float(e.get("W", 0.0))
	var market := maxf(float(e.get("market_wage", 1.0)), 1.0)
	var avg := float(db.country_info(str(c.get("_country", ""))).get("average_wage", 1000.0))
	var ratio := w / market
	var margin := float(e.get("P", 0.0)) / maxf(float(e.get("R", 1.0)), 1.0)
	var need := float(e.get("нужно", n))
	var vacancy := (need - n) / maxf(need, 1.0)

	# 1. Mood.
	out.append("[b]" + _t("sw_mood") % [db.percent(h), _t("sat_level_%d" % clampi(int(h * 5.0), 0, 4))] + "[/b]")
	for p in e.get("satisfaction_parts", []):
		var key := str(p[0])
		var val := float(p[1]) * 100.0
		if key == "base":
			continue
		out.append("   %s %s — %s" % [_signed_pts(val), _t("sat_" + key), _t("sw_part_" + key + ("_up" if val >= 0.0 else "_down"))])
	# 2. Wages.
	out.append("")
	out.append("[b]" + _t("sw_wage") % [db.people(w), db._num(ratio, 2), db._num(w / maxf(avg, 1.0), 2)] + "[/b]")
	out.append("   " + _t("sw_wage_market") % [db.people(market), db.sector_name(str(c.get("sector", "")))])
	if vacancy > float(cfg.get("vacancy_threshold", 0.03)) and margin > 0.05:
		out.append("   " + _t("sw_policy_raise") % [db.percent(vacancy), db.percent(float(cfg.get("raise_on_vacancies", 0.004)))])
	elif margin > 0.0:
		out.append("   " + _t("sw_policy_index") % db.percent(float(cfg.get("wage_inflation", 0.04))))
	else:
		out.append("   " + _t("sw_policy_freeze"))
	if w >= market * 3.0:
		out.append("   " + _t("sw_policy_cap"))
	# 3. Who came and went.
	var came := 0.0
	var left := 0.0
	var fired := 0.0
	var flows: Array = e.get("flows", [])
	for i in range(maxi(0, flows.size() - 4), flows.size()):
		came += float(flows[i][0])
		left += float(flows[i][1])
		fired += float(flows[i][2])
	out.append("")
	out.append("[b]" + _t("sw_flows") % [db.people(came), db.people(left), db.people(fired)] + "[/b]")
	var quit_week := float(cfg.get("exit_base", 0.0015)) * (1.0 + float(cfg.get("exit_discontent", 3.0)) * pow(1.0 - h, 2.0)) / clampf(ratio, 0.5, 2.0)
	out.append("   " + _t("sw_quits") % [db.percent(quit_week * 52.0), _t("sw_quits_why_" + ("pay" if ratio < 0.9 else ("mood" if h < 0.45 else "normal")))])
	if vacancy > 0.005:
		var attract := clampf(ratio * ratio * (0.5 + h), 0.1, 3.0)
		out.append("   " + _t("sw_vacancies") % [db.people(need - n), db.percent(vacancy), _t("sw_attract_" + ("good" if attract >= 1.0 else "poor"))])
	elif n > need * (1.0 + float(cfg.get("surplus", 0.06))):
		out.append("   " + _t("sw_excess") % db.people(n - need))
	else:
		out.append("   " + _t("sw_balanced"))
	if margin < float(cfg.get("loss_threshold", -0.03)):
		out.append("   " + _t("sw_loss") % [db.percent(margin), db.percent(float(cfg.get("layoff_share", 0.015)))])
	if float(e.get("план", 1.0)) < 0.999:
		out.append("   " + _t("sw_plan") % db.percent(1.0 - float(e.get("план", 1.0))))
	var demand_m := float(e.get("market_demand", 1.0)) * float(e.get("crisis_demand", 1.0)) * float(e.get("event_demand", 1.0)) * float(e.get("climate_demand", 1.0))
	if absf(demand_m - 1.0) > 0.03:
		out.append("   " + _t("sw_demand_" + ("up" if demand_m > 1.0 else "down")) % db.percent(demand_m - 1.0, true))
	# 4. Strikes and sites.
	out.append("")
	var thr := float(cfg.get("strike_threshold", 0.3))
	var strikes: Array = e.get("strikes", [])
	var pts: Array = c.get("sites", [])
	out.append("[b]" + (_t("sw_strikes_now") % strikes.size() if not strikes.is_empty() else _t("sw_strikes_none")) + "[/b]")
	for s in strikes:
		var sd: Dictionary = s
		var i := int(sd.get("site", -1))
		var place := db.text((pts[i] as Dictionary).get("name", "")) if i >= 0 and i < pts.size() else "?"
		out.append("   " + _t("sw_strike_" + ("sabotage" if bool(sd.get("sabotage", false)) else "site")) % [place, db.people(float(sd.get("людей", 0.0))), int(sd.get("weeks", 0))])
	var risky: PackedStringArray = []
	for i in pts.size():
		var hs := db.point_satisfaction(c, i)
		if hs < thr + 0.1:
			risky.append("%s (%s)" % [db.text((pts[i] as Dictionary).get("name", "")), db.percent(hs)])
	out.append("   " + (_t("sw_risk") % [db.percent(thr), ", ".join(risky)] if not risky.is_empty() else _t("sw_risk_none") % db.percent(thr)))
	# 5. The last weeks' chronicle about people.
	var recent: PackedStringArray = []
	var chron: Array = c.get("_chronicle", [])
	for i in range(chron.size() - 1, -1, -1):
		var entry: Dictionary = chron[i]
		if int(entry.get("день", 0)) < game.day() - 56 or recent.size() >= 8:
			break
		var kind := str(entry.get("вид", ""))
		if kind in ["layoffs", "набор", "wage", "strike", "забастовка_конец", "уступка", "ladder"] \
				or (kind == "competition" and str(entry.get("что", "")) in ["переманивание", "силовое"]):
			recent.append("   • " + chron_text(c, entry))
	if not recent.is_empty():
		out.append("")
		out.append("[b]" + _t("sw_recent") + "[/b]")
		out.append_array(recent)
	# 6. What it means.
	out.append("")
	var pop_q := 0.0
	for p in e.get("popularity_parts", []):
		if str(p[0]) == "quality":
			pop_q = float(p[1])
	out.append(_t("sw_effect") % [_signed_pts(pop_q), db.percent(minf(1.0, float(e.get("offer", 1.0)) / maxf(float(e.get("demand_money", 1.0)), 1e-6)))])
	return "\n".join(out)


func _signed_pts(x: float) -> String:
	return ("+" if x >= 0.0 else "−") + db._num(absf(x), 0)


static func _strip_bbcode(s: String) -> String:
	return s.replace("[b]", "").replace("[/b]", "")


# ---------- founding a company ----------

## The dialog: goods (industry), name, description, capital, the place of the headquarters; below — what the
## analysts expect (revenue, people, wages, shares) from the market and the country's situation, live.
func open_founding() -> void:
	if not on_found.is_valid():
		return
	if not _found.is_empty() and is_instance_valid(_found["dlg"]):
		(_found["dlg"] as Window).popup_centered()
		return
	var info: Dictionary = founding_info.call()
	var dlg := ConfirmationDialog.new()
	dlg.title = _t("found_title")
	dlg.ok_button_text = _t("found_ok")
	dlg.cancel_button_text = _t("found_cancel")
	dlg.min_size = Vector2i(560, 0)
	dlg.dialog_hide_on_ok = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	dlg.add_child(v)
	v.add_child(_label(_t("found_form_state") if bool(info["polity"]) else _t("found_form_person") % str(info["name"]), GOLD))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = _t("found_name_ph")
	v.add_child(_field(_t("found_name"), name_edit))
	var goods_sel := OptionButton.new()
	var keys: Array = (db.goods.get("goods", {}) as Dictionary).keys()
	for k in keys:
		goods_sel.add_item(db.text(((db.goods["goods"] as Dictionary)[k] as Dictionary).get("name", k)))
	v.add_child(_field(_t("found_goods"), goods_sel))
	var desc := TextEdit.new()
	desc.placeholder_text = _t("found_desc_ph")
	desc.custom_minimum_size = Vector2(0, 60)
	desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(_field(_t("found_desc"), desc))
	var money := float(info["money"])
	var cap := SpinBox.new()
	cap.min_value = 1.0
	cap.max_value = maxf(1.0, money)
	cap.step = 1.0
	cap.value = clampf(roundf(money * 0.02), 1.0, maxf(1.0, money))
	cap.suffix = _t("found_mln")
	cap.custom_minimum_size = Vector2(160, 0)
	var cap_row := HBoxContainer.new()
	cap_row.add_theme_constant_override("separation", 6)
	cap_row.add_child(cap)
	for f in [0.01, 0.05, 0.1]:
		var q := Button.new()
		q.text = db.percent(float(f))
		q.tooltip_text = _t("found_share_tip")
		q.focus_mode = Control.FOCUS_NONE
		q.pressed.connect(func() -> void: cap.value = maxf(1.0, roundf(money * float(f))))
		cap_row.add_child(q)
	cap_row.add_child(_label(_t("found_treasury") % db.money(money), DIM))
	v.add_child(_field(_t("found_capital"), cap_row))
	var place_row := HBoxContainer.new()
	var place_l := _label("")
	place_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place_row.add_child(place_l)
	var pick := Button.new()
	pick.text = "🗺 " + _t("found_pick")
	pick.focus_mode = Control.FOCUS_NONE
	place_row.add_child(pick)
	v.add_child(_field(_t("found_place"), place_row))
	var ask := CheckBox.new()
	ask.text = _t("found_ask_ai")
	ask.button_pressed = true
	v.add_child(ask)
	v.add_child(HSeparator.new())
	var preview := _label("", Color(1, 1, 1, 0.9))
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.custom_minimum_size = Vector2(520, 0)
	v.add_child(preview)
	var err := _label("", DOWN)
	err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(err)
	_found = {"dlg": dlg, "place": info.get("место", {}), "keys": keys}
	var update := func() -> void:
		var place: Dictionary = _found["place"]
		place_l.text = str(place.get("name_ru" if db.lang() == "ru" else "имя_en", "—")) + (" (%s)" % str(place.get("country", "")) if not place.is_empty() else "")
		var country := str(place.get("country", info["country"]))
		var p: Dictionary = on_found_preview.call(str(keys[goods_sel.selected]), cap.value, country)
		preview.text = _founding_preview_text(p, cap.value, country)
	name_edit.text_changed.connect(func(_t2: String) -> void: err.text = "")
	goods_sel.item_selected.connect(func(_i: int) -> void: update.call())
	cap.value_changed.connect(func(_x: float) -> void: update.call())
	pick.pressed.connect(func() -> void:
		dlg.hide()
		on_pick_place.call(func(place: Dictionary) -> void:
			if not place.is_empty():
				_found["place"] = place
			update.call()
			dlg.popup_centered()))
	dlg.confirmed.connect(func() -> void:
		var spec := {"название": name_edit.text, "description": desc.text.strip_edges(), "goods_key": str(keys[goods_sel.selected]),
			"capital": cap.value, "место": _found["place"], "ask_ai_flag": ask.button_pressed}
		var result: String = on_found.call(spec)
		if result.is_empty():
			dlg.hide()
			dlg.queue_free()
			_found = {}
		else:
			err.text = result)
	dlg.canceled.connect(func() -> void:
		dlg.queue_free()
		_found = {})
	add_child(dlg)
	update.call()
	dlg.popup_centered()


func _field(title: String, control: Control) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := _label(title, DIM)
	l.custom_minimum_size = Vector2(150, 0)
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h


func _founding_preview_text(p: Dictionary, capital: float, country: String) -> String:
	if not bool(p.get("ok", false)):
		return _t(str(p.get("why", "found_err_capital")))
	var lines: PackedStringArray = [_t("found_pv_title")]
	lines.append(_t("found_pv_market") % [db.money(float(p["рынок"])), db.percent(float(p["доля"])), db.percent(float(p["export"]))])
	lines.append(_t("found_pv_revenue") % [db.money(float(p["выручка"])), db.money(float(p["profit"])), db.percent(float(p["margin"]))])
	lines.append(_t("found_pv_people") % [db.people(float(p["staff"])), db.people(float(p["wage"]))])
	lines.append(_t("found_pv_shares") % [db._num(float(p["shares_mln"]), 2), db.money_price(float(p["price"])), db.money(capital)])
	lines.append(_t("found_pv_money") % [db.money(float(p["invested"])), db.money(float(p["money"]))])
	var ex := float(p.get("обстановка", 0.0))
	lines.append(_t("found_pv_situation") % [country, _signed(ex)])
	return "\n".join(lines)


## The world's situation for a company in a few words (for the assistant).
func situation_text(c: Dictionary) -> String:
	var parts: Dictionary = (c.get("_climate", {}) as Dictionary).get("parts", {})
	var sit: PackedStringArray = []
	for ev in parts.keys():
		sit.append("%s %s" % [_t("event_" + str(ev)), _signed(float(parts[ev]))])
	return ", ".join(sit) if not sit.is_empty() else _t("situation_calm")


# ---------- the game's AI assistant ----------

## The assistant offers to explain a share price move; «yes» sends it the question with the company's facts.
func _offer_ai(c: Dictionary) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = _t("ai_title")
	dlg.dialog_text = _t("ai_offer") % [db.name_of(c), db.percent(db.change(c, 4), true)]
	dlg.dialog_autowrap = true
	dlg.min_size = Vector2i(420, 0)
	dlg.ok_button_text = _t("ai_yes")
	dlg.cancel_button_text = _t("ai_no")
	dlg.confirmed.connect(func() -> void: on_ask_ai.call(_ai_question(c)))
	dlg.visibility_changed.connect(func() -> void:
		if not dlg.visible:
			dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()


## The question with what the mod knows: price, money, the world's situation, the market, people, debt,
## rivals and the chronicle of the last four weeks — so the answer rests on the game's facts.
func _ai_question(c: Dictionary) -> String:
	var e := db.econ(c)
	var h := db.history(c)
	var before := float(h[maxi(0, h.size() - 5)]) if not h.is_empty() else db.price(c)
	var lines: PackedStringArray = []
	lines.append(_t("ai_q_head") % [db.name_of(c), str(c.get("_country", "")), db.sector_name(str(c.get("sector", ""))),
		db.percent(db.change(c, 4), true)])
	lines.append(_t("ai_q_price") % [db.money_price(before), db.money_price(db.price(c)), db.money(db.cap(c)), db.percent(db.change(c, 52), true)])
	lines.append(_t("ai_q_money") % [db.money(db.fund(c, "выручка")), db.money(db.fund(c, "profit")), db.money(db.fund(c, "debt")), str(c.get("_rating", ""))])
	var parts: Dictionary = (c.get("_climate", {}) as Dictionary).get("parts", {})
	var sit: PackedStringArray = []
	for ev in parts.keys():
		sit.append("%s %s" % [_t("event_" + str(ev)), _signed(float(parts[ev]))])
	lines.append(_t("ai_q_situation") % (", ".join(sit) if not sit.is_empty() else _t("situation_calm")))
	if not e.is_empty():
		lines.append(_t("ai_q_people") % [db.people(db.staff(c)), db.percent(float(e.get("H", 0.5))), (e.get("strikes", []) as Array).size(),
			db.percent(float(e.get("W", 0.0)) / maxf(float(e.get("market_wage", 1.0)), 1.0) - 1.0, true)])
		if e.has("market_home"):
			lines.append(_t("ai_q_market") % [goods.goods_name(db, c) if goods != null else "", db.percent(float(e.get("home_share_mod", 0.0))),
				roundi(float(e.get("popularity", 50.0))), db.percent(float(e.get("market_demand", 1.0)) - 1.0, true)])
	if events != null and int(events.crisis.get("stage", 0)) > 0:
		lines.append(_t("ai_q_crisis") % _t("crisis_stage_%d" % int(events.crisis["stage"])))
	if rivals != null:
		for w in rivals.wars_of(str(c["id"])):
			var other := str(w["b"]) if str(w["a"]) == str(c["id"]) else str(w["a"])
			lines.append(_t("ai_q_war") % [_name_of_id(other), int(w["weeks"])])
	var recent: PackedStringArray = []
	var chron: Array = c.get("_chronicle", [])
	for i in range(chron.size() - 1, -1, -1):
		var entry: Dictionary = chron[i]
		if int(entry.get("день", 0)) < game.day() - 28 or recent.size() >= 8:
			break
		recent.append(chron_text(c, entry))
	lines.append(_t("ai_q_events") % ("; ".join(recent) if not recent.is_empty() else _t("ai_q_no_events")))
	lines.append(_t("ai_q_ask"))
	return "\n".join(lines)


func _name_of_id(cid: String) -> String:
	var c := db.company(cid)
	if c.is_empty() and db.gone.has(cid):
		return db.text((db.gone[cid] as Dictionary).get("название", cid))   # a company that left the game (lifecycle.gd)
	return db.name_of(c) if not c.is_empty() else cid


# ---------- helpers ----------

func _date_of(day: int) -> String:
	var now := game.date()
	var now_unix := Time.get_unix_time_from_datetime_dict({"year": int(now.get("year", 2026)),
		"month": int(now.get("month", 3)), "day": int(now.get("day", 1))})
	var d := Time.get_datetime_dict_from_unix_time(now_unix - (game.day() - day) * 86400)
	return "%02d.%02d.%d" % [int(d["day"]), int(d["month"]), int(d["year"])]


func _points_count(c: Dictionary) -> int:
	return (c.get("sites", []) as Array).size()


func _parts_text(parts: Variant, unit: String) -> String:
	var lines: PackedStringArray = []
	if parts is Array:
		for p in parts:
			var val := float(p[1])
			lines.append("%s%s%s  %s" % ["+" if val >= 0.0 else "−", db._num(absf(val), 1), unit, str(p[0])])
	return "\n".join(lines)


func _level_word(v: float) -> String:
	var i := clampi(int(v / 20.0), 0, 4)
	return _t("level_%d" % i)


func _vbox(_title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


func _scroll(content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 8)
	m.add_child(content)
	s.add_child(m)
	return s


func _label(text: String, color: Color = Color(1, 1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	if color != Color(1, 1, 1, 1):
		l.add_theme_color_override("font_color", color)
	return l


## Text that looks like a label but works like a link.
func _link(text: String, color: Color, on_press: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.pressed.connect(on_press)
	return b


## «Diamond status · 3rd in the world» (frames.gd).
func _frame_text(c: Dictionary) -> String:
	return _t("frame_line") % [_t(Frames.label_key(Frames.of(c))), int(c.get("_world_place", 0))] + Frames.why_line(c, _t)


func _frame_next(c: Dictionary) -> String:
	var n := Frames.to_next(c)
	return _t("frame_next") % n if n > 0 else _t("frame_top")


func _badge(c: Dictionary, d: float) -> Control:
	var big := Frames.of(c) == "diamond" or Frames.of(c) == "sapphire"
	var b := Charts.Badge.new(d * 1.4 if big else d)   # the crystal frames need room around the icon
	b.color = db.color_of(c)
	b.icon = db.icon_of(c)
	b.tier = Frames.of(c)
	if not b.tier.is_empty():
		b.tooltip_text = _frame_text(c)
		b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## A portrait placeholder: initials on the company colour (photos come in a later stage).
func _portrait(person: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.darkened(0.2)
	sb.set_corner_radius_all(24)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(48, 48)
	var initials := ""
	for part in person.split(" ", false):
		initials += part.substr(0, 1)
	var l := _label(initials.left(2))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	p.add_child(l)
	return p


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	return UiStyle.box(bg, border, 6, Vector4(8, 6, 8, 6))


## A clickable pill (a mover, a change that asks the AI): tinted with its colour, brighter under the mouse.
func _chip(text: String, col: Color, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", UiStyle.FS_SMALL + 1)
	for st in ["normal", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, UiStyle.box(Color(col, 0.14), Color(0, 0, 0, 0), 4, Vector4(6, 1, 6, 1)))
	b.add_theme_stylebox_override("hover", UiStyle.box(Color(col, 0.26), Color(col, 0.6), 4, Vector4(6, 1, 6, 1)))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, col)
	b.pressed.connect(on_press)
	return b


# ---------- the home and its screens (dashboard.gd) ----------

## World / My country on the home and its screens (kept between games).
func set_scope(s: String) -> void:
	scope = s
	mod.set_setting("dash_scope", s)
	if _screen == "list" and _current.is_empty():
		_tab = "country" if s == "country" else "world"
	refresh()


## A home tile opens its screen like an app on a phone: a glass card grows from the tile to the whole window.
func open_screen(key: String) -> void:
	if _animating or not SCREENS.has(key):
		return
	var tile: Variant = _home.tut.get(key)
	var from := (tile as Control).get_global_rect() if tile is Control else get_global_rect()
	_from = key
	_animating = true
	_grow(from, get_global_rect(), _tile_title(key), func() -> void:
		_screen = str(SCREENS[key])
		if key == "top":
			_current = ""
			_tab = "country" if scope == "country" else "world"
			_list_limit = LIST_PAGE
		refresh())


## ✕ of the dossier: the window closes from wherever it is; it opens again on the list.
func close_window() -> void:
	_current = ""
	refresh()
	if on_close.is_valid():
		on_close.call()
	elif is_instance_valid(panel):
		panel.hide()


## ✕: a screen folds back into its tile on the home; on the home ✕ closes the window.
func close_screen() -> void:
	if _animating:
		return
	if _screen == "home":
		if on_close.is_valid():
			on_close.call()
		elif is_instance_valid(panel):
			panel.hide()
		return
	_animating = true
	var ex := _expander_node()
	var full := get_global_rect()
	ex.position = full.position
	ex.size = full.size
	ex.modulate.a = 1.0
	_expander_title.text = _tile_title(_from)
	ex.visible = true
	_screen = "home"
	_current = ""
	refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	var tile: Variant = _home.tut.get(_from)
	var to := (tile as Control).get_global_rect() if tile is Control and is_instance_valid(tile) else Rect2(full.get_center(), Vector2(40, 40))
	var tw := ex.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ex, "position", to.position, 0.3)
	tw.tween_property(ex, "size", to.size, 0.3)
	tw.tween_property(ex, "modulate:a", 0.0, 0.12).set_delay(0.22)
	tw.chain().tween_callback(func() -> void:
		ex.visible = false
		_animating = false)


## A zone's screen (from the map's zone layer): straight there, the zone chosen.
func open_zone(id: String) -> void:
	zone_sel = id
	if _screen == "zones":
		refresh()
		return
	_from = "zones"
	_screen = "zones"
	_current = ""
	refresh()


## Back to the home without animation (the window opens on it).
func show_home() -> void:
	_screen = "home"
	_current = ""
	refresh()


func home_target(part: String) -> Control:
	var c: Variant = _home.tut.get(part)
	return c as Control if is_instance_valid(c) else null


## From the analytics screen to a list tab (the goods markets).
func open_list_tab(tab: String) -> void:
	_screen = "list"
	_current = ""
	_tab = tab
	refresh()


func _tile_title(key: String) -> String:
	match key:
		"top":
			return _t("dash_top_" + scope)
		"market":
			return _t("dash_market_" + scope)
		"news":
			return _t("dash_news")
		"deals":
			return _t("dash_deals")
		"zones":
			return _t("zones_title")
	return ""


func _expander_node() -> PanelContainer:
	if is_instance_valid(_expander):
		return _expander
	_expander = PanelContainer.new()
	_expander.top_level = true
	_expander.z_index = 60
	_expander.mouse_filter = Control.MOUSE_FILTER_STOP
	_expander.add_theme_stylebox_override("panel", UiStyle.box(Color(0.12, 0.2, 0.32, 0.97), Color(0.85, 0.93, 1.0, 0.45), 14, Vector4(0, 0, 0, 0)))
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_expander.add_child(cc)
	_expander_title = Label.new()
	_expander_title.add_theme_font_size_override("font_size", 16)
	_expander_title.add_theme_color_override("font_color", Color(UiStyle.TEXT, 0.9))
	cc.add_child(_expander_title)
	_expander.visible = false
	add_child(_expander)
	return _expander


func _grow(from: Rect2, to: Rect2, title: String, done: Callable) -> void:
	var ex := _expander_node()
	ex.position = from.position
	ex.size = from.size
	ex.modulate.a = 0.85
	_expander_title.text = title
	ex.visible = true
	var tw := ex.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ex, "position", to.position, 0.32)
	tw.tween_property(ex, "size", to.size, 0.32)
	tw.tween_property(ex, "modulate:a", 1.0, 0.12)
	tw.chain().tween_callback(func() -> void:
		done.call()
		var fade := ex.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fade.tween_property(ex, "modulate:a", 0.0, 0.18)
		fade.tween_callback(func() -> void:
			ex.visible = false
			_animating = false))
