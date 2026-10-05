extends RefCounted
## The player founds a company: where, what it costs, the founding itself; the game's AI assistant and letters to a head.
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")   # Main's methods, 0.24 names
const Host := preload("res://mods/pax_corporations/main.gd")

var app: Host   # the host: its modules and data


func _init(host: Host) -> void:
	app = host


## Who the player is and what they have: {"polity": bool, "name": the person's name, "money": млн $,
## "место": the default headquarters place, "country": the player's country}.
func founding_info() -> Dictionary:
	var role: Variant = app._game.main.get("роль_игрока")
	var pf: Dictionary = app._game.player_faction()
	var lead: Variant = pf.get("leader", {})
	var person := str((lead as Dictionary).get("name", "")) if lead is Dictionary else ""
	return {"polity": role == null or str(role) in ["country", ""], "name": person, "money": app.treasury_money(),
		"место": _default_place(), "country": app._player_country()}


## Where the player's country's companies mostly sit (usually the capital), else any province of the country.
func _default_place() -> Dictionary:
	var count := {}
	for item in app.db.companies:
		var c: Dictionary = item
		if str(c.get("_country", "")) == app._player_country():
			var pid := int(app.db.hq_of(c).get("province", -1))
			count[pid] = int(count.get(pid, 0)) + 1
	var best := -1
	for pid in count.keys():
		if best < 0 or int(count[pid]) > int(count[best]):
			best = int(pid)
	if best < 0:
		var mine := Host.Data.provinces_of(Host.Data.province_owners(), app._player_country())
		if not mine.is_empty():
			best = int(mine[0])
	return place_of(best, app._player_country())


## A place in a province (the map's numbering, data/regions2.json). at — the clicked point (latitude, longitude):
## the headquarters stand exactly where the player clicked; without it (or when it is far from the province's
## centre — a wrapped map) — the centre of the province.
func place_of(pid: int, owner: String, at: Vector2 = Vector2.INF) -> Dictionary:
	var info := app.db.province_info(pid)
	if info.is_empty():
		app.log_warning("found: province %d is unknown (data/regions2.json)" % pid)
		return {}
	var names: Dictionary = info.get("имена", {})
	var lat := float(info["ш"])
	var lon := float(info["д"])
	if at.is_finite() and Vector2(at.y - lon, at.x - lat).length() < 12.0:
		lat = at.x
		lon = at.y
	app.log_info("found: province %d «%s» of %s, centre %.2f/%.2f, place %.2f/%.2f" % [pid, str(names.get("ru", pid)), owner, float(info["ш"]), float(info["д"]), lat, lon])
	return {"province": pid, "ш": lat, "д": lon, "name_ru": str(names.get("ru", pid)), "имя_en": str(names.get("en", pid)),
		"country": owner}


func founding_preview(goods_key: String, capital: float, country: String) -> Dictionary:
	return Host.Founding.propose(app.db, app.goods, app.events, country, goods_key, capital)


## The window hides, the map opens, the next click on a province of the player's country becomes the place.
func pick_place(done: Callable) -> void:
	app._close_window()
	if not app._open_map():
		done.call({})
		return
	app._toast(app.tr_key("pax_corporations_found_pick_hint"))
	app._layer.pick_province(func(pid: int, owner: String, at: Vector2) -> void:
		if pid >= 0 and owner != app._player_country():
			app._toast(app.tr_key("pax_corporations_found_err_not_ours"))
			pid = -1
		if is_instance_valid(app._window):
			app._window.show_window()
		done.call(place_of(pid, owner, at) if pid >= 0 else {}))


## Founds the company: the money leaves the treasury, the company joins the world at once.
## spec: {название, описание, товар, капитал, место, спросить_ии}. Returns "" or an error text.
func found_company(spec: Dictionary) -> String:
	var info := founding_info()
	var capital := float(spec.get("capital", 0.0))
	var place: Dictionary = spec.get("место", {})
	if str(spec.get("название", "")).strip_edges().is_empty():
		return app.tr_key("pax_corporations_found_err_name")
	if place.is_empty():
		return app.tr_key("pax_corporations_found_err_place")
	if capital > float(info["money"]):
		return app.tr_key("pax_corporations_found_err_money")
	var country := str(place.get("country", app._player_country()))
	var p := Host.Founding.propose(app.db, app.goods, app.events, country, str(spec["goods_key"]), capital)
	if not bool(p["ok"]):
		return app.tr_key("pax_corporations_" + str(p["why"]))
	var verdict := {"decision": "молча", "fee": 0.0, "ключ": ""}
	if bool(info["polity"]):
		# The antimonopoly service reviews a new state company at once (antitrust.gd).
		verdict = app.antitrust.review_founding(app.db, app.goods, country, str(spec["goods_key"]), capital)
		if str(verdict["decision"]) == "ban":
			app._service_says(str(verdict["ключ"]), [str(spec["название"]).strip_edges()])
			return app.tr_key("pax_corporations_found_err_antitrust")
		if capital + float(verdict["fee"]) > float(info["money"]):
			return app.tr_key("pax_corporations_found_err_money")
		if str(verdict["decision"]) == "условие" and not bool(spec.get("_terms_accepted", false)):
			var fee := float(verdict["fee"])
			var nm := str(spec["название"]).strip_edges()
			app.ask_deal(app.tr_key("pax_corporations_am_deal_title"), app.tr_key("pax_corporations_am_deal_found_intro") % nm, [
				[app.tr_key("pax_corporations_am_deal_capital"), app.db.money(capital)],
				[app.tr_key("pax_corporations_am_deal_fee") % app.db.percent(fee / maxf(capital, 1e-6)), app.db.money(fee), true],
				[app.tr_key("pax_corporations_am_deal_total"), app.db.money(capital + fee)],
				[app.tr_key("pax_corporations_am_deal_left"), app.db.money(float(info["money"]) - capital - fee)]],
				app.tr_key("pax_corporations_am_deal_note"), func() -> void:
					var again := spec.duplicate()
					again["_terms_accepted"] = true
					var err := found_company(again)
					if not err.is_empty():
						app._toast(err), nm)
			return ""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var full := spec.duplicate()
	full.merge({"country": country, "polity": bool(info["polity"]), "founder": str(info["name"]),
		"год": int(app._game.date().get("year", 2026)), "день": app._game.day(), "character_ru": "", "character_en": ""}, true)
	full["название"] = str(spec["название"]).strip_edges()
	var c := Host.Founding.build(app.db, p, full, rng)
	app._game.add_resource(app._game.home_body(), "money", -capital - float(verdict["fee"]))
	app.db.add_company(c)
	app.economy.init_company(app.db, c)
	app.goods.baseline(app.db)
	app.debt.init_company(app.db, c, app._game.day())
	app.db.recompute()
	app.letters.on_founded(c, app._game.day())
	if bool(info["polity"]):
		app.antitrust.remember(app.db, "founding", 1.0)
	var text := app.tr_key("pax_corporations_found_done") % [app.db.name_of(c), app.db.money(capital)]
	app._toast(text)
	if str(verdict["decision"]) != "молча":
		app._service_says(str(verdict["ключ"]), [app.db.name_of(c), app.db.money(float(verdict["fee"]))] if float(verdict["fee"]) > 0.0 else [app.db.name_of(c)])
	if is_instance_valid(app._window):
		app._window.favorites[str(c["id"])] = true
		app._window.open_company(str(c["id"]))
	if bool(spec.get("ask_ai_flag", true)) and GameApi.has(app._game.main, "_спросить_помощника"):
		ask_assistant(app.tr_key("pax_corporations_found_ai") % [app.db.name_of(c), app.goods.goods_name(app.db, c), place.get("name_ru", ""),
			app.db.money(capital), app.db.money(float(p["выручка"])), app.db.people(float(p["staff"])), app.db.percent(float(p["доля"])),
			app._window.situation_text(c) if is_instance_valid(app._window) else ""])
	return ""


## Opens the game's assistant window and asks it (Main._спросить_помощника). False if it cannot now.
func ask_assistant(text: String) -> bool:
	var main: Object = app._game.main
	if not GameApi.has(main, "_спросить_помощника"):
		app._toast(app.tr_key("pax_corporations_ai_unavailable"))
		return false
	if main.has_method("_печатает") and bool(main.call("_печатает")):
		app._toast(app.tr_key("pax_corporations_ai_busy"))
		return false
	var win: Variant = main.get("окно_помощника")
	if win is Control and not (win as Control).is_visible_in_tree() and GameApi.has(main, "_переключить_окно"):
		GameApi.call_main(main, "_переключить_окно", [win])
	GameApi.call_main(main, "_спросить_помощника", [text])
	return true


## The player clicked the head's name in the dossier: the head becomes a contact of the game (if not yet) and the
## game's own conversation with them opens (Main._говорить_с_контактом) — the game's AI plays the head.
func write_head(cid: String) -> void:
	var c := app.db.company(cid)
	if c.is_empty():
		return
	var person := app.politics.add_head(app.db, app._game, c)
	var main: Object = app._game.main
	if person.is_empty() or not GameApi.has(main, "_говорить_с_контактом"):
		app._toast(app.tr_key("pax_corporations_head_write_unavailable"))
		return
	if GameApi.has(main, "_обновить_контакты"):
		GameApi.call_main(main, "_обновить_контакты")
	app._close_window()
	GameApi.call_main(main, "_говорить_с_контактом", [person])
