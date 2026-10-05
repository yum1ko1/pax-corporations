extends VBoxContainer
## The home screen of the «Corporations» window — a glass dashboard (after the reference «research station»):
##   [ 3 · NEWS: the week's news with company icons + THE COMPANY OF THE WEEK: why, the AI's bulletin, 🎙 ] [ 4 · DEALS ]
##   [ 1 · TOP: badges in their frames, value, 4-week move, revenue, staff ] [ 2 · MARKET: charts to switch ] [ 5 · TRENDS ]
## A click on tiles 1–4 opens its screen with an «app» animation (ui_window.open_screen): 1 — the company lists,
## 2 — analytics, 3 — news, 4 — the week's top-20 deals; tile 5 pages by itself (every few seconds; after a manual
## flip it waits 10 s) — each card: a donut of the companies that make the sector's move and the reason.
## On top right — World / My country: every tile then shows only the player's country.
## The deals tile is never empty: the takeovers and breakups (rivals.gd) and the deals in the companies' chronicles
## (buybacks, sales, state stakes, nationalisations, mergers, IPOs, rescues…); a quiet week — the last month's, or
## the week's most shameful event; the featured one comes with its news and a quote of the company's head.
## The AI writes the week's bulletin on the company of the week and the head's quote (once a week, cached).

const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")   # Main's methods, 0.24 names
const UiStyle := preload("res://mods/pax_corporations/src/look/ui_style.gd")
const Charts := preload("res://mods/pax_corporations/src/market/charts.gd")
const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Guard := preload("res://mods/pax_corporations/src/news/news_guard.gd")
const Zones := preload("res://mods/pax_corporations/src/zones/zones.gd")
const VOICE_METHODS := ["сказать", "говорить", "озвучить", "произнести", "прочитать", "speak", "say", "talk"]
const DEAL_KINDS := ["выкуп_акций", "продана", "слияние", "ipo", "state_stake", "nationalisation", "confiscation", "rescue",
	"takeover", "купила", "белый_рыцарь", "рыцарь_перебил", "repelled", "breakup", "санация", "новая"]
const SHAME_KINDS := ["дефолт", "банкротство", "scandal", "дело", "confiscation"]
const CHARTS := ["cap", "state", "share"]
const AUTO_SEC := 7.0
const PAUSE_SEC := 10.0

static var _ai: Dictionary = {}       # "week|scope" -> {сводка, почему, цитата} from the AI
static var _asked: Dictionary = {}

var win: Object                   # ui_window.gd
var db: Data
var tut: Dictionary = {}          # tiles by key for the animation and the tutorial: news, deals, top, market, trends
var _card := 0                    # the trends carousel page
var _cards: Array = []
var _card_box: VBoxContainer
var _auto := 0.0
var _hold := 0.0
var _star_text: Label
var _founding := false            # the «Zones» screen shows the picker of a new union
var _leave_armed := ""            # «leave» pressed once for this zone — the second press confirms
var _quote_text: Label


func _t(key: String) -> String:
	return str(win.call("_t", key))


func setup(w: Object, data: Data) -> void:
	win = w
	db = data
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)


func _scope() -> String:
	return str(win.get("scope"))


func _country() -> String:
	return str(win.call("_player_country"))


func _day() -> int:
	return int(win.get("game").call("day"))


## The first week of a game: no weekly history yet — no news, no company of the week, no deals, no trends.
func fresh() -> bool:
	var most := 0
	for c in db.companies.slice(0, 60):
		most = maxi(most, db.history(c).size())
	return most < 2


func _first_week(v: Control) -> void:
	var l := _wrap(_t("dash_first_week"), UiStyle.DIM, 13)
	v.add_child(l)


## The companies of the scope: the world, or the player's country.
func companies() -> Array:
	if _scope() == "country":
		return db.companies.filter(func(c): return str(c.get("_country", "")) == _country())
	return db.companies


# ---------- building the home ----------

func build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	tut.clear()
	add_child(_top_bar(_t("dash_title"), false))
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 8)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(grid)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.3
	grid.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(right)
	var news := _tile_news()
	news.size_flags_stretch_ratio = 0.85
	left.add_child(news)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(row)
	var top := _tile_top()
	top.size_flags_stretch_ratio = 1.15
	row.add_child(top)
	row.add_child(_tile_market())
	right.add_child(_tile_deals())
	right.add_child(_tile_trends())
	_ask_ai()


## The bar on top of the home and of every screen: the title, World / My country, ?, ✕.
func _top_bar(title: String, detail: bool) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var t := Label.new()
	t.text = title.to_upper()
	t.add_theme_font_size_override("font_size", 20 if not detail else 17)
	t.add_theme_color_override("font_color", Color(UiStyle.TEXT, 0.92))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var zb := Button.new()
	zb.text = "🌐 " + _t("zones_title")
	zb.tooltip_text = _t("zones_open_tip")
	zb.focus_mode = Control.FOCUS_NONE
	zb.custom_minimum_size = Vector2(0, 30)
	zb.pressed.connect(func() -> void: win.call("open_screen", "zones"))
	h.add_child(zb)
	tut["zones"] = zb
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 0)
	h.add_child(seg)
	tut["scope"] = seg
	for s in ["world", "country"]:
		var b := Button.new()
		b.text = _t("dash_scope_" + s)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 30)
		var on: bool = _scope() == str(s)
		b.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.GOLD, 0.28) if on else UiStyle.PANEL, UiStyle.GOLD if on else UiStyle.LINE, 8, Vector4(12, 4, 12, 4)))
		var key := str(s)
		b.pressed.connect(func() -> void: win.call("set_scope", key))
		seg.add_child(b)
	var help := Button.new()
	help.text = "?"
	help.tooltip_text = _t("tut_mini_tip")
	help.focus_mode = Control.FOCUS_NONE
	help.custom_minimum_size = Vector2(30, 30)
	help.pressed.connect(func() -> void:
		var cb: Variant = win.get("on_tutorial")
		if cb is Callable and (cb as Callable).is_valid():
			# The tour of the screen that is open (on «Zones» it took the player back to the home for the home's tour).
			(cb as Callable).call("zones" if str(win.get("_screen")) == "zones" else "home"))
	h.add_child(help)
	h.move_child(help, 0)   # on the left, far from ✕ — not pressed by chance when closing
	tut["help"] = help
	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = _t("close_window_tip")
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(34, 30)
	close.pressed.connect(func() -> void: win.call("close_screen"))
	h.add_child(close)
	return h


func _tile(key: String, title: String, opens: bool) -> VBoxContainer:
	var p := PanelContainer.new()
	var normal := UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 14, Vector4(14, 10, 14, 10))
	var hover := UiStyle.box(UiStyle.PANEL2, Color(UiStyle.GOLD, 0.55), 14, Vector4(14, 10, 14, 10))
	p.add_theme_stylebox_override("panel", normal)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if opens:
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.tooltip_text = _t("dash_open_tip")
		p.mouse_entered.connect(func() -> void: p.add_theme_stylebox_override("panel", hover))
		p.mouse_exited.connect(func() -> void: p.add_theme_stylebox_override("panel", normal))
		p.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				win.call("open_screen", key))
	tut[key] = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(_lab(title.to_upper(), Color(UiStyle.TEXT, 0.75), 12))
	return v


func _panel_of(v: Control) -> Control:
	return v.get_parent() as Control


func _lab(text: String, col: Color, fs: int = 13) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", fs)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wrap(text: String, col: Color, fs: int) -> Label:
	var l := _lab(text, col, fs)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(120, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _icon(c: Dictionary, s: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = db.icon_of(c)
	tr.custom_minimum_size = Vector2(s, s)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.modulate = db.color_of(c).lightened(0.35)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return tr


## A company's badge in its status frame (the same as in the lists).
func _badge(c: Dictionary, d: float) -> Control:
	var b: Variant = win.call("_badge", c, d)
	if b is Control:
		(b as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(b as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return b as Control
	return _icon(c, d)


func _sign_col(x: float) -> Color:
	return UiStyle.UP if x >= 0.0 else UiStyle.DOWN


## ▲ green for good news, ▼ red for bad, a grey dot when it is neither.
func _arrow(sign: int) -> Label:
	var l := _lab("▲" if sign > 0 else ("▼" if sign < 0 else "•"), UiStyle.UP if sign > 0 else (UiStyle.DOWN if sign < 0 else UiStyle.DIM), 14)
	l.custom_minimum_size = Vector2(16, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A clickable company name: opens its dossier.
func _name_link(c: Dictionary, fs: int) -> Button:
	var cid := str(c.get("id", ""))
	var b := win.call("_link", db.name_of(c), UiStyle.TEXT, func() -> void: win.call("open_company", cid)) as Button
	b.add_theme_font_size_override("font_size", fs)
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = _t("dash_open_company")
	return b


# ---------- 3 · news and the company of the week ----------

func _tile_news() -> Control:
	var v := _tile("news", _t("dash_news"), true)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(list)
	if fresh():
		_first_week(list)
		return _panel_of(v)
	var items := news(9)
	if items.is_empty():
		list.add_child(_lab(_t("dash_news_none"), UiStyle.DIM, 12))
	for it in items:
		var d: Dictionary = it
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.add_child(row)
		var c: Dictionary = db.company(str(d.get("id", "")))
		row.add_child(_arrow(int(d.get("sign", 0))))
		if not c.is_empty():
			row.add_child(_icon(c, 22.0))
		var l := _lab(str(d["текст"]), UiStyle.TEXT, 14)
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
	h.add_child(_star_card(standout(), false))
	return _panel_of(v)


## The company of the week as a card: badge, name, the move, WHY it stands out, the AI's bulletin and 🎙.
func _star_card(c: Dictionary, big: bool) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL2, Color(UiStyle.GOLD, 0.35), 12, Vector4(14, 10, 14, 10)))
	p.custom_minimum_size = Vector2(420 if not big else 560, 0)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	if c.is_empty():
		v.add_child(_lab(_t("dash_star_none"), UiStyle.DIM, 12))
		return p
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	h.add_child(_badge(c, 52.0))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(nv)
	nv.add_child(_lab(_t("dash_star").to_upper(), UiStyle.GOLD, 10))
	nv.add_child(_name_link(c, 19 if not big else 23))
	var ch := db.change(c, 1)
	nv.add_child(_lab(_t("dash_star_move") % db.percent(ch, true) + "  ·  " + db.sector_name(str(c.get("sector", ""))) + " · " + str(c.get("_country", "")), _sign_col(ch), 13))
	var mic := Button.new()
	mic.text = "🎙"
	mic.tooltip_text = _t("dash_mic_tip")
	mic.focus_mode = Control.FOCUS_NONE
	mic.custom_minimum_size = Vector2(34, 34)
	mic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mic.pressed.connect(func() -> void: _speak(c))
	h.add_child(mic)
	tut["mic"] = mic
	v.add_child(_wrap(_why(c), UiStyle.DIM, 13))
	var ai: Dictionary = _ai.get(_ai_key(), {})
	_star_text = _wrap(str(ai.get("digest", _t("dash_ai_wait"))), UiStyle.TEXT, 14)
	v.add_child(_star_text)
	return p


## Why this company is the company of the week: its move, its rank and its loudest event of the week.
func _why(c: Dictionary) -> String:
	var ch := db.change(c, 1)
	var line := _t("dash_why_" + ("up" if ch >= 0.0 else "down")) % [db.percent(absf(ch)), db.money(absf(db.cap(c) - db.cap(c) / (1.0 + ch)))]
	var best := ""
	var size := 0.0
	for e in (c.get("_chronicle", []) as Array).slice(-8):
		var ed: Dictionary = e
		if _day() - int(ed.get("день", -999)) > 10:
			continue
		var s := absf(float(ed.get("доля", 0.1)))
		if s >= size:
			size = s
			best = str(win.call("chron_text", c, ed))
	if not best.is_empty():
		line += " " + _t("dash_why_cause") % best
	return line


## 🎙: the game's own voice (Main.голос — a method that speaks a text), else the system's voice (DisplayServer).
func _speak(c: Dictionary) -> void:
	var ai: Dictionary = _ai.get(_ai_key(), {})
	var text := str(ai.get("digest", "")) if not str(ai.get("digest", "")).is_empty() else db.name_of(c) + ". " + _why(c)
	var game: Object = win.get("game")
	var main: Object = game.get("main")
	var mod: Object = win.get("mod")
	var v: Variant = main.get("голос") if main != null else null
	if v is Object and is_instance_valid(v):
		var names: PackedStringArray = []
		for m in (v as Object).get_method_list():
			names.append(str((m as Dictionary)["name"]))
		for want in VOICE_METHODS:
			for n in names:
				if n.trim_prefix("_") == want or n.trim_prefix("_").begins_with(want):
					var args: Array = []
					var defaults: Array = []
					for m2 in (v as Object).get_method_list():
						if str((m2 as Dictionary)["name"]) == n:
							args = (m2 as Dictionary).get("args", [])
							defaults = (m2 as Dictionary).get("default_args", [])
					if args.size() >= 1:
						var arg_names: PackedStringArray = []
						for ad in args:
							arg_names.append("%s:%s" % [str((ad as Dictionary).get("name", "")), type_string(int((ad as Dictionary).get("type", 0)))])
						var need := args.size() - defaults.size()
						var call_args: Array = [text]
						for k in range(1, maxi(1, need)):
							# A required second argument: the speaker — the game's assistant voice when the type is a string.
							call_args.append("" if int((args[k] as Dictionary).get("type", TYPE_STRING)) == TYPE_STRING else null)
						(v as Object).callv(n, call_args)
						mod.call("log_info", "voice: Main.голос.%s(%s), sent %d args" % [n, ", ".join(arg_names), call_args.size()])
						return
		mod.call("log_info", "voice: no speaking method in Main.голос — " + ", ".join(names.slice(0, 60)))
	var lang := "ru" if TranslationServer.get_locale().begins_with("ru") else "en"
	var voices := DisplayServer.tts_get_voices_for_language(lang)
	if not voices.is_empty():
		DisplayServer.tts_stop()
		DisplayServer.tts_speak(text, voices[0])
		return
	game.call("toast", _t("dash_no_voice"))


## The biggest weekly move among the large companies of the scope (the top half by value).
func standout() -> Dictionary:
	var list := companies().duplicate()
	if list.is_empty():
		return {}
	list.sort_custom(func(a, b): return db.cap(a) > db.cap(b))
	list = list.slice(0, maxi(1, mini(list.size(), maxi(20, list.size() / 2))))
	var best: Dictionary = {}
	var score := -1.0
	for c in list:
		var s := absf(db.change(c, 1))
		if s > score:
			score = s
			best = c
	return best


## The week's corporate news of the scope: the newspaper candidates, then the companies' chronicles.
func news(n: int) -> Array:
	var out: Array = []
	var nr: Variant = win.get("narrator")
	var me := _country()
	if nr is Object and is_instance_valid(nr):
		var press: Array = (nr as Object).get("press")
		var items := press.duplicate()
		items.sort_custom(func(a, b): return int((a as Dictionary).get("день", 0)) > int((b as Dictionary).get("день", 0)))
		for it in items:
			var d: Dictionary = it
			if _scope() == "country" and str(d.get("country", "")) != me:
				continue
			var text := str(d.get("текст", "")).strip_edges()
			if text.is_empty():
				continue
			var pc: Dictionary = db.company(str(d.get("id", "")))
			var ps := 0
			if not pc.is_empty() and absf(db.change(pc, 1)) >= 0.01:
				ps = 1 if db.change(pc, 1) > 0.0 else -1
			out.append({"текст": "%s: %s" % [str(d.get("company", "")), text], "id": str(d.get("id", "")), "sign": ps})
			if out.size() >= n:
				return out
	var big := companies().duplicate()
	big.sort_custom(func(a, b): return db.cap(a) > db.cap(b))
	var rows: Array = []
	for c in big.slice(0, 80):
		for e in (c.get("_chronicle", []) as Array).slice(-3):
			var ed: Dictionary = e
			if _day() - int(ed.get("день", -999)) <= 14:
				rows.append([int(ed.get("день", 0)), db.name_of(c) + ": " + str(win.call("chron_text", c, ed)), str(c["id"]), _entry_sign(c, ed)])
	rows.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	for r in rows:
		out.append({"текст": str(r[1]), "id": str(r[2]), "sign": int(r[3])})
		if out.size() >= n:
			break
	return out


## Good or bad news: the entry's own move, its kind, else the company's week.
func _entry_sign(c: Dictionary, ed: Dictionary) -> int:
	var kind := str(ed.get("вид", ""))
	if kind in SHAME_KINDS or kind in ["strike", "layoffs", "кризис", "дефолт", "банкротство", "kickback", "ban", "business_reaction"]:
		return -1
	if kind in ["birth", "ipo", "rescue", "похвала", "технология", "возможность", "набор"]:
		return 1
	if ed.has("up"):
		return 1 if bool(ed["up"]) else -1
	if ed.has("доля") and absf(float(ed["доля"])) >= 0.005 and kind in ["price", "событие", "условия"]:
		return 1 if float(ed["доля"]) > 0.0 else -1
	var ch := db.change(c, 1)
	return 0 if absf(ch) < 0.01 else (1 if ch > 0.0 else -1)


# ---------- 1 · the top ----------

func _tile_top() -> Control:
	var v := _tile("top", _t("dash_top_" + _scope()), true)
	var cols := [["", 22], ["", 30], [_t("dash_c_name"), 0], [_t("dash_c_cap"), 86], [_t("dash_c_move"), 62], [_t("dash_c_rev"), 80], [_t("dash_c_staff"), 70]]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	for col in cols:
		var l := _lab(str(col[0]), UiStyle.DIM, 10)
		l.custom_minimum_size = Vector2(float(col[1]), 0)
		if int(col[1]) == 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(l)
	head.tooltip_text = _t("dash_top_cols_tip")
	var list := companies().duplicate()
	list.sort_custom(func(a, b): return float(a.get("_index", 0.0)) > float(b.get("_index", 0.0)))
	for i in mini(14, list.size()):
		var c: Dictionary = list[i]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(h)
		var r := _lab("%d" % (i + 1), UiStyle.DIM, 14)
		r.custom_minimum_size = Vector2(22, 0)
		h.add_child(r)
		var bd := _badge(c, 28.0)
		bd.custom_minimum_size = Vector2(30, 30)
		h.add_child(bd)
		var n := _lab(db.name_of(c), UiStyle.TEXT, 14)
		n.clip_text = true
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var vals := [[db.money(db.cap(c)), UiStyle.TEXT, 86], [db.percent(db.change(c, 4), true), _sign_col(db.change(c, 4)), 62],
			[db.money(db.fund(c, "выручка")), UiStyle.DIM, 80], [db.people(db.staff(c)), UiStyle.DIM, 70]]
		for val in vals:
			var l2 := _lab(str(val[0]), val[1] as Color, 13)
			l2.custom_minimum_size = Vector2(float(val[2]), 0)
			l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.add_child(l2)
	return _panel_of(v)


# ---------- 2 · the market ----------

func _tile_market() -> Control:
	var v := _tile("market", _t("dash_market_" + _scope()), true)
	var mode := str(win.get("chart_mode"))
	if not (mode in CHARTS):
		mode = "cap"
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	v.add_child(bar)
	for m in CHARTS:
		var b := Button.new()
		b.text = _t("dash_chart_" + str(m))
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		var on := str(m) == mode
		b.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.GOLD, 0.25) if on else UiStyle.PANEL, UiStyle.GOLD if on else UiStyle.LINE, 8, Vector4(8, 2, 8, 2)))
		var key := str(m)
		b.pressed.connect(func() -> void:
			win.set("chart_mode", key)
			win.call("refresh"))
		bar.add_child(b)
	v.add_child(_wrap(_t("dash_chart_" + mode + "_what"), UiStyle.DIM, 11))
	var chart := Charts.LineChart.new()
	chart.custom_minimum_size = Vector2(0, 140)
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.line_color = UiStyle.GOLD
	chart.trend = mode != "share"   # market value: green up, red down
	chart.empty_text = _t("dash_chart_wait")
	if mode == "share":
		chart.format_value = func(x: float) -> String: return "%.1f%%" % x
	else:
		chart.format_value = func(x: float) -> String: return db.money(x)
	chart.set_values(series(mode, 26))
	v.add_child(chart)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(chips)
	for s in sectors(4).slice(0, 4):
		chips.add_child(_sector_chip(s))
	return _panel_of(v)


func _sector_chip(s: Array) -> Control:
	var x := float(s[1])
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(Color(_sign_col(x), 0.14), Color(0, 0, 0, 0), 8, Vector4(8, 3, 8, 3)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.tooltip_text = _t("dash_sector_tip")
	p.add_child(_lab("%s %s" % [db.sector_name(str(s[0])), db.percent(x, true)], _sign_col(x), 11))
	return p


## The weekly series of a chart: «cap» — the scope's market value; «state» — the value of the shares the player's
## state holds; «share» — the player's country's share of the world's market value, %.
func series(mode: String, weeks: int) -> Array:
	match mode:
		"state":
			return _sum_series(db.companies.filter(func(c): return db.state_share(c) > 0.0), weeks, true)
		"share":
			var me := _country()
			var mine := _sum_series(db.companies.filter(func(c): return str(c.get("_country", "")) == me), weeks, false)
			var all := _sum_series(db.companies, weeks, false)
			var out: Array = []
			for i in mini(mine.size(), all.size()):
				out.append(100.0 * float(mine[i]) / maxf(float(all[i]), 1e-6))
			return out
	return _sum_series(companies(), weeks, false)


func _sum_series(list: Array, weeks: int, state: bool) -> Array:
	var out: Array = []
	var w := 0
	for c in list:
		w = maxi(w, db.history(c).size())
	w = mini(w, weeks)
	for k in w:
		var sum := 0.0
		for c in list:
			var h: Array = db.history(c)
			var i := h.size() - w + k
			if i >= 0 and i < h.size():
				sum += float(h[i]) * db.shares(c) * (db.state_share(c) if state else 1.0)
		out.append(sum)
	return out


## Sectors of the scope by the change of their total value over `weeks`: [[sector, change, value], …], best first.
func sectors(weeks: int) -> Array:
	var now := {}
	var was := {}
	for c in companies():
		var s := str(c.get("sector", ""))
		var h: Array = db.history(c)
		if h.is_empty():
			continue
		var a: float = float(h[h.size() - 1]) * db.shares(c)
		var b: float = float(h[maxi(0, h.size() - 1 - weeks)]) * db.shares(c)
		now[s] = float(now.get(s, 0.0)) + a
		was[s] = float(was.get(s, 0.0)) + b
	var out: Array = []
	for s in now.keys():
		if float(was[s]) > 0.0:
			out.append([str(s), float(now[s]) / float(was[s]) - 1.0, float(now[s])])
	out.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return out


# ---------- 4 · deals ----------

func _tile_deals() -> Control:
	var v := _tile("deals", _t("dash_deals"), true)
	if fresh():
		_first_week(v)
		var p0 := _panel_of(v)
		p0.size_flags_stretch_ratio = 1.1
		return p0
	var list := deals(20)
	var feat := featured()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	h.add_child(_lab("%d" % list.size(), UiStyle.TEXT, 26))
	var sub := _lab(_t("dash_deals_sub"), UiStyle.DIM, 12)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sub)
	if not feat.is_empty():
		var c: Dictionary = feat["c"]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL2, Color(UiStyle.DOWN if bool(feat["shame"]) else UiStyle.GOLD, 0.4), 12, Vector4(12, 8, 12, 8)))
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(cv)
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 10)
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(ch)
		ch.add_child(_badge(c, 36.0))
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 0)
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ch.add_child(tv)
		tv.add_child(_lab(_t("dash_feat_shame" if bool(feat["shame"]) else "dash_feat_big").to_upper(), UiStyle.DOWN if bool(feat["shame"]) else UiStyle.GOLD, 10))
		tv.add_child(_name_link(c, 16))
		cv.add_child(_wrap(str(feat["текст"]), UiStyle.TEXT, 13))
		var ai: Dictionary = _ai.get(_ai_key(), {})
		var head := _head_name(c)
		var quote := str(ai.get("quote", ""))
		if not quote.is_empty() and not Guard.ok(quote, {"down": true, "polity": Guard.any_state(c), "facts": str(feat["текст"])}) and bool(feat["shame"]):
			quote = ""
		if quote.is_empty():
			quote = _t("dash_quote_" + ("shame" if bool(feat["shame"]) else ("sell" if bool(feat.get("sale", false)) else "buy")))
		_quote_text = _wrap("«%s»" % quote, Color(UiStyle.TEXT, 0.85), 12)
		_quote_text.add_theme_font_override("font", _italic())
		cv.add_child(_quote_text)
		if not head.is_empty():
			var who := _lab("— " + head + _t("dash_quote_role") % db.name_of(c), UiStyle.DIM, 11)
			who.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cv.add_child(who)
	for d in list.slice(0, 4):
		var dd: Dictionary = d
		var dc: Dictionary = dd["c"]
		var did := str(dc.get("id", ""))
		var l := win.call("_link", "•  " + str(dd["текст"]), UiStyle.DIM, func() -> void: win.call("open_company", did)) as Button
		l.clip_text = true
		l.alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.add_theme_font_size_override("font_size", 12)
		v.add_child(l)
	var p := _panel_of(v)
	p.size_flags_stretch_ratio = 1.1
	return p


static func _italic() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(UiStyle.FONTS)
	f.font_italic = true
	return f


func _head_name(c: Dictionary) -> String:
	var h: Variant = c.get("глава")
	if h is Dictionary:
		return db.text((h as Dictionary).get("name", ""))
	return ""


func _name(cid: String) -> String:
	return str(win.call("_name_of_id", cid))


func _in_scope(c: Dictionary) -> bool:
	return _scope() != "country" or str(c.get("_country", "")) == _country()


## Every deal of the last `days`: takeovers and breakups (rivals.gd) and deals in the chronicles, biggest first —
## [{день, c, текст, сумма, продажа}].
func _deals_in(days: int) -> Array:
	var out: Array = []
	var day := _day()
	var rv: Variant = win.get("rivals")
	if rv is Object and is_instance_valid(rv):
		for d in ((rv as Object).get("deals") as Array):
			var dd: Dictionary = d
			if day - int(dd.get("день", -999)) > days:
				continue
			var a: Dictionary = db.company(str(dd.get("a", "")))
			var b: Dictionary = db.company(str(dd.get("b", "")))
			if not (_in_scope(a) or _in_scope(b)):
				continue
			var text := _t("dash_kind_" + str(dd.get("вид", ""))) + ": " + _name(str(dd.get("a", ""))) + " → " + _name(str(dd.get("b", ""))) \
				+ ", " + db.percent(float(dd.get("доля", 0.0))) + ", " + db.money(float(dd.get("amount", 0.0)))
			out.append({"день": int(dd.get("день", 0)), "c": b if not b.is_empty() else a, "текст": text, "amount": float(dd.get("amount", 0.0)),
				"a": str(dd.get("a", "")), "b": str(dd.get("b", "")), "вид": str(dd.get("вид", "")), "доля": float(dd.get("доля", 0.0)), "sale": false})
	for c in companies():
		for e in (c.get("_chronicle", []) as Array).slice(-6):
			var ed: Dictionary = e
			var kind := str(ed.get("вид", ""))
			if not (kind in DEAL_KINDS) or day - int(ed.get("день", -999)) > days:
				continue
			var sum := float(ed.get("count_value", ed.get("amount", 0.0)))
			out.append({"день": int(ed.get("день", 0)), "c": c, "текст": db.name_of(c) + ": " + str(win.call("chron_text", c, ed)), "amount": sum,
				"a": str(c["id"]), "b": str(c["id"]), "вид": kind, "доля": float(ed.get("доля", 0.0)), "sale": kind in ["продана", "breakup"]})
	out.sort_custom(func(x, y): return float((x as Dictionary)["amount"]) > float((y as Dictionary)["amount"]))
	return out


## The week's biggest deals of the scope; a quiet week — those of the last month.
func deals(n: int) -> Array:
	var list := _deals_in(7)
	if list.size() < 3:
		list = _deals_in(28)
	return list.slice(0, n)


## The deal to show with its news: the week's biggest; no deal at all — the week's most shameful event.
func featured() -> Dictionary:
	var list := deals(1)
	if not list.is_empty():
		var d: Dictionary = list[0]
		d["shame"] = false
		return d
	var day := _day()
	var worst: Dictionary = {}
	var score := -1.0
	for c in companies():
		for e in (c.get("_chronicle", []) as Array).slice(-6):
			var ed: Dictionary = e
			if str(ed.get("вид", "")) in SHAME_KINDS and day - int(ed.get("день", -999)) <= 28:
				var s := db.cap(c) * (1.0 + absf(float(ed.get("доля", 0.0))))
				if s > score:
					score = s
					worst = {"c": c, "текст": db.name_of(c) + ": " + str(win.call("chron_text", c, ed)), "shame": true, "amount": 0.0}
	if worst.is_empty():
		# Nothing at all: the week's biggest fall is the shame of the week.
		var list2 := companies().duplicate()
		list2.sort_custom(func(a, b): return db.change(a, 1) < db.change(b, 1))
		if not list2.is_empty():
			var c2: Dictionary = list2[0]
			worst = {"c": c2, "текст": _t("dash_shame_fall") % [db.name_of(c2), db.percent(absf(db.change(c2, 1)))], "shame": true, "amount": 0.0}
	return worst


# ---------- 5 · trends: a donut of the movers and the reason ----------

func _tile_trends() -> Control:
	var v := _tile("trends", _t("dash_trends"), false)
	if fresh():
		_cards = []
		_first_week(v)
		return _panel_of(v)
	_cards = trends()
	_card = clampi(_card, 0, maxi(0, _cards.size() - 1))
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	v.add_child(nav)
	var prev := Button.new()
	prev.text = "‹"
	prev.focus_mode = Control.FOCUS_NONE
	prev.custom_minimum_size = Vector2(30, 26)
	prev.pressed.connect(func() -> void: _page(-1, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var next := Button.new()
	next.text = "›"
	next.focus_mode = Control.FOCUS_NONE
	next.custom_minimum_size = Vector2(30, 26)
	next.pressed.connect(func() -> void: _page(1, true))
	nav.add_child(sp)
	nav.add_child(prev)
	nav.add_child(next)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", 8)
	_card_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_card_box)
	_show_card(0)
	var p := _panel_of(v)
	p.size_flags_stretch_ratio = 1.4
	return p


## Auto-paging: a card every few seconds; a manual flip holds it for 10 s.
func _process(delta: float) -> void:
	if not is_visible_in_tree() or _cards.size() < 2:
		return
	if _hold > 0.0:
		_hold -= delta
		return
	_auto += delta
	if _auto >= AUTO_SEC:
		_auto = 0.0
		_page(1, false)


func _page(d: int, manual: bool) -> void:
	if _cards.is_empty():
		return
	if manual:
		_hold = PAUSE_SEC
	_auto = 0.0
	_show_card(d)


func _show_card(d: int) -> void:
	if not is_instance_valid(_card_box):
		return
	for c in _card_box.get_children():
		_card_box.remove_child(c)
		c.queue_free()
	if _cards.is_empty():
		_card_box.add_child(_lab(_t("dash_trends_none"), UiStyle.DIM, 12))
		return
	_card = posmod(_card + d, _cards.size())
	var card: Dictionary = _cards[_card]
	var col: Color = card["colour"]
	_card_box.add_child(_wrap(str(card["title"]), col, 15))
	var pie := Charts.Pie.new()
	pie.custom_minimum_size = Vector2(190, 190)
	pie.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pie.slices = card["shares_map"]
	pie.center_value = db.percent(float(card["change"]), true)
	pie.center_title = _t("dash_trend_4w")
	_card_box.add_child(pie)
	for c in (card["companies"] as Array):
		var cd: Dictionary = c
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_card_box.add_child(row)
		row.add_child(_icon(cd, 20.0))
		var n := _lab(db.name_of(cd), UiStyle.TEXT, 12)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		row.add_child(n)
		row.add_child(_lab(db.percent(db.change(cd, 4), true), _sign_col(db.change(cd, 4)), 12))
	if not str(card["reason"]).is_empty():
		var why := PanelContainer.new()
		why.add_theme_stylebox_override("panel", UiStyle.box(Color(col, 0.1), Color(col, 0.35), 10, Vector4(10, 6, 10, 6)))
		_card_box.add_child(why)
		why.add_child(_wrap(_t("dash_trend_why") % str(card["reason"]), UiStyle.TEXT, 12))


## The market's trends: rising and falling sectors of the scope (events.market_news) and the companies that set them.
func trends() -> Array:
	var ev: Variant = win.get("events")
	var out: Array = []
	var mn: Dictionary = (ev as Object).call("market_news", _country() if _scope() == "country" else "") if ev is Object and is_instance_valid(ev) else {}
	var secs := sectors(4)
	var by := {}
	for s in secs:
		by[str(s[0])] = float(s[1])
	for dir in ["up", "down"]:
		for k in mn.get(dir, []):
			out.append(_trend_card(str(k), dir == "up", float(by.get(str(k), 0.0))))
	if out.size() < 3:
		for s in secs.slice(0, 2) + secs.slice(maxi(0, secs.size() - 2)):
			var known := out.any(func(x): return str((x as Dictionary)["sector"]) == str(s[0]))
			if not known:
				out.append(_trend_card(str(s[0]), float(s[1]) >= 0.0, float(s[1])))
	return out


func _trend_card(sector: String, up: bool, ch: float) -> Dictionary:
	var list := companies().filter(func(c): return str(c.get("sector", "")) == sector)
	list.sort_custom(func(a, b): return db.change(a, 4) > db.change(b, 4) if up else db.change(a, 4) < db.change(b, 4))
	var lead := list.slice(0, 4)
	# The donut: each leader's share of the sector's value, the rest of the sector grey.
	var total := 0.0
	for c in list:
		total += db.cap(c)
	var slices: Array = []
	var used := 0.0
	for i in lead.size():
		var share := db.cap(lead[i]) / maxf(total, 1e-6)
		used += share
		slices.append([share, Charts.PIE_COLORS[i % Charts.PIE_COLORS.size()], db.name_of(lead[i])])
	if used < 0.999:
		slices.append([1.0 - used, Color(UiStyle.TEXT, 0.18), _t("dash_trend_rest")])
	# The reason: the loudest recent event of the sector's companies.
	var reason := ""
	var loud := 0.0
	for c in list.slice(0, 12):
		for e in (c.get("_chronicle", []) as Array).slice(-4):
			var ed: Dictionary = e
			if _day() - int(ed.get("день", -999)) > 28:
				continue
			var s := absf(float(ed.get("доля", 0.05)))
			if s > loud:
				loud = s
				reason = db.name_of(c) + ": " + str(win.call("chron_text", c, ed))
	return {"sector": sector, "title": _t("dash_trend_" + ("up" if up else "down")) % [db.sector_name(sector), db.percent(ch, true)],
		"companies": lead, "shares_map": slices, "change": ch, "reason": reason, "colour": UiStyle.UP if up else UiStyle.DOWN}


# ---------- the AI's weekly bulletin and the head's quote ----------

func _ai_key() -> String:
	return "%d|%s" % [_day() / 7, _scope()]


func _ask_ai() -> void:
	var key := _ai_key()
	if _ai.has(key) or _asked.has(key):
		return
	var m: Variant = win.get("mod")
	if not (m is Object) or not is_instance_valid(m) or not (m as Object).has_method("ask_ai"):
		return
	var star := standout()
	if star.is_empty() or fresh():
		return
	_asked[key] = true
	var feat := featured()
	var lines: Array = []
	for e in (star.get("_chronicle", []) as Array).slice(-5):
		lines.append(str(win.call("chron_text", star, e)))
	var data := {"язык": "ru" if TranslationServer.get_locale().begins_with("ru") else "en",
		"company_of_week": {"name": db.name_of(star), "отрасль": db.sector_name(str(star.get("sector", ""))), "country": str(star.get("_country", "")),
			"week_percent": roundi(db.change(star, 1) * 100.0), "four_weeks_percent": roundi(db.change(star, 4) * 100.0),
			"market_cap": db.money(db.cap(star)), "события": lines, "direction": "up" if db.change(star, 1) >= 0.0 else "down",
			"owners": Guard.owners(db, star), "state_owns": Guard.any_state(star)},
		"deal_of_week": {"текст": str(feat.get("текст", "")), "shame": bool(feat.get("shame", false)),
			"глава": _head_name(feat.get("c", {})), "company": db.name_of(feat.get("c", {}))} if not feat.is_empty() else {}}
	var prompt := "You write for a business newspaper of a strategy game, in the language «язык». STRICT FACT RULES: use ONLY the " \
		+ "given data; never invent events, people, deaths, arrests, resignations, elections, products, contracts or numbers; never " \
		+ "call a company state-owned unless «государство_владеет» is true (use «владельцы» as given); a fall is a fall and a rise " \
		+ "is a rise — follow «направление». 1) «сводка»: a 2–3 sentence news-bulletin summary about «компания_недели» — what " \
		+ "happened this week and why, from its «события» only. 2) «цитата»: one short quote (1 sentence) of the head «глава» of the " \
		+ "company in «сделка_недели» about that deal; if «позор» is true the quote must be sober and apologetic, never boasting " \
		+ "of growth or success; no quotation marks. Return ONLY JSON: {\"digest\": \"…\", \"quote\": \"…\"}"
	var sent: bool = (m as Object).call("ask_ai", "dash_week", prompt, data, func(answer: Dictionary) -> void:
		if answer.is_empty():
			return
		var sv := str(answer.get("digest", "")).strip_edges()
		var facts_text := " ".join(PackedStringArray(lines)) + " " + " ".join(PackedStringArray(Guard.owners(db, star)))
		if not Guard.ok(sv, {"down": db.change(star, 1) < 0.0, "polity": Guard.any_state(star), "facts": facts_text}):
			sv = ""   # the AI went beyond the facts: the card keeps the game's own «why»
		var qt := str(answer.get("quote", "")).strip_edges()
		if not feat.is_empty() and not Guard.ok(qt, {"polity": Guard.any_state(feat["c"]), "facts": str(feat.get("текст", ""))}):
			qt = ""
		_ai[key] = {"digest": sv, "quote": qt}
		if is_instance_valid(_star_text) and str(_ai[key]["digest"]).is_empty():
			_star_text.text = ""
		if is_instance_valid(_star_text) and not str(_ai[key]["digest"]).is_empty():
			_star_text.text = str(_ai[key]["digest"])
		if is_instance_valid(_quote_text) and not str(_ai[key]["quote"]).is_empty():
			_quote_text.text = "«%s»" % str(_ai[key]["quote"]), {"max_tokens": 500, "temperature": 0.7})
	if not sent:
		_asked.erase(key)


# ---------- the detail screens (2, 3, 4) ----------

func build_detail(key: String, box: VBoxContainer) -> void:
	box.add_child(_top_bar(_t("dash_screen_" + key), true))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	match key:
		"market":
			_detail_market(v)
		"news":
			_detail_news(v)
		"deals":
			_detail_deals(v)
		"zones":
			_detail_zones(v)


func _card_panel(parent: Control, title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 14, Vector4(14, 12, 14, 12)))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	if not title.is_empty():
		v.add_child(_lab(title.to_upper(), Color(UiStyle.TEXT, 0.75), 12))
	return v


func _detail_market(v: VBoxContainer) -> void:
	for m in CHARTS:
		var c1 := _card_panel(v, _t("dash_chart_" + str(m)) + " · " + _t("dash_year"))
		c1.add_child(_wrap(_t("dash_chart_" + str(m) + "_what"), UiStyle.DIM, 11))
		var chart := Charts.LineChart.new()
		chart.custom_minimum_size = Vector2(0, 200)
		if str(m) == "share":
			chart.format_value = func(x: float) -> String: return "%.1f%%" % x
		else:
			chart.format_value = func(x: float) -> String: return db.money(x)
		chart.empty_text = _t("dash_chart_wait")
		chart.set_values(series(str(m), 52))
		c1.add_child(chart)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var c2 := _card_panel(row, _t("dash_sectors"))
	for s in sectors(4):
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		c2.add_child(h)
		var n := _lab(db.sector_name(str(s[0])), UiStyle.TEXT, 12)
		n.custom_minimum_size = Vector2(150, 0)
		n.clip_text = true
		h.add_child(n)
		var bar := Charts.Bar.new()
		bar.value = clampf(50.0 + float(s[1]) * 250.0, 2.0, 100.0)
		bar.custom_minimum_size = Vector2(120, 6)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(bar)
		var x := float(s[1])
		h.add_child(_lab(db.percent(x, true), _sign_col(x), 12))
	var movers := companies().duplicate()
	movers.sort_custom(func(a, b): return db.change(a, 4) > db.change(b, 4))
	var c3 := _card_panel(row, _t("dash_gainers"))
	for c in movers.slice(0, 10):
		_company_line(c3, c, db.change(c, 4))
	var c4 := _card_panel(row, _t("dash_losers"))
	var rev := movers.duplicate()
	rev.reverse()
	for c in rev.slice(0, 10):
		_company_line(c4, c, db.change(c, 4))
	var more := Button.new()
	more.text = _t("dash_goods_markets")
	more.focus_mode = Control.FOCUS_NONE
	more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	more.pressed.connect(func() -> void: win.call("open_list_tab", "markets"))
	v.add_child(more)


func _company_line(parent: Control, c: Dictionary, x: float) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	parent.add_child(h)
	h.add_child(_icon(c, 18.0))
	var cid := str(c["id"])
	var b := win.call("_link", db.name_of(c), UiStyle.TEXT, func() -> void: win.call("open_company", cid)) as Button
	b.clip_text = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(b)
	h.add_child(_lab(db.percent(x, true), _sign_col(x), 12))


func _detail_news(v: VBoxContainer) -> void:
	if fresh():
		_first_week(v)
		return
	v.add_child(_star_card(standout(), true))
	var c1 := _card_panel(v, _t("dash_news"))
	var items := news(30)
	if items.is_empty():
		c1.add_child(_lab(_t("dash_news_none"), UiStyle.DIM, 12))
	for it in items:
		var d: Dictionary = it
		var cid := str(d.get("id", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		c1.add_child(row)
		var c: Dictionary = db.company(cid)
		if not c.is_empty():
			row.add_child(_icon(c, 22.0))
		var l := win.call("_link", str(d["текст"]), UiStyle.TEXT, func() -> void:
			if not cid.is_empty():
				win.call("open_company", cid)) as Button
		l.alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)


func _detail_deals(v: VBoxContainer) -> void:
	if fresh():
		_first_week(v)
		return
	var c1 := _card_panel(v, _t("dash_deals_top"))
	var list := deals(20)
	if list.is_empty():
		var feat := featured()
		c1.add_child(_lab(_t("deals_none"), UiStyle.DIM, 12))
		if not feat.is_empty():
			c1.add_child(_wrap(str(feat["текст"]), UiStyle.DOWN, 13))
		return
	for i in list.size():
		var d: Dictionary = list[i]
		var c: Dictionary = d["c"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		c1.add_child(row)
		row.add_child(_lab("%d" % (i + 1), UiStyle.DIM, 13))
		row.add_child(_badge(c, 26.0))
		var cid := str(c.get("id", ""))
		var link := win.call("_link", str(d["текст"]), UiStyle.TEXT, func() -> void: win.call("open_company", cid)) as Button
		link.alignment = HORIZONTAL_ALIGNMENT_LEFT
		link.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(link)
		row.add_child(_lab(str(win.call("_date_of", int(d.get("день", 0)))), UiStyle.DIM, 11))


# ---------- the «Zones» screen: every economic zone, its members, its corporations and its rules ----------

func _lang() -> String:
	return "ru" if TranslationServer.get_locale().begins_with("ru") else "en"


func _detail_zones(v: VBoxContainer) -> void:
	var zones := Zones.all()
	if zones.is_empty():
		v.add_child(_lab(_t("zones_none"), UiStyle.DIM, 13))
		return
	var me := _country()
	var sel := str(win.get("zone_sel"))
	if Zones.zone(sel).is_empty():
		var mine := Zones.zones_of(me)
		sel = str((mine[0] as Dictionary).get("id", "")) if not mine.is_empty() else str((zones[0] as Dictionary).get("id", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	# The list of zones.
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.custom_minimum_size = Vector2(270, 0)
	row.add_child(list)
	tut["z_list"] = list
	for z in zones:
		var zd: Dictionary = z
		var id := str(zd.get("id", ""))
		var b := Button.new()
		b.text = "  %s  (%d)" % [Zones.name_of(zd, _lang()), (zd.get("members", []) as Array).size()]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.clip_text = true
		var col := Zones.color_of(zd)
		b.add_theme_stylebox_override("normal", UiStyle.box(Color(col, 0.28) if id == sel else UiStyle.PANEL, Color(col, 0.9) if id == sel else Color(col, 0.4), 10, Vector4(12, 4, 12, 4)))
		if me in (zd.get("members", []) as Array):
			b.text += "  ★"
			b.tooltip_text = _t("zones_member")
		b.pressed.connect(func() -> void:
			_founding = false
			win.set("zone_sel", id)
			win.call("refresh"))
		list.add_child(b)
	var fb := Button.new()
	fb.text = "＋ " + _t("zones_found_btn")
	fb.tooltip_text = _t("zones_found_tip")
	fb.focus_mode = Control.FOCUS_NONE
	fb.custom_minimum_size = Vector2(0, 34)
	UiStyle.as_primary(fb)
	fb.pressed.connect(func() -> void:
		_founding = true
		win.call("refresh"))
	list.add_child(fb)
	if _founding:
		_found_picker(row)
		return
	var z := Zones.zone(sel)
	var col2 := Zones.color_of(z)
	var members: Array = z.get("members", [])
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	# Head: name, type, our country, description.
	var head := _card_panel(right, "")
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 12)
	head.add_child(hh)
	var sw := ColorRect.new()
	sw.color = col2
	sw.custom_minimum_size = Vector2(8, 46)
	hh.add_child(sw)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(hv)
	hv.add_child(_lab(Zones.name_of(z, _lang()), UiStyle.TEXT, 22))
	hv.add_child(_lab(Zones.text_of(z, "type", _lang()).to_upper(), col2.lightened(0.3), 11))
	var inside: bool = me in members
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 4)
	hh.add_child(mv)
	mv.add_child(_lab(_t("zones_you_in" if inside else "zones_you_out") % me, UiStyle.UP if inside else UiStyle.DIM, 13))
	var zid := str(z.get("id", ""))
	if true:   # every zone has the button: «Join» — or, when the player cannot, the reason on hover and on a click
		var act := Button.new()
		act.focus_mode = Control.FOCUS_NONE
		var m: Object = win.get("mod")
		if inside and bool(z.get("союз", true)):
			act.text = _t("zones_leave_sure") if _leave_armed == zid else _t("zones_leave")
			act.tooltip_text = _t("zones_leave_tip")
			act.pressed.connect(func() -> void:
				if _leave_armed != zid:
					_leave_armed = zid
					win.call("refresh")
					return
				_leave_armed = ""
				m.call("zone_leave", zid)
				win.call("refresh"))
		else:
			var reason := str(m.call("zone_join_reason", zid)) if not inside else _t("zones_why_member")
			act.text = _t("zones_join")
			if reason.is_empty():
				act.tooltip_text = _t("zones_join_tip")
				act.pressed.connect(func() -> void:
					m.call("zone_join", zid)
					win.call("refresh"))
			else:
				# Not disabled (a disabled button keeps no tooltip on some systems): dimmed, the reason on hover and click.
				act.tooltip_text = "⛔ " + reason
				act.modulate = Color(1, 1, 1, 0.55)
				act.pressed.connect(func() -> void:
					_join_reason = zid
					win.call("refresh"))
				if _join_reason == zid:
					mv.add_child(_wrap("⛔ " + reason, UiStyle.DOWN, 11))
		mv.add_child(act)
	head.add_child(_wrap(Zones.text_of(z, "description", _lang()), UiStyle.TEXT, 14))
	# Members with their flags.
	var mc := _card_panel(right, _t("zones_members") + " · %d" % members.size())
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 6)
	mc.add_child(flow)
	var main: Object = (win.get("game") as Object).get("main")
	for m in members:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 5)
		flow.add_child(chip)
		var fl := TextureRect.new()
		fl.custom_minimum_size = Vector2(26, 17)
		fl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fl.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if main != null and GameApi.has(main, "_флаг_чей"):
			var tex: Variant = GameApi.call_main(main, "_флаг_чей", [str(m)])
			if tex is Texture2D:
				fl.texture = tex as Texture2D
		chip.add_child(fl)
		chip.add_child(_lab(str(m), UiStyle.TEXT if str(m) != me else UiStyle.GOLD, 13))
	# The corporations of the zone in numbers.
	var cs: Array = db.companies.filter(func(c): return str(c.get("_country", "")) in members)
	var cap := 0.0
	var world := 0.0
	var rev := 0.0
	var staff := 0.0
	var was := 0.0
	for c in db.companies:
		world += db.cap(c)
	for c in cs:
		cap += db.cap(c)
		rev += db.fund(c, "выручка")
		staff += db.staff(c)
		was += db.cap(c) / (1.0 + db.change(c, 4))
	var kc := _card_panel(right, _t("zones_numbers"))
	tut["z_kpi"] = kc
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	kc.add_child(grid)
	var ch := cap / maxf(was, 1e-6) - 1.0
	for kv in [[_t("zones_k_companies"), "%d" % cs.size(), UiStyle.TEXT], [_t("zones_k_cap"), db.money(cap), UiStyle.TEXT],
			[_t("zones_k_share"), db.percent(cap / maxf(world, 1e-6)), UiStyle.TEXT], [_t("zones_k_rev"), db.money(rev), UiStyle.TEXT],
			[_t("zones_k_staff"), db.people(staff), UiStyle.TEXT], [_t("zones_k_move"), db.percent(ch, true), _sign_col(ch)]]:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		grid.add_child(cell)
		cell.add_child(_lab(str(kv[0]).to_upper(), UiStyle.DIM, 10))
		cell.add_child(_lab(str(kv[1]), kv[2] as Color, 20))
	# The biggest corporations and the sectors.
	var two := HBoxContainer.new()
	two.add_theme_constant_override("separation", 12)
	right.add_child(two)
	var tc := _card_panel(two, _t("zones_top"))
	tut["z_top"] = tc
	var top := cs.duplicate()
	top.sort_custom(func(a, b): return db.cap(a) > db.cap(b))
	for c in top.slice(0, 10):
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		tc.add_child(r)
		r.add_child(_badge(c, 24.0))
		var nl := _name_link(c, 13)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(nl)
		r.add_child(_lab(str(c.get("_country", "")), UiStyle.DIM, 11))
		r.add_child(_lab(db.money(db.cap(c)), UiStyle.TEXT, 12))
		r.add_child(_lab(db.percent(db.change(c, 4), true), _sign_col(db.change(c, 4)), 12))
	var sc := _card_panel(two, _t("zones_sectors"))
	tut["z_sectors"] = sc
	var by := {}
	for c in cs:
		var s := str(c.get("sector", ""))
		by[s] = float(by.get(s, 0.0)) + db.cap(c)
	var keys: Array = by.keys()
	keys.sort_custom(func(a, b): return float(by[a]) > float(by[b]))
	var slices: Array = []
	var other := 0.0
	for i in keys.size():
		var share := float(by[keys[i]]) / maxf(cap, 1e-6)
		if i < 7:
			slices.append([share, db.sector_color(str(keys[i])), db.sector_name(str(keys[i]))])
		else:
			other += share
	if other > 0.0:
		slices.append([other, Color(UiStyle.TEXT, 0.2), _t("dash_trend_rest")])
	var pie := Charts.Pie.new()
	pie.custom_minimum_size = Vector2(200, 200)
	pie.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pie.slices = slices
	pie.center_value = db.money(cap)
	pie.center_title = _t("zones_k_cap")
	sc.add_child(pie)
	for s2 in slices:
		var lr := HBoxContainer.new()
		lr.add_theme_constant_override("separation", 6)
		sc.add_child(lr)
		var dot := ColorRect.new()
		dot.color = s2[1] as Color
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lr.add_child(dot)
		var ln := _lab(str(s2[2]), UiStyle.TEXT, 12)
		ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lr.add_child(ln)
		lr.add_child(_lab(db.percent(float(s2[0])), UiStyle.DIM, 12))
	# The rules of the zone — what each does in the game.
	var rc := _card_panel(right, _t("zones_rules"))
	tut["z_rules"] = rc
	for rule in z.get("правила", []):
		var rr := HBoxContainer.new()
		rr.add_theme_constant_override("separation", 10)
		rc.add_child(rr)
		var bar := ColorRect.new()
		bar.color = col2
		bar.custom_minimum_size = Vector2(4, 36)
		rr.add_child(bar)
		var rv := VBoxContainer.new()
		rv.add_theme_constant_override("separation", 1)
		rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.add_child(rv)
		var key := "zone_rule_" + str(rule)
		rv.add_child(_lab(_t(key), UiStyle.TEXT, 14))
		var txt := _t(key + "_text")
		match str(rule):
			"общая_конкуренция":
				txt = txt % db.percent(float(z.get("competition_k", 1.15)) - 1.0)
			"external_tariff":
				txt = txt % db.percent(float(z.get("external_tariff", 0.0)))
			"фильтр_инвестиций":
				txt = txt % db.percent(Zones.screen_cap())
			"единый_рынок":
				txt = txt % db.percent(float(Zones.cfg.get("single_market_k", 0.12)))
		rv.add_child(_wrap(txt, UiStyle.DIM, 12))
	_how_companies(right, z, inside)


## «How companies work» in this zone: inside it and with the outside world — and what it means for the player's companies.
func _how_companies(parent: Control, z: Dictionary, inside: bool) -> void:
	var hc := _card_panel(parent, _t("zones_how"))
	tut["z_how"] = hc
	var col := Zones.color_of(z)
	var two := HBoxContainer.new()
	two.add_theme_constant_override("separation", 16)
	hc.add_child(two)
	var a := VBoxContainer.new()
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.add_theme_constant_override("separation", 4)
	two.add_child(a)
	var b := VBoxContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_constant_override("separation", 4)
	two.add_child(b)
	a.add_child(_lab(_t("zones_how_in").to_upper(), col.lightened(0.3), 11))
	b.add_child(_lab(_t("zones_how_out").to_upper(), col.lightened(0.3), 11))
	var ins := 0
	for pair in [["без_пошлин", "zones_in_free"], ["единый_рынок", "zones_in_single"], ["свободный_капитал", "zones_in_capital"],
			["лёгкий_переезд", "zones_in_move"], ["общая_конкуренция", "zones_in_comp"]]:
		if Zones.has_rule(z, str(pair[0])):
			a.add_child(_wrap("•  " + _t(str(pair[1])), UiStyle.TEXT, 12))
			ins += 1
	if Zones.same_zone_rule_takeover():
		a.add_child(_wrap("•  " + _t("zones_in_takeover"), UiStyle.TEXT, 12))
	if ins == 0:
		a.add_child(_wrap(_t("zones_in_none"), UiStyle.DIM, 12))
	var outs := 0
	if float(z.get("external_tariff", 0.0)) > 0.0:
		b.add_child(_wrap("•  " + _t("zones_out_tariff") % db.percent(float(z.get("external_tariff", 0.0))), UiStyle.TEXT, 12))
		outs += 1
	for pair2 in [["общая_торговая_политика", "zones_out_bloc"], ["фильтр_инвестиций", "zones_out_screen"], ["закрытый_капитал", "zones_out_closed"]]:
		if Zones.has_rule(z, str(pair2[0])):
			var tx := _t(str(pair2[1]))
			if str(pair2[0]) == "фильтр_инвестиций":
				tx = tx % db.percent(Zones.screen_cap())
			b.add_child(_wrap("•  " + tx, UiStyle.TEXT, 12))
			outs += 1
	if outs == 0:
		b.add_child(_wrap(_t("zones_out_open"), UiStyle.DIM, 12))
	# For the player's own companies.
	var me := _country()
	var mine := db.companies.filter(func(c): return str(c.get("_country", "")) == me)
	var line := ""
	if inside:
		line = _t("zones_you_inside") % mine.size()
	elif float(z.get("external_tariff", 0.0)) > 0.0 or Zones.has_rule(z, "закрытый_капитал") or Zones.has_rule(z, "фильтр_инвестиций"):
		line = _t("zones_you_outside") % mine.size()
	else:
		line = _t("zones_you_open")
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiStyle.box(Color(col, 0.12), Color(col, 0.45), 10, Vector4(12, 8, 12, 8)))
	hc.add_child(box)
	box.add_child(_wrap(line, UiStyle.TEXT, 13))


## A new union: the countries the player knows, by their attitude; the ones who like the player (≥ the threshold)
## agree, the rest refuse. A name, then «Found».
var _join_reason := ""             # the zone whose «Join» was pressed while the player cannot join (its reason shows)
var _found_filter := "free"       # the new union's list: all | free (in no union) | union (in one)
var _found_result: Dictionary = {}  # the last answer of the countries (who agreed, who refused and why)
var _found_picked: Dictionary = {}
var _found_name := ""


func _found_picker(row: HBoxContainer) -> void:
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var c1 := _card_panel(right, _t("zones_found_btn"))
	c1.add_child(_wrap(_t("zones_found_text2") % [db.percent(float(Zones.cfg.get("accession_from", 0.35))), db.percent(float(Zones.cfg.get("accession_sure", 0.7)))], UiStyle.TEXT, 13))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = _t("zones_found_name") % _country()
	name_edit.text = _found_name
	name_edit.text_changed.connect(func(s: String) -> void: _found_name = s)
	c1.add_child(name_edit)
	# The answer of the last attempt: who agreed, who refused and why.
	if not _found_result.is_empty() and not bool(_found_result.get("ok", false)):
		var res := VBoxContainer.new()
		c1.add_child(res)
		res.add_child(_wrap("⚠ " + str(_found_result.get("line", "")), UiStyle.DOWN, 13))
		for r in _found_result.get("refused", []):
			res.add_child(_wrap("• %s — %s" % [str(r[0]), str(r[1])], UiStyle.DIM, 12))
	var m: Object = win.get("mod")
	var me := _country()
	# Filter: in no union / in a union / all.
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 6)
	c1.add_child(fr)
	for f in [["free", "zones_f_free"], ["union", "zones_f_union"], ["all", "zones_f_all"]]:
		var fb := Button.new()
		fb.text = _t(str(f[1]))
		fb.toggle_mode = true
		fb.button_pressed = _found_filter == str(f[0])
		fb.focus_mode = Control.FOCUS_NONE
		var key := str(f[0])
		fb.pressed.connect(func() -> void:
			_found_filter = key
			win.call("refresh"))
		fr.add_child(fb)
	var cands: Array = []
	for f in (win.get("game") as Object).call("factions"):
		var fd: Dictionary = f
		var nm := str(fd.get("name", ""))
		if nm == me or nm.is_empty() or not bool(fd.get("polity", true)) or not bool(fd.get("met", false)) or bool(fd.get("perished", false)):
			continue
		var ch := float(m.call("zone_join_chance", nm))
		if (_found_filter == "free" and ch < 0.0) or (_found_filter == "union" and ch >= 0.0):
			continue
		cands.append([nm, float(m.call("zone_relation", nm)), ch])
	cands.sort_custom(func(x, y): return float(x[1]) > float(y[1]))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 320)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	c1.add_child(sc)
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lv)
	if cands.is_empty():
		lv.add_child(_lab(_t("zones_f_none"), UiStyle.DIM, 12))
	for cd in cands.slice(0, 80):
		var nm2 := str(cd[0])
		var rel := float(cd[1])
		var ch2 := float(cd[2])
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 10)
		lv.add_child(r)
		var cb := CheckBox.new()
		cb.text = nm2
		cb.focus_mode = Control.FOCUS_NONE
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.button_pressed = _found_picked.has(nm2)
		cb.disabled = ch2 < 0.0
		cb.toggled.connect(func(on: bool) -> void:
			if on:
				_found_picked[nm2] = true
			else:
				_found_picked.erase(nm2))
		r.add_child(cb)
		if ch2 < 0.0:
			var u := ""
			for z in Zones.zones_of(nm2):
				if bool((z as Dictionary).get("союз", true)):
					u = Zones.name_of(z, _lang())
					break
			var ul := _lab(_t("zones_in_union") % u, UiStyle.DIM, 11)
			ul.tooltip_text = _t("zones_in_union_tip")
			ul.mouse_filter = Control.MOUSE_FILTER_PASS
			r.add_child(ul)
		else:
			var chl := _lab(_t("zones_chance") % roundi(ch2 * 100.0), UiStyle.UP if ch2 >= 0.99 else (UiStyle.GOLD if ch2 > 0.0 else UiStyle.DOWN), 12)
			chl.tooltip_text = _t("zones_chance_tip")
			chl.mouse_filter = Control.MOUSE_FILTER_PASS
			r.add_child(chl)
		r.add_child(_lab(_t("zones_rel") % roundi(rel * 100.0), UiStyle.TEXT, 12))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.alignment = BoxContainer.ALIGNMENT_END
	c1.add_child(bar)
	var picked_l := _lab(_t("zones_picked") % _found_picked.size(), UiStyle.DIM, 12)
	picked_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(picked_l)
	var cancel := Button.new()
	cancel.text = _t("am_deal_decline")
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func() -> void:
		_founding = false
		_found_result = {}
		_found_picked = {}
		win.call("refresh"))
	bar.add_child(cancel)
	var go := Button.new()
	go.text = _t("zones_found_go")
	go.focus_mode = Control.FOCUS_NONE
	UiStyle.as_primary(go)
	go.pressed.connect(func() -> void:
		if _found_picked.is_empty():
			_found_result = {"ok": false, "line": _t("zones_pick_first"), "refused": []}
			win.call("refresh")
			return
		_found_result = m.call("zone_found", _found_picked.keys(), _found_name)
		if bool(_found_result.get("ok", false)):
			_founding = false
			_found_picked = {}
			_found_name = ""
		win.call("refresh"))
	bar.add_child(go)
