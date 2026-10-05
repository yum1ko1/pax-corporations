extends RefCounted
## The game's AI writes the mod's texts (design doc 22, 20.4 step 6; config balance.json «нейросеть»).
##
## One batch a week (not one call per text): when the week's work is done the mod sends the AI, in one request,
##   • the sharp moves of the week (the player's, favourite and world top-100 companies) with the game events that
##     push the company hardest — a headline and an explanation come back (the numbers are the mod's, the AI may
##     not change them); they replace the template line in the chronicle and the news;
##   • the companies born that week — a name fitting their country, a description, the founder's character;
##   • the heads' new letters — rewritten in the head's own voice, every fact and number kept;
##   • the loudest stories for the newspaper — an article each.
## During a long time skip nothing is sent until the skip is over (then one batch for its end), so a skip of a
## century does not turn into a hundred requests. Without the AI (no network, the limit) the templates stay.
##
## The newspaper (hook «report_ready»): when the game writes its report for a stretch of time, the mod adds
## articles about the loudest corporate stories of that stretch — the world's and the player's country's, a few of
## each — and a paragraph for the player's personal report. Stories of 20 % and more always qualify (20.4).

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Guard := preload("res://mods/pax_corporations/src/news/news_guard.gd")
const Events := preload("res://mods/pax_corporations/src/news/events.gd")
const Letters := preload("res://mods/pax_corporations/src/news/letters.gd")

var _moves: Array = []           # [{c, entry}] — sharp moves waiting for an explanation
var _births: Array = []          # company ids born and still named by a template
var _letters: Array = []         # letter numbers to rewrite
var _renames: Array = []         # [{id, страна}] — companies that passed under another country
var rename_cb: Callable          # func(company, {ru, en}) — lifecycle.rename (saved)
var press: Array = []            # newspaper candidates since the last report: {ключ, id, страна, день, размер, текст, мир, ии}
var _busy := false
var _next_key := 1
var stats: Dictionary = {}       # sent, answered, empty
var db: Data
var game: PaxGame
var mod: PaxMod
var events: Events
var letters: Letters
var text_of: Callable            # func(company, entry) -> String — the chronicle line (ui_window.chron_text)
var treasury_year: Callable      # func() -> float — what the companies pay the player's treasury a year


func setup(m: PaxMod, d: Data, g: PaxGame, ev: Events, lt: Letters, text_cb: Callable, treasury_cb: Callable) -> void:
	mod = m
	db = d
	game = g
	events = ev
	letters = lt
	text_of = text_cb
	treasury_year = treasury_cb
	_rng.randomize()


func _cfg() -> Dictionary:
	return db.balance.get("neural_net", {})


# ---------- collecting the week ----------

## The week's news items (all of them, before the feed filters), the letters that came, the player's country.
func collect(items: Array, fresh_letters: Array, player: String, favorites: Dictionary, day: int) -> void:
	var cfg := _cfg()
	if not bool(cfg.get("enabled_flag", true)):
		return
	for n in items:
		var item: Dictionary = n
		var c: Dictionary = item.get("c", {})
		var entry: Dictionary = item.get("entry", {})
		if c.is_empty() or entry.is_empty():
			continue
		var size := float(item.get("size", 0.0))
		var kind := str(entry.get("вид", ""))
		var country := str(c.get("_country", ""))
		var watched := country == player or favorites.has(str(c["id"])) or int(c.get("_world_place", 999)) <= 100
		if kind == "событие" and watched and size >= float(cfg.get("explain_from", 0.08)) and not entry.has("ии"):
			_moves.append({"c": c, "entry": entry})
		if kind == "birth" and str(c.get("id", "")).begins_with("born_"):
			_births.append(str(c["id"]))
		# Development news of any country (big tree steps, НО research, technologies of the new time): always in the
		# paper — the player's own as an official statement, a foreign one as rumours or its government's statement.
		if bool(item.get("газета", false)):
			_press_development(item, c, entry, player, day)
			continue
		# The newspaper: the loud stories — 20 % and more, or what the modules call big.
		var loud := size >= float(cfg.get("paper_from", 0.2)) or bool(item.get("big", false))
		if loud:
			var text := str(text_of.call(c, entry)) if text_of.is_valid() else ""
			var story := {"ключ": _next_key, "id": str(c["id"]), "company": db.name_of(c), "country": country, "день": day,
				"размер": size + (0.3 if bool(item.get("big", false)) else 0.0), "текст": text, "мир": country != player, "ии": {}}
			if kind == "условия" and entry.has("reason"):
				# A change of the country's conditions: the paper ties the share move to it (a new highway, a power line…).
				var dir := "_up" if int(entry.get("стало", 0)) >= int(entry.get("было", 0)) else "_down"
				story["link_to_shares"] = {"what_changed": str(entry["reason"]), "где": str(entry.get("province", "")),
					"было": int(entry.get("было", 0)), "стало": int(entry.get("стало", 0)),
					"shares_week_percent": roundi(db.change(c, 1) * 100.0),
					"likely_cause": mod.tr_key("pax_corporations_cond_cause_" + str(entry["reason"]) + dir)}
			press.append(story)
			_next_key += 1
	for l in fresh_letters:
		var ld: Dictionary = l
		if not str(ld.get("from_value", "")).is_empty():
			_letters.append(int(ld["number"]))
	_trim()


var _rng := RandomNumberGenerator.new()


func _press_development(item: Dictionary, c: Dictionary, entry: Dictionary, player: String, day: int) -> void:
	var country := str(item.get("tree_country", c.get("_country", "")))
	var form := "заявление" if country == player or _rng.randf() < 0.5 else "слухи"
	var kind := str(item.get("paper_kind", "узел"))
	var what := str(entry.get("текст", ""))
	var sector := str(item.get("отрасль", ""))
	var text := mod.tr_key("pax_corporations_press_%s_%s" % [kind, form]) % [country, what, db.sector_name(sector) if not sector.is_empty() else "", db.name_of(c)]
	press.append({"ключ": _next_key, "id": str(c["id"]), "company": db.name_of(c), "country": country, "день": day,
		"размер": 5.0 if kind == "будущее" else (3.0 if kind == "исследование" else 2.0), "текст": text, "мир": country != player, "ии": {},
		"required": true, "form": form, "вид": kind})
	_next_key += 1


func _trim() -> void:
	var cfg := _cfg()
	_moves.sort_custom(func(a, b): return float((a["entry"] as Dictionary).get("доля", 0.0)) > float((b["entry"] as Dictionary).get("доля", 0.0)))
	_moves = _moves.slice(0, int(cfg.get("explanations_per_batch", 6)))
	_births = _births.slice(maxi(0, _births.size() - int(cfg.get("companies_per_batch", 4))))
	_letters = _letters.slice(maxi(0, _letters.size() - int(cfg.get("letters_per_batch", 4))))
	press.sort_custom(func(a, b): return float(a["размер"]) > float(b["размер"]))
	press = press.slice(0, int(cfg.get("paper_keep", 40)) + int(cfg.get("газета_развитие", 10)))


# ---------- the weekly batch ----------

func queue_rename(c: Dictionary, country: String) -> void:
	_renames.append({"id": str(c["id"]), "country": country})


## Sends the batch (when the week's work is done and no skip is running). One request at a time.
func flush() -> void:
	if _busy or db == null:
		return
	var cfg := _cfg()
	if not bool(cfg.get("enabled_flag", true)):
		return
	var data := _batch_data()
	if (data["movements"] as Array).is_empty() and (data["new_companies"] as Array).is_empty() and (data["renames"] as Array).is_empty() \
			and (data["letters"] as Array).is_empty() and (data["газета"] as Array).is_empty() and (data["week_events"] as Array).is_empty():
		return
	var prompt := "You write the texts of a living-corporations layer of a strategy game. STRICT FACT RULES (every part): write ONLY what the given " \
		+ "data says happened in the game. Never invent events, people, deaths, arrests, resignations, elections, coups, products, " \
		+ "contracts or deals; never say that any leader or president died or left. Never call a company state-owned or the " \
		+ "government's unless «государство_владеет» is true — use «владельцы» as given. A fall is a fall and a rise is a rise: " \
		+ "follow «направление» exactly. The numbers are fixed by the game: never change " \
		+ "them, never invent new numbers. Write in the language «язык». " \
		+ "«движения»: for each, a short news headline and 1–2 sentences explaining why it happened — ONLY from its «события_мира» " \
		+ "(the game's computed causes) and «события_компании» (what really happened to it); if they do not explain it, say " \
		+ "plainly that the market moved the shares. «новые_компании»: for each, a brand name fitting its country and industry, one sentence " \
		+ "about the idea and the founder's character in a few words. «переименования»: a company passed under the control of " \
		+ "«страна» (war or nationalisation) — give it a new name such a new owner would choose. «письма»: rewrite each letter in the voice of its author (the head " \
		+ "of the company, his character is given), 2–4 sentences, keeping every fact, name and number and the request at the end. " \
		+ "«газета»: for each story, a newspaper headline and 2–3 sentences in a lively press style, retelling ONLY «что_случилось» " \
		+ "and «события_компании» — add no new facts. When a story has " \
		+ "«форма»: «слухи» — write it as rumours from unnamed sources (it is said, sources claim), «заявление» — as the country's " \
		+ "official statement (the government announced). Development stories are about a country's breakthrough. When a story has " \
		+ "«связь_с_акциями», tie the company's share move (its number) to that change of the country: name the place and the likely " \
		+ "cause as an event (a new highway opened, a power line launched, roads destroyed by fighting), e.g. X shares rose after the highway opened. " \
		+ "«события_недели»: these events were rolled by the game and HAVE happened (type, company, direction and size are fixed — " \
		+ "do not change them, add no others): for each, a news headline and 1–2 sentences telling the event itself, fitting the " \
		+ "company's industry, country and owners; a partnership names «партнёр»; регулирование is a new rule for the company's " \
		+ "whole industry in its country; авария is an accident at one of its sites (no deaths unless given). " \
				+ "Return ONLY JSON: {\"week_events\": [{\"n\": 0, \"title\": \"…\", \"текст\": \"…\"}], \"movements\": [{\"id\": 0, \"title\": \"…\", \"объяснение\": \"…\"}], " \
		+ "\"new_companies\": [{\"id\": \"…\", \"название\": \"…\", \"description\": \"…\", \"характер\": \"…\"}], " \
		+ "\"renames\": [{\"id\": \"…\", \"название\": \"…\"}], " \
		+ "\"letters\": [{\"number\": 0, \"текст\": \"…\"}], \"газета\": [{\"ключ\": 0, \"title\": \"…\", \"текст\": \"…\"}]}"
	var rolled: Array = _rolled.duplicate()
	_rolled.clear()
	var moves := _moves.duplicate()
	_moves.clear()
	_births.clear()
	_letters.clear()
	_renames.clear()
	_busy = true
	stats["sent"] = int(stats.get("sent", 0)) + 1
	var asked: bool = mod.ask_ai("corp_week", prompt, data, func(answer: Dictionary) -> void:
		_apply(answer, moves)
		_apply_rolled(answer, rolled),
		{"max_tokens": int(cfg.get("tokens", 2000)), "temperature": minf(float(cfg.get("температура", 0.8)), 0.45)})
	if not asked:
		_busy = false
		_apply_rolled({}, rolled)   # no AI: the events still happen, told by the templates


func _batch_data() -> Dictionary:
	var moves: Array = []
	for i in _moves.size():
		var m: Dictionary = _moves[i]
		var c: Dictionary = m["c"]
		var e: Dictionary = m["entry"]
		var parts: Dictionary = (c.get("_climate", {}) as Dictionary).get("parts", {})
		var why: Array = parts.keys()
		why.sort_custom(func(a, b): return absf(float(parts[a])) > absf(float(parts[b])))
		moves.append({"id": i, "company": db.name_of(c), "отрасль": db.sector_name(str(c.get("sector", ""))), "country": str(c.get("_country", "")),
			"indicator": str(e.get("что", "price")), "direction": "up" if bool(e.get("up", true)) else "down",
			"size_percent": roundi(float(e.get("доля", 0.0)) * 100.0), "world_events": why.slice(0, 5),
			"owners": Guard.owners(db, c), "state_owns": Guard.any_state(c),
			"company_events": Guard.facts(db, c, text_of, game.day())["company_events"],
			"template": str(text_of.call(c, e)) if text_of.is_valid() else ""})
	var born: Array = []
	for cid in _births:
		var c := db.company(str(cid))
		if c.is_empty():
			continue
		born.append({"id": str(cid), "country": str(c.get("_country", "")), "отрасль": db.sector_name(str(c.get("sector", ""))),
			"повод": str(c.get("born_f", "")), "now_called": db.name_of(c)})
	var lets: Array = []
	for n in _letters:
		var l := letters.letter(int(n))
		if l.is_empty():
			continue
		var c := db.company(str(l.get("from_value", "")))
		lets.append({"number": int(n), "author": str(l.get("name", "")), "company": str(l.get("company", "")), "country": str(l.get("country", "")),
			"характер": db.text((c.get("глава", {}) as Dictionary).get("характер", "")) if not c.is_empty() else "", "текст": str(l.get("текст", ""))})
	var stories: Array = []
	for p in press:
		if (p["ии"] as Dictionary).is_empty() and stories.size() < int(_cfg().get("articles_per_batch", 4)) + (4 if bool(p.get("required", false)) else 0):
			var st := {"ключ": int(p["ключ"]), "company": str(p["company"]), "country": str(p["country"]), "что_случилось": str(p["текст"])}
			var pc := db.company(str(p.get("id", "")))
			if not pc.is_empty():
				var pf := Guard.facts(db, pc, text_of, game.day())
				st["owners"] = pf["owners"]
				st["state_owns"] = pf["state_owns"]
				st["company_events"] = pf["company_events"]
			if p.has("form"):
				st["form"] = str(p["form"])
			if p.has("link_to_shares"):
				st["link_to_shares"] = p["link_to_shares"]
			stories.append(st)
	var renames: Array = []
	for r in _renames.slice(0, 4):
		var c := db.company(str(r["id"]))
		if not c.is_empty():
			renames.append({"id": str(r["id"]), "now_called": db.name_of(c), "country": str(r["country"]), "отрасль": db.sector_name(str(c.get("sector", "")))})
	return {"язык": "ru" if db.lang() == "ru" else "en", "week_events": _roll_events(), "movements": moves, "new_companies": born, "renames": renames, "letters": lets, "газета": stories}


func _apply(answer: Dictionary, moves: Array) -> void:
	_busy = false
	if db == null:
		return
	if answer.is_empty():
		stats["empty"] = int(stats.get("empty", 0)) + 1
		return
	stats["answers_count"] = int(stats.get("answers_count", 0)) + 1
	for a in _list(answer, "movements"):
		var i := int((a as Dictionary).get("id", -1))
		if i < 0 or i >= moves.size():
			continue
		var e: Dictionary = (moves[i] as Dictionary)["entry"]
		var mc: Dictionary = (moves[i] as Dictionary)["c"]
		var head := str((a as Dictionary).get("title", "")).strip_edges()
		var why := str((a as Dictionary).get("объяснение", "")).strip_edges()
		var mf := Guard.facts(db, mc, text_of, game.day())
		var tpl := str(text_of.call(mc, e)) if text_of.is_valid() else ""
		if not Guard.ok(head + " " + why, {"down": not bool(e.get("up", true)), "polity": bool(mf["state_owns"]),
				"facts": str(mf["_text"]) + " " + tpl}):
			stats["dropped"] = int(stats.get("dropped", 0)) + 1
			continue   # the AI went beyond the facts: the game's own line stays
		if not why.is_empty():
			e["ии"] = (head + " — " + why) if not head.is_empty() else why
	for a in _list(answer, "new_companies"):
		var c := db.company(str((a as Dictionary).get("id", "")))
		var title := str((a as Dictionary).get("название", "")).strip_edges()
		if c.is_empty() or title.is_empty() or title.length() > 40:
			continue
		c["название"] = {"ru": title, "en": title}
		var desc := str((a as Dictionary).get("description", "")).strip_edges()
		if not desc.is_empty():
			c["description"] = {"ru": desc, "en": desc}
		var temper := str((a as Dictionary).get("характер", "")).strip_edges()
		if not temper.is_empty() and c.get("глава") is Dictionary:
			(c["глава"] as Dictionary)["характер"] = {"ru": temper, "en": temper}
		db.version += 1
	for a in _list(answer, "renames"):
		var c := db.company(str((a as Dictionary).get("id", "")))
		var title := str((a as Dictionary).get("название", "")).strip_edges()
		if not c.is_empty() and not title.is_empty() and title.length() <= 40 and rename_cb.is_valid():
			rename_cb.call(c, {"ru": title, "en": title})
	for a in _list(answer, "letters"):
		var l := letters.letter(int((a as Dictionary).get("number", -1)))
		var text := str((a as Dictionary).get("текст", "")).strip_edges()
		if not l.is_empty() and text.length() >= 20:
			l["текст"] = text
	for a in _list(answer, "газета"):
		var k := int((a as Dictionary).get("ключ", -1))
		for p in press:
			if int(p["ключ"]) == k:
				var story := str((a as Dictionary).get("title", "")) + " " + str((a as Dictionary).get("текст", ""))
				var sc := db.company(str(p.get("id", "")))
				var ctx := {"polity": Guard.any_state(sc) if not sc.is_empty() else true, "facts": str(p.get("текст", ""))}
				if not sc.is_empty():
					ctx["facts"] = str(ctx["facts"]) + " " + str(Guard.facts(db, sc, text_of, game.day())["_text"])
					var ch := db.change(sc, 1)
					if absf(ch) >= 0.03:
						ctx["down"] = ch < 0.0
				if Guard.ok(story, ctx):
					p["ии"] = {"title": str((a as Dictionary).get("title", "")), "текст": str((a as Dictionary).get("текст", ""))}
				else:
					stats["dropped"] = int(stats.get("dropped", 0)) + 1


# ---------- the week's business events: rolled by the game, told by the AI ----------
# Each kind has its chance a week (balance «ии_события» «вероятность»); the game picks the company (bigger ones are
# likelier, an accident needs sites), the direction and the size (its span); the AI only writes the headline and
# the text of what the game rolled — it neither invents events nor picks numbers. Without the AI the templates
# «pax_corporations_ev_<kind>_<up|down>» tell them.

const EVENT_TYPES := {"contract": 1, "продукт": 1, "partnership": 1, "scandal": -1, "авария": -1, "иск": -1, "regulation": 0}
const SITE_SECTORS := ["oil_gas", "энергетика", "metallurgy", "химия", "добыча", "авто", "defence", "semiconductors", "pharma", "транспорт", "строительство"]

var _rolled: Array = []          # [{тип, id, партнёр, знак, размер}] waiting for their texts
var _rolled_day := -1


func _roll_events() -> Array:
	var cfg: Dictionary = db.balance.get("ai_events", {})
	if not bool(cfg.get("enabled_flag", true)) or db.companies.is_empty():
		return []
	var day := game.day()
	var weeks := 1 if _rolled_day < 0 else clampi(floori(float(day - _rolled_day) / 7.0), 0, 4)
	if weeks <= 0:
		return _events_data()
	_rolled_day = day
	var chances: Dictionary = cfg.get("probability", {})
	var big := db.companies.duplicate()
	big.sort_custom(func(a, b): return db.cap(a) > db.cap(b))
	big = big.slice(0, 300)
	var cap_n := int(cfg.get("per_week", 2)) * weeks
	for w in weeks:
		for kind in EVENT_TYPES.keys():
			if _rolled.size() >= cap_n:
				break
			if _rng.randf() >= float(chances.get(kind, 0.0)):
				continue
			var pool: Array = big
			if kind == "авария":
				pool = big.filter(func(x): return str((x as Dictionary).get("sector", "")) in SITE_SECTORS and not ((x as Dictionary).get("sites", []) as Array).is_empty())
			var c := _pick_weighted(pool)
			if c.is_empty():
				continue
			var sign := int(EVENT_TYPES[kind])
			if sign == 0:
				sign = 1 if _rng.randf() < float(cfg.get("regulation_plus", 0.4)) else -1
			var span: Array = cfg.get(kind, [0.02, 0.06])
			var size := _rng.randf_range(float(span[0]), float(span[1]))
			var ev := {"type": str(kind), "id": str(c["id"]), "partner": "", "sign": sign, "размер": size}
			if kind == "partnership":
				var same: Array = big.filter(func(x): return x != c and str((x as Dictionary).get("sector", "")) == str(c.get("sector", "")))
				var other := _pick_weighted(same if not same.is_empty() else big)
				if other.is_empty() or other == c:
					continue
				ev["partner"] = str(other["id"])
			_rolled.append(ev)
	return _events_data()


## A company from the list, the bigger the likelier (by the square root of its value).
func _pick_weighted(pool: Array) -> Dictionary:
	var total := 0.0
	for c in pool:
		total += sqrt(maxf(db.cap(c), 1.0))
	if total <= 0.0:
		return {}
	var r := _rng.randf() * total
	for c in pool:
		r -= sqrt(maxf(db.cap(c), 1.0))
		if r <= 0.0:
			return c
	return pool.back() if not pool.is_empty() else {}


## The rolled events with their real facts, for the AI to write about.
func _events_data() -> Array:
	var out: Array = []
	for i in _rolled.size():
		var ev: Dictionary = _rolled[i]
		var c := db.company(str(ev["id"]))
		if c.is_empty():
			continue
		var f := Guard.facts(db, c, text_of, game.day())
		var other := db.company(str(ev.get("partner", "")))
		out.append({"n": i, "type": str(ev["type"]), "company": db.name_of(c), "отрасль": db.sector_name(str(c.get("sector", ""))),
			"country": str(c.get("_country", "")), "direction": "хорошо" if int(ev["sign"]) > 0 else "плохо",
			"shares_push_percent": roundi(float(ev["размер"]) * 100.0 * float(ev["sign"])),
			"partner": db.name_of(other) if not other.is_empty() else "", "owners": f["owners"],
			"state_owns": f["state_owns"], "company_events": f["company_events"]})
	return out


## The rolled events happen: the AI's text if it passed the guard, else the template.
func _apply_rolled(answer: Dictionary, rolled: Array) -> void:
	var texts := {}
	for a in _list(answer, "week_events"):
		texts[int((a as Dictionary).get("n", -1))] = a
	var player := str(game.player_faction().get("name", ""))
	for i in rolled.size():
		var ev: Dictionary = rolled[i]
		var c := db.company(str(ev["id"]))
		if c.is_empty():
			continue
		var kind := str(ev["type"])
		var sign := int(ev["sign"])
		var size := float(ev["размер"])
		var other := db.company(str(ev.get("partner", "")))
		var line := ""
		if texts.has(i):
			var ad: Dictionary = texts[i]
			var head := str(ad.get("title", "")).strip_edges()
			var text := str(ad.get("текст", "")).strip_edges()
			var f := Guard.facts(db, c, text_of, game.day())
			if not head.is_empty() and text.length() >= 12 and text.length() <= 400 \
					and Guard.ok(head + " " + text, {"down": sign < 0, "polity": bool(f["state_owns"]), "facts": str(f["_text"])}):
				line = head + " — " + text
			else:
				stats["events_dropped"] = int(stats.get("events_dropped", 0)) + 1
		if line.is_empty():
			var tpl := mod.tr_key("pax_corporations_ev_%s_%s" % [kind, "up" if sign > 0 else "down"])
			line = tpl % ([db.name_of(c), db.name_of(other)] if tpl.count("%s") >= 2 else [db.name_of(c)])
		_happen(c, kind, sign * size, line, player)
		if kind == "partnership" and not other.is_empty():
			_happen(other, kind, sign * size * 0.8, line, player)
		elif kind == "regulation":
			for o in db.companies:
				if o != c and str(o.get("sector", "")) == str(c.get("sector", "")) and str(o.get("_country", "")) == str(c.get("_country", "")):
					var oe := db.econ(o)
					if not oe.is_empty():
						oe["шок"] = float(oe.get("шок", 0.0)) + log(1.0 + sign * size * 0.5)
		stats["events_count"] = int(stats.get("events_count", 0)) + 1


## One event happens to a company: its shares get the shock, its chronicle and the newspaper tell it.
func _happen(c: Dictionary, kind: String, move: float, line: String, player: String) -> void:
	var e := db.econ(c)
	if not e.is_empty():
		e["шок"] = float(e.get("шок", 0.0)) + log(1.0 + move)
	var entry := {"день": game.day(), "вид": "ии_событие", "type": kind, "текст": line, "доля": move, "up": move >= 0.0}
	(c["_chronicle"] as Array).append(entry)
	var country := str(c.get("_country", ""))
	press.append({"ключ": _next_key, "id": str(c["id"]), "company": db.name_of(c), "country": country, "день": game.day(),
		"размер": 0.6 + absf(move) * 4.0, "текст": line, "мир": country != player, "ии": {"title": line.get_slice(" — ", 0), "текст": line.get_slice(" — ", 1)}})
	_next_key += 1
	db.version += 1


static func _list(answer: Dictionary, key: String) -> Array:
	var v: Variant = answer.get(key, [])
	return (v as Array).filter(func(x): return x is Dictionary) if v is Array else []


# ---------- the newspaper ----------

## The game's report for a stretch of time is ready (hook «report_ready»): the loudest corporate stories of the
## world and of the player's country go into its newspaper, a paragraph into the player's personal report.
func on_report(d: Dictionary, player: String) -> void:
	if db == null:
		return
	var report: Variant = d.get("report")
	if not (report is Dictionary):
		return
	var rep: Dictionary = report
	mod.save_data("report_sample", _shape(rep, 0))
	var cfg := _cfg()
	# Development news first (all of them, up to «газета_развитие»), then the loudest of the world and of the country.
	var dev: Array = press.filter(func(p): return bool(p.get("required", false)))
	var rest: Array = press.filter(func(p): return not bool(p.get("required", false)))
	var world: Array = rest.filter(func(p): return bool(p["мир"]))
	var home: Array = rest.filter(func(p): return not bool(p["мир"]))
	var picked: Array = dev.slice(0, int(cfg.get("газета_развитие", 10))) + world.slice(0, int(cfg.get("paper_world", 3))) + home.slice(0, int(cfg.get("paper_country", 3)))
	var articles: Array = []
	for p in picked:
		var ai: Dictionary = p["ии"]
		var title := str(ai.get("title", "")).strip_edges()
		var text := str(ai.get("текст", "")).strip_edges()
		if title.is_empty() and p.has("form"):
			title = mod.tr_key("pax_corporations_press_title_%s_%s" % [str(p.get("вид", "узел")), str(p["form"])]) % str(p["country"])
		if title.is_empty():
			title = "%s: %s" % [str(p["company"]), str(p["текст"])]
		if text.is_empty():
			text = str(p["текст"])
		articles.append({"title": title, "текст": text, "country": str(p["country"])})
	press.clear()
	var placed := _into_newspaper(rep, articles)
	_into_personal(rep, player)
	if not placed and not articles.is_empty():
		# The report has no newspaper the mod recognises — the stories go to the game's news feed instead.
		var feed: Variant = game.main.get("вести")
		for a in articles:
			if feed is Object and (feed as Object).has_method("весть"):
				(feed as Object).call("весть", "neutral", "📰 " + str(a["title"]), str(a["текст"]), 0, "")


## Finds the newspaper in the report: a list of articles (dictionaries with a title and a text) — appends in
## the same shape; a text field — appends paragraphs.
func _into_newspaper(rep: Dictionary, articles: Array) -> bool:
	if articles.is_empty():
		return true
	for key in rep.keys():
		var name := str(key).to_lower()
		if not (name.contains("газет") or name.contains("стать") or name.contains("newspaper") or name.contains("article") or name.contains("пресс")):
			continue
		var v: Variant = rep[key]
		if v is Array:
			_append_articles(v as Array, articles)
			return true
		if v is Dictionary:
			for k2 in (v as Dictionary).keys():
				if (v as Dictionary)[k2] is Array:
					_append_articles((v as Dictionary)[k2] as Array, articles)
					return true
		if v is String:
			var s := str(v)
			for a in articles:
				s += "\n\n" + str(a["title"]) + "\n" + str(a["текст"])
			rep[key] = s
			return true
	# No named newspaper: any list of dictionaries that look like articles.
	for key in rep.keys():
		var v: Variant = rep[key]
		if v is Array and not (v as Array).is_empty() and (v as Array)[0] is Dictionary and _title_key((v as Array)[0] as Dictionary) != "":
			_append_articles(v as Array, articles)
			return true
	return false


func _append_articles(list: Array, articles: Array) -> void:
	var proto: Dictionary = list[0] if not list.is_empty() and list[0] is Dictionary else {}
	var tk := _title_key(proto) if not proto.is_empty() else "title"
	var xk := _text_key(proto) if not proto.is_empty() else "текст"
	for a in articles:
		var item := {}
		for k in proto.keys():
			item[k] = proto[k] if not (proto[k] is String) else ""
		item[tk if not tk.is_empty() else "title"] = str(a["title"])
		item[xk if not xk.is_empty() else "текст"] = str(a["текст"])
		list.append(item)


static func _title_key(d: Dictionary) -> String:
	for k in d.keys():
		var n := str(k).to_lower()
		if n.contains("заголов") or n.contains("title") or n.contains("headline"):
			return str(k)
	return ""


static func _text_key(d: Dictionary) -> String:
	for k in d.keys():
		var n := str(k).to_lower()
		if n.contains("текст") or n.contains("text") or n.contains("gist") or n.contains("body"):
			return str(k)
	return ""


## The personal report: a paragraph about the country's corporations (what they pay, who rose and fell).
func _into_personal(rep: Dictionary, player: String) -> void:
	var key := ""
	for k in rep.keys():
		var n := str(k).to_lower()
		if (n.contains("доклад") or n.contains("личн") or n.contains("personal")) and rep[k] is String:
			key = str(k)
	if key.is_empty():
		return
	var mine: Array = db.companies.filter(func(x): return str(x.get("_country", "")) == player)
	if mine.is_empty():
		return
	mine.sort_custom(func(a, b): return db.change(a, 13) > db.change(b, 13))
	var best: Dictionary = mine[0]
	var worst: Dictionary = mine[mine.size() - 1]
	var t := mod.tr_key("pax_corporations_press_personal") % [db.money(float(treasury_year.call()) if treasury_year.is_valid() else 0.0),
		db.name_of(best), db.percent(db.change(best, 13), true), db.name_of(worst), db.percent(db.change(worst, 13), true)]
	rep[key] = str(rep[key]) + "\n\n" + t


static func _shape(x: Variant, depth: int) -> Variant:
	if depth > 3:
		return type_string(typeof(x))
	if x is Dictionary:
		var out := {}
		for k in (x as Dictionary).keys():
			out[str(k)] = _shape((x as Dictionary)[k], depth + 1)
		return out
	if x is Array:
		return [(x as Array).size(), _shape((x as Array)[0], depth + 1) if not (x as Array).is_empty() else null]
	if x is String:
		return "String(%d)" % str(x).length()
	return x


# ---------- save ----------

func save_state() -> Dictionary:
	return {"газета": press, "ключ": _next_key, "results": stats}


func load_state(state: Dictionary) -> void:
	press = (state.get("газета", []) as Array).duplicate(true) if state.get("газета") is Array else []
	_next_key = int(state.get("ключ", 1))
	stats = (state.get("results", {}) as Dictionary).duplicate() if state.get("results") is Dictionary else {}
