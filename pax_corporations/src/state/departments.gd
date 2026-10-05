extends RefCounted
## State departments (config/departments.json): health care, police, prosecutors, roads, utilities, education,
## the antimonopoly service (its mood towards the player — antitrust.gd).
##
## The player's country: the player sets each department's funding as a share of its norm (the norm is a share of
## the state's tax income, «доля_налогов» — 100 % of all of them ≈ a fifth of the taxes); the money leaves the
## treasury every week. Each department has a quality 0–100 that moves slowly (several months) towards the level
## its funding buys: Q* = 100 × (1 − e^(−1.2 × f' × (1 − ½ corruption))). Money above the norm works worse:
## f' = min(f, 1) + «отдача_сверх_нормы» × (1 − corruption) × (f − 1), and part of it is stolen — the country's
## corruption grows by «распил» × average overspend × (½ + corruption). Maxing every slider costs ~40 % of the taxes
## and feeds corruption.
## Quality above 50 helps, below 50 hurts — linearly, k = (Q − 50) / 50:
##   health care — staff satisfaction, fewer people quit;   police — less corruption, fewer violent acts of rivals;
##   prosecutors — less corruption (so more of the taxes are really paid);   roads — lower costs for every company;
##   utilities — lower costs for industry, a bit of satisfaction;   education — higher productivity.
## Other countries: the same effects, the funding share from their wealth and corruption:
##   f = clamp(base + spread × tanh(ln wealth) − corruption_weight × (corruption − 0.25)),
## and 80 % of the corporate taxes the mod pays them goes to their departments (their money is spent too).
## The effects reach the companies through corp_data.dept(country, key) (economy.gd, rivals.gd, corruption).

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const Goods := preload("res://mods/pax_corporations/src/companies/goods.gd")

var funding: Dictionary = {}       # player: department -> share of the norm (0..2)
var quality: Dictionary = {}       # player: department -> 0..100
var ai_quality: Dictionary = {}    # other country -> 0..100 (one level for all its departments)
var spent_weeks: Array = []        # player: what the departments cost, week by week (last 52)
var short := false                 # the treasury could not pay the last week in full
var _started := false


func cfg(db: Data) -> Dictionary:
	return db.departments


func keys(db: Data) -> Array:
	return (cfg(db).get("departments", {}) as Dictionary).keys()


## The player's GDP a year, млн $ (the game's economy; a budget-based guess if the game has none).
func gdp(game: PaxGame, goods: Goods, country: String) -> float:
	var farms: Variant = game.main.get("хозяйства")
	if farms is Dictionary:
		var w := float(((farms as Dictionary).get(game.home_body(), {}) as Dictionary).get("gdp_week", 0.0)) * 52.0
		if w > 0.0:
			return w
	var info := goods.country_info(country)
	return float(info.get("humans", 0.0)) * float(info.get("богатство", 1.0)) * 5000.0 * 4.0 / 1e6


## The state's tax income a year, млн $ — what the departments' norms are measured against (the game's taxes;
## a share of GDP when the game has none).
func budget(game: PaxGame, goods: Goods, country: String) -> float:
	var farms: Variant = game.main.get("хозяйства")
	if farms is Dictionary:
		var t := float(((farms as Dictionary).get(game.home_body(), {}) as Dictionary).get("taxes_week", 0.0)) * 52.0
		if t > 0.0:
			return t
	return gdp(game, goods, country) * 0.175   # taxes / GDP when the game reports no taxes


func norm(db: Data, key: String, budget_year: float) -> float:
	return budget_year * float(((cfg(db).get("departments", {}) as Dictionary).get(key, {}) as Dictionary).get("tax_share", 0.03)) \
		* db.cfx(db.player_country, "departments_price")   # the digital state of the AI tree


## Funding that really works: above the norm money buys less, and less still in a corrupt country.
func effective(db: Data, f: float, corruption: float) -> float:
	var extra := float(cfg(db).get("excess_return", 0.4))
	return minf(f, 1.0) + extra * (1.0 - clampf(corruption, 0.0, 1.0)) * maxf(0.0, f - 1.0)


## How much the country's corruption grows from overfunded departments (money that gets stolen).
func theft(db: Data, corruption: float) -> float:
	var over := 0.0
	var n := 0
	for key in keys(db):
		over += maxf(0.0, float(funding.get(key, 0.0)) - 1.0)
		n += 1
	return float(cfg(db).get("embezzlement", 0.08)) * (over / maxf(1.0, float(n))) * (0.5 + clampf(corruption, 0.0, 1.0))


## The level of departments a country keeps on its own (other countries, and the player's start).
func natural_funding(db: Data, wealth: float, corruption: float) -> float:
	var ai: Dictionary = cfg(db).get("other_countries", {})
	var f := float(ai.get("база", 0.6)) + float(ai.get("spread", 0.45)) * tanh(log(maxf(wealth, 0.01))) \
		- float(ai.get("corruption_weight", 0.8)) * (corruption - 0.25)
	return clampf(f, 0.05, 2.0)


func target_quality(f: float, corruption: float) -> float:
	return 100.0 * (1.0 - exp(-1.2 * f * (1.0 - 0.5 * clampf(corruption, 0.0, 1.0))))


# ---------- weekly ----------

## paid: what the mod paid each country's treasury this week ({country: {налоги, дивиденды}}).
func step(db: Data, game: PaxGame, goods: Goods, paid: Dictionary) -> void:
	var player := str(game.player_faction().get("name", ""))
	db.player_country = player
	var c := cfg(db)
	# A step may cover several weeks of a long time skip (db.dt).
	var speed := 1.0 - pow(1.0 - float(c.get("speed", 0.03)), db.dt)
	if not _started:
		start(db, goods, player)
	# The player: pay, then quality moves towards what the money buys.
	var g := budget(game, goods, player)
	var want := 0.0
	for key in keys(db):
		want += float(funding.get(key, 0.0)) * norm(db, str(key), g) * db.dt / 52.0
	var money := float(game.resources(game.home_body()).get("money", 0.0))
	var pay := minf(want, maxf(money, 0.0))
	short = pay < want - 0.01
	var paid_share := pay / want if want > 0.0 else 1.0
	if pay > 0.0:
		game.add_resource(game.home_body(), "money", -pay)
	spent_weeks.append(pay / float(db.dt))
	while spent_weeks.size() > 52:
		spent_weeks.pop_front()
	var k_now := db.country_corruption(player)
	for key in keys(db):
		var t := target_quality(effective(db, float(funding.get(key, 0.0)) * paid_share, k_now), k_now)
		var q := float(quality.get(key, t))
		quality[key] = q + speed * (t - q)
	var eff := effects(db, quality)
	eff["corruption"] = float(eff["corruption"]) + theft(db, db.country_corruption_base(player))
	db.dept_effects[player] = eff
	# Other countries: a level from their wealth and corruption; most of the mod's taxes go to it.
	var share := float((c.get("other_countries", {}) as Dictionary).get("spending_from_taxes", 0.8))
	for f in game.factions():
		var fd: Dictionary = f
		var name := str(fd.get("name", ""))
		if name == player or not db.countries.has(name):
			continue
		var info := goods.country_info(name)
		var corr := db.country_corruption_base(name)
		var t := target_quality(natural_funding(db, float(info.get("богатство", 1.0)), corr), corr)
		var q := float(ai_quality.get(name, t))
		ai_quality[name] = q + speed * (t - q)
		var levels := {}
		for key in keys(db):
			levels[key] = ai_quality[name]
		db.dept_effects[name] = effects(db, levels)
		var t_paid: Dictionary = paid.get(name, {})
		var spend := share * (float(t_paid.get("taxes", 0.0)) + float(t_paid.get("dividends", 0.0)))
		if spend > 0.0:
			fd["money"] = float(fd.get("money", 0.0)) - spend


## The player's departments at the start: funded at the level the country keeps on its own.
func start(db: Data, goods: Goods, player: String) -> void:
	_started = true
	var corruption := db.country_corruption_base(player)
	var info := goods.country_info(player)
	var f := natural_funding(db, float(info.get("богатство", 1.0)), corruption)
	# Departments added by a newer version of the mod start at the same level in an old save.
	for key in keys(db):
		if not funding.has(key):
			funding[key] = snappedf(f, 0.05)
			quality[key] = target_quality(f, corruption)


## What departments of these qualities do to a country's companies (keys read by corp_data.dept()).
func effects(db: Data, levels: Dictionary) -> Dictionary:
	var deps: Dictionary = cfg(db).get("departments", {})
	var out := {"corruption": 0.0, "satisfaction": 0.0, "exit": 1.0, "издержки": 1.0, "costs_industry": 1.0, "производительность": 1.0, "security_forces": 1.0,
		"antitrust": 1.0}
	for key in deps.keys():
		var k := (float(levels.get(key, 50.0)) - 50.0) / 50.0
		var eff: Dictionary = (deps[key] as Dictionary).get("effects", {})
		for what in eff.keys():
			var v := float(eff[what])
			out[what] = float(out[what]) + v * k if what in ["corruption", "satisfaction"] else float(out[what]) * (1.0 + v * k)
	return out


# ---------- for the window ----------

func spent_year() -> float:
	var s := 0.0
	for v in spent_weeks:
		s += float(v)
	return s * 52.0 / maxf(1.0, float(spent_weeks.size()))


func average_quality() -> float:
	if quality.is_empty():
		return 50.0
	var s := 0.0
	for v in quality.values():
		s += float(v)
	return s / float(quality.size())


# ---------- save ----------

func save_state() -> Dictionary:
	return {"funding": funding, "качество": quality, "others_list": ai_quality, "spending": spent_weeks}


func load_state(state: Dictionary) -> void:
	funding = (state.get("funding", {}) as Dictionary).duplicate() if state.get("funding") is Dictionary else {}
	quality = (state.get("качество", {}) as Dictionary).duplicate() if state.get("качество") is Dictionary else {}
	ai_quality = (state.get("others_list", {}) as Dictionary).duplicate() if state.get("others_list") is Dictionary else {}
	spent_weeks = (state.get("spending", []) as Array).duplicate() if state.get("spending") is Array else []
