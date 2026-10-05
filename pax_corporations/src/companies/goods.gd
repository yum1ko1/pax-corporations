extends RefCounted
## Markets of goods: demand comes from people (config/goods.json).
##
## Every company sells one kind of goods — its profile (oil, cars, medicines…). A country's market for it is
## population × consumption per person × wealth; the world market is the same summed over all states of the
## game. Population («люди») and wealth (budget per person, «бюджет») are read live from the game's factions,
## so a war that kills millions or a country that grows richer changes what companies can sell.
##
## Part of a company's sales goes abroad («экспорт» of the goods) and competes on the world market, the rest
## on its home market. Inside a market the companies of the mod and the «others» (producers outside the list)
## split it by popularity: weight = e^(strength × (P − P_start) / 50). Popularity (0–100, how much people like
## the company's goods) follows the quality of work (staff satisfaction), strikes, layoffs and reputation
## (the trace of random events). So the company's demand = its markets' growth × its share's change,
## e["market_demand"], which economy.gd multiplies into demand (need of people, revenue).
##
## Start: each company's share is its starting sales against the market (a market is never smaller than what
## the listed companies sell there plus the others' minimum), so at the start nothing jumps.

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")

var start_people: Dictionary = {}   # country -> population × wealth at the start
var start_world := 0.0
var markets: Dictionary = {}        # "дом|goods|country" / "мир|goods" -> {"объём": млн $ at start, "others_rest": others' share}
var now_people: Dictionary = {}     # this week's population × wealth by country
var now_world := 0.0
var _info: Dictionary = {}          # country -> {"humans", "богатство"} this week (for the dossier)
var _player_wealth := -1.0          # the player's wealth from GDP, smoothed week to week
var _others_weight := 1.0           # the «others» producers' weight: the world's average company weight
var members: Dictionary = {}        # pool -> [company ids] this week (rivals.gd, the «Markets» tab)
var pool_volume: Dictionary = {}    # pool -> what the game's companies sell there, млн $ a year (for the player)


# ---------- start ----------

func setup(db: Data, game: PaxGame, state: Dictionary) -> void:
	_player_wealth = float(state.get("player_wealth", -1.0))
	_read_countries(db, game)
	if state.get("страны") is Dictionary and not (state["страны"] as Dictionary).is_empty():
		start_people = (state["страны"] as Dictionary).duplicate()
		start_world = float(state.get("мир", now_world))
		markets = (state.get("markets", {}) as Dictionary).duplicate(true) if state.get("markets") is Dictionary else {}
	else:
		start_people = now_people.duplicate()
		start_world = now_world
	for country in now_people.keys():
		if not start_people.has(country):
			start_people[country] = now_people[country]
	_baseline(db)
	step(db, game)


## A company born during the game (founded by the player) gets its starting shares of its markets.
func baseline(db: Data) -> void:
	_baseline(db)


## Starting shares of the companies that have none yet (a new game, or companies added to an old save).
func _baseline(db: Data) -> void:
	var cfg: Dictionary = db.goods
	var min_others := float(cfg.get("others_share_min", 0.15))
	var sales := {}     # pool -> the listed companies' starting sales there
	var fresh: Array = []
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty():
			continue
		var x := export_share(db, c)
		var r0 := float(e["R0"])
		var home := _home_pool(c)
		var world := _world_pool(c)
		sales[home] = float(sales.get(home, 0.0)) + (1.0 - x) * r0
		sales[world] = float(sales.get(world, 0.0)) + x * r0
		if not e.has("home_share0"):
			fresh.append(c)
	if fresh.is_empty():
		return
	for pool in sales.keys():
		if markets.has(pool):
			continue
		var parts := str(pool).split("|")
		var per_person := float(_goods(db, parts[1]).get("consumption", 300.0))
		var people := start_world if parts[0] == "мир" else float(start_people.get(parts[2], 0.0))
		var size := maxf(people * per_person / 1e6, float(sales[pool]) / (1.0 - min_others))
		markets[pool] = {"объём": size, "others_rest": maxf(min_others, 1.0 - float(sales[pool]) / size)}
	for c in fresh:
		var e := db.econ(c)
		var x := export_share(db, c)
		var r0 := float(e["R0"])
		e["home_share0"] = (1.0 - x) * r0 / maxf(float((markets[_home_pool(c)] as Dictionary)["объём"]), 1e-6)
		e["world_share0"] = x * r0 / maxf(float((markets[_world_pool(c)] as Dictionary)["объём"]), 1e-6)
		var target := _popularity_target(db, c, e)
		e["popularity"] = float(target["value"])
		e["popularity0"] = float(target["value"])
		e["popularity_parts"] = target["parts"]


# ---------- weekly ----------

func step(db: Data, game: PaxGame) -> void:
	_read_countries(db, game)
	var pcfg: Dictionary = db.goods.get("popularity", {})
	var strength := float(pcfg.get("сила", 0.6))
	var smooth := float(pcfg.get("smoothing", 0.02))
	var fade := float(pcfg.get("reputation_decay", 0.02))
	# Popularity, then the weight of every company in its two markets.
	var sums := {}      # pool -> Σ s·f now
	var sums0 := {}     # pool -> Σ s (all at f = 1: the start)
	var mean_w := 0.0   # the world's average weight (by starting revenue): the «others» get better as fast
	var mean_n := 0.0   # as the average company, so only popularity above the norm wins share from them
	var price_war_weight := float((db.balance.get("competition", {}) as Dictionary).get("dumping_weight", 1.15))
	members.clear()
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty() or not e.has("home_share0"):
			continue
		e["репутация"] = float(e.get("репутация", 0.0)) * (1.0 - fade)
		var target := _popularity_target(db, c, e)
		var p := float(e.get("popularity", target["value"]))
		p += smooth * (float(target["value"]) - p)
		e["popularity"] = p
		e["popularity_parts"] = target["parts"]
		var f := exp(strength * (p - float(e.get("popularity0", 50.0))) / 50.0)
		mean_w += f * float(e["R0"])
		mean_n += float(e["R0"])
		if int(e.get("dumping_weeks", 0)) > 0:
			f *= price_war_weight   # a price war: cheaper goods sell more (rivals.gd), the average is not moved by it
		e["_weight"] = f
		for pair in [[_home_pool(c), float(e["home_share0"])], [_world_pool(c), float(e["world_share0"])]]:
			if not members.has(pair[0]):
				members[pair[0]] = []
			(members[pair[0]] as Array).append(str(c["id"]))
			sums[pair[0]] = float(sums.get(pair[0], 0.0)) + float(pair[1]) * f
			sums0[pair[0]] = float(sums0.get(pair[0], 0.0)) + float(pair[1])
	_others_weight = mean_w / mean_n if mean_n > 0.0 else 1.0
	var world_growth := now_world / maxf(start_world, 1e-6) if start_world > 0.0 else 1.0
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty() or not e.has("home_share0"):
			continue
		var country := str(c.get("_country", ""))
		var home_growth := float(now_people.get(country, 0.0)) / float(start_people.get(country, 1.0)) \
			if float(start_people.get(country, 0.0)) > 0.0 and now_people.has(country) else 1.0
		var hp := _home_pool(c)
		var wp := _world_pool(c)
		var f := float(e["_weight"])
		var h_ratio := f * _denominator(hp, sums0, 1.0) / maxf(_denominator(hp, sums, _others_weight), 1e-9)
		var w_ratio := f * _denominator(wp, sums0, 1.0) / maxf(_denominator(wp, sums, _others_weight), 1e-9)
		var x := export_share(db, c)
		e["market_demand"] = (1.0 - x) * home_growth * h_ratio + x * world_growth * w_ratio
		# For the dossier: the markets now (nominal) and the company's shares of them.
		var prices := float(e.get("цены", 1.0))
		e["market_home"] = float((markets.get(hp, {}) as Dictionary).get("объём", 0.0)) * home_growth * prices
		e["market_world"] = float((markets.get(wp, {}) as Dictionary).get("объём", 0.0)) * world_growth * prices
		e["home_share"] = float(e["home_share0"]) * h_ratio
		e["world_share"] = float(e["world_share0"]) * w_ratio
	_shares_among_listed(db)


## For the player: a market is what the companies of the game sell there, and a company's share is its part
## of that (the «others» of the demand model stay inside the economy only).
func _shares_among_listed(db: Data) -> void:
	pool_volume.clear()
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty():
			continue
		var x := export_share(db, c)
		var r := float(e.get("R", e.get("R0", 0.0)))
		pool_volume[home_pool(c)] = float(pool_volume.get(home_pool(c), 0.0)) + (1.0 - x) * r
		pool_volume[world_pool(c)] = float(pool_volume.get(world_pool(c), 0.0)) + x * r
	for item in db.companies:
		var c: Dictionary = item
		var e := db.econ(c)
		if e.is_empty():
			continue
		var x := export_share(db, c)
		var r := float(e.get("R", e.get("R0", 0.0)))
		e["home_share_mod"] = (1.0 - x) * r / maxf(float(pool_volume.get(home_pool(c), 0.0)), 1e-6)
		e["world_share_mod"] = x * r / maxf(float(pool_volume.get(world_pool(c), 0.0)), 1e-6)


func _denominator(pool: String, sums: Dictionary, others: float) -> float:
	return float(sums.get(pool, 0.0)) + others * float((markets.get(pool, {}) as Dictionary).get("others_rest", 0.15))


## Target popularity with its parts (for the tooltip).
func _popularity_target(db: Data, c: Dictionary, e: Dictionary) -> Dictionary:
	var pcfg: Dictionary = db.goods.get("popularity", {})
	var h := float(e.get("H", 0.5))
	var laid := float(e.get("fired26", 0.0)) / maxf(float(e.get("N", 1.0)), 1.0)
	var striking := not (e.get("strikes", []) as Array).is_empty()
	var parts: Array = [
		["base", 50.0],
		["quality", float(pcfg.get("качество", 40.0)) * (h - 0.5)],
		["layoffs", -float(pcfg.get("layoffs", 150.0)) * laid],
		["reputation", float(e.get("репутация", 0.0))],
		["tree", db.tree(c, "popularity", 0.0)],
	]
	if striking:
		parts.append(["strike", -float(pcfg.get("strike", 10.0))])
	var v := 0.0
	for p in parts:
		v += float(p[1])
	return {"value": clampf(v, 0.0, 100.0), "parts": parts}


## A random event that hits the company's name (events.gd, kinds «репутация» and «точка»).
static func reputation_event(db: Data, e: Dictionary, dir: float, size: float) -> void:
	var k := float((db.goods.get("popularity", {}) as Dictionary).get("reputation_from_event", 60.0))
	e["репутация"] = clampf(float(e.get("репутация", 0.0)) + dir * size * k, -40.0, 40.0)


# ---------- lookups ----------

func _read_countries(db: Data, game: PaxGame) -> void:
	now_people.clear()
	_info.clear()
	now_world = 0.0
	var base := float(db.goods.get("wealth_base", 5000.0))
	for f in game.factions():
		var fd: Dictionary = f
		if not bool(fd.get("polity", false)) or bool(fd.get("perished", false)):
			continue
		var people := float(fd.get("humans", 0.0))
		if people <= 0.0:
			continue
		var wealth := maxf(0.05, float(fd.get("budget", 0.0)) * 1e6 / people / base)
		_add_country(str(fd.get("name", "")), people, wealth)
	# The player's country is not among the factions: its wealth comes from the game's economy (weekly GDP,
	# smoothed — the player's policy moves the home market), its population from the faction or the config.
	var pf: Dictionary = game.player_faction()
	var player := str(pf.get("name", ""))
	if not player.is_empty() and not now_people.has(player):
		var people := float(pf.get("humans", 0.0))
		if people <= 0.0:
			people = float((db.goods.get("население", {}) as Dictionary).get(player, 0.0))
		var wealth := float(pf.get("budget", 0.0)) * 1e6 / people / base if people > 0.0 else 0.0
		var farms: Variant = game.main.get("хозяйства")
		if farms is Dictionary and people > 0.0:
			var gdp := float(((farms as Dictionary).get(game.home_body(), {}) as Dictionary).get("gdp_week", 0.0)) * 52.0
			if gdp > 0.0:
				var now := gdp * 1e6 / people * float(db.goods.get("budget_from_gdp", 0.25)) / base
				_player_wealth = now if _player_wealth <= 0.0 else _player_wealth + 0.1 * (now - _player_wealth)
				wealth = _player_wealth
		if people > 0.0:
			_add_country(player, people, maxf(0.05, wealth))


func _add_country(name: String, people: float, wealth: float) -> void:
	now_people[name] = people * wealth
	_info[name] = {"humans": people, "богатство": wealth}
	now_world += people * wealth


func country_info(country: String) -> Dictionary:
	return _info.get(country, {})


func goods_of(c: Dictionary) -> String:
	return str(c.get("profile", ""))


func goods_name(db: Data, c: Dictionary) -> String:
	return db.text(_goods(db, goods_of(c)).get("name", goods_of(c)))


func export_share(db: Data, c: Dictionary) -> float:
	if c.has("export"):
		return clampf(float(c["export"]), 0.0, 1.0)
	return clampf(float(_goods(db, goods_of(c)).get("export", 0.3)), 0.0, 1.0)


func _goods(db: Data, key: String) -> Dictionary:
	return (db.goods.get("goods", {}) as Dictionary).get(key, {})


func home_pool(c: Dictionary) -> String:
	return "дом|%s|%s" % [goods_of(c), str(c.get("_country", ""))]


func world_pool(c: Dictionary) -> String:
	return "мир|" + goods_of(c)


func _home_pool(c: Dictionary) -> String:
	return home_pool(c)


func _world_pool(c: Dictionary) -> String:
	return world_pool(c)


## Shares of one market for a pie: [[company id, share], …] biggest first — among the game's companies only.
func pool_shares(db: Data, pool: String) -> Array:
	var out: Array = []
	var world := pool.begins_with("мир|")
	for cid in members.get(pool, []):
		var e := db.econ(db.company(str(cid)))
		out.append([str(cid), float(e.get("world_share_mod" if world else "home_share_mod", 0.0))])
	out.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return out


# ---------- save ----------

func save_state() -> Dictionary:
	return {"страны": start_people, "мир": start_world, "markets": markets, "player_wealth": _player_wealth}
