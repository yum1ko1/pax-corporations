extends RefCounted
## Letters to the player (the «Письма» tab of the Corporations window). The game's own inbox holds only
## countries and organisations, so the heads of companies — of the player's country and foreign ones — and
## the antimonopoly service write here. Texts come from data/lang (the numbers are the mod's); an offer can be
## accepted or declined within «срок_недель», silence is a refusal.
##
## Who writes and why:
##   • a law of the player's country touching a sector (politics.gd new_laws): the most affected heads complain
##     or thank; foreign heads of the sector answer an open market with an offer to build a plant, new taxes
##     with second thoughts about their plans;
##   • the escalation ladder (politics.gd): a demand (rung 2) and a threat with 8 weeks to answer (rung 4) —
##     a subsidy can buy peace;
##   • the life of companies (lifecycle.gd): a bankrupt asks for a rescue for shares, a company that moved
##     explains itself, a newborn introduces itself, a captured headquarters reports;
##   • offers now and then: a joint investment project, a holder selling a stake to the state at a discount,
##     a sponsorship of the state services, a defence order, a foreign company buying into a state company,
##     a truce in a corporate war with a foreign company;
##   • the player's own decisions: a state company founded in someone's market, control taken over a company;
##   • the antimonopoly service (antitrust.gd): its mood turns, cases.

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Politics := preload("res://mods/pax_corporations/src/state/politics.gd")
const Lifecycle := preload("res://mods/pax_corporations/src/companies/lifecycle.gd")
const Antitrust := preload("res://mods/pax_corporations/src/state/antitrust.gd")
const Rivals := preload("res://mods/pax_corporations/src/companies/rivals.gd")
const Stakes := preload("res://mods/pax_corporations/src/market/stakes.gd")
const Debt := preload("res://mods/pax_corporations/src/companies/debt.gd")
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")
const OFFERS := ["инвестпроект", "stake", "sponsorship", "оборонный_заказ", "иностранный_выкуп", "иностранный_завод", "перемирие"]

var letters: Array = []          # oldest first: {номер, день, от, имя, роль, страна, вид, текст, предложение, статус, прочитано}
var fresh: Array = []            # letters that came this week (main shows a toast)
var _next := 1
var _rng := RandomNumberGenerator.new()
var db: Data
var game: PaxGame
var rivals: Rivals
var antitrust: Antitrust
var goods: Goods
var invest: Object               # investments.gd: foreign governments' offers (accept_offer, haggle)


func setup(d: Data, g: PaxGame, r: Rivals, a: Antitrust, gd: Goods) -> void:
	db = d
	game = g
	rivals = r
	antitrust = a
	goods = gd


func start_new() -> void:
	_rng.randomize()


func _cfg() -> Dictionary:
	return db.balance.get("letters", {})


func _t(key: String) -> String:
	return db.mod.tr_key("pax_corporations_" + key)


func _player() -> String:
	return str(game.player_faction().get("name", ""))


func unread() -> int:
	var n := 0
	for l in letters:
		if not bool((l as Dictionary).get("read_flag", false)):
			n += 1
	return n


func mark_read() -> void:
	for l in letters:
		(l as Dictionary)["read_flag"] = true


# ---------- weekly ----------

func step(politics: Politics, life: Lifecycle, day: int) -> void:
	fresh.clear()
	var player := _player()
	_expire(day)
	_laws(politics, player, day)
	for ev in politics.letter_events:
		_ladder_letter(ev, day)
	for ev in life.events_for_letters:
		_life_letter(ev, player, day)
	for ev in antitrust.events_for_letters:
		_service_letter(ev, day)
	if _rng.randf() < float(_cfg().get("offers_per_year", 10.0)) / 52.0:
		_offer(player, day)
	var keep := int(_cfg().get("keep", 80))
	while letters.size() > keep:
		letters.pop_front()


## A letter from a company's head. offer: {} — just a letter; else {вид, сумма, …}.
func _write(c: Dictionary, kind: String, text: String, offer: Dictionary, day: int) -> Dictionary:
	var lead: Dictionary = c.get("глава", {})
	var l := {"number": _next, "день": day, "from_value": str(c.get("id", "")), "name": db.text(lead.get("name", "")),
		"роль": str(lead.get("роль", "")), "company": db.name_of(c), "country": str(c.get("_country", "")),
		"вид": kind, "текст": text, "offer": offer, "status": "ждёт" if not offer.is_empty() else "письмо", "read_flag": false}
	if not offer.is_empty():
		l["срок"] = day + 7 * int(_cfg().get("term_weeks", 8))
	_next += 1
	letters.append(l)
	fresh.append(l)
	return l


## A foreign government's offer about one of the player's companies (investments.gd): the letter is about the company
## (its link opens the dossier), the sender is the government.
func government_offer(c: Dictionary, country: String, text: String, offer: Dictionary) -> void:
	var day := game.day()
	var l := {"number": _next, "день": day, "from_value": str(c.get("id", "")), "name": _t("inv_government") % country, "роль": "",
		"company": db.name_of(c), "country": country, "вид": "иноинвестор", "текст": text, "offer": offer, "status": "ждёт",
		"read_flag": false, "срок": day + 7 * int(_cfg().get("term_weeks", 8))}
	_next += 1
	letters.append(l)
	fresh.append(l)


## The player haggles over a government's offer (investments.gd): a better price — or the offer is gone.
func haggle(number: int) -> String:
	var l := letter(number)
	if l.is_empty() or str(l["status"]) != "ждёт" or invest == null:
		return ""
	var c := db.company(str(l["from_value"]))
	var o: Dictionary = l["offer"]
	var line := str(invest.call("haggle", c, o))
	l[""] = "отклонено" if bool(o.get("отказ", false)) else str(l["текст"]) + "\n\n" + line
	return line


func _write_service(kind: String, text: String, day: int) -> void:
	var l := {"number": _next, "день": day, "from_value": "", "name": _t("am_head"), "роль": "", "company": _t("am_name"), "country": _player(),
		"вид": kind, "текст": text, "offer": {}, "status": "письмо", "read_flag": false}
	_next += 1
	letters.append(l)
	fresh.append(l)


## The service's instant answer to a deal or an order (main.gd has already shown it as a notification, so it is
## filed as read and does not raise another «new letters» notice).
func service_letter(text: String, day: int) -> void:
	_write_service("служба", text, day)
	var l: Dictionary = letters[letters.size() - 1]
	l["read_flag"] = true
	fresh.erase(l)


## The result of the player's order (orders.gd) — from the government's office; shown at once as a notification.
func office_letter(text: String, day: int) -> void:
	var l := {"number": _next, "день": day, "from_value": "", "name": _t("office_head"), "роль": "", "company": _t("office_name"), "country": _player(),
		"вид": "приказ", "текст": text, "offer": {}, "status": "письмо", "read_flag": true}
	_next += 1
	letters.append(l)


## An offer nobody answered is a refusal (the domestic head is offended a little).
func _expire(day: int) -> void:
	for item in letters:
		var l: Dictionary = item
		if str(l["status"]) == "ждёт" and day > int(l.get("срок", day)):
			l["status"] = "истекло"
			_offended(str(l["from_value"]), float(_cfg().get("grudge_silence", 3.0)))


func _offended(cid: String, points: float) -> void:
	var e := db.econ(db.company(cid))
	if e.has("trust"):
		e["trust"] = clampf(float(e["trust"]) - points, 0.0, 100.0)


func _pleased(cid: String, points: float) -> void:
	var e := db.econ(db.company(cid))
	if e.has("trust"):
		e["trust"] = clampf(float(e["trust"]) + points, 0.0, 100.0)


func _has_pending(cid: String, kind: String) -> bool:
	for l in letters:
		if str((l as Dictionary)["from_value"]) == cid and str((l as Dictionary)["вид"]) == kind and str((l as Dictionary)["status"]) == "ждёт":
			return true
	return false


# ---------- laws (politics.gd) ----------

func _laws(politics: Politics, player: String, day: int) -> void:
	var per_law := int(_cfg().get("letters_per_law", 3))
	for item in politics.new_laws:
		var law: Dictionary = item
		var rows: Array = []
		for x in db.companies:
			var c: Dictionary = x
			if str(c.get("_country", "")) != player:
				continue
			var r := Politics.law_reaction(db, c, law)
			if absf(r) >= 1.0:
				rows.append([c, r, absf(r) * pow(maxf(db.cap(c), 1.0), 0.3)])
		rows.sort_custom(func(a, b): return float(a[2]) > float(b[2]))
		for row in rows.slice(0, per_law):
			var c: Dictionary = row[0]
			var r := float(row[1])
			var labour := str(law["вид"]) == "labour_rights"
			var key := "letter_law_%s%s_%d" % ["labour_" if labour else "", "pos" if r > 0.0 else "neg", _rng.randi_range(1, 2)]
			_write(c, "закон", _t(key) % [str(law["title"]), db.sector_name(str(c.get("sector", "")))], {}, day)
		_foreign_reaction(law, player, day)


## Foreign heads of the sectors a law touches: an open market — an offer to build a plant; new taxes — doubts.
func _foreign_reaction(law: Dictionary, player: String, day: int) -> void:
	var kind := str(law["вид"])
	if float(law["sign"]) <= 0.0 or not (kind in ["market_opening", "tax_growth", "windfall_tax"]):
		return
	var scope: Array = law.get("sectors", [])
	var cfg_k: Dictionary = db.balance.get("competition", {})
	var best: Dictionary = {}
	for x in db.companies:
		var c: Dictionary = x
		if str(c.get("_country", "")) == player or not Rivals.open_border(cfg_k, str(c.get("_country", "")), player):
			continue
		if not scope.is_empty() and not (str(c.get("sector", "")) in scope):
			continue
		if best.is_empty() or db.cap(c) > db.cap(best):
			best = c
	if best.is_empty():
		return
	if kind == "market_opening":
		_plant_offer(best, str(law["title"]), day)
	else:
		_write(best, "закон_иностранный", _t("letter_foreign_tax") % [str(law["title"]), player], {}, day)


# ---------- the escalation ladder (politics.gd) ----------

func _ladder_letter(ev: Dictionary, day: int) -> void:
	var c: Dictionary = ev["c"]
	var e := db.econ(c)
	var rung := int(ev["ступень"])
	var share := float(_cfg().get("subsidy_from_revenue", 0.005)) * (2.0 if rung == 4 else 1.0)
	var amount := maxf(1.0, float(e.get("R", 0.0)) * share)
	var why := _grievance(str(ev["grudge"]))
	var text := _t("letter_ladder_%d" % rung) % ([why, db.money(amount)] if rung == 2 else [why, db.people(db.staff(c) * 0.1), db.money(amount)])
	_write(c, "ladder", text, {"вид": "субсидия", "amount": amount, "trust": 15.0 if rung == 2 else 20.0, "ступень": rung}, day)


func _grievance(key: String) -> String:
	if key.begins_with("law:"):
		return _t("grievance_law") % key.substr(4)
	return _t("grievance_" + key) if not key.is_empty() else _t("grievance_")


# ---------- the life of companies (lifecycle.gd) ----------

func _life_letter(ev: Dictionary, player: String, day: int) -> void:
	var c: Dictionary = ev["c"]
	var kind := str(ev["вид"])
	var mine := str(c.get("_country", "")) == player
	match kind:
		"банкротство":
			if not mine:
				return
			var e := db.econ(c)
			var amount := maxf(1.0, float(e.get("debt", 0.0)) * float(_cfg().get("rescue_debt_share", 0.3)))
			var stake := clampf(amount / maxf(db.cap(c) + amount, 1.0), 0.1, 0.5)
			var weeks := int((e.get("банкротство", {}) as Dictionary).get("weeks", 12))
			_write(c, "банкротство", _t("letter_bankrupt") % [db.name_of(c), weeks, db.money(amount), db.percent(stake)],
				{"вид": "rescue", "amount": amount, "доля": stake}, day)
		"переезд":
			if str(ev.get("откуда", "")) == player:
				_write(c, "переезд", _t("letter_relocated") % str(ev["country"]), {}, day)
		"переезд_точки":
			if mine:
				_write(c, "переезд", _t("letter_site_moved") % str(ev["country"]), {}, day)
		"birth":
			if mine:
				_write(c, "birth", _t("letter_born") % [db.name_of(c), db.sector_name(str(c.get("sector", "")))], {}, day)
		"слияние":
			if mine:
				_write(c, "слияние", _t("letter_merged") % _name(ev.get("b", {})), {}, day)
		"antitrust_ban":
			if mine:
				_write(c, "слияние", _t("letter_merger_banned") % _name(ev.get("b", {})), {}, day)
		"штаб_захвачен":
			if mine or _owns_stake(c, player):
				_write(c, "война", _t("letter_hq_captured") % [str(ev["country"]), _t("war_outcome_" + str(ev.get("что", "")))], {}, day)
		"точка_захвачена":
			if mine:
				_write(c, "война", _t("letter_site_captured") % str(ev["country"]), {}, day)
		"ликвидация":
			if mine:
				_write(c, "ликвидация", _t("letter_liquidated") % db.name_of(c), {}, day)


func _name(c: Variant) -> String:
	return db.name_of(c) if c is Dictionary and not (c as Dictionary).is_empty() else ""


func _owns_stake(c: Dictionary, country: String) -> bool:
	return Stakes.state_stake(c, country) > 0.0


# ---------- the antimonopoly service (antitrust.gd) ----------

func _service_letter(ev: Dictionary, day: int) -> void:
	match str(ev["вид"]):
		"служба_настроение":
			var zone := str(ev["zone"])
			var key := "letter_am_" + ("bad" if zone == "плохо" else ("good" if zone == "хорошо" else ("calm_from_bad" if str(ev["было"]) == "плохо" else "calm_from_good")))
			_write_service("служба", _t(key), day)
		"служба_дело":
			var c: Dictionary = ev["c"]
			if str(ev["что"]) == "section":
				_write_service("служба", _t("letter_am_split") % db.name_of(c), day)
			else:
				_write_service("служба", _t("letter_am_fine") % [db.name_of(c), db.money(float(ev["amount"]))], day)
				_write(c, "служба", _t("letter_am_fine_reply") % db.money(float(ev["amount"])), {}, day)


# ---------- the player's own decisions ----------

## The state founded a company: the biggest domestic rival in that market is worried.
func on_founded(c: Dictionary, day: int) -> void:
	var player := _player()
	var best: Dictionary = {}
	for cid in goods.members.get(goods.home_pool(c), []):
		var o := db.company(str(cid))
		if o.is_empty() or str(o["id"]) == str(c["id"]) or str(o.get("_country", "")) != player:
			continue
		if best.is_empty() or db.cap(o) > db.cap(best):
			best = o
	if not best.is_empty():
		_write(best, "decision", _t("letter_rival_founded") % db.name_of(c), {}, day)
		_offended(str(best["id"]), 4.0)


## The state took control of a company (bought past half): its head answers — a founder is bitter, a hired
## manager is careful.
func on_control(c: Dictionary, day: int) -> void:
	var role := str((c.get("глава", {}) as Dictionary).get("роль", ""))
	var key := "letter_control_founder" if role in ["founder", "акционер_владелец"] else "letter_control_manager"
	_write(c, "decision", _t(key) % db.name_of(c), {}, day)


# ---------- offers ----------

func _offer(player: String, day: int) -> void:
	var kinds: Array = OFFERS.duplicate()
	kinds.shuffle()
	for kind in kinds:
		if _try_offer(str(kind), player, day):
			return


func _try_offer(kind: String, player: String, day: int) -> bool:
	var home: Array = db.companies.filter(func(x): return str(x.get("_country", "")) == player and not db.econ(x).is_empty())
	match kind:
		"инвестпроект":
			var c := _pick(home.filter(func(x): return float(db.econ(x).get("P", 0.0)) > 0.0))
			if c.is_empty():
				return false
			var e := db.econ(c)
			var amount := maxf(1.0, float(e.get("R", 0.0)) * float(_cfg().get("project_from_revenue", 0.02)))
			var growth := float(_cfg().get("project_return", 0.35)) * amount / maxf(float(e.get("R", 1.0)), 1.0)
			_write(c, "offer", _t("letter_offer_инвестпроект") % [goods.goods_name(db, c), db.money(amount), db.percent(growth)],
				{"вид": "инвестпроект", "amount": amount, "рост": growth}, day)
			return true
		"stake":
			for c in _shuffled(home):
				var holder := _private_holder(c)
				if holder.is_empty() or db.state_share(c) > 0.5:
					continue
				var share := minf(float(holder["доля"]), float(_cfg().get("stake_share", 0.1)))
				var discount := float(_cfg().get("stake_discount", 0.15))
				var amount := db.cap(c) * share * (1.0 - discount)
				_write(c, "offer", _t("letter_offer_stake") % [db.text(holder.get("кто", "")), db.percent(share), db.money(amount), db.percent(discount)],
					{"вид": "stake", "amount": amount, "доля": share, "holder": db.text(holder.get("кто", ""))}, day)
				return true
			return false
		"sponsorship":
			var c := _pick(home.filter(func(x): return float(db.econ(x).get("money", 0.0)) > 0.2 * float(db.econ(x).get("R", 1.0))))
			if c.is_empty():
				return false
			var amount := maxf(1.0, float(db.econ(c).get("R", 0.0)) * float(_cfg().get("sponsorship_from_revenue", 0.004)))
			_write(c, "offer", _t("letter_offer_sponsorship") % db.money(amount), {"вид": "sponsorship", "amount": amount}, day)
			return true
		"оборонный_заказ":
			var c := _pick(home.filter(func(x): return str(x.get("sector", "")) == "defence"))
			if c.is_empty():
				return false
			var e := db.econ(c)
			var amount := maxf(1.0, float(e.get("R", 0.0)) * float(_cfg().get("order_from_revenue", 0.05)))
			_write(c, "offer", _t("letter_offer_оборонный_заказ") % db.money(amount),
				{"вид": "оборонный_заказ", "amount": amount, "рост": 0.6 * amount / maxf(float(e.get("R", 1.0)), 1.0)}, day)
			return true
		"иностранный_выкуп":
			var target := _pick(home.filter(func(x): return db.state_share(x) > 0.5))
			if target.is_empty():
				return false
			var cfg_k: Dictionary = db.balance.get("competition", {})
			var buyer: Dictionary = {}
			for x in _shuffled(db.companies):
				var o: Dictionary = x
				if str(o.get("_country", "")) != player and str(o.get("sector", "")) == str(target.get("sector", "")) \
						and Rivals.open_border(cfg_k, str(o.get("_country", "")), player) and float(db.econ(o).get("money", 0.0)) > db.cap(target) * 0.1:
					buyer = o
					break
			if buyer.is_empty():
				return false
			var share := float(_cfg().get("buyout_share", 0.1))
			var premium := float(_cfg().get("buyout_premium", 0.2))
			var amount := db.cap(target) * share * (1.0 + premium)
			_write(buyer, "offer", _t("letter_offer_иностранный_выкуп") % [db.percent(share), db.name_of(target), db.money(amount), db.percent(premium)],
				{"вид": "иностранный_выкуп", "amount": amount, "доля": share, "цель": str(target["id"])}, day)
			return true
		"иностранный_завод":
			var cfg_k: Dictionary = db.balance.get("competition", {})
			var c := _pick(db.companies.filter(func(x): return str(x.get("_country", "")) != player and db.cap(x) > 5000.0 \
				and Rivals.open_border(cfg_k, str(x.get("_country", "")), player)))
			if c.is_empty():
				return false
			_plant_offer(c, "", day)
			return true
		"перемирие":
			for w in rivals.wars:
				var a := db.company(str(w["a"]))
				var b := db.company(str(w["b"]))
				if a.is_empty() or b.is_empty():
					continue
				var mine: Dictionary = a if str(a.get("_country", "")) == player else (b if str(b.get("_country", "")) == player else {})
				var other: Dictionary = b if str(mine.get("id", "")) == str(a["id"]) else a
				if mine.is_empty() or str(other.get("_country", "")) == player or _has_pending(str(other["id"]), "перемирие"):
					continue
				_write(other, "перемирие", _t("letter_offer_перемирие") % db.name_of(mine), {"вид": "перемирие", "rival": str(mine["id"])}, day)
				return true
			return false
	return false


func _plant_offer(c: Dictionary, law: String, day: int) -> void:
	if _has_pending(str(c["id"]), "предложение_завод"):
		return
	var amount := maxf(10.0, float(db.econ(c).get("R", 0.0)) * float(_cfg().get("plant_from_revenue", 0.01)))
	var text := _t("letter_foreign_open") % [law, db.money(amount)] if not law.is_empty() else _t("letter_offer_иностранный_завод") % db.money(amount)
	_write(c, "предложение_завод", text, {"вид": "иностранный_завод", "amount": amount}, day)


func _pick(list: Array) -> Dictionary:
	if list.is_empty():
		return {}
	var c: Dictionary = list[_rng.randi_range(0, list.size() - 1)]
	return {} if _has_pending(str(c["id"]), "offer") else c


func _shuffled(list: Array) -> Array:
	var out := list.duplicate()
	out.shuffle()
	return out


func _private_holder(c: Dictionary) -> Dictionary:
	for o in c.get("owners", []):
		var od: Dictionary = o
		if str(od.get("type", "")) in ["крупный", "founder"] and float(od.get("доля", 0.0)) >= 0.05 \
				and (not od.has("country") or str(od["country"]) == str(c.get("_country", ""))):
			return od
	return {}


# ---------- answers ----------

func letter(number: int) -> Dictionary:
	for l in letters:
		if int((l as Dictionary)["number"]) == number:
			return l
	return {}


## The player accepts an offer. Returns the line shown to the player.
func accept(number: int) -> String:
	var l := letter(number)
	if l.is_empty() or str(l["status"]) != "ждёт":
		return ""
	var o: Dictionary = l["offer"]
	var c := db.company(str(l["from_value"]))
	if c.is_empty():
		l["status"] = "истекло"
		return _t("letter_gone")
	var e := db.econ(c)
	var amount := float(o.get("amount", 0.0))
	var home := game.home_body()
	var money := float(game.resources(home).get("money", 0.0))
	if str(o["вид"]) == "иноинвестор" and invest != null:
		var err := str(invest.call("accept_offer", c, o, game.day()))
		if not err.is_empty():
			l["status"] = "истекло"
			return _t(err) % db.name_of(c)
		l["status"] = "принято"
		db.recompute()
		return _t("inv_accepted") % [str(o.get("country", "")), db.name_of(c)]
	var pays := str(o["вид"]) in ["субсидия", "инвестпроект", "stake", "оборонный_заказ", "rescue"]
	if pays and money < amount:
		return _t("letter_no_money") % db.money(amount)
	var day := game.day()
	match str(o["вид"]):
		"субсидия":
			game.add_resource(home, "money", -amount)
			e["money"] = float(e.get("money", 0.0)) + amount
			_pleased(str(c["id"]), float(o.get("trust", 15.0)))
			e["ladder"] = maxi(0, int(e.get("ladder", 0)) - 2)
			e["ladder_weeks"] = 0
			e.erase("threat_day")
		"инвестпроект":
			game.add_resource(home, "money", -amount)
			e["money"] = float(e.get("money", 0.0)) + amount
			e["demand"] = float(e["demand"]) * (1.0 + float(o.get("рост", 0.0)))
			_pleased(str(c["id"]), 8.0)
			(c["_chronicle"] as Array).append({"день": day, "вид": "письмо", "что": "инвестпроект", "count_value": amount})
		"stake":
			if not _buy_from_holder(c, str(o.get("holder", "")), float(o["доля"]), amount, day):
				l["status"] = "истекло"
				return _t("letter_gone")
			game.add_resource(home, "money", -amount)
			antitrust.remember(db, "stake", float(o["доля"]) * 10.0)
		"sponsorship":
			if float(e.get("money", 0.0)) < amount:
				l["status"] = "истекло"
				return _t("letter_gone")
			e["money"] = float(e["money"]) - amount
			game.add_resource(home, "money", amount)
			_pleased(str(c["id"]), 10.0)
			antitrust.remember(db, "sponsorship", 1.0)
			(c["_chronicle"] as Array).append({"день": day, "вид": "письмо", "что": "sponsorship", "count_value": amount})
		"оборонный_заказ":
			game.add_resource(home, "money", -amount)
			e["money"] = float(e.get("money", 0.0)) + amount
			e["demand"] = float(e["demand"]) * (1.0 + float(o.get("рост", 0.0)))
			_pleased(str(c["id"]), 10.0)
			(c["_chronicle"] as Array).append({"день": day, "вид": "письмо", "что": "оборонный_заказ", "count_value": amount})
		"rescue":
			game.add_resource(home, "money", -amount)
			e["money"] = float(e.get("money", 0.0)) + amount
			e["state_rescue"] = true   # lifecycle.gd: the state's rescue when the manager's term ends
			Debt.dilute(c, {"кто": {"ru": "Государство (%s)" % _player(), "en": "The state (%s)" % _player()}, "type": "polity",
				"country": _player()}, float(o["доля"]))
			Stakes._retype(db, c)
			_pleased(str(c["id"]), 15.0)
		"иностранный_выкуп":
			var target := db.company(str(o.get("цель", "")))
			if target.is_empty() or Stakes.state_stake(target, _player()) < float(o["доля"]) or float(e.get("money", 0.0)) < amount:
				l["status"] = "истекло"
				return _t("letter_gone")
			_sell_to_company(target, c, float(o["доля"]), amount, day)
			game.add_resource(home, "money", amount)
			_relations(str(c.get("_country", "")), 0.01)
		"иностранный_завод":
			_open_plant(c, amount, day)
			game.add_resource(home, "money", amount * float(_cfg().get("plant_fee", 0.1)))
			_relations(str(c.get("_country", "")), 0.01)
		"перемирие":
			var other := str(o.get("rival", ""))
			rivals.wars = rivals.wars.filter(func(w): return not ((str(w["a"]) == other and str(w["b"]) == str(c["id"])) \
				or (str(w["b"]) == other and str(w["a"]) == str(c["id"]))))
			rivals.tension.erase(Rivals._pair(other, str(c["id"])))
			db.wars = rivals.wars
			_relations(str(c.get("_country", "")), 0.01)
	l["status"] = "принято"
	db.recompute()
	return _t("letter_accepted") % db.name_of(c)


func decline(number: int) -> String:
	var l := letter(number)
	if l.is_empty() or str(l["status"]) != "ждёт":
		return ""
	l["status"] = "отклонено"
	var kind := str((l["offer"] as Dictionary).get("вид", ""))
	_offended(str(l["from_value"]), float(_cfg().get("grudge_refusal", 6.0)) if kind in ["субсидия", "rescue"] else float(_cfg().get("grudge_silence", 3.0)))
	return _t("letter_declined")


func _buy_from_holder(c: Dictionary, holder_name: String, share: float, amount: float, day: int) -> bool:
	for o in c.get("owners", []):
		var od: Dictionary = o
		if db.text(od.get("кто", "")) == holder_name and float(od.get("доля", 0.0)) >= share - 0.0001:
			od["доля"] = float(od["доля"]) - share
			var st := Stakes._state_holder(c, _player(), true)
			st["доля"] = float(st.get("доля", 0.0)) + share
			c["owners"] = (c["owners"] as Array).filter(func(x): return float((x as Dictionary).get("доля", 0.0)) > 0.00005)
			c["_owners_changed"] = true
			Stakes._retype(db, c)
			(c["_chronicle"] as Array).append({"день": day, "вид": "state_stake", "что": "buyout", "доля": share, "count_value": amount, "country": _player()})
			return true
	return false


func _sell_to_company(target: Dictionary, buyer: Dictionary, share: float, amount: float, day: int) -> void:
	var st := Stakes._state_holder(target, _player(), false)
	st["доля"] = float(st.get("доля", 0.0)) - share
	(target["owners"] as Array).append({"кто": (buyer["название"] as Dictionary).duplicate(), "type": "company",
		"country": str(buyer.get("_country", "")), "company": str(buyer["id"]), "доля": share})
	target["owners"] = (target["owners"] as Array).filter(func(x): return float((x as Dictionary).get("доля", 0.0)) > 0.00005)
	target["_owners_changed"] = true
	Stakes._retype(db, target)
	var eb := db.econ(buyer)
	eb["money"] = float(eb.get("money", 0.0)) - amount
	(target["_chronicle"] as Array).append({"день": day, "вид": "state_stake", "что": "sale", "доля": share, "count_value": amount, "country": _player()})


## A foreign company opens a plant in the player's country: a new site where the player's companies sit.
func _open_plant(c: Dictionary, amount: float, day: int) -> void:
	var home: Array = db.companies.filter(func(x): return str(x.get("_country", "")) == _player())
	if home.is_empty():
		return
	var hq := db.hq_of(home[_rng.randi_range(0, home.size() - 1)])
	var e := db.econ(c)
	var share := clampf(amount / maxf(float(e.get("R", 1.0)), 1.0), 0.005, 0.1)
	var people := float(e.get("N", 0.0)) * share
	var pts: Array = c.get("sites", [])
	pts.append({"type": "завод", "name": hq.get("name", {"ru": "", "en": ""}), "ш": float(hq.get("ш", 0.0)), "д": float(hq.get("д", 0.0)),
		"province": int(hq.get("province", 0)), "staff": int(people)})
	c["sites"] = pts
	c["_sites_changed"] = true
	var shares: Array = e.get("site_shares", [])
	shares = shares.map(func(v): return float(v) * (1.0 - share))
	shares.append(share)
	e["site_shares"] = shares
	for key in ["D0", "R0", "N"]:
		e[key] = float(e[key]) * (1.0 + share)
	e["money"] = float(e.get("money", 0.0)) - amount
	(c["_chronicle"] as Array).append({"день": day, "вид": "письмо", "что": "завод", "country": _player(), "count_value": amount})


func _relations(country: String, delta: float) -> void:
	for f in game.factions():
		var fd: Dictionary = f
		if str(fd.get("name", "")) == country and fd.has("relations"):
			fd["relations"] = clampf(float(fd["relations"]) + delta, 0.0, 1.0)
			return


# ---------- save ----------

func save_state() -> Dictionary:
	return {"letters": letters, "number": _next, "зерно": str(_rng.seed), "состояние": str(_rng.state)}


func load_state(state: Dictionary) -> void:
	letters = (state.get("letters", []) as Array).duplicate(true) if state.get("letters") is Array else []
	_next = int(state.get("number", 1))
	var seed_text := str(state.get("зерно", ""))
	if seed_text.is_empty():
		_rng.randomize()
	else:
		_rng.seed = seed_text.to_int()
		_rng.state = str(state.get("состояние", "0")).to_int()
