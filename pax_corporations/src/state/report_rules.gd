extends RefCounted
## Rules for the game's own AI report of a stretch of time (the hook «ai_request», channel «report»). The AI must not
## decide by itself to destroy what the player built: whether there is an accident, where and how big is ROLLED by
## the game here — a chance per week of the stretch (balance «отчёт» «авария_в_неделю», at most «авария_макс» for one
## report), a random province of the player's country, a kind from «виды»; the AI is told exactly that (or that
## there is none) and that an accident is told as an accident in the news. Nothing else of the report is touched:
## the country's economy stays the game's.
## The first requests' text is kept (mod data «report_prompt_sample») to tune the rules to the game's prompt.

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")

var db: Data
var mod: PaxMod
var game: PaxGame
var _last_day := -1
var _rng := RandomNumberGenerator.new()
var _sampled := 0
var last_roll := {}              # the last decision, for the console: {день, недель, шанс, авария, где, вид}


func setup(m: PaxMod, d: Data, g: PaxGame) -> void:
	mod = m
	db = d
	game = g
	_rng.randomize()


func _cfg() -> Dictionary:
	return db.balance.get("report", {})


func _t(key: String) -> String:
	return mod.tr_key("pax_corporations_" + key)


## The hook: d = {channel, system, user}; the rules go to the END of the system text (its start is cached).
func on_request(d: Dictionary, player: String) -> void:
	if str(d.get("channel", "")) != "report" or not bool(_cfg().get("enabled_flag", true)):
		return
	if _sampled < 2:
		_sampled += 1
		mod.save_data("report_prompt_sample", {"system_end": str(d.get("system", "")).right(6000), "user_start": str(d.get("user", "")).left(3000)})
	d["system"] = str(d.get("system", "")) + "\n\n" + rules(player)


func rules(player: String) -> String:
	var cfg := _cfg()
	var day := game.day()
	var weeks := 1.0 if _last_day < 0 else maxf(1.0, float(day - _last_day) / 7.0)
	_last_day = day
	var chance := minf(float(cfg.get("accident_max", 0.35)), 1.0 - pow(1.0 - float(cfg.get("accident_per_week", 0.02)), weeks))
	var accident := _rng.randf() < chance
	var place := ""
	var kind := ""
	if accident:
		var mine := Data.provinces_of(Data.province_owners(), player)
		if mine.is_empty():
			accident = false
		else:
			place = db.province_name(int(mine[_rng.randi_range(0, mine.size() - 1)]))
			var kinds: Array = cfg.get("kinds", ["пожар на заводе"])
			kind = str(kinds[_rng.randi_range(0, kinds.size() - 1)])
	last_roll = {"день": day, "weeks": snappedf(weeks, 0.1), "шанс": snappedf(chance, 0.001), "авария": accident, "где": place, "вид": kind}
	var lines: PackedStringArray = [
		"WORLD RULES (Pax Corporations — binding for this report):",
		"• Destruction is decided by the game, not by you. Never destroy, damage or lower the player's buildings, infrastructure, " +
			"development levels, resources or provinces by your own choice — no disasters, sabotage, riots or wars invented for colour.",
		"• Never let one event hit several regions at once.",
	]
	if accident:
		lines.append("• The game rolled exactly ONE accident for this stretch: «%s» in the province «%s» of %s. Its damage is small " % [kind, place, player] +
			"(one facility, or −1 level of one development scale of that province, at most). Tell it as an ACCIDENT (not an attack or a " +
			"disaster) in the events and in the newspaper, with its cause and the repair under way.")
	else:
		lines.append("• The game rolled NO accident for this stretch: report no accidents, disasters or destruction in %s." % player)
	lines.append("• Anything bad that happens must appear in the events or the newspaper — never a silent loss.")
	return "\n".join(lines)
