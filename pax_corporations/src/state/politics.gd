extends RefCounted
## Companies as political actors (sections 8, 12, 13). Only the player's country has laws, taxes and
## a political system in the game, so this works for its companies:
##
## Trust in the state (0..100) — the mood towards power. Target = base (state companies trust more,
## corruption erodes it) + reactions to the laws passed or repealed during the game (the sector table
## «законы» in config/sectors.json; a law is recognised by its section and words) + the tax rate against
## the start + the military course against the start. It moves smoothly (20.13).
##
## Escalation ladder of a discontented company (trust below the threshold for several weeks):
## 1 criticism in the press → 2 the head demands (a letter) → 3 backs the opposition (it sponsors the opposition,
## influence.gd) → 4 a threat (cut jobs, move production) → 5 carries it out (layoffs and
## part of the business leaves the country: fewer taxes, jobs and rating). A content company does the
## opposite: praises the government; the business mood reaches the «бизнес» force through influence.gd.
##
## A head becomes a game contact («Связи», played by the game's AI) only when the player chooses to talk to them
## (the head's name in the dossier, «Поговорить» in a letter) — never on its own: every new contact makes the game
## announce it and build a character.

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const LAW_KINDS := ["tax_growth", "windfall_tax", "science_subsidies", "military_course", "экология", "labour_rights", "market_opening"]
## How a law is recognised: its section and words in its title/summary (ru + en).
const LAW_WORDS := {
	"windfall_tax": ["сверхприбыл", "windfall", "excess profit"],
	"tax_growth": ["налог", "сбор", "пошлин", "акциз", "tax", "levy", "duty"],
	"science_subsidies": ["наук", "исследован", "грант", "субсид", "технолог", "science", "research", "grant", "subsid"],
	"military_course": ["армия", "оборон", "мобилиз", "военн", "призыв", "army", "defen", "military", "draft"],
	"экология": ["эколог", "выброс", "природ", "климат", "лес", "загрязн", "ecolog", "emission", "climate", "pollut", "green"],
	"labour_rights": ["труд", "рабоч", "профсоюз", "зарплат", "пенси", "отпуск", "labour", "labor", "union", "wage", "worker"],
	"market_opening": ["приватиз", "инвест", "иностран", "свобод", "дерегул", "privati", "invest", "foreign", "free trade", "deregul"],
}
const LAW_SECTIONS := {"оборона": "military_course", "наука": "science_subsidies", "земля": "экология"}
## Which industries a law is about (its words); a law naming none is about every industry.
const SECTOR_WORDS := {
	"oil_gas": ["нефт", "gas", "топлив", "oil", "gas", "fuel"],
	"metallurgy": ["шахт", "горн", "руд", "металл", "сталь", "уголь", "mine", "mining", "steel", "metal", "coal"],
	"энергетика": ["энерг", "электр", "энергосет", "power", "electric", "energy"],
	"it": ["цифров", "интернет", "программ", "связ", "it-", "айти", "digital", "internet", "software", "telecom"],
	"semiconductors": ["чип", "микроэлектрон", "полупровод", "chip", "semiconductor"],
	"banks": ["банк", "кредит", "финанс", "страхов", "bank", "credit", "financ", "insur"],
	"pharma": ["врач", "медиц", "здравоохр", "больниц", "лекарств", "фарм", "doctor", "medic", "health", "hospital", "pharma", "drug"],
	"defence": ["оборонн", "военно-промышл", "вооружен", "defence industry", "arms", "weapon"],
	"авиа": ["водител", "транспорт", "авиа", "перевоз", "логист", "driver", "transport", "aviation", "airline", "logistic"],
	"tourism": ["туризм", "отел", "гостиниц", "tourism", "hotel"],
	"auto_industry": ["автомоб", "автопром", "car industry", "automotive"],
	"retail": ["торгов", "магазин", "ритейл", "retail", "shop", "store"],
	"медиа": ["сми", "медиа", "журналист", "media", "journalist", "press"],
	"строительство": ["строит", "стройк", "жильё", "жилищ", "construct", "building", "housing"],
	"ии": ["искусственн", "нейросет", "ии-", " ии ", "artificial intelligence", " ai "],
	"наука": ["наук", "учён", "учен", "исследоват", "science", "scientist", "research"],
	"космос": ["космо", "спутник", "ракет", "орбит", "space", "satellite", "rocket", "orbit"],
}
## A labour law against workers: these words; otherwise a labour law is for them.
const ANTI_WORKER := ["запрет забаст", "запрещ забаст", "огранич профсоюз", "увелич рабоч", "продлен рабоч", "продлить рабоч",
	"сократ отпуск", "отмен минимал", "отмен профсоюз", "ban strike", "ban on strike", "restrict union", "longer working", "extend working"]

var _heads_added: Dictionary = {}
var _law_kinds: Dictionary = {}      # law title|section -> kind, so the words are searched once per law
var _start: Dictionary = {}          # tax rate and military share at the start of the game
var _seen_laws: Dictionary = {}      # law key -> its sign last week (new laws and repeals become events)
var _laws_ready := false
var news: Array = []                 # this week's: {c, entry, tone, size}
var new_laws: Array = []             # laws passed or repealed this week: {вид, знак, заголовок, сектора, за_работников}
var business_mood := 0.0            # companies' mood towards the government, −1..1, weighted by size
var letter_events: Array = []        # this week's demands and threats of heads (letters.gd)


func setup(game: PaxGame) -> void:
	if _start.is_empty():
		_start = {"tax": _tax_rate(game), "army": _army_share(game)}


# ---------- weekly ----------

func step(db: Data, game: PaxGame, day: int, _favorites: Dictionary) -> void:
	news.clear()
	letter_events.clear()
	setup(game)
	var cfg: Dictionary = db.balance.get("policy", {})
	var player := str(game.player_faction().get("name", ""))
	var laws := _law_reactions(game)
	_new_laws(laws, db, player, day)
	_labour_effects(db, laws, player, cfg)
	var tax_now := _tax_rate(game)
	var army_now := _army_share(game)
	var mood_sum := 0.0
	var weight_sum := 0.0
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty() or str(c.get("_country", "")) != player:
			continue
		var target := _trust_target(db, c, laws, tax_now, army_now, cfg)
		var t := float(e.get("trust", -1.0))
		t = float(target["value"]) if t < 0.0 else t + float(cfg.get("smoothing", 0.1)) * (float(target["value"]) - t)
		e["trust"] = t
		e["trust_parts"] = target["parts"]
		_ladder(db, c, e, t, target, cfg, day)
		var w := sqrt(maxf(db.cap(c), 1.0))
		mood_sum += w * (t - 50.0) / 50.0
		weight_sum += w
	# The business mood (−1..1) — influence.gd passes it to the «бизнес» force (and to «олигархи» in old presets).
	business_mood = mood_sum / weight_sum if weight_sum > 0.0 else 0.0


# ---------- trust (sections 8, 13) ----------

func _trust_target(db: Data, c: Dictionary, laws: Array, tax_now: float, army_now: float, cfg: Dictionary) -> Dictionary:
	var reactions: Dictionary = db.sector_of(c).get("законы", {})
	var parts: Array = [["base", 50.0]]
	if db.tree(c, "trust", 0.0) != 0.0:
		parts.append(["tree", db.tree(c, "trust", 0.0)])   # the industry's tree (tree.gd)
	var state := db.state_share(c)
	if state > 0.5:
		parts.append(["state_owned", float(cfg.get("state_companies", 10.0))])
	var k := float(((c.get("_statuses", {}) as Dictionary).get("corruption", {}) as Dictionary).get("value", 30.0)) / 100.0
	parts.append(["corruption", -20.0 * maxf(0.0, k - 0.3)])
	var per_point := float(cfg.get("law_points", 10.0))
	for law in laws:
		var r := law_reaction(db, c, law)
		if r != 0.0:
			parts.append(["law:" + str(law["title"]), r * per_point])
	if tax_now > 0.0 and float(_start.get("tax", 0.0)) > 0.0:
		var d_tax := (tax_now - float(_start["tax"])) / 0.05
		var r_tax := float(reactions.get("tax_growth", -1.0))
		if absf(d_tax) > 0.01:
			parts.append(["taxes", -absf(r_tax) * per_point * d_tax])
	var d_army := (army_now - float(_start.get("army", army_now))) / 0.1
	if absf(d_army) > 0.01:
		parts.append(["military_course", float(reactions.get("military_course", 0.0)) * per_point * d_army])
	var v := 0.0
	for p in parts:
		v += float(p[1])
	return {"value": clampf(v, 0.0, 100.0), "parts": parts}


## How a company takes a law: the sector table «законы» (−2..+2) × passed (+1) or repealed (−1). A labour law
## touches only the industries it names; one against workers pleases the employers.
static func law_reaction(db: Data, c: Dictionary, law: Dictionary) -> float:
	var r := float((db.sector_of(c).get("законы", {}) as Dictionary).get(str(law["вид"]), 0.0)) * float(law["sign"])
	if str(law["вид"]) == "labour_rights":
		var scope: Array = law.get("sectors", [])
		if not scope.is_empty() and not (str(c.get("sector", "")) in scope):
			return 0.0
		if not bool(law.get("pro_workers", true)):
			r = -r
	return r


## Laws passed or repealed during the game: [{вид, знак, заголовок}] — знак +1 passed, −1 repealed.
func _law_reactions(game: PaxGame) -> Array:
	var out: Array = []
	var laws: Variant = game.main.get("законы")
	if not (laws is Array):
		return out
	for item in laws:
		if not (item is Dictionary):
			continue
		var law: Dictionary = item
		var native := bool(law.get("native", false))
		var repealed := bool(law.get("canceled", false))
		var passed := str(law.get("status", "")) == "принят"
		var dir := 0.0
		if not native and passed and not repealed:
			dir = 1.0
		elif native and repealed:
			dir = -1.0
		if dir == 0.0:
			continue
		var key := str(law.get("title", "")) + "|" + str(law.get("section", ""))
		if not _law_kinds.has(key):
			_law_kinds[key] = classify_law(law)   # the text of a law does not change — classify once
		var kind := str(_law_kinds[key])
		if not kind.is_empty():
			var text := (str(law.get("title", "")) + " " + str(law.get("gist", "")) + " " + str(law.get("текст", ""))).to_lower()
			out.append({"вид": kind, "sign": dir, "title": str(law.get("title", "")), "ключ": key,
				"sectors": law_sectors(text), "pro_workers": not _any_word(text, ANTI_WORKER)})
	return out


## Industries named in a law's text; [] — the law is about all of them.
static func law_sectors(text: String) -> Array:
	var out: Array = []
	for sector in SECTOR_WORDS.keys():
		if _any_word(text, SECTOR_WORDS[sector]):
			out.append(str(sector))
	return out


static func _any_word(text: String, words: Array) -> bool:
	for w in words:
		if text.contains(str(w)):
			return true
	return false


## Laws that appeared (or were repealed) since last week — events for letters (letters.gd) and the labour rules.
func _new_laws(laws: Array, db: Data, player: String, day: int) -> void:
	new_laws.clear()
	var now := {}
	for law in laws:
		now[str(law["ключ"])] = float(law["sign"])
	if not _laws_ready:
		# The first week (a new game or a save from before 2.1.0): the laws already in force are not news.
		_laws_ready = true
		_seen_laws = now
		return
	for law in laws:
		var key := str(law["ключ"])
		if not _seen_laws.has(key) or float(_seen_laws[key]) != float(law["sign"]):
			new_laws.append(law)
			if str(law["вид"]) == "labour_rights" and float(law["sign"]) > 0.0:
				_mandated_raise(db, law, player, day)
	_seen_laws = now


## A labour law for workers raises the market wage (and the wages) in the industries it covers at once.
func _mandated_raise(db: Data, law: Dictionary, player: String, day: int) -> void:
	if not bool(law["pro_workers"]):
		return
	var raise := float((db.balance.get("policy", {}) as Dictionary).get("labour_law_markup", 0.03))
	var scope: Array = law["sectors"]
	for item in db.companies:
		var c: Dictionary = item
		if str(c.get("_country", "")) != player or not (scope.is_empty() or str(c.get("sector", "")) in scope):
			continue
		var e := db.econ(c)
		if e.is_empty():
			continue
		e["market_wage"] = float(e["market_wage"]) * (1.0 + raise)
		e["W"] = float(e["W"]) * (1.0 + raise)
		(c["_chronicle"] as Array).append({"день": day, "вид": "трудовой_закон", "доля": raise, "текст": str(law["title"])})


## Labour laws in force (player's country): what they do to the companies of the industries they cover —
## db.labour[sector] = {довольство (+/−), забастовки ×, уход ×, издержки ×}. Read by economy.gd.
func _labour_effects(db: Data, laws: Array, player: String, cfg: Dictionary) -> void:
	var per: Dictionary = cfg.get("labour_laws", {})
	var pro: Dictionary = per.get("pro_workers", {"satisfaction": 0.05, "strikes": 1.5, "exit": 0.9, "издержки": 1.01})
	var anti: Dictionary = per.get("anti_workers", {"satisfaction": -0.06, "strikes": 0.5, "exit": 1.2, "издержки": 0.99})
	var out := {}
	for law in laws:
		if str(law["вид"]) != "labour_rights":
			continue
		var eff: Dictionary = pro if bool(law["pro_workers"]) == (float(law["sign"]) > 0.0) else anti
		var scope: Array = law["sectors"]
		for sector in db.sectors.keys():
			if not scope.is_empty() and not (str(sector) in scope):
				continue
			var cur: Dictionary = out.get(sector, {"satisfaction": 0.0, "strikes": 1.0, "exit": 1.0, "издержки": 1.0, "laws_count": 0})
			cur["satisfaction"] = float(cur["satisfaction"]) + float(eff.get("satisfaction", 0.0))
			for k in ["strikes", "exit", "издержки"]:
				cur[k] = float(cur[k]) * float(eff.get(k, 1.0))
			cur["laws_count"] = int(cur["laws_count"]) + 1
			out[sector] = cur
	db.labour_rules = out
	db.labour_country = player


## Which sector reaction a law triggers: by its words first, then by its section.
static func classify_law(law: Dictionary) -> String:
	var text := (str(law.get("title", "")) + " " + str(law.get("gist", "")) + " " + str(law.get("заголовок_en", ""))
		+ " " + str(law.get("текст", ""))).to_lower()
	for kind in ["windfall_tax", "tax_growth", "labour_rights", "экология", "market_opening", "science_subsidies", "military_course"]:
		for w in LAW_WORDS[kind]:
			if text.contains(str(w)):
				return kind
	return str(LAW_SECTIONS.get(str(law.get("section", "")), ""))


func _tax_rate(game: PaxGame) -> float:
	var farms: Variant = game.main.get("хозяйства")
	if farms is Dictionary:
		var h: Dictionary = (farms as Dictionary).get(game.home_body(), {})
		return float(h.get("tax", 0.0))
	return 0.0


func _army_share(game: PaxGame) -> float:
	var course: Variant = game.main.get("курс")
	if course is Dictionary:
		var fact: Variant = (course as Dictionary).get("факт", {})
		if fact is Dictionary:
			return float((fact as Dictionary).get("army", 0.0))
	return 0.0


# ---------- escalation ladder (section 13) ----------

func _ladder(db: Data, c: Dictionary, e: Dictionary, trust: float, target: Dictionary, cfg: Dictionary, day: int) -> void:
	var low := float(cfg.get("discontent_threshold", 35.0))
	var high := float(cfg.get("satisfaction_threshold", 70.0))
	var weeks_per_step := int(cfg.get("weeks_per_step", 4))
	var rung := int(e.get("ladder", 0))
	var weeks := int(e.get("ladder_weeks", 0))
	if trust < low:
		weeks += 1
		if weeks >= weeks_per_step and rung < 5:
			rung += 1
			weeks = 0
			_ladder_step(db, c, e, rung, target, day)
			if rung == 5:
				rung = 3   # the threat is carried out; the company stays hostile but starts over from «backs the opposition»
	elif trust > low + 10.0:
		weeks = 0
		if rung > 0:
			rung -= 1
			if rung == 0:
				_chron_news(c, day, {"вид": "лестница_мир"}, "good", 0.2)
	e["ladder"] = rung
	e["ladder_weeks"] = weeks
	# A content company praises the government now and then.
	if trust > high and day - int(e.get("praise_day", -9999)) > 180:
		e["praise_day"] = day
		_chron_news(c, day, {"вид": "похвала"}, "good", 0.2)


func _ladder_step(db: Data, c: Dictionary, e: Dictionary, rung: int, target: Dictionary, day: int) -> void:
	var grievance := worst_part(target)
	var entry := {"вид": "ladder", "ступень": rung, "grudge": grievance}
	if rung in [2, 4]:
		# The head writes to the player (letters.gd): a demand, then a threat with 8 weeks to answer (20.7).
		letter_events.append({"вид": "ladder", "c": c, "ступень": rung, "grudge": grievance})
	if rung == 4:
		entry["count_value"] = db.staff(c) * 0.1
		e["threat_day"] = day
	if rung == 5:
		# Carries out the threat: 10% of the staff laid off, a tenth of the business moves abroad.
		var fired := float(e["N"]) * 0.1
		e["N"] = float(e["N"]) - fired
		e["fired26"] = float(e.get("fired26", 0.0)) + fired
		e["demand"] = float(e["demand"]) * 0.9
		e["шок"] = float(e.get("шок", 0.0)) - 0.05
		entry["count_value"] = fired
		e["trust"] = 40.0
	_chron_news(c, day, entry, "bad", 0.3 + 0.1 * rung)


## The biggest negative part of the trust target — what the company is angry about.
static func worst_part(target: Dictionary) -> String:
	var worst := ""
	var worst_v := 0.0
	for p in target.get("parts", []):
		if float(p[1]) < worst_v:
			worst_v = float(p[1])
			worst = str(p[0])
	return worst


func _chron_news(c: Dictionary, day: int, entry: Dictionary, tone: String, size: float) -> void:
	entry["день"] = day
	(c["_chronicle"] as Array).append(entry)
	news.append({"c": c, "entry": entry, "tone": tone, "size": size, "big": true})


# ---------- heads as contacts (section 12) ----------

## Makes the company's head a contact of the game (the AI plays them); returns the person's name ("" — no head).
## Only on the player's request: the head's name in the dossier, «Поговорить» in a letter (main.write_head).
func add_head(db: Data, game: PaxGame, c: Dictionary) -> String:
	var lead: Dictionary = c.get("глава", {})
	var person := db.text(lead.get("name", ""))
	if person.is_empty():
		return ""
	_heads_added[str(c["id"])] = true
	if game.has_character(person):
		return person
	var year := int(game.date().get("year", 2026))
	var info := {
		"name": person,
		"кто": db.mod.tr_key("pax_corporations_head_who") % [db.name_of(c), db.mod.tr_key("pax_corporations_role_" + str(lead.get("роль", "")))],
		"лор": db.text(c.get("description", "")) + " " + db.mod.tr_key("pax_corporations_head_lore") % [
			db.people(db.staff(c)), db.money(db.cap(c)), int(lead.get("с_года", year))],
		"характер": db.text(lead.get("характер", "")),
		"возраст": year - int(lead.get("born_year", year - 55)),
		"occupation": db.mod.tr_key("pax_corporations_head_doing") % db.name_of(c),
		"хочет": db.mod.tr_key("pax_corporations_head_wants"),
	}
	game.add_character(game.home_body(), info, "", false)
	return person


func heads_added(cid: String) -> bool:
	return _heads_added.has(cid)


# ---------- save ----------

func save_state() -> Dictionary:
	return {"старт": _start, "главы": _heads_added.keys(), "законы": _seen_laws}


func load_state(state: Dictionary) -> void:
	if state.get("старт") is Dictionary:
		_start = (state["старт"] as Dictionary).duplicate()
	if state.get("законы") is Dictionary:
		_seen_laws = (state["законы"] as Dictionary).duplicate()
		_laws_ready = true
	if state.get("главы") is Array:
		for cid in state["главы"]:
			_heads_added[str(cid)] = true
