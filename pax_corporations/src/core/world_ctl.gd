extends RefCounted
## The mod's life: loading, the world's start (every module made and bound), the save, data reload, teardown.
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const Host := preload("res://mods/pax_corporations/main.gd")
const KeyMigration := preload("res://mods/pax_corporations/src/shared/key_migration.gd")
const Log := preload("res://mods/pax_corporations/src/shared/log.gd")
const TierLook := preload("res://mods/pax_corporations/src/shared/tier_look.gd")

var app: Host   # the host: its modules and data
var _state: Dictionary = {}


func _init(host: Host) -> void:
	app = host


func _mod_loaded() -> void:
	Log.setup(app, "pax_corporations")
	app.hook("order_parsed", app._on_order)   # the antimonopoly service hears the player's orders
	app.hook("report_ready", func(d: Dictionary) -> void:
		if app._active and app.narrator != null:
			app.narrator.on_report(d, _player_country()))
	# Country capabilities (capabilities.gd): research of a closed one gets no chance; the order interpreter gets
	# a short registry of what the country can and cannot do.
	app.hook("research_priced", func(d: Dictionary) -> void:
		if app._active and app.capabilities != null:
			app.capabilities.research(d))
	app.hook("ai_request", func(d: Dictionary) -> void:
		if app._active and app.capabilities != null and str(d.get("channel", "")) == "interpreter":
			d["system"] = str(d.get("system", "")) + "\n\n" + app.capabilities.registry_text(_player_country())
		# The game's report of a skip: accidents are rolled by the game (report_rules.gd), not decided by the AI.
		if app._active and app.report_rules != null:
			app.report_rules.on_request(d, _player_country()))
	app.hook("election_held", func(d: Dictionary) -> void:
		if app._active and app.influence != null:
			app.influence.on_election(d))
	Host.Zones.load_cfg(app)   # economic zones and their rules (zones.gd)
	app.hud_skin = Host.HudSkin.new()
	app.hud_skin.name = "PaxCorporationsHudSkin"
	app.add_child(app.hud_skin)
	# The game's own menu is Pax Corpface's business: the skin starts only when Corpface's interface stands
	# (Corpface calls restart_hud_skin / stop_hud_skin). Without Corpface the game's menu stays the game's own,
	# with just the «Corporations», «Development» and «Departments» buttons added.
	Pax.register_command("corp", app._command,
		"corp [list|week N|bench N|threads on|off|show <id>|shock <id|all> <factor>|events|crisis|debt <id> [kind]] — Pax Corporations: companies, weeks, timing, dossier, tests")


func _mod_unloaded() -> void:
	Log.shutdown(app)
	TierLook.stop()
	_teardown()
	if is_instance_valid(app.hud_skin):
		app.hud_skin.restore()
		app.hud_skin.queue_free()
	app.hud_skin = null


func _game_loaded(_g: PaxGame, state: Dictionary) -> void:
	KeyMigration.renamed = 0
	_state = KeyMigration.migrate(state) as Dictionary   # a save made before the keys were English
	if KeyMigration.renamed > 0:
		Log.info("save", "an old save: %d Russian keys renamed to English" % KeyMigration.renamed)


func _world_ready(game: PaxGame) -> void:
	_teardown()
	app._game = game
	Log.info("life", "world start, %s" % ("a loaded save" if not _state.is_empty() else "a new game"))
	app.db = Host.Data.new()
	app.db.load_all(app)
	app.market = Host.Market.new()
	app.economy = Host.Economy.new()
	app.events = Host.Events.new()
	app.politics = Host.Politics.new()
	app.digest = Host.Digest.new()
	app.debt = Host.Debt.new()
	app.goods = Host.Goods.new()
	app.rivals = Host.Rivals.new()
	app.rivals.setup(app)
	app.departments = Host.Departments.new()
	app.departments.load_state(_dict(_state, "state_departments"))
	app.lifecycle = Host.Lifecycle.new()
	app.letters = Host.Letters.new()
	app.antitrust = Host.Antitrust.new()
	app.badges = Host.Badges.new()
	app.orders = Host.Orders.new()
	app.arena = Host.Arena.new()
	app.influence = Host.Influence.new()
	app.investments = Host.Investments.new()
	app.conditions = Host.Conditions.new()
	app.capabilities = Host.Capabilities.new()
	app.report_rules = Host.ReportRules.new()
	app.techlevel = Host.TechLevel.new()
	app.narrator = Host.Narrator.new()
	app.tutorial = Host.Tutorial.new()
	app.whatsnew = Host.WhatsNew.new()
	app.frames = Host.Frames.new()
	app.tree = Host.DevTree.new()
	app.tree.load_cfg(app)
	app.state_goals = Host.StateGoals.new()
	Host.Frames.fx = clampi(int(app.get_setting("frames_fx", 2)), 0, 2)
	Host.Frames.on_map = bool(app.get_setting("frames_on_map", true))
	if app.db.companies.is_empty():
		app.log_warning("no companies loaded — the mod stays idle")
		return
	if _state.is_empty():
		app.market.start_new()
		app.economy.start_new()
		app.events.start_new()
		app.debt.start_new()
		app.rivals.start_new()
		app.lifecycle.start_new()
		app.letters.start_new()
		app.antitrust.start_new()
		app.orders.start_new()
		app.arena.start_new()
		app.influence.start_new()
		app.investments.start_new()
		app.tree.start_new()
		app.state_goals.start_new()
		Host.Zones.load_state({})   # the unions as in the config (a new world)
		app._tutorial_in = 6.0   # a new game: offer the tutorial once the game's own intro is over
	else:
		# Companies born in the game come back first — the other modules' saved state refers to them.
		Host.Rivals.restore_companies(app.db, _dict(_state, "competition"))
		app.rivals.load_state(_dict(_state, "competition"))
		# Companies that left the game go, moved ones move, new heads take over — before the rest loads.
		app.lifecycle.restore(app.db, _dict(_state, "жизнь"))
		if not bool(_state.get("prov2", false)):
			app.db.migrate_all()   # a save from before the provinces were the map's own: its moved sites too
		app.antitrust.load_state(_dict(_state, "antitrust"))
		app.letters.load_state(_dict(_state, "letters"))
		app.orders.load_state(_dict(_state, "приказы"))
		app.arena.load_state(_dict(_state, "arena"))
		app.influence.load_state(_dict(_state, "influence"))
		app.investments.load_state(_dict(_state, "investments"))
		Host.Zones.load_state(_dict(_state, "zones"))
		app.conditions.load_state(_dict(_state, "условия"))
		app.capabilities.load_state(_dict(_state, "capabilities_list"))
		app.techlevel.load_state(_dict(_state, "tech_level"))
		app.narrator.load_state(_dict(_state, "neural_net"))
		Host.Frames.load_state(app.db, _dict(_state, "frames"))
		app.tree.load_state(_dict(_state, "tree"))
		app.state_goals.load_state(_dict(_state, "state_goals"))
		app.market.load_state(app.db, _dict(_state, "рынок"))
		app.economy.load_state(app.db, _dict(_state, "экономика"))
		app.events.load_state(_dict(_state, "события"))
		app.politics.load_state(_dict(_state, "policy"))
		app.digest.load_state(_state.get("digests", []))
		app.debt.load_state(_dict(_state, "debt"))
		Host.Stakes.load_state(app.db, _dict(_state, "owners"))
		app._days = int(_state.get("дни", 0))
		if _state.get("treasury") is Array:
			app.treasury_weeks = (_state["treasury"] as Array).duplicate()
		if int(_state.get("version", 0)) < 3:
			app.events.migrate_v3(app.db, app.market.week)
		if _state.get("queue") is Array:
			app._pending = (_state["queue"] as Array).duplicate()
		# A world saved before an incompatibility flag (config/compat.json): warn once the world is shown.
		app._compat_flags = Host.Compat.flags_after(app, _state)
		app._compat_saved = str(_state.get("mod_flag", "0"))
		app._compat_in = 1.5 if not app._compat_flags.is_empty() else -1.0
	app.db.recompute()
	app.tree.recompute(app.db)   # the trees' effects before the first week
	Host.Frames.init_missing(app.db)   # frames at once (a new game or companies without one); no waiting is counted
	app.economy.init_all(app.db)
	app.goods.setup(app.db, game, _dict(_state, "goods"))
	app.db.recompute()
	app.debt.init_all(app.db, game.day())
	app.db.recompute()
	app.politics.setup(game)
	app.departments.start(app.db, app.goods, _player_country())
	app.db.player_country = _player_country()
	app.letters.setup(app.db, game, app.rivals, app.antitrust, app.goods)
	app.orders.setup(app, app.db, game, app.goods, app.rivals, app.antitrust, app._order_says)
	app.arena.setup(app, app.db, game, app.goods, app.rivals, app._order_says)
	app.influence.setup(app, app.db, game, app.goods, func(c: Dictionary, role: String, day: int, why: String) -> void: app.lifecycle.replace_head(app.db, c, role, day, why), app._order_says)
	app.investments.setup(app, app.db, game, app.tree, app.arena, app._order_says)
	app.conditions.setup(app.db, game)
	app.capabilities.setup(app, app.db, game, app.tree, app.arena, app._order_says)
	app.report_rules.setup(app, app.db, game)
	app.state_goals.setup(app.db, game, app.goods, app.events, app.orders)
	if app.country_rank == null:
		app.country_rank = Host.CountryRank.new()
		app.country_rank.name = "PaxCorpCountryRank"
		app.country_rank.mod = app
		app.add_child(app.country_rank)
	app.country_rank.start(game)
	app.country_rank.load_state(_dict(_state, "rank"))
	app.econ_watch = Host.EconWatch.new()
	app.econ_watch.load_state(_dict(_state, "econ"))
	app.techlevel.setup(app.db, game, app.tree, app.conditions, app.events)
	app.techlevel.investments = app.investments
	app.investments.write_offer = func(c: Dictionary, country: String, text: String, offer: Dictionary) -> void: app.letters.government_offer(c, country, text, offer)
	app.letters.invest = app.investments
	app.orders.on_conflict = func(why: String, country: String, c: Dictionary) -> void: app.arena.crisis(why, country, c)
	app.orders.ask_terms = app.ask_terms
	app.orders.on_control = func(c: Dictionary) -> void:
		app.letters.on_control(c, app._game.day())
		app.lifecycle.replace_head(app.db, c, "госслужащий", app._game.day(), "nationalisation")
	app.orders.replace_head = func(c: Dictionary, role: String, day: int, why: String) -> void: app.lifecycle.replace_head(app.db, c, role, day, why)
	app._build_window(game, _state.get("favourites", []))
	app.narrator.setup(app, app.db, game, app.events, app.letters,
		func(c: Dictionary, e: Dictionary) -> String: return app._window.chron_text(c, e) if is_instance_valid(app._window) else "", app.treasury_year)
	app.lifecycle.on_rename = func(c: Dictionary, country: String) -> void: app.narrator.queue_rename(c, country)
	app.tutorial.setup(app, game, app.tutorial_action)
	app.whatsnew.setup(app, game, "pax_corporations_")
	app._whatsnew_in = 2.5
	app._window.on_tutorial = func(tour: String) -> void: app.tutorial.start(tour)
	app.narrator.rename_cb = func(c: Dictionary, title: Dictionary) -> void: app.lifecycle.rename(app.db, c, title, app._game.day())
	app._build_departments_window(game)
	app._build_development(game)
	app._attach_layer()
	app._active = true
	Engine.set_meta("pax_corporations_api", app)
	app._build_buildings.call_deferred()   # Pax Corpface reads the mod's resources through it, if installed
	_state = {}


static func _dict(d: Dictionary, key: String) -> Dictionary:
	return d[key] if d.get(key) is Dictionary else {}


func _save_state(_g: PaxGame) -> Dictionary:
	if not app._active:
		return {}
	app._finish_week()
	return {"version": Host.SAVE_VERSION, "mod_flag": Host.Compat.current(app), "дни": app._days, "рынок": app.market.save_state(app.db), "экономика": app.economy.save_state(app.db),
		"события": app.events.save_state(), "treasury": app.treasury_weeks, "queue": app._pending,
		"policy": app.politics.save_state(), "digests": app.digest.save_state(), "debt": app.debt.save_state(),
		"owners": Host.Stakes.save_state(app.db), "goods": app.goods.save_state(), "competition": app.rivals.save_state(app.db),
		"state_departments": app.departments.save_state(), "жизнь": app.lifecycle.save_state(app.db), "antitrust": app.antitrust.save_state(),
		"letters": app.letters.save_state(), "приказы": app.orders.save_state(), "arena": app.arena.save_state(), "influence": app.influence.save_state(), "investments": app.investments.save_state(), "zones": Host.Zones.state(), "prov2": true, "rank": app.country_rank.save_state() if app.country_rank != null else {}, "econ": app.econ_watch.save_state() if app.econ_watch != null else {}, "условия": app.conditions.save_state(), "capabilities_list": app.capabilities.save_state(), "tech_level": app.techlevel.save_state(), "neural_net": app.narrator.save_state(), "frames": Host.Frames.save_state(app.db), "tree": app.tree.save_state(),
		"state_goals": app.state_goals.save_state(),
		"favourites": app._window.favorites.keys() if is_instance_valid(app._window) else []}


func _data_reloaded() -> void:
	if app._active and app._game != null:
		var saved := _save_state(app._game)
		_state = saved
		_world_ready(app._game)


func _favorites() -> Dictionary:
	return app._window.favorites if is_instance_valid(app._window) else {}


func _player_country() -> String:
	return str(app._game.player_faction().get("name", ""))


## The compatibility warning's «start anew»: the mod's data in this world are dropped and the companies start as
## in a new game; the world itself (the game's own save) stays as it is.
func _reset_mod_data() -> void:
	if app._game == null:
		return
	_state = {}
	app._pending.clear()
	app._phase_day = -1
	app._days = 0
	app.treasury_weeks.clear()
	_world_ready(app._game)


func _teardown() -> void:
	if is_instance_valid(app.buildings):
		app.buildings.queue_free()
	app.buildings = null
	if Engine.has_meta("pax_corporations_api") and Engine.get_meta("pax_corporations_api") == app:
		Engine.remove_meta("pax_corporations_api")
	if app.compat != null:
		app.compat.teardown()
	app._compat_in = -1.0
	if is_instance_valid(app._dev):
		app._dev.queue_free()
	app._dev = null
	if is_instance_valid(app._dev_button):
		app._dev_button.queue_free()
	app._dev_button = null
	if app.tutorial != null:
		app.tutorial.teardown()
	if app.whatsnew != null:
		app.whatsnew.teardown()
	if app.badges != null:
		app.badges.teardown()
	app._corp_button = null
	app._active = false
	app._post_queue.clear()
	app._skip_news.clear()
	app._skip_letters = 0
	if is_instance_valid(app._layer):
		app._layer.detach()
	app._layer = null
	_drop_bar_buttons()
	if is_instance_valid(app._panel):
		app._panel.queue_free()
	app._panel = null
	app._window = null
	if is_instance_valid(app._dept_panel):
		app._dept_panel.queue_free()
	app._dept_panel = null
	app._dept_window = null


## A control inside one of the mod's own windows (its buttons are never bar buttons).
func _inside_ours(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p.has_meta(&"pax_corp_skin_skip"):
			return true
		p = p.get_parent()
	return false


## game.add_window puts a button into the bottom bar, and freeing the window leaves that button behind — after a
## restart of the mod (a new world, «start mod data anew», reloaded data) the old «Корпорации» and
## «Госдепартаменты» buttons stayed, pointing at freed windows. They go here, with our windows' entries in the
## game's list of mod windows.
func _drop_bar_buttons() -> void:
	if app._game == null or not is_instance_valid(app._game.main):
		return
	var main: Node = app._game.main as Node
	var ours: Array = [app._panel, app._dept_panel]
	var titles: PackedStringArray = [app.tr_key("pax_corporations_button").strip_edges(), app.tr_key("pax_corporations_dept_button").strip_edges()]
	# The whole tree, not only Main: «Pax Interface» copies mod buttons into its own dock (in the HUD layer), and
	# its copies of our old buttons stayed visible and dead.
	for b in app.get_tree().root.find_children("*", "Button", true, false):
		var btn := b as Button
		if btn == null or btn == app._dev_button or btn.is_queued_for_deletion() or _inside_ours(btn):
			continue
		var win: Variant = btn.get_meta("win") if btn.has_meta("win") else null
		# Ours by its window, or any button with our titles (before our windows are made, or at teardown, all such
		# buttons are leftovers).
		if (win != null and is_instance_valid(win) and ours.has(win)) or btn.text.strip_edges() in titles:
			btn.get_parent().remove_child(btn)
			btn.queue_free()
	var windows: Variant = main.get("окна_модов")
	if windows is Array:
		for w in ours:
			while (windows as Array).has(w):
				(windows as Array).erase(w)
