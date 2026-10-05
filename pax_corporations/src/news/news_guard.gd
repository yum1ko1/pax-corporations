extends RefCounted
## A strict filter for every text the AI writes about companies (narrator.gd, the home's bulletin): the game's
## facts win. A text is thrown away (the game's own line stays) when it
##   • tells of a death, an arrest, a resignation, an election or a coup that the facts do not mention;
##   • calls the company the state's / the government's while no state holds a share;
##   • goes the wrong way: a fall told as growth or a rise told as a fall (more words of one direction).
## facts(): the company's real situation for the prompt — owners, the state's share, the last chronicle events.

const DRAMA := ["умер", "скончал", "погиб", "убит", "смерт", "арест", "задержан", "отставк", "уволен глав", "переворот", "выбор",
	"died", "dies", "dead", "death", "killed", "arrest", "resign", "fired", "coup", "election"]
const STATE := ["государств", "правительств", "госкомпан", "госкорпор", "национализ", "кремл", "министерств",
	"state-owned", "government", "nationali", "the state", "ministry"]
const UP := ["вырос", "рост", "растёт", "растет", "подорож", "взлет", "взлёт", "прибав", "увелич", "укреп", "улучш", "рекорд",
	"успех", "подъём", "подъем", "rose", "rise", "gain", "surge", "jump", "record", "grew", "growth", "improv", "rally", "soar"]
const DOWN := ["упал", "паден", "снизи", "сниж", "обвал", "рухн", "потер", "убыт", "кризис", "провал", "подешев", "просел",
	"fell", "fall", "drop", "plung", "loss", "slump", "declin", "crash", "lost", "tumbl", "sank"]


## true — the text fits the facts. ctx: {"down": true/false (or absent — no direction check), "polity": bool,
## "facts": the facts as one text (what they mention is allowed)}.
static func ok(text: String, ctx: Dictionary) -> bool:
	var low := text.to_lower()
	var facts := str(ctx.get("facts", "")).to_lower()
	for w in DRAMA:
		if low.contains(w) and not facts.contains(w):
			return false
	if not bool(ctx.get("polity", false)):
		for w in STATE:
			if low.contains(w) and not facts.contains(w):
				return false
	if ctx.has("down"):
		var up := 0
		var down := 0
		for w in UP:
			up += low.count(w)
		for w in DOWN:
			down += low.count(w)
		if bool(ctx["down"]) and up > down:
			return false
		if not bool(ctx["down"]) and down > up:
			return false
	return true


## Does any state hold a share of the company (its own or a foreign one)?
static func any_state(c: Dictionary) -> bool:
	for o in c.get("owners", []):
		if o is Dictionary and str((o as Dictionary).get("type", "")) == "polity" and float((o as Dictionary).get("доля", 0.0)) > 0.0:
			return true
	return false


## The company's owners for a prompt: [«who — type — share %»…], biggest first.
static func owners(db: Object, c: Dictionary) -> Array:
	var list: Array = (c.get("owners", []) as Array).filter(func(o): return o is Dictionary and float((o as Dictionary).get("доля", 0.0)) > 0.001)
	list.sort_custom(func(a, b): return float((a as Dictionary)["доля"]) > float((b as Dictionary)["доля"]))
	var out: Array = []
	for o in list.slice(0, 4):
		var od: Dictionary = o
		out.append("%s — %s — %d%%" % [str(db.call("text", od.get("кто", ""))), str(od.get("type", "")), roundi(float(od["доля"]) * 100.0)])
	return out


## The company's real facts for a prompt and for ok(): owners, the state's presence, its recent chronicle lines.
static func facts(db: Object, c: Dictionary, chron_text: Callable, day: int) -> Dictionary:
	var lines: Array = []
	for e in (c.get("_chronicle", []) as Array).slice(-6):
		var ed: Dictionary = e
		if day - int(ed.get("день", -999)) <= 35 and chron_text.is_valid():
			lines.append(str(chron_text.call(c, ed)))
	var own := owners(db, c)
	return {"owners": own, "state_owns": any_state(c), "company_events": lines,
		"_text": " ".join(PackedStringArray(own)) + " " + " ".join(PackedStringArray(lines))}
