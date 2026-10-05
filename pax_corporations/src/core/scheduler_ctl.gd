extends RefCounted
## The weekly schedule: the game's days queued as weeks, worked off phase by phase within a frame's budget,
## faster while the game skips time, waiting while it is busy; the frame's work (_process).
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")
const Host := preload("res://mods/pax_corporations/main.gd")
const Log := preload("res://mods/pax_corporations/src/shared/log.gd")

var app: Host   # the host: its modules and data
var _since_badges := 0.0
var _since_check := 0.0
var _since_refresh := 0.0
var _phase := 0
var _phase_paid: Dictionary = {}
var _digest_open := false             # weeks were queued since the last summary — close it when they are done
var _week_timing: Dictionary = {}
var _postponed := 0
var _ai_due := false
var _ai_weeks := 0
var _ai_skip := false


func _init(host: Host) -> void:
	app = host


## Weeks are queued and worked off in _process within a time budget per frame: a skip of months does not
## freeze the game, it takes a few frames. The summary closes when the queue is empty.
func _days_passed(_g: PaxGame, from_day: int, days: int) -> void:
	if not app._active:
		return
	app._days += days
	app.digest.begin(app.db, from_day)
	while app._days >= Host.WEEK:
		app._days -= Host.WEEK
		app._pending.append(from_day + days - app._days)
		_digest_open = true


## A week is worked off phase by phase (PHASES), as many phases a frame as fit into the budget — a week is
## never one long freeze; the heavy pure phases (economy, statuses) also run on worker threads (parallel.gd).
func _run_pending(budget_usec: int) -> void:
	if app._pending.is_empty() and app._phase_day < 0 and not _digest_open:
		return
	var start := Time.get_ticks_usec()
	while true:
		if app._phase_day < 0:
			if app._pending.is_empty():
				break
			# The game is still skipping: wait until a batch of weeks gathers — 8 weeks in one step cost about as much
			# as one week, so a skip of 10 years is ~65 steps instead of 520.
			if app._pending.size() < Host.SKIP_BATCH and _game_skipping():
				break
			# A long backlog: one step covers several weeks (the last one's day), the modules scale by db.dt.
			var k := _step_weeks()
			for i in k:
				app._phase_day = int(app._pending.pop_front())
			app.db.dt = k
			if k > 1:
				_ai_skip = true   # after a skip the AI batch goes at once
			_phase = 0
			_week_timing = {}
		var t := Time.get_ticks_usec()
		_run_phase(app._phase_day, _phase)
		_lap(_week_timing, Host.PHASES[_phase], t)
		_phase += 1
		if _phase >= Host.PHASES.size():
			app._phase_day = -1
			app.last_week_usec = _week_timing.duplicate()
			for k: Variant in app.db.last_timing.keys():
				app.last_week_usec["recompute." + str(k)] = app.db.last_timing[k]
			app._refresh_wanted = true
		if Time.get_ticks_usec() - start >= budget_usec:
			break
	if app._pending.is_empty() and app._phase_day < 0:
		app.digest.close(app.db, app._game.day(), app._player_country(), app._favorites())
		_digest_open = false
		app._refresh_wanted = true
		app.db.dt = 1
		app._flush_skip_news()
		_ai_due = true     # one AI batch (narrator.gd) — every few weeks, never while the game itself waits for its AI


## The time a frame may spend on the queued weeks. Only while the GAME itself skips time (its own flags) may a
## frame work long — the picture does not matter then. In play (also right after loading a save with weeks still
## queued) a frame gets a small budget, so the frame rate holds and the backlog is worked off in the background.
func _budget() -> int:
	if app._pending.size() > 4 and _game_skipping():
		return Host.SKIP_BUDGET_USEC
	if app._pending.size() > Host.EXACT_WEEKS:
		return Host.CATCHUP_BUDGET_USEC
	return Host.FRAME_BUDGET_USEC


func _game_skipping() -> bool:
	var main: Object = app._game.main
	for flag in ["идёт_перемотка", "мотаем_до_события", "_прыжок_вперёд_машиной"]:
		var v: Variant = main.get(flag)
		if v is bool and v:
			return true
	return false


## How many weeks the next step covers: 1 in normal play and short skips, more when the backlog is long.
func _step_weeks() -> int:
	var n := app._pending.size()
	if _game_skipping():
		return clampi(n, 1, Host.MAX_STEP_WEEKS)
	if n <= Host.EXACT_WEEKS:
		return 1
	return clampi(ceili(float(n) / Host.SKIP_STEPS), 2, mini(Host.MAX_STEP_WEEKS, n))


## Finishes a week that is half done (before saving or a console week) — the data must not stay half-way.
func _finish_week() -> void:
	while app._phase_day >= 0:
		_run_phase(app._phase_day, _phase)
		_phase += 1
		if _phase >= Host.PHASES.size():
			app._phase_day = -1


## The game itself is skipping time or waiting for its AI's results of a skip: the mod's AI requests wait, so the
## game's own report is not queued behind them.
func _game_busy() -> bool:
	if _game_skipping():
		return true
	var w: Variant = app._game.main.get("_ждём_последствий")
	if w is bool and w:
		return true
	var res: Variant = app._game.main.get("итоги_ждём")
	return res is Dictionary and not (res as Dictionary).is_empty()


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	GameApi.perf("corporations.scheduler_ctl.process", t0)


func _process_body(delta: float) -> void:
	if not app._active or app._game == null or Pax.game != app._game:
		return
	app._hide_game_hint()
	if _ai_due and not _game_busy() and app.narrator != null:
		_ai_due = false
		_ai_weeks += 1
		if _ai_weeks >= int((app.db.balance.get("neural_net", {}) as Dictionary).get("every_weeks", 2)) or _ai_skip:
			_ai_weeks = 0
			_ai_skip = false
			app.narrator.flush()
	# Budget-aware scheduling: after a heavy frame (the map redrawing its layers) the week's work waits a frame
	# or two, so two heavy things do not land in one frame — but never more than POSTPONE_MAX frames in a row.
	# Only in normal play (a week or less queued): a time skip queues many weeks and must not be slowed down.
	if delta > Host.SLOW_FRAME_SEC and _postponed < Host.POSTPONE_MAX and app._pending.size() < 2 \
			and (not app._post_queue.is_empty() or not app._pending.is_empty() or app._phase_day >= 0):
		_postponed += 1
	elif not app._post_queue.is_empty():
		_postponed = 0
		app._post(app._post_queue.pop_front())
	else:
		_postponed = 0
		_run_pending(_budget())
	app._fit_fullscreen()
	_since_refresh += delta
	if app._refresh_wanted and (_since_refresh >= Host.REFRESH_EVERY or app._pending.is_empty()):
		app._refresh_wanted = false
		_since_refresh = 0.0
		if is_instance_valid(app._window) and app._window.is_visible_in_tree():
			var t := Time.get_ticks_usec()
			app._window.refresh()
			app.last_refresh_usec = Time.get_ticks_usec() - t
		if is_instance_valid(app._dept_window) and app._dept_window.is_visible_in_tree():
			app._dept_window.refresh()
		if is_instance_valid(app._dev) and app._dev.visible:
			app._dev.refresh()
	if app._compat_in > 0.0:
		app._compat_in -= delta
		if app._compat_in <= 0.0:
			app.compat = Host.Compat.new()
			app.compat.on_reset = app._reset_mod_data
			app.compat.show(app, app._game, app._compat_flags, app._compat_saved)
	if app._whatsnew_in > 0.0 and (app._compat_in > 0.0 or (app.compat != null and app.compat.is_open())):
		app._whatsnew_in = 1.0   # «what's new» waits until the compatibility warning is answered
	if app._whatsnew_in > 0.0:
		app._whatsnew_in -= delta
		if app._whatsnew_in <= 0.0:
			app.whatsnew.maybe_show()
	# The tutorial's offer waits until «what's new» is closed.
	if app._tutorial_in > 0.0 and not app.whatsnew.is_open():
		app._tutorial_in -= delta
		if app._tutorial_in <= 0.0:
			app.tutorial.offer()
	_since_badges += delta
	if _since_badges >= 0.5:
		_since_badges = 0.0
		app._update_badges()
	_since_check += delta
	if _since_check < 1.0:
		return
	_since_check = 0.0
	# The game may rebuild its map (another planet, a loaded save) — follow it.
	# From orbit the layer moves onto the 3D Earth and back when the flat map opens (windows_ctl.layer_target).
	var map := app.windows_ctl.layer_target()
	if map != null and (not is_instance_valid(app._layer) or not app._layer.is_attached_to(map)):
		Log.info("map", "corporations layer → %s" % ("the 3D Earth" if map == app._globe else "the flat map"))
		app._attach_layer()


## One game week: the world's events reach the companies, then people and money, then prices (they follow
## the money), then statuses; taxes and dividends go to the treasuries, news to the player.
## `timing` (console «corp bench») collects microseconds per phase.
func _week(day: int, timing: Dictionary = {}) -> void:
	_finish_week()
	app.db.dt = 1
	for i in Host.PHASES.size():
		var t := Time.get_ticks_usec()
		_run_phase(day, i)
		_lap(timing, Host.PHASES[i], t)


func _run_phase(day: int, phase: int) -> void:
	match phase:
		0:
			app.events.step(app.db, app._game, day)
		1:
			app.goods.step(app.db, app._game)
		2:
			app.rivals.step(app.db, app._game, app.goods, app.debt, day)
		3:
			app.lifecycle.step(app.db, app._game, app.goods, app.debt, app.events, app.rivals, day)
		4:
			app.debt.step(app.db, day)
		5:
			app.conditions.step(app.departments, app.goods, app.events, day)   # roads, power, health… where the companies work
			_phase_paid = app.economy.step(app.db, day, {"кризис": app.events.crisis_on(), "taxes": app._tax_rates()})
		6:
			app.market.step(app.db, day)
		7:
			app.db.recompute()
			app.frames.step(app.db, day, app._player_country())   # status frames follow the new world places
			if is_instance_valid(app.buildings) and app._pending.size() <= 1:
				app.buildings.rebuild()   # towers grow, strikes smoke, ruins (not every step of a long skip)
		8:
			app.politics.step(app.db, app._game, day, app._favorites())
			app.antitrust.step(app.db, app._game, float(app.departments.funding.get("antitrust", 1.0)), app.rivals, day)
			app.influence.step(day, app.politics, app.departments.gdp(app._game, app.goods, app._player_country()))
			app.orders.step(day)
			app.state_goals.step(day)   # the states act on what they lack, fear and want (after the player's orders)
			app.arena.step(day, app.lifecycle.events_for_letters)
			app.investments.step(day)
			app.techlevel.step(day)   # research companies' technology level (before the trees: it scales their effects)
			app.tree.step(app.db, day, app._player_country(), app.lifecycle.events_for_letters)
			app.capabilities.step(day)   # what the country can do now that its trees changed
			app.letters.step(app.politics, app.lifecycle, day)
		9:
			app._pay_treasuries(_phase_paid)
			if app.db.dept_fines > 0.0:
				app._game.add_resource(app._game.home_body(), "money", app.db.dept_fines)   # antimonopoly fines go to the state
				app.db.dept_fines = 0.0
			app.departments.step(app.db, app._game, app.goods, _phase_paid)   # the state spends: the player's departments, the others'
			_phase_paid = {}
			app._deliver_news(day)
			if app.econ_watch != null:
				app.econ_watch.week(app.db, app._game, app._player_country(), _counters(), func(line: String) -> void: Log.info("econ", line))


## The modules' counters since the start (the economy watch takes the year's difference).
func _counters() -> Dictionary:
	var out := {}
	for pair in [["life", app.lifecycle.stats], ["rivals", app.rivals.stats]]:
		var d: Dictionary = pair[1]
		for k in d.keys():
			if d[k] is int or d[k] is float:
				out["%s.%s" % [str(pair[0]), str(k)]] = int(d[k])
	return out


static func _lap(timing: Dictionary, key: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	timing[key] = int(timing.get(key, 0)) + (now - since)
	return now
