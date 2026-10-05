extends RefCounted
## The state's stakes: quotes and trades, the antimonopoly service's verdicts, the player's orders and the deal dialogs.
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const Host := preload("res://mods/pax_corporations/main.gd")

var app: Host   # the host: its modules and data


func _init(host: Host) -> void:
	app = host


## Money in the player's treasury, млн $.
func treasury_money() -> float:
	return float(app._game.resources(app._game.home_body()).get("money", 0.0))


func quote_trade(cid: String, fraction: float, buy: bool) -> Dictionary:
	var c := app.db.company(cid)
	if c.is_empty():
		return {"ok": false, "why": "stake_nothing", "доля": 0.0, "amount": 0.0, "premium": 0.0}
	# A country cold to the player does not let it buy into its companies (investments.gd, 16.5).
	var home := str(c.get("_country", ""))
	if buy and Host.Zones.closed(home, app._player_country()):
		return {"ok": false, "why": "zone_closed", "доля": 0.0, "amount": 0.0, "premium": 0.0}
	if buy and Host.Zones.screened(c, app._player_country()) and Host.Stakes.state_stake(c, app._player_country()) + fraction > Host.Zones.screen_cap() + 1e-6:
		return {"ok": false, "why": "zone_screened", "доля": 0.0, "amount": 0.0, "premium": 0.0}
	if buy and home != app._player_country() and app.investments != null \
			and app.investments.relation(home) < float((app.db.balance.get("investments", {}) as Dictionary).get("no_sale_to", 0.25)):
		return {"ok": false, "why": "inv_refused_sale", "доля": 0.0, "amount": 0.0, "premium": 0.0}
	return Host.Stakes.quote(app.db, c, app._player_country(), fraction, buy, treasury_money())


## The «Owners» tab's buttons: the player's state buys or sells a block of shares at once, even on pause.
## Returns the line shown to the player.
func trade(cid: String, fraction: float, buy: bool) -> String:
	var c := app.db.company(cid)
	var q := quote_trade(cid, fraction, buy)
	if c.is_empty() or not bool(q["ok"]):
		return app.tr_key("pax_corporations_" + str(q["why"]))
	var amount := float(q["amount"])
	# The antimonopoly service looks at the deal at once (antitrust.gd): it may ban it or ask a fee.
	var verdict := app.antitrust.review_stake(app.db, c, float(q["доля"]), amount, buy, app._game.day())
	var fee := float(verdict["fee"])
	if str(verdict["decision"]) == "ban":
		return _service_says(str(verdict["ключ"]), [app.db.name_of(c), app.db.percent(float(verdict.get("блок", q["доля"])))])
	if str(verdict["decision"]) == "условие":
		# The service approves only with a fee: the player sees the new terms first and decides.
		ask_terms(c, float(q["доля"]), amount, fee, buy, func() -> void:
			var line := _trade_now(c, q, verdict, buy)
			app._toast(line)
			if is_instance_valid(app._window) and app._window.is_visible_in_tree():
				app._window.refresh())
		return app.tr_key("pax_corporations_am_deal_wait")
	return _trade_now(c, q, verdict, buy)


## The trade itself, after the service's verdict (and the player's consent to its terms).
func _trade_now(c: Dictionary, q: Dictionary, verdict: Dictionary, buy: bool) -> String:
	var amount := float(q["amount"])
	var fee := float(verdict["fee"])
	if buy and amount + fee > treasury_money():
		return app.tr_key("pax_corporations_stake_no_money")
	app._game.add_resource(app._game.home_body(), "money", -(amount + fee) if buy else amount)
	var had := app.db.state_share(c)
	Host.Stakes.apply(app.db, c, app._player_country(), q, buy, app._game.day())
	if fee > 0.0:
		((c["_chronicle"] as Array).back() as Dictionary)["fee"] = fee   # the service counts the fees of a creeping purchase
	if buy:
		# Even an approved purchase tenses the country's independent business (orders.business_reacts).
		app.orders.business_reacts(c, float(q["доля"]), had <= 0.5 and app.db.state_share(c) > 0.5, app._game.day())
	if buy:
		app.antitrust.remember(app.db, "state_stake", float(q["доля"]) * 10.0 * (1.0 + float(app.db.econ(c).get("home_share_mod", 0.0))))
		if had <= 0.5 and app.db.state_share(c) > 0.5:
			# Control passes to the state: the head answers, a civil servant takes over.
			app.letters.on_control(c, app._game.day())
			app.lifecycle.replace_head(app.db, c, "госслужащий", app._game.day(), "nationalisation")
	app.db.recompute()
	var text := app.tr_key("pax_corporations_stake_done_" + ("buy" if buy else "sell")) % [app.db.percent(float(q["доля"])), app.db.name_of(c), app.db.money(amount)]
	app._toast(text)
	if str(verdict["decision"]) != "молча":
		text += "\n" + _service_says(str(verdict["ключ"]), [app.db.name_of(c), app.db.money(fee)] if fee > 0.0 else [app.db.name_of(c)])
	return text


## The antimonopoly service speaks: a notification right away and a letter in the «Letters» tab.
func _service_says(key: String, args: Array) -> String:
	var line := app.tr_key("pax_corporations_" + key)
	if line.count("%s") == args.size():
		line = line % args
	elif line.count("%s") > 0:
		line = line % args.slice(0, line.count("%s"))
	app._toast("🏛 %s: %s" % [app.tr_key("pax_corporations_am_name"), line])
	app.letters.service_letter(line, app._game.day())
	return line


## An order's result: a notification right away and a letter from the government's office in «Letters».
func _order_says(line: String) -> void:
	app._toast("📜 " + line)
	app.letters.office_letter(line, app._game.day())


## The game's «order_parsed» hook: the player gave an order. The antimonopoly service reacts at once to orders
## about competition and to takeovers or nationalisations of a company (antitrust.review_order); a furious
## service blocks such an order.
func _on_order(d: Dictionary) -> void:
	if not app._active or app._game == null:
		return
	var r := app.antitrust.review_order(app.db, app.rivals, str(d.get("order", "")), app._game.day())
	if str(r.get("вид", "")).is_empty() or str(r.get("вид", "")) == "сделка":
		# Not the service's own business (or only its comment): the order may be about a company (orders.gd).
		# Only a warning is worth a separate notice — a purchase gets the service's verdict anyway (orders.gd).
		if str(r.get("вид", "")) == "сделка" and not bool(r.get("отмена", false)) and str(r.get("ключ", "")) == "am_order_warn":
			_service_says(str(r["ключ"]), [app.db.name_of(r.get("c", {}))])
		if bool(r.get("отмена", false)):
			_service_says(str(r["ключ"]), [app.db.name_of(r.get("c", {}))])
			d["cancel"] = true
			return
		# Sanctions, tariffs, trade wars, espionage (arena.gd), then orders about one company (orders.gd).
		if app.capabilities.handle(d):   # buying a technology, or a closed capability (the order is cancelled)
			app._refresh_wanted = true
			return
		if app.investments.handle(d) or app.arena.handle(d) or app.orders.handle(d):
			app.db.recompute()
			app._refresh_wanted = true
		return
	if str(r["вид"]) == "сведение" and (app.arena.handle(d) or app.orders.handle(d)):
		app.db.recompute()   # words about competition, but the order is really about founding or a company
		app._refresh_wanted = true
		return
	var c: Dictionary = r.get("c", {})
	var args: Array = [app.db.name_of(c)] if not c.is_empty() else []
	if float(r.get("amount", 0.0)) > 0.0:
		args.append(app.db.money(float(r["amount"])))
	if not args.is_empty() or str(r["ключ"]) == "am_order_noted":
		if str(r["ключ"]) == "am_order_noted":
			args = [str(roundi(app.antitrust.mood))]
		_service_says(str(r["ключ"]), args)
	if bool(r.get("отмена", false)):
		d["cancel"] = true
	app.db.recompute()
	app._refresh_wanted = true


## The antimonopoly service's new terms of a share deal (trade buttons and orders): the player decides first.
func ask_terms(c: Dictionary, stake: float, amount: float, fee: float, buy: bool, on_accept: Callable) -> void:
	ask_deal(app.tr_key("pax_corporations_am_deal_title"), app.tr_key("pax_corporations_am_deal_intro") % app.db.name_of(c), [
		[app.tr_key("pax_corporations_am_deal_company"), app.db.name_of(c)],
		[app.tr_key("pax_corporations_am_deal_stake"), app.db.percent(stake)],
		[app.tr_key("pax_corporations_am_deal_price"), app.db.money(amount)],
		[app.tr_key("pax_corporations_am_deal_fee") % app.db.percent(fee / maxf(amount, 1e-6)), app.db.money(fee), true],
		[app.tr_key("pax_corporations_am_deal_total"), app.db.money(amount + fee)],
		[app.tr_key("pax_corporations_am_deal_left"), app.db.money(treasury_money() - amount - fee)]],
		app.tr_key("pax_corporations_am_deal_note"), on_accept, app.db.name_of(c))


## A modal card «New terms of the deal» on the HUD: accept — on_accept; cancel — a notification.
func ask_deal(title: String, intro: String, rows: Array, note: String, on_accept: Callable, what: String) -> void:
	var layer: Variant = app._game.hud_layer() if app._game != null else null
	if not (layer is Node):
		on_accept.call()
		return
	var d := Host.DealDialog.new()
	d.open(layer as Node, title, intro, rows, note, app.tr_key("pax_corporations_am_deal_accept"),
		app.tr_key("pax_corporations_am_deal_decline"), on_accept, func() -> void:
			app._toast("🏛 " + app.tr_key("pax_corporations_am_deal_declined") % what))
