extends PaxMod
## Pax Corporations — living corporations of the «Our time» world.
## Stage 1: company data (companies/*.json), game events reaching companies (events.gd), staff, wages and
## money (economy.gd), weekly share prices (market.gd), statuses and the rating index (corp_data.gd),
## taxes and dividends into the treasuries, news for the player, the «Corporations» window with dossiers,
## and the corporations layer on the political map.
## Design document: sections 3–9, 11, 18, 20. Everything the player does to companies goes through words —
## the interface here only shows.
##
## How it is built: see the note above the parts (src/<feature>/*_ctl.gd).
const Zones := preload("res://mods/pax_corporations/src/zones/zones.gd")
const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Market := preload("res://mods/pax_corporations/src/market/market.gd")
const Economy := preload("res://mods/pax_corporations/src/companies/economy.gd")
const Events := preload("res://mods/pax_corporations/src/news/events.gd")
const Politics := preload("res://mods/pax_corporations/src/state/politics.gd")
const Digest := preload("res://mods/pax_corporations/src/news/digest.gd")
const Debt := preload("res://mods/pax_corporations/src/companies/debt.gd")
const MapLayer := preload("res://mods/pax_corporations/src/map/map_layer.gd")
const GlobeMap := preload("res://mods/pax_corporations/src/map/globe_map.gd")
const CorpWindow := preload("res://mods/pax_corporations/src/window/ui_window.gd")
const Stakes := preload("res://mods/pax_corporations/src/market/stakes.gd")
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")
const Rivals := preload("res://mods/pax_corporations/src/companies/rivals.gd")
const Founding := preload("res://mods/pax_corporations/src/founding/founding.gd")
const Parallel := preload("res://mods/pax_corporations/src/core/parallel.gd")
const Departments := preload("res://mods/pax_corporations/src/state/departments.gd")
const DepartmentsWindow := preload("res://mods/pax_corporations/src/state/departments_window.gd")
const Lifecycle := preload("res://mods/pax_corporations/src/companies/lifecycle.gd")
const Letters := preload("res://mods/pax_corporations/src/news/letters.gd")
const Antitrust := preload("res://mods/pax_corporations/src/state/antitrust.gd")
const Badges := preload("res://mods/pax_corporations/src/window/badges.gd")
const Orders := preload("res://mods/pax_corporations/src/state/orders.gd")
const Arena := preload("res://mods/pax_corporations/src/world/arena.gd")
const Influence := preload("res://mods/pax_corporations/src/state/influence.gd")
const Narrator := preload("res://mods/pax_corporations/src/news/narrator.gd")
const Tutorial := preload("res://mods/pax_corporations/src/window/tutorial.gd")
const WhatsNew := preload("res://mods/pax_corporations/src/shared/whatsnew.gd")
const Frames := preload("res://mods/pax_corporations/src/companies/frames.gd")
const DevTree := preload("res://mods/pax_corporations/src/tech/tree.gd")
const DevWindow := preload("res://mods/pax_corporations/src/tech/dev_window.gd")
const Compat := preload("res://mods/pax_corporations/src/core/compat.gd")
const HudSkin := preload("res://mods/pax_corporations/src/look/hud_skin.gd")
const Glass := preload("res://mods/pax_corporations/src/look/glass.gd")
const DealDialog := preload("res://mods/pax_corporations/src/market/deal_dialog.gd")
const Investments := preload("res://mods/pax_corporations/src/market/investments.gd")
const Conditions := preload("res://mods/pax_corporations/src/state/conditions.gd")
const Capabilities := preload("res://mods/pax_corporations/src/state/capabilities.gd")
const ReportRules := preload("res://mods/pax_corporations/src/state/report_rules.gd")
const CountryRank := preload("res://mods/pax_corporations/src/world/country_rank.gd")
const CountryCard := preload("res://mods/pax_corporations/src/world/country_card.gd")
const EconWatch := preload("res://mods/pax_corporations/src/world/econ_watch.gd")
const StateGoals := preload("res://mods/pax_corporations/src/world/state_goals.gd")
const Buildings := preload("res://mods/pax_corporations/src/map/buildings.gd")
const BuildingBank := preload("res://mods/pax_corporations/src/map/building_bank.gd")
const TechLevel := preload("res://mods/pax_corporations/src/tech/techlevel.gd")
# The parts of the mod's work, each its own object (src/<feature>/*_ctl.gd, each holds «app» — this object).
# main.gd only registers: modules, shared state and one-line entry points with the old names (the game's
# callbacks, the windows, the other mods' api.call, the console). New logic goes into a part, not here.
const FoundingCtl := preload("res://mods/pax_corporations/src/founding/founding_ctl.gd")
const StakesCtl := preload("res://mods/pax_corporations/src/market/stakes_ctl.gd")
const TreasuryCtl := preload("res://mods/pax_corporations/src/state/treasury_ctl.gd")
const NewsCtl := preload("res://mods/pax_corporations/src/news/news_ctl.gd")
const BridgeCtl := preload("res://mods/pax_corporations/src/core/bridge_ctl.gd")
const ZonesCtl := preload("res://mods/pax_corporations/src/zones/zones_ctl.gd")
const ConsoleCtl := preload("res://mods/pax_corporations/src/core/console_ctl.gd")
const WindowsCtl := preload("res://mods/pax_corporations/src/window/windows_ctl.gd")
const WorldCtl := preload("res://mods/pax_corporations/src/core/world_ctl.gd")
const SchedulerCtl := preload("res://mods/pax_corporations/src/core/scheduler_ctl.gd")
const HudCtl := preload("res://mods/pax_corporations/src/look/hud_ctl.gd")

const WEEK := 7
const SAVE_VERSION := 3
const FRAME_BUDGET_USEC := 6000   # a long time skip is worked off a few weeks per frame, not in one freeze
const SKIP_BUDGET_USEC := 22000   # while the game itself skips time a frame may work longer (but the picture keeps moving)
const SKIP_BATCH := 8             # during the game's own skip weeks are gathered and worked off 8 at a time (one step, db.dt)
const CATCHUP_BUDGET_USEC := 10000 # a long backlog in play (e.g. a save made mid-skip): a bit more than usual
## A long skip: up to EXACT_WEEKS queued are worked off week by week; beyond that one step covers several weeks
## (db.dt, at most MAX_STEP_WEEKS), so that the whole backlog takes about SKIP_STEPS steps — a century is
## ~120 steps (about 10 months each) instead of 5200 weeks of ~140 ms. Every yearly rate scales with db.dt.
const EXACT_WEEKS := 26
const SKIP_STEPS := 120.0
const MAX_STEP_WEEKS := 52
const NEWS_AFTER_SKIP := 10       # after a skip only the latest news reach the feed
const REFRESH_EVERY := 0.5        # seconds between window refreshes while time runs

var db: Data
var market: Market
var economy: Economy
var events: Events
var politics: Politics
var digest: Digest
var debt: Debt
var goods: Goods
var rivals: Rivals
var departments: Departments
var lifecycle: Lifecycle
var letters: Letters
var antitrust: Antitrust
var badges: Badges
var orders: Orders
var arena: Arena
var influence: Influence
var investments: Investments
var conditions: Conditions
var capabilities: Capabilities
var report_rules: ReportRules
var country_rank: CountryRank      # the country's world step and its change (country_rank.gd)
var country_card: CountryCard      # a country's card (country_card.gd), made on the first click on the globe
var econ_watch: EconWatch          # a yearly snapshot of the corporate world to the journal (econ_watch.gd)
var state_goals: StateGoals        # what the states lack, fear and want — their decisions move the companies (state_goals.gd)
var techlevel: TechLevel
var buildings: Buildings         # 3D buildings on the globe (buildings.gd), a setting
var bank: BuildingBank           # the pictures the map draws: Pax CorpInc3D's models, else the voxel ones
var narrator: Narrator
var tutorial: Tutorial
var _tutorial_in := -1.0          # seconds until the tutorial is offered (a new game)
var whatsnew: WhatsNew
var frames: Frames
var tree: DevTree
var _dev: DevWindow
var _dev_button: Button
var _whatsnew_in := -1.0          # seconds until «what's new» is shown (every world start)
var compat: Compat
var hud_skin: HudSkin             # the game's own interface in the mod's look (hud_skin.gd), a setting
var _compat_flags: Array = []     # incompatibility flags newer than the loaded world's save (compat.gd)
var _compat_saved := ""           # the mod version the loaded world was saved with
var _compat_in := -1.0            # seconds until the warning is shown
var _corp_button: Button          # the bottom bar's «Corporations» button (found once, badges.gd)
var _dept_window: DepartmentsWindow
var _dept_panel: Control
var _paid_week: Dictionary = {}   # the player's treasury got last week: {налоги, дивиденды} (Pax Corpface)
var treasury_weeks: Array = []   # what the player's treasury got from companies, week by week (last 52)
var _game: PaxGame
var _layer: MapLayer
var _globe: GlobeMap            # the layer's map over the 3D Earth while the flat map is closed
var _window: CorpWindow
var _panel: Control
var _days := 0
var _active := false
var _pending: Array = []          # days of the weeks still to simulate
var _refresh_wanted := false
## The week in progress (worked off phase by phase in _run_pending): its day (-1 — none), next phase, money.
const PHASES: PackedStringArray = ["events", "goods", "rivals", "lifecycle", "debt", "economy", "market", "recompute", "politics", "treasury+news"]
var _phase_day := -1
var last_week_usec: Dictionary = {}   # microseconds per phase of the last finished week (Pax Corptimizer reads it)
var last_refresh_usec := 0            # the last refresh of the open window
var _post_queue: Array = []           # news items waiting to be posted, one per frame
var _skip_news: Array = []            # news of a skip in progress — only the latest NEWS_AFTER_SKIP are kept
var _skip_letters := 0                # letters that came during a skip (one toast at its end)
const SLOW_FRAME_SEC := 0.025         # a frame longer than this is «heavy» — the week's work waits
const POSTPONE_MAX := 8


# ---------- the parts of the mod (src/<feature>/*_ctl.gd) ----------
var world_ctl: WorldCtl = WorldCtl.new(self)               # loading, world start, save, teardown
var scheduler_ctl: SchedulerCtl = SchedulerCtl.new(self)   # the weekly schedule and the frame's work
var founding_ctl: FoundingCtl = FoundingCtl.new(self)      # founding a company, the assistant, letters to heads
var stakes_ctl: StakesCtl = StakesCtl.new(self)            # the state's stakes, orders, deal dialogs
var treasury_ctl: TreasuryCtl = TreasuryCtl.new(self)      # taxes and dividends to the treasuries
var news_ctl: NewsCtl = NewsCtl.new(self)                  # news to the feed, toasts
var windows_ctl: WindowsCtl = WindowsCtl.new(self)         # the mod's windows, map links, tutorial actions
var bridge_ctl: BridgeCtl = BridgeCtl.new(self)            # API for Pax Corpface and Pax CorpInc3D
var zones_ctl: ZonesCtl = ZonesCtl.new(self)               # economic unions
var hud_ctl: HudCtl = HudCtl.new(self)                     # the game's interface skin and hint
var console_ctl: ConsoleCtl = ConsoleCtl.new(self)         # console commands


func _mod_loaded() -> void:
	world_ctl._mod_loaded()


func _mod_unloaded() -> void:
	world_ctl._mod_unloaded()


## The ⚙ menu's «game interface in the mod's look».
func set_hud_skin(on: bool) -> void:
	hud_ctl.set_hud_skin(on)


func _game_loaded(_g: PaxGame, state: Dictionary) -> void:
	world_ctl._game_loaded(_g, state)


func _world_ready(game: PaxGame) -> void:
	world_ctl._world_ready(game)


static func _dict(d: Dictionary, key: String) -> Dictionary:
	return WorldCtl._dict(d, key)


## Weeks are queued and worked off in _process within a time budget per frame: a skip of months does not
## freeze the game, it takes a few frames. The summary closes when the queue is empty.
func _days_passed(_g: PaxGame, from_day: int, days: int) -> void:
	scheduler_ctl._days_passed(_g, from_day, days)


## A week is worked off phase by phase (PHASES), as many phases a frame as fit into the budget — a week is
## never one long freeze; the heavy pure phases (economy, statuses) also run on worker threads (parallel.gd).
func _run_pending(budget_usec: int) -> void:
	scheduler_ctl._run_pending(budget_usec)


func _game_skipping() -> bool:
	return scheduler_ctl._game_skipping()


## The skip is over: no notifications — what happened is in the «Corporations» news and the letters' tab.
func _flush_skip_news() -> void:
	news_ctl._flush_skip_news()


## Finishes a week that is half done (before saving or a console week) — the data must not stay half-way.
func _finish_week() -> void:
	scheduler_ctl._finish_week()


func _save_state(_g: PaxGame) -> Dictionary:
	return world_ctl._save_state(_g)


func _data_reloaded() -> void:
	world_ctl._data_reloaded()


## The game's hover hint of a body (Main.подсказка — «Земля: единственное место, где точно есть жизнь») follows the
## mouse over the map under our window and covered the window's ✕: while a window of the mod is open it is hidden.
func _hide_game_hint() -> void:
	hud_ctl._hide_game_hint()


func _process(delta: float) -> void:
	scheduler_ctl._process(delta)


## One game week: the world's events reach the companies, then people and money, then prices (they follow
## the money), then statuses; taxes and dividends go to the treasuries, news to the player.
## `timing` (console «corp bench») collects microseconds per phase.
func _week(day: int, timing: Dictionary = {}) -> void:
	scheduler_ctl._week(day, timing)


static func _lap(timing: Dictionary, key: String, since: int) -> int:
	return SchedulerCtl._lap(timing, key, since)


# ---------- the player founds a company ----------

## Who the player is and what they have: {"polity": bool, "name": the person's name, "money": млн $,
## "место": the default headquarters place, "country": the player's country}.
func founding_info() -> Dictionary:
	return founding_ctl.founding_info()


## A place in a province (the map's numbering, data/regions2.json). at — the clicked point (latitude, longitude):
## the headquarters stand exactly where the player clicked; without it (or when it is far from the province's
## centre — a wrapped map) — the centre of the province.
func place_of(pid: int, owner: String, at: Vector2 = Vector2.INF) -> Dictionary:
	return founding_ctl.place_of(pid, owner, at)


func founding_preview(goods_key: String, capital: float, country: String) -> Dictionary:
	return founding_ctl.founding_preview(goods_key, capital, country)


## The window hides, the map opens, the next click on a province of the player's country becomes the place.
func pick_place(done: Callable) -> void:
	founding_ctl.pick_place(done)


## Founds the company: the money leaves the treasury, the company joins the world at once.
## spec: {название, описание, товар, капитал, место, спросить_ии}. Returns "" or an error text.
func found_company(spec: Dictionary) -> String:
	return founding_ctl.found_company(spec)


# ---------- the game's AI assistant ----------

## Opens the game's assistant window and asks it (Main._спросить_помощника). False if it cannot now.
func ask_assistant(text: String) -> bool:
	return founding_ctl.ask_assistant(text)


# ---------- talking to a company's head ----------

## The player clicked the head's name in the dossier: the head becomes a contact of the game (if not yet) and the
## game's own conversation with them opens (Main._говорить_с_контактом) — the game's AI plays the head.
func write_head(cid: String) -> void:
	founding_ctl.write_head(cid)


# ---------- the state's stakes (section 6) ----------

## Money in the player's treasury, млн $.
func treasury_money() -> float:
	return stakes_ctl.treasury_money()


func quote_trade(cid: String, fraction: float, buy: bool) -> Dictionary:
	return stakes_ctl.quote_trade(cid, fraction, buy)


## The «Owners» tab's buttons: the player's state buys or sells a block of shares at once, even on pause.
## Returns the line shown to the player.
func trade(cid: String, fraction: float, buy: bool) -> String:
	return stakes_ctl.trade(cid, fraction, buy)


## The antimonopoly service speaks: a notification right away and a letter in the «Letters» tab.
func _service_says(key: String, args: Array) -> String:
	return stakes_ctl._service_says(key, args)


## An order's result: a notification right away and a letter from the government's office in «Letters».
func _order_says(line: String) -> void:
	stakes_ctl._order_says(line)


## The game's «order_parsed» hook: the player gave an order. The antimonopoly service reacts at once to orders
## about competition and to takeovers or nationalisations of a company (antitrust.review_order); a furious
## service blocks such an order.
func _on_order(d: Dictionary) -> void:
	stakes_ctl._on_order(d)


# ---------- treasury (sections 9, 20.15) ----------

## Profit tax rates by country: the player's comes from the game's economy, the rest from config.
func _tax_rates() -> Dictionary:
	return treasury_ctl._tax_rates()


## Taxes and dividends on state stakes go on top of what the game already counts — on purpose (section 9):
## a player who ignores the country's corporations falls behind in money.
func _pay_treasuries(paid: Dictionary) -> void:
	treasury_ctl._pay_treasuries(paid)


func treasury_year() -> float:
	return treasury_ctl.treasury_year()


func _favorites() -> Dictionary:
	return world_ctl._favorites()


func _player_country() -> String:
	return world_ctl._player_country()


# ---------- news (section 18) ----------

## Who hears what: the player's country and favourites — everything (only the biggest when there is a lot);
## the world top-100 — only big events; the world crisis — always; the rest stays in the chronicles.
func _deliver_news(day: int) -> void:
	news_ctl._deliver_news(day)


func _post(item: Dictionary) -> void:
	news_ctl._post(item)


# ---------- building ----------

## «State departments» — its own button in the bottom bar.
func _build_departments_window(game: PaxGame) -> void:
	windows_ctl._build_departments_window(game)


## «Развитие»: a full-screen window over the map, opened by its own bottom button next to «Корпорации».
func _build_development(game: PaxGame) -> void:
	windows_ctl._build_development(game)


func _build_window(game: PaxGame, favs: Variant) -> void:
	windows_ctl._build_window(game, favs)


func _attach_layer() -> void:
	windows_ctl._attach_layer()


## A click on the empty map closes the «Corporations» window (the bottom button still toggles it).
func _close_window() -> void:
	windows_ctl._close_window()


## A tutorial step opens its place and returns the control to outline (tutorial.gd).
func tutorial_action(what: String) -> Control:
	return windows_ctl.tutorial_action(what)


## Unread counters on the bottom bar (badges.gd): the mod's letters and a new summary on «Corporations»; the game's
## unread letters on «Связи», science news on the projects button, new stages on the path button.
func _update_badges() -> void:
	windows_ctl._update_badges()


# ---------- 3D buildings on the globe ----------

## The buildings stand on the home planet's 3D node (they move with it); off by the ⚙ setting «3D-постройки».
func _build_buildings() -> void:
	bridge_ctl._build_buildings()


## Every site of every company for Pax CorpInc3D's 3D Earth: [{k kind, f frame, s sector, st state, lat, lon, c id}].
func sites_3d() -> Array:
	return bridge_ctl.sites_3d()


## The point the flat map shows in its middle: Vector2(latitude, longitude), INF — no map (Pax CorpInc3D turns the
## globe's camera there when the map closes).
func map_center() -> Vector2:
	return bridge_ctl.map_center()


## Changes when the sites change (a new week's data).
func sites_version() -> int:
	return bridge_ctl.sites_version()


## Pax CorpInc3D was switched on or off (or came and went): the buildings are built anew.
func refresh_buildings() -> void:
	bridge_ctl.refresh_buildings()


func set_buildings_3d(on: bool) -> void:
	bridge_ctl.set_buildings_3d(on)


## A click on a country on the 3D globe (Pax CorpInc3D): its card in its world step's look; "" — the card closes.
func open_country_card(country: String) -> void:
	if _game == null:
		return
	if country_card == null or not is_instance_valid(country_card):
		country_card = CountryCard.new()
		country_card.setup(self, _game)
		add_child(country_card)
	if country.is_empty():
		country_card.close()
	else:
		country_card.open(country)


## The economic zones for Pax CorpInc3D's globe while the layer «Экономические зоны» is on: {country: the colour
## of its zone} (a country in several zones — the first); {} when the layer is off.
func zone_colours() -> Dictionary:
	if not is_instance_valid(_layer) or not _layer.zones_on:
		return {}
	var out := {}
	for z in Zones.all():
		var col := Zones.color_of(z)
		for c in Zones.members(z):
			if not out.has(str(c)):
				out[str(c)] = col
	return out


## A country in numbers (country_card.gd summary) for Pax Corpface's «Держава»; {} before the world is ready.
func country_summary(country: String) -> Dictionary:
	if _game == null:
		return {}
	if country_card == null or not is_instance_valid(country_card):
		country_card = CountryCard.new()
		country_card.setup(self, _game)
		add_child(country_card)
	return country_card.summary(country)


## A company in a few lines for Pax CorpInc3D's hover over its 3D building (the bubble): [name, country · industry,
## value · the week's change, its status (frame), «click — the dossier»]; [] — no such company.
func company_brief(cid: String) -> Array:
	var c: Dictionary = db.company(cid) if db != null else {}
	if c.is_empty():
		return []
	var lines: Array = [db.name_of(c)]
	lines.append("%s · %s" % [str(c.get("_country", "")), db.sector_name(str(c.get("sector", "")))])
	var ch := db.change(c, 1) * 100.0
	lines.append(tr_key("pax_corporations_brief_value") % [db.money(db.cap(c)), ("+" if ch >= 0.0 else "") + ("%.1f%%" % ch)])
	var fr := Frames.of(c)
	if not fr.is_empty() and fr != "none":
		lines.append(tr_key("pax_corporations_frame_" + fr))
	lines.append(tr_key("pax_corporations_brief_click"))
	return lines


## A click on a company's 3D building (Pax CorpInc3D): its dossier, as a click on its mark on the map.
func open_company_3d(cid: String) -> void:
	windows_ctl._open_from_map(cid)


# ---------- Pax Corpface: the shared interface ----------

## The mod's resources for Pax Corpface's panel (a separate mod; no dependency either way): [{id, имя, значение,
## показ, значок, подсказка}…]. Corpface samples «значение» daily for its arrow; «значок» is one of its icons.
## The country's world step for Pax Corpface's interface: [step, place] ("" — not counted yet).
func country_tier() -> Array:
	return bridge_ctl.country_tier()


## Console demos (zz_corp_probe): «rank_anim up|down [step]», «rank_<step>».
func rank_demo(dir: String, to_tier: String) -> String:
	return bridge_ctl.rank_demo(dir, to_tier)


## The world's top states with their frames (Pax Corpface: a click on the rank line; console «rank_top»).
func open_country_top() -> void:
	bridge_ctl.open_country_top()


## The country's frame drawn around a flag on any CanvasItem (Pax Corpface's column) — the companies' family.
func draw_flag_frame(ci: CanvasItem, r: Rect2, tier: String) -> void:
	bridge_ctl.draw_flag_frame(ci, r, tier)


## The room the frame needs around a flag, as a share of the flag's height: Vector4(left, top, right, bottom).
func flag_frame_margin(tier: String) -> Vector4:
	return bridge_ctl.flag_frame_margin(tier)


func rank_demo_to(to_tier: String) -> String:
	return bridge_ctl.rank_demo_to(to_tier)


func corpface_rows() -> Array:
	return bridge_ctl.corpface_rows()


## A click on one of them in Pax Corpface: the window of the mod about it.
func corpface_open(id: String) -> void:
	bridge_ctl.corpface_open(id)


## The compatibility warning's «start anew»: the mod's data in this world are dropped and the companies start as
## in a new game; the world itself (the game's own save) stays as it is.
func _reset_mod_data() -> void:
	world_ctl._reset_mod_data()


## game.add_window puts a button into the bottom bar, and freeing the window leaves that button behind — after a
## restart of the mod (a new world, «start mod data anew», reloaded data) the old «Корпорации» and
## «Госдепартаменты» buttons stayed, pointing at freed windows. They go here, with our windows' entries in the
## game's list of mod windows.
func _drop_bar_buttons() -> void:
	world_ctl._drop_bar_buttons()


# ---------- links between the map and the window ----------


func _open_map() -> bool:
	return windows_ctl._open_map()


# ---------- console ----------

func _command(args: PackedStringArray) -> String:
	return console_ctl._command(args)


## A bar button as the player sees it: with Pax Corpface's new header the bottom bar is hidden and the button
## lives there as a proxy icon — the tutorial outlines that one.
func _shown_button(b: Button) -> Control:
	return hud_ctl._shown_button(b)


## Pax Corpface unloaded Pax Interface for its new header: the skin (off while Pax Interface was there) starts now.
func restart_hud_skin() -> void:
	hud_ctl.restart_hud_skin()


## Pax Corpface's interface is off (or Corpface is gone): the game's menu goes back to the game's own look.
func stop_hud_skin() -> void:
	hud_ctl.stop_hud_skin()


## The «Corporations» window over the game's whole window area (a setting in its ⚙): its minimum size follows the
## area (right of Pax Corpface's column, below the header); off — the window's own size again.
func _fit_fullscreen() -> void:
	hud_ctl._fit_fullscreen()


## The antimonopoly service's new terms of a share deal (trade buttons and orders): the player decides first.
func ask_terms(c: Dictionary, stake: float, amount: float, fee: float, buy: bool, on_accept: Callable) -> void:
	stakes_ctl.ask_terms(c, stake, amount, fee, buy, on_accept)


## A modal card «New terms of the deal» on the HUD: accept — on_accept; cancel — a notification.
func ask_deal(title: String, intro: String, rows: Array, note: String, on_accept: Callable, what: String) -> void:
	stakes_ctl.ask_deal(title, intro, rows, note, on_accept, what)


## A zone's window (the corporations' «Zones» screen, dashboard.gd) — from the map's zone layer or the home.
func open_zone(id: String) -> void:
	zones_ctl.open_zone(id)


# ---------- economic unions: joining, leaving, founding (zones.gd) ----------

## The player's country's attitude of a country (0..1), for the unions' conditions.
func zone_relation(country: String) -> float:
	return zones_ctl.zone_relation(country)


## Why the player's country cannot join ("" — it can).
func zone_join_block(id: String) -> String:
	return zones_ctl.zone_join_block(id)


## Why the player cannot join, in full words ("" — he can): which customs union holds him, how warm the members are.
func zone_join_reason(id: String) -> String:
	return zones_ctl.zone_join_reason(id)


func zone_join(id: String) -> String:
	return zones_ctl.zone_join(id)


## Leaving: the country's companies lose the single market at once (a share shock), the partners cool.
func zone_leave(id: String) -> String:
	return zones_ctl.zone_leave(id)


## Would this country join the player's new union? [yes, reason]: a member of another union refuses at once; below
## «вступление_от» it refuses; from «вступление_точно» it agrees; between — by chance growing with its attitude.
func zone_join_answer(country: String) -> Array:
	return zones_ctl.zone_join_answer(country)


## The chance a country agrees, 0..1 (−1 — it is in another union), for the list.
func zone_join_chance(country: String) -> float:
	return zones_ctl.zone_join_chance(country)


## A new union with the partners who agree. Returns {ok, line, agreed: [names], refused: [[name, reason]], id}.
func zone_found(partners: Array, title: String) -> Dictionary:
	return zones_ctl.zone_found(partners, title)


## A notification — not during a time skip, the wait for its results, or 4 s after (the news tell what happened).
func _toast(text: String) -> void:
	news_ctl._toast(text)
