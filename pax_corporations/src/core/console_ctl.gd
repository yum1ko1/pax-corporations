extends RefCounted
## The mod's console commands (corp …).
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const Host := preload("res://mods/pax_corporations/main.gd")

var app: Host   # the host: its modules and data


func _init(host: Host) -> void:
	app = host


func _command(args: PackedStringArray) -> String:
	if not app._active:
		return "Pax Corporations: no world or no companies"
	var cmd := args[0] if args.size() > 0 else "list"
	match cmd:
		"econ":
			# corp econ — the yearly snapshots of the corporate world (econ_watch.gd); corp econ now — one more now.
			if args.size() > 1 and args[1] == "now" and app.econ_watch != null:
				var s := app.econ_watch.take(app.db, app._game, app._player_country(), {}, false)
				return "\n".join(app.econ_watch.lines(s, {}))
			return app.econ_watch.table() if app.econ_watch != null else "no economy watch"
		"goals":
			# corp goals — what each state wanted at its last review (state_goals.gd).
			var g := app.state_goals.agenda_text()
			return "\n".join(g) if not g.is_empty() else "no reviews yet"
		"map":
			return app._layer.debug_info() if is_instance_valid(app._layer) else "no map layer"
		"life":
			# corp life — stage 3 lifecycle totals, the world's births and deaths, the antimonopoly service.
			var out: PackedStringArray = ["lifecycle: %s" % str(app.lifecycle.stats), "companies: %d, gone: %d" % [app.db.companies.size(), app.db.gone.size()],
				"antimonopoly mood %.1f, parts %s, cases %d" % [app.antitrust.mood, str(app.antitrust.parts), app.antitrust.cases.size()],
				"letters: %d, unread %d" % [app.letters.letters.size(), app.letters.unread()]]
			for w in app.lifecycle.world.slice(maxi(0, app.lifecycle.world.size() - 10)):
				out.append("  day %d %s %s (%s)" % [int(w["день"]), str(w["вид"]), app.db.text(w.get("название", "")), str(w.get("country", ""))])
			return "\n".join(out)
		"bankrupt":
			# corp bankrupt <id> — a temporary manager now (12 weeks, then the outcome).
			if args.size() < 2 or app.db.company(args[1]).is_empty():
				return "usage: corp bankrupt <id>"
			app.lifecycle._start_procedure(app.db, app.db.company(args[1]), app.db.econ(app.db.company(args[1])), 12, app._game.day())
			return "procedure started"
		"born":
			# corp born [country] — a company is born now.
			var where := args[1] if args.size() > 1 else app._player_country()
			var born := app.lifecycle._give_birth(app.db, app._game, app.goods, app.events, where, "", "", (app.db.balance.get("lifecycle", {}) as Dictionary).get("births", {}), app._game.day())
			app.goods.baseline(app.db)
			app.db.recompute()
			return "born: %s" % (str(born.get("id", "")) + " " + app.db.name_of(born) if not born.is_empty() else "nothing (no place or market)")
		"letter":
			# corp letter — an offer arrives now.
			app.letters._offer(app._player_country(), app._game.day())
			return "letters: %d, unread %d" % [app.letters.letters.size(), app.letters.unread()]
		"am":
			# corp am <0..100> — set the antimonopoly service's mood.
			if args.size() > 1:
				app.antitrust.mood = clampf(float(args[1]), 0.0, 100.0)
				app.db.antitrust_mood = app.antitrust.mood
			return "antimonopoly mood %.1f" % app.antitrust.mood
		"rivals":
			# corp rivals — stage 3 so far: moves, wars, takeovers, breakups.
			var lines: PackedStringArray = ["totals since the start: %s" % str(app.rivals.stats)]
			for w in app.rivals.wars:
				lines.append("war: %s vs %s, %d weeks, heat %.2f" % [str(w["a"]), str(w["b"]), int(w["weeks"]), float(w["heat"])])
			for d in app.rivals.deals:
				lines.append("deal day %d: %s %s → %s (%s)" % [int(d["день"]), str(d["вид"]), str(d["a"]), str(d["b"]), app.db.percent(float(d["доля"]))])
			var hot: Array = app.rivals.tension.keys()
			hot.sort_custom(func(a, b): return float(app.rivals.tension[a]) > float(app.rivals.tension[b]))
			for k in hot.slice(0, 5):
				lines.append("tension %s: %.2f" % [str(k), float(app.rivals.tension[k])])
			return "\n".join(lines)
		"war":
			# corp war <a> <b> — push two companies over the edge (the war starts next week).
			if args.size() < 3 or app.db.company(args[1]).is_empty() or app.db.company(args[2]).is_empty():
				return "usage: corp war <id> <id>"
			app.rivals.tension[Host.Rivals._pair(args[1], args[2])] = 5.0
			return "tension set — skip a week (corp week 1)"
		"takeover":
			# corp takeover <buyer> <target> — a takeover attempt right now.
			if args.size() < 3 or app.db.company(args[1]).is_empty() or app.db.company(args[2]).is_empty():
				return "usage: corp takeover <buyer> <target>"
			app.rivals._try_takeover(app.db, app.goods, app.debt, app.db.company(args[1]), app.db.company(args[2]), app.db.balance.get("competition", {}), app._game.day())
			app.db.recompute()
			return "owners of %s: %s" % [args[2], str(app.db.company(args[2]).get("owners", []))]
		"split":
			# corp split <id> — the company falls apart now.
			if args.size() < 2 or app.db.company(args[1]).is_empty():
				return "usage: corp split <id>"
			var child := app.rivals.split(app.db, app.db.company(args[1]), "breakup", app._game.day())
			app.db.recompute()
			return "new company: %s" % (str(child.get("id", "")) if not child.is_empty() else "none (a single site)")
		"bench":
			# corp bench [weeks] — how long a week takes, by phase (to find what slows long skips down).
			var n := int(args[1]) if args.size() > 1 else 4
			var timing := {}
			var start := Time.get_ticks_usec()
			app.digest.begin(app.db, app._game.day())
			for i in n:
				app._week(app._game.day(), timing)
			app.digest.close(app.db, app._game.day(), app._player_country(), app._favorites())
			var total := Time.get_ticks_usec() - start
			var lines: PackedStringArray = ["%d companies, %d week(s): %.1f ms a week · threads %s (%d chunks)" % [app.db.companies.size(), n,
				total / 1000.0 / n, "on" if Host.Parallel.enabled else "off", Host.Parallel.threads_used]]
			for k in timing.keys():
				lines.append("  %-14s %.2f ms" % [str(k), float(timing[k]) / 1000.0 / n])
			var t0 := Time.get_ticks_usec()
			if is_instance_valid(app._window):
				app._window.refresh()
			lines.append("  window refresh %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
			return "\n".join(lines)
		"threads":
			# corp threads on|off — worker threads for the economy and statuses (compare with corp bench).
			if args.size() > 1:
				Host.Parallel.enabled = args[1] != "off"
			return "threads: %s" % ("on" if Host.Parallel.enabled else "off")
		"week":
			var n := int(args[1]) if args.size() > 1 else 1
			app.digest.begin(app.db, app._game.day())
			for i in n:
				app._week(app._game.day())
			app.digest.close(app.db, app._game.day(), app._player_country(), app._favorites())
			if is_instance_valid(app._window):
				app._window.refresh()
			return "%d week(s) simulated" % n
		"shock":
			# corp shock <id|all> <factor> — multiply demand (0.7 = −30%) to test layoffs, discontent, strikes.
			if args.size() < 3:
				return "usage: corp shock <id|all> <factor>"
			var factor := float(args[2])
			var hit := 0
			for item in app.db.companies:
				var c: Dictionary = item
				if args[1] == "all" or str(c["id"]) == args[1]:
					var e := app.db.econ(c)
					if not e.is_empty():
						e["demand"] = float(e["demand"]) * factor
						hit += 1
			return "demand ×%s for %d companies — skip a few weeks (corp week 8)" % [args[2], hit]
		"debt":
			# corp debt <id> [инвест_кредит|штраф|переоценка|госпомощь|владелец_погасил|списание|досрочно]
			if args.size() < 2 or app.db.company(args[1]).is_empty():
				return "usage: corp debt <id> [kind]"
			var c := app.db.company(args[1])
			app.debt.force_event(app.db, c, app._game.day(), args[2] if args.size() > 2 else "")
			app.db.recompute()
			if is_instance_valid(app._window):
				app._window.refresh()
			return "debt of %s: %s, rate %.1f%%" % [args[1], app.db.money(app.db.fund(c, "debt")), 100.0 * float(app.db.econ(c).get("rate", 0.0))]
		"crisis":
			app.events.force_crisis(app._game.day())
			return "world financial crisis started — skip a few weeks (corp week 4)"
		"events":
			var lines: PackedStringArray = []
			for country in app.events.signals.keys():
				lines.append("%s: %s" % [str(country), str(app.events.signals[country])])
			lines.append("crisis: %s" % str(app.events.crisis))
			lines.append("market news: %s" % str(app.events.market_news()))
			lines.append("to our treasury: %s a year" % app.db.money(app.treasury_year()))
			return "\n".join(lines)
		"show":
			if args.size() < 2 or app.db.company(args[1]).is_empty():
				return "usage: corp show <id>"
			app._window.open_company(args[1])
			return "opened " + args[1]
		_:
			var lines: PackedStringArray = []
			if is_instance_valid(app._layer):
				lines.append("map zoom %.2f" % app._layer.zoom())
			for c in app.db.companies:
				lines.append("#%d %s  %s  staff %s  wage $%d  satisf %.0f%%  exposure %+.2f  index %.1f  %s  breakup %.1f%%" % [
					int(c["_world_place"]), str(c["id"]), app.db.money(app.db.cap(c)), app.db.people(app.db.staff(c)), int(app.db.wage(c)),
					100.0 * float(app.db.econ(c).get("H", 0.5)), float((c.get("_climate", {}) as Dictionary).get("total", 0.0)),
					float(c["_index"]), str(c["_rating"]), float((c["_breakup"] as Dictionary)["value"])])
			return "\n".join(lines)
