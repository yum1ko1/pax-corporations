extends RefCounted
## Company pool: reads companies/*.json and config/*.json, keeps the derived numbers (price,
## capitalisation, statuses, rating index) and formats them. No drawing and no game rules here —
## the weekly market lives in market.gd.
##
## Derived fields are stored on the company dictionaries with a leading underscore:
##   _цена, _история (weekly prices), _хроника, _индекс, _место_мир, _место_страна,
##   _статусы {key: {"value": 0..100, "parts": [[label, delta], …]}}, _q, _рейтинг, _распад.
const GameApi := preload("res://mods/pax_corporations/src/shared/game_api.gd")

const Zones := preload("res://mods/pax_corporations/src/zones/zones.gd")
const ICON_FILES := {"oil": "icons/oil.svg", "gas": "icons/gas.svg", "bank": "icons/bank.svg",
	"metals": "icons/metals.svg", "it": "icons/it.svg", "energy": "icons/power.svg", "химия": "icons/chem.svg",
	"retail": "icons/retail.svg", "стройка": "icons/build.svg", "авиа": "icons/plane.svg", "diamonds": "icons/diamond.svg",
	"pharma": "icons/pharma.svg", "semiconductors": "icons/wafer.svg", "defence": "icons/defense.svg", "авто": "icons/car.svg", "медиа": "icons/media.svg",
	"ии": "icons/ai.svg", "наука": "icons/science.svg", "космос": "icons/space.svg"}
const FALLBACK_ICON := "icons/factory.svg"
const RATINGS := [[0.9, "AAA", 0.5], [0.8, "AA", 0.8], [0.7, "A", 1.2], [0.6, "BBB", 2.0], [0.5, "BB", 3.5],
	[0.4, "B", 5.5], [0.3, "CCC", 10.0], [0.2, "CC", 15.0], [0.1, "C", 20.0], [-1.0, "D", 0.0]]
const FRIENDLY := ["сама", "founder", "крупный"]
## Every fixed _t() key _statuses() uses — translated on the main thread before the parallel pass.
const STATUS_KEYS: PackedStringArray = ["part_base", "part_share_country", "part_share_world", "part_country_corruption",
	"part_state_bonus", "part_volatility", "part_debt", "part_trend", "part_satisfaction", "part_sector_pollution",
	"part_instability", "part_independence", "part_owner_conflict", "trust_law", "part_merger"]
const Parallel := preload("res://mods/pax_corporations/src/core/parallel.gd")

var mod: PaxMod
var sectors: Dictionary = {}
var profiles: Dictionary = {}
var point_types: Dictionary = {}
var balance: Dictionary = {}
var goods: Dictionary = {}       # config/goods.json — markets of goods (goods.gd)
var departments: Dictionary = {} # config/departments.json — state departments (departments.gd)
var dept_effects: Dictionary = {}   # country -> effects of its departments (departments.gd writes, the economy reads)
var companies: Array = []
var by_id: Dictionary = {}
var countries: Dictionary = {}   # country name -> {iso, средняя_зарплата}
var version := 0                 # grows with every recompute — drawing caches compare it
var wars: Array = []             # running corporate wars {a, b, недель, накал} (rivals.gd) — the map draws them
var labour_rules: Dictionary = {}  # sector -> effects of the labour laws in force in the player's country (politics.gd)
var labour_country := ""
var player_country := ""         # set every week by departments.gd
var antitrust_mood := 50.0       # 0..100: the player's antimonopoly service towards the player (antitrust.gd)
var rate_shift: Dictionary = {}   # country -> loan rate change from its prestige (arena.gd → debt.gd)
var prestige: Dictionary = {}     # country -> prestige 0..100 (arena.gd)
var tree_fx: Dictionary = {}     # "country|sector" -> effects of the industry's development tree (tree.gd)
var tree_country: Dictionary = {} # country -> country-wide effects of its technologies (tree.gd)
var cond_index: Dictionary = {}  # country -> its conditions' mean 0..1 (conditions.gd), for relocations
var tech_ratio: Dictionary = {}  # "country|sector" -> T/F of the country's best research company (techlevel.gd)
var tech_prestige: Dictionary = {} # country -> prestige points of its research leaders (techlevel.gd → arena.gd)
var cap_fx: Dictionary = {}      # company id -> debuffs of learning a bought technology (capabilities.gd), merged into tree()
var inv_fx: Dictionary = {}      # company id -> effects of its foreign investors (investments.gd), merged into tree()
var inv_vote := 0.0              # election points lost to selling strategic companies abroad (investments.gd → influence.gd)
var dt := 1                      # game weeks one step covers: 1, or more while a long time skip is worked off (main.gd)
var dept_fines := 0.0            # fines of the service this week, млн $ — main pays them into the treasury
var gone: Dictionary = {}        # id -> {день, причина, название} of companies that left the game (lifecycle.gd)
var _icons: Dictionary = {}
var _province_names: Dictionary = {}
var _province_points: Dictionary = {}   # province id -> {ш, д, имена}
var _hq: Dictionary = {}         # company id -> its headquarters point
var _tr: Dictionary = {}         # translation cache of _t(), cleared when the language changes
var _tr_lang := ""
var _corruption: Dictionary = {} # country -> corruption, read once per recompute
var _sector_rev: Dictionary = {} # sector -> world revenue; "sector|country" -> the country's
var _par_lang := ""              # set while worker threads run _statuses(): lang() and _t() only read
var last_timing: Dictionary = {} # microseconds of the parts of the last recompute() (for the analysis)


func load_all(m: PaxMod) -> void:
	mod = m
	var sec: Variant = GameApi.json(m, "config/sectors.json", {})
	if sec is Dictionary:
		sectors = (sec as Dictionary).get("sectors_list", {})
		profiles = (sec as Dictionary).get("profiles", {})
		point_types = (sec as Dictionary).get("sites", {})
	var bal: Variant = GameApi.json(m, "config/balance.json", {})
	balance = bal if bal is Dictionary else {}
	var gd: Variant = GameApi.json(m, "config/goods.json", {})
	goods = gd if gd is Dictionary else {}
	var dp: Variant = GameApi.json(m, "config/departments.json", {})
	departments = dp if dp is Dictionary else {}
	companies.clear()
	by_id.clear()
	countries.clear()
	var files: Variant = m.list_files("companies")
	for f in files:
		var name := str(f)
		if not name.ends_with(".json"):
			continue
		var raw: Variant = GameApi.json(m, "companies/" + name, {})
		if not (raw is Dictionary):
			m.log_warning("companies/%s: not a JSON object" % name)
			continue
		var file: Dictionary = raw
		var country := str(file.get("country", ""))
		countries[country] = {"iso": file.get("iso", ""), "average_wage": float(file.get("average_wage", 1000.0))}
		for item in file.get("companies", []):
			if not (item is Dictionary):
				continue
			var c: Dictionary = item
			var cid := str(c.get("id", ""))
			if cid.is_empty() or by_id.has(cid):
				m.log_warning("companies/%s: empty or duplicate id «%s»" % [name, cid])
				continue
			c["_country"] = country
			for p in c.get("sites", []):
				if p is Dictionary:
					migrate_point(p)   # the data is on the first cut of provinces
			_init_company(c)
			companies.append(c)
			by_id[cid] = c
	m.log_info("companies loaded: %d" % companies.size())


func _init_company(c: Dictionary) -> void:
	var market: Dictionary = c.get("рынок", {})
	var shares := maxf(float(market.get("shares_mln", 1.0)), 0.001)
	var cap := float(market.get("market_cap", 0.0))
	c["_price"] = cap / shares
	c["_history"] = [c["_price"]]
	c["_chronicle"] = []
	c["_statuses"] = {}


# ---------- lookups ----------

func company(cid: String) -> Dictionary:
	return by_id.get(cid, {})


## A company born during the game (a breakup, rivals.gd) — its derived fields are already set.
func add_company(c: Dictionary) -> void:
	var cid := str(c.get("id", ""))
	if cid.is_empty() or by_id.has(cid):
		return
	companies.append(c)
	by_id[cid] = c
	_hq.erase(cid)


## Who owns each province now (the political map «пров.владелец»): a PackedStringArray indexed by province id
## (a Dictionary in older builds). Read it once, then owner_in() for each province.
static func province_owners() -> Variant:
	var g: PaxGame = Pax.game
	if g == null:
		return null
	var map: Variant = g.main.get("полит_карта")
	var prov: Variant = (map as Object).get("пров") if map is Object else null
	return ((prov as Object).get("owner_of") if (prov as Object).get("owner_of") != null else (prov as Object).get("владелец")) if prov is Object else null


static func owner_in(owners: Variant, pid: int) -> String:
	if owners is Array:
		var a: Array = owners
		return str(a[pid]) if pid >= 0 and pid < a.size() else ""
	if owners is PackedStringArray:
		var arr: PackedStringArray = owners
		return arr[pid] if pid >= 0 and pid < arr.size() else ""
	if owners is Dictionary:
		return str((owners as Dictionary).get(pid, (owners as Dictionary).get(str(pid), "")))
	return ""


## Province ids owned by a country.
static func provinces_of(owners: Variant, country: String) -> Array:
	var out: Array = []
	if owners is PackedStringArray:
		var arr: PackedStringArray = owners
		for i in arr.size():
			if arr[i] == country:
				out.append(i)
	elif owners is Array:
		var a: Array = owners
		for i in a.size():
			if str(a[i]) == country:
				out.append(i)
	elif owners is Dictionary:
		for k in (owners as Dictionary).keys():
			if str((owners as Dictionary)[k]) == country:
				out.append(int(str(k)))
	return out


## A company leaves the game (liquidated or absorbed, lifecycle.gd).
func remove_company(cid: String, day: int, reason: String) -> void:
	var c: Dictionary = by_id.get(cid, {})
	if c.is_empty():
		return
	gone[cid] = {"день": day, "reason": reason, "название": c.get("название", cid), "country": str(c.get("_country", ""))}
	for i in companies.size():
		if str((companies[i] as Dictionary).get("id", "")) == cid:
			companies.remove_at(i)
			break
	by_id.erase(cid)
	_hq.erase(cid)
	version += 1


func lang() -> String:
	if not _par_lang.is_empty():
		return _par_lang
	var g: PaxGame = Pax.game
	var code := g.language() if g != null else "ru"
	return "ru" if code == "ru" else "en"


## A {"ru": …, "en": …} field (or a plain string) in the player's language.
func text(v: Variant) -> String:
	if v is Dictionary:
		var d: Dictionary = v
		return str(d.get(lang(), d.get("en", d.get("ru", ""))))
	return "" if v == null else str(v)


func name_of(c: Dictionary) -> String:
	return text(c.get("название", c.get("id", "")))


func sector_of(c: Dictionary) -> Dictionary:
	return sectors.get(str(c.get("sector", "")), {})


func sector_name(key: String) -> String:
	return text((sectors.get(key, {}) as Dictionary).get("name", key))


func point_type_name(key: String) -> String:
	return text((point_types.get(key, {}) as Dictionary).get("name", key))


func color_of(c: Dictionary) -> Color:
	var arr: Variant = (profiles.get(str(c.get("profile", "")), {}) as Dictionary).get("colour",
		sector_of(c).get("colour", [0.5, 0.5, 0.5]))
	if arr is Array and (arr as Array).size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return Color(0.5, 0.5, 0.5)


func sector_color(key: String) -> Color:
	var arr: Variant = (sectors.get(key, {}) as Dictionary).get("colour", [0.5, 0.5, 0.5])
	if arr is Array and (arr as Array).size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return Color(0.5, 0.5, 0.5)


func icon_key(c: Dictionary) -> String:
	# An industry with its own icon («значок_отрасли»: semiconductors sell «it» goods but have a wafer, not a chip).
	if bool(sector_of(c).get("sector_icon", false)):
		return str(sector_of(c).get("icon", ""))
	var prof: Dictionary = profiles.get(str(c.get("profile", "")), {})
	return str(prof.get("icon", sector_of(c).get("icon", "")))


func icon_of(c: Dictionary) -> Texture2D:
	var key := icon_key(c)
	if _icons.has(key):
		return _icons[key]
	var tex: Texture2D = GameApi.picture(mod, str(ICON_FILES.get(key, FALLBACK_ICON)))   # SVG: texture() gives none in 0.24
	_icons[key] = tex
	return tex


func hq_of(c: Dictionary) -> Dictionary:
	var cid := str(c.get("id", ""))
	if _hq.has(cid):
		return _hq[cid]
	var found: Dictionary = {}
	for p in c.get("sites", []):
		if p is Dictionary and str((p as Dictionary).get("type", "")) == "штаб":
			found = p
			break
	if found.is_empty():
		var pts: Array = c.get("sites", [])
		found = pts[0] if not pts.is_empty() and pts[0] is Dictionary else {}
	_hq[cid] = found
	return found


static func uv_of(p: Dictionary) -> Vector2:
	return Vector2((float(p.get("д", 0.0)) + 180.0) / 360.0, (90.0 - float(p.get("ш", 0.0))) / 180.0)


func province_name(pid: int) -> String:
	_load_provinces()
	return text(_province_names.get(pid, str(pid)))


## A province's centre {"ш", "д"} and its names {"ru", "en"} (data/regions2.json), {} if unknown.
func province_info(pid: int) -> Dictionary:
	_load_provinces()
	return _province_points.get(pid, {})


## The map numbers its provinces by data/regions2.json (the id is the index in Main.полит_карта.пров.владелец);
## the companies' data was made on the first cut (data/regions.json) — its numbers mean other provinces.
func _load_provinces() -> void:
	if not _province_names.is_empty():
		return
	for r in regions2():
		var rd: Dictionary = r
		_province_names[int(rd.get("id", 0))] = rd.get("names", rd.get("имена", {}))
		_province_points[int(rd.get("id", 0))] = {"ш": float(rd.get("ш", 0.0)), "д": float(rd.get("д", 0.0)), "имена": rd.get("names", rd.get("имена", {}))}


static var _regions2: Array = []
static var _old_to_new: Dictionary = {}   # first-cut id -> [second-cut id…]


static func regions2() -> Array:
	if _regions2.is_empty():
		var raw: Variant = Pax.json("res://data/regions2.json", {})
		if raw is Dictionary:
			_regions2 = ((raw as Dictionary).get("regions", (raw as Dictionary).get("регионы", [])) as Array).filter(func(x): return x is Dictionary)
	return _regions2


## A site's province from the first cut to the map's (data/regions2_из1.json: new -> [[old, share]…]); a cut-up
## old province goes to the new part nearest to the site. Marks the site «_пр2» — never translated twice.
static func migrate_point(p: Dictionary) -> void:
	if bool(p.get("_pr2", false)) or not p.has("province"):
		return
	if _old_to_new.is_empty():
		var raw: Variant = Pax.json("res://data/regions2_из1.json", {})
		var m: Variant = (raw as Dictionary).get("new_result_old", (raw as Dictionary).get("новая_из_старых", {})) if raw is Dictionary else {}
		if m is Dictionary:
			for k in (m as Dictionary).keys():
				for pair in (m as Dictionary)[k]:
					if pair is Array and (pair as Array).size() >= 2:
						var old := int(float(pair[0]))
						if not _old_to_new.has(old):
							_old_to_new[old] = []
						(_old_to_new[old] as Array).append(int(str(k)))
	var parts: Array = _old_to_new.get(int(p["province"]), [])
	if parts.is_empty():
		p["_pr2"] = true
		return
	var best := int(parts[0])
	if parts.size() > 1 and p.has("ш"):
		var centres := {}
		for r in regions2():
			centres[int((r as Dictionary).get("id", 0))] = Vector2(float((r as Dictionary).get("д", 0.0)), float((r as Dictionary).get("ш", 0.0)))
		var at := Vector2(float(p.get("д", 0.0)), float(p.get("ш", 0.0)))
		var dist := INF
		for n in parts:
			var cen: Vector2 = centres.get(int(n), Vector2(1e9, 1e9))
			if cen.distance_to(at) < dist:
				dist = cen.distance_to(at)
				best = int(n)
	# A site far from its province (the data put a site abroad on a home province: TSMC in Arizona) — the
	# province nearest to the site itself.
	if p.has("ш"):
		var at2 := Vector2(float(p.get("д", 0.0)), float(p.get("ш", 0.0)))
		var cen := Vector2.INF
		for r in regions2():
			if int((r as Dictionary).get("id", 0)) == best:
				cen = Vector2(float((r as Dictionary).get("д", 0.0)), float((r as Dictionary).get("ш", 0.0)))
				break
		if not cen.is_finite() or cen.distance_to(at2) > 6.0:
			var dmin := INF
			for r in regions2():
				var c2 := Vector2(float((r as Dictionary).get("д", 0.0)), float((r as Dictionary).get("ш", 0.0)))
				if c2.distance_to(at2) < dmin:
					dmin = c2.distance_to(at2)
					best = int((r as Dictionary).get("id", 0))
	p["province"] = best
	p["_pr2"] = true


## Every site of every company onto the map's provinces (new games: the data; old saves: once, main.gd).
func migrate_all() -> void:
	for c in companies:
		for p in (c as Dictionary).get("sites", []):
			if p is Dictionary:
				migrate_point(p)
	_hq.clear()


# ---------- numbers ----------

func price(c: Dictionary) -> float:
	return float(c.get("_price", 0.0))


func shares(c: Dictionary) -> float:
	return float((c.get("рынок", {}) as Dictionary).get("shares_mln", 0.0))


func cap(c: Dictionary) -> float:
	return price(c) * shares(c)


## A yearly money figure: the live one from economy.gd when it exists, else the starting data.
func fund(c: Dictionary, key: String) -> float:
	var live: Variant = c.get("_fin")
	if live is Dictionary and (live as Dictionary).has(key):
		return float((live as Dictionary)[key])
	return float((c.get("fundamental", {}) as Dictionary).get(key, 0.0))


func country_info(country: String) -> Dictionary:
	return countries.get(country, {})


func econ(c: Dictionary) -> Dictionary:
	return c.get("_ec", {}) if c.get("_ec") is Dictionary else {}


func staff(c: Dictionary) -> float:
	var e := econ(c)
	return float(e["N"]) if not e.is_empty() else float(c.get("staff", 0))


func wage(c: Dictionary) -> float:
	var e := econ(c)
	return float(e["W"]) if not e.is_empty() else float(c.get("wage", 0))


## A site's satisfaction 0..1: the company's, shifted by the kind of site (a field in the tundra is harder).
func point_satisfaction(c: Dictionary, index: int) -> float:
	var e := econ(c)
	var pts: Array = c.get("sites", [])
	if e.is_empty() or index < 0 or index >= pts.size():
		return 0.5
	var kind := str((pts[index] as Dictionary).get("type", ""))
	var shift := float((point_types.get(kind, {}) as Dictionary).get("satisfaction", 0.0)) / 100.0
	return clampf(float(e["H"]) + shift, 0.0, 1.0)


func point_striking(c: Dictionary, index: int) -> bool:
	for s in econ(c).get("strikes", []):
		if int((s as Dictionary).get("site", -1)) == index:
			return true
	return false


## People at one site now: its share of the starting staff applied to today's staff.
func point_staff(c: Dictionary, index: int) -> float:
	var e := econ(c)
	var pts: Array = c.get("sites", [])
	if index < 0 or index >= pts.size():
		return 0.0
	if e.is_empty():
		return float((pts[index] as Dictionary).get("staff", 0))
	var shares: Array = e.get("site_shares", [])
	return float(e["N"]) * (float(shares[index]) if index < shares.size() else 0.0)


func history(c: Dictionary) -> Array:
	return c.get("_history", [])


## Price change over the last `weeks` weeks (or since the start of the game), as a fraction.
func change(c: Dictionary, weeks: int) -> float:
	var h := history(c)
	if h.size() < 2:
		return 0.0
	var from := float(h[maxi(0, h.size() - 1 - weeks)])
	return float(h[h.size() - 1]) / from - 1.0 if from > 0.0 else 0.0


## Weekly volatility: the spread of weekly log returns, or the sector's default while history is short.
## Counted once a week in recompute(); between weeks the stored value is read.
func volatility(c: Dictionary) -> float:
	if c.has("_vol"):
		return float(c["_vol"])
	return _volatility_now(c)


func _volatility_now(c: Dictionary) -> float:
	var h := history(c)
	if h.size() < 9:
		return float(sector_of(c).get("volatility", 0.03))
	var rets: Array = []
	for i in range(maxi(1, h.size() - 26), h.size()):
		rets.append(log(float(h[i]) / float(h[i - 1])))
	var mean := 0.0
	for r in rets:
		mean += float(r)
	mean /= rets.size()
	var v := 0.0
	for r in rets:
		v += pow(float(r) - mean, 2.0)
	return sqrt(v / rets.size())


## What a country's state departments do to its companies (departments.gd): a delta for «коррупция» and
## «довольство», a multiplier for the rest («уход», «издержки», «издержки_пром», «производительность», «силовые»).
func dept(country: String, key: String, neutral: float) -> float:
	var e: Variant = dept_effects.get(country)
	return float((e as Dictionary).get(key, neutral)) if e is Dictionary else neutral


## What the labour laws in force do to a company of the player's country (politics.gd fills db.labour per
## sector): «довольство» a delta, «забастовки», «уход», «издержки» multipliers.
func labour(c: Dictionary, key: String, neutral: float) -> float:
	if labour_rules.is_empty() or str(c.get("_country", "")) != labour_country:
		return neutral
	var e: Variant = labour_rules.get(str(c.get("sector", "")))
	return float((e as Dictionary).get(key, neutral)) if e is Dictionary else neutral


## How strict a country's competition authority is (×1 — the usual): its quality (the «антимонополия»
## department, departments.gd) and, in the player's country, its mood towards the player — a hostile service
## looks for trouble, a friendly one turns a blind eye.
func antitrust(country: String) -> float:
	var k := dept(country, "antitrust", 1.0) * Zones.antitrust_k(country)
	if country == player_country and not player_country.is_empty():
		k *= lerpf(1.6, 0.4, clampf(antitrust_mood / 100.0, 0.0, 1.0))
	return k


## An effect of the company's development: its industry tree in its country (tree.gd) and its foreign investors
## (investments.gd). Percent keys as a share (0 — none, the parts add up), multipliers (1 — none, they multiply), points.
func tree(c: Dictionary, key: String, neutral: float) -> float:
	var e: Variant = tree_fx.get(str(c.get("_country", "")) + "|" + str(c.get("sector", "")))
	var v := float((e as Dictionary).get(key, neutral)) if e is Dictionary else neutral
	for src in [inv_fx, cap_fx]:
		var i: Variant = (src as Dictionary).get(str(c.get("id", "")))
		if i is Dictionary and (i as Dictionary).has(key):
			var x := float((i as Dictionary)[key])
			v = v * x if neutral == 1.0 else v + x
	return v


## A country-wide mechanic from its research trees (AI, science, space — tree.gd «страна»): a multiplier, 1 — none,
## 0 — switched off. Keys: see gen_science_trees.py (забастовки, штат, волатильность, событие_<…>, технологии_срок…).
func cfx(country: String, key: String) -> float:
	var e: Variant = tree_country.get(country)
	return float((e as Dictionary).get(key, 1.0)) if e is Dictionary else 1.0


## The same for a company's country.
func cfx_c(c: Dictionary, key: String) -> float:
	return cfx(str(c.get("_country", "")), key)


## Corruption with the departments' effect (police and prosecutors).
func country_corruption(country: String) -> float:
	return clampf(country_corruption_base(country) + dept(country, "corruption", 0.0), 0.0, 1.0)


## The country's own corruption (from the game; the player's country is not among the factions — config).
func country_corruption_base(country: String) -> float:
	if _corruption.is_empty():
		var g: PaxGame = Pax.game
		if g == null:
			return 0.3
		for f in g.factions():
			if f is Dictionary:
				_corruption[str((f as Dictionary).get("name", ""))] = float((f as Dictionary).get("corruption", 0.3))
		_corruption[" filled"] = 0.0   # marks the cache as filled even when there are no factions
	return float(_corruption.get(country, float(departments.get("corruption_default", 0.3))))


## What the state really gets dividends on: its own stake plus a front man's (orders.gd, a covert nationalisation).
func state_take(c: Dictionary) -> float:
	var s := state_share(c)
	for o in c.get("owners", []):
		if o is Dictionary and bool((o as Dictionary).get("proxy", false)):
			s += float((o as Dictionary).get("доля", 0.0))
	return s


func state_share(c: Dictionary) -> float:
	var s := 0.0
	for o in c.get("owners", []):
		if o is Dictionary and str((o as Dictionary).get("type", "")) == "polity" \
				and str((o as Dictionary).get("country", "")) == str(c.get("_country", "")):
			s += float((o as Dictionary).get("доля", 0.0))
	return s


# ---------- statuses (stage 1: provisional formulas, every number keeps its parts) ----------

## Statuses of all companies. _statuses() of different companies are independent, so they run on worker
## threads (parallel.gd). Everything they share is filled here first, on the main thread: the corruption
## cache (it asks the game), the translations of _t() and the language — workers never call the game.
func recompute() -> void:
	var t0 := Time.get_ticks_usec()
	_corruption.clear()
	_sector_rev.clear()
	var keys := {}
	var list := companies
	var vol := func(from: int, to: int) -> void:
		for i in range(from, to):
			var co: Dictionary = list[i]
			co["_vol"] = _volatility_now(co)
	Parallel.for_each(list.size(), vol)
	for c in companies:
		var sector := str(c.get("sector", ""))
		var rev := fund(c, "выручка")
		var key := sector + "|" + str(c.get("_country", ""))
		_sector_rev[sector] = float(_sector_rev.get(sector, 0.0)) + rev
		_sector_rev[key] = float(_sector_rev.get(key, 0.0)) + rev
		_status_keys(c, keys)
	country_corruption("")
	for k: String in STATUS_KEYS:
		_t(k)
	for k: String in keys.keys():
		_t(k)
	_par_lang = lang()
	var t1 := Time.get_ticks_usec()
	var chunk := func(from: int, to: int) -> void:
		for i in range(from, to):
			_statuses(list[i])
	Parallel.for_each(list.size(), chunk)
	_par_lang = ""
	var t2 := Time.get_ticks_usec()
	_index()
	version += 1
	last_timing = {"prepare": t1 - t0, "statuses": t2 - t1, "index": Time.get_ticks_usec() - t2}


## Translation keys of the parts that depend on the company's own data (trust, satisfaction, popularity).
func _status_keys(c: Dictionary, keys: Dictionary) -> void:
	var e := econ(c)
	if e.is_empty():
		return
	for p in e.get("trust_parts", []):
		var k := str(p[0])
		keys["trust_law" if k.begins_with("law:") else "trust_" + k] = true
	for p in e.get("satisfaction_parts", []):
		keys["sat_" + str(p[0])] = true
	for p in e.get("popularity_parts", []):
		keys["pop_" + str(p[0])] = true


func _statuses(c: Dictionary) -> void:
	var st: Dictionary = {}
	var country := str(c.get("_country", ""))
	var rev := maxf(fund(c, "выручка"), 1.0)
	var lev := fund(c, "debt") / rev
	var margin := fund(c, "profit") / rev

	# Independence (section 8): own and friendly holders minus the state, other companies, foreigners.
	var friendly := 0.0
	var hostile := 0.0
	var parts_n: Array = []
	for o in c.get("owners", []):
		if not (o is Dictionary):
			continue
		var od: Dictionary = o
		var kind := str(od.get("type", ""))
		var share := float(od.get("доля", 0.0))
		var foreign := od.has("country") and str(od["country"]) != country
		if kind in FRIENDLY and not foreign:
			friendly += share
			parts_n.append([text(od.get("кто", "")), 50.0 * share])
		elif kind == "polity" or kind == "company" or foreign:
			hostile += share
			parts_n.append([text(od.get("кто", "")), -50.0 * share])
	var n := clampf(0.5 + 0.5 * (friendly - hostile) + tree(c, "независимость", 0.0) / 100.0, 0.0, 1.0)
	parts_n.push_front([_t("part_base"), 50.0])
	st["независимость"] = {"value": n * 100.0, "parts": parts_n}

	# Monopolism: share of the sector by revenue, in the country and in the world (within the mod's pool).
	var sector := str(c.get("sector", ""))
	var in_country := float(_sector_rev.get(sector + "|" + country, 0.0))
	var in_world := float(_sector_rev.get(sector, 0.0))
	var share_c := fund(c, "выручка") / maxf(in_country, 1.0)
	var share_w := fund(c, "выручка") / maxf(in_world, 1.0)
	st["monopolism"] = {"value": share_c * 100.0, "parts": [[_t("part_share_country"), share_c * 100.0],
		[_t("part_share_world"), share_w * 100.0]]}

	# Corruption (section 10): the country's corruption, higher at state companies.
	var base_k := country_corruption(country)
	var kind_c := str(c.get("type", ""))
	var mult := 1.3 if kind_c == "государственная" else (1.15 if kind_c == "смешанная" else 1.0)
	var k := clampf(base_k * mult + tree(c, "corruption", 0.0) / 100.0, 0.0, 1.0)
	st["corruption"] = {"value": k * 100.0, "parts": [[_t("part_country_corruption"), base_k * 100.0],
		[_t("part_state_bonus"), (k - base_k) * 100.0]]}

	# Stability (section 8): volatility, debt load, half-year price trend, staff satisfaction.
	var vol := volatility(c)
	var trend := clampf(2.0 * change(c, 26), -0.2, 0.2)
	var e := econ(c)
	var happy := clampf(float(e.get("H", 0.5)), 0.0, 1.0) if not e.is_empty() else 0.5
	var mood := 0.2 * (happy - 0.5)
	var s := clampf(0.85 - 4.0 * vol - 0.08 * minf(lev, 4.0) + trend + mood + tree(c, "stability", 0.0) / 100.0, 0.0, 1.0)
	st["stability"] = {"value": s * 100.0, "parts": [[_t("part_base"), 85.0], [_t("part_volatility"), -400.0 * vol],
		[_t("part_debt"), -8.0 * minf(lev, 4.0)], [_t("part_trend"), trend * 100.0], [_t("part_satisfaction"), mood * 100.0]]}

	# Trust in the state (sections 8, 13) — computed by politics.gd for the player's country's companies.
	if not e.is_empty() and e.has("trust"):
		var trust_parts: Array = []
		for p in e.get("trust_parts", []):
			var key := str(p[0])
			var label := _t("trust_law") % key.substr(4) if key.begins_with("law:") else _t("trust_" + key)
			trust_parts.append([label, float(p[1])])
		st["trust"] = {"value": float(e["trust"]), "parts": trust_parts}

	# Staff satisfaction (section 5) — computed by economy.gd, shown here with its parts.
	if not e.is_empty():
		var sat_parts: Array = []
		for p in e.get("satisfaction_parts", []):
			sat_parts.append([_t("sat_" + str(p[0])), float(p[1]) * 100.0])
		st["satisfaction"] = {"value": happy * 100.0, "parts": sat_parts}

	# Popularity of the goods (goods.gd) — how much people like what the company sells.
	if not e.is_empty() and e.has("popularity"):
		var pop_parts: Array = []
		for p in e.get("popularity_parts", []):
			pop_parts.append([_t("pop_" + str(p[0])), float(p[1])])
		st["popularity"] = {"value": float(e["popularity"]), "parts": pop_parts}

	# Ecology: the sector's pollution (a light model, section 10).
	var dirt := float(sector_of(c).get("pollution", 0.3))
	st["экология"] = {"value": (1.0 - dirt) * 100.0, "parts": [[_t("part_sector_pollution"), -dirt * 100.0]]}
	c["_statuses"] = st

	# Credit rating (20.14).
	var q := 0.35 * (1.0 - clampf(lev / 4.0, 0.0, 1.0)) + 0.25 * clampf(5.0 * margin + 0.5, 0.0, 1.0) \
		+ 0.2 * s + 0.1 * n + 0.1 * (1.0 - k)
	c["_q"] = q
	c["_rating"] = rating_of(q)

	# Breakup chance (8, 20.11), % a year.
	var cfg: Dictionary = balance.get("breakup", {})
	var a := float(cfg.get("a", 0.1))
	var b := float(cfg.get("b", 0.05))
	var parts_p: Array = [[_t("part_base"), float(cfg.get("база", 1.0))], [_t("part_instability"), a * (100.0 - s * 100.0)],
		[_t("part_independence"), -b * n * 100.0]]
	var holders: Array = []
	for o in c.get("owners", []):
		if o is Dictionary and str((o as Dictionary).get("type", "")) != "частные":
			holders.append(float((o as Dictionary).get("доля", 0.0)))
	holders.sort()
	holders.reverse()
	if not holders.is_empty() and float(holders[0]) <= 0.5 and holders.size() >= 2 \
			and float(holders[0]) - float(holders[1]) < 0.1:
		parts_p.append([_t("part_owner_conflict"), float(cfg.get("conflict", 4.0))])
	var stress := float(c.get("_integration", 0.0))   # a recent merger of equals (lifecycle.gd, 20.11)
	if stress > 0.0:
		parts_p.append([_t("part_merger"), stress])
	var p := 0.0
	for part in parts_p:
		p += float(part[1])
	c["_breakup"] = {"value": clampf(p, 0.0, float(cfg.get("ceiling", 60.0))), "parts": parts_p}


## The rate spread over the country's base for a credit quality q (20.14), as a fraction a year.
func spread_of(q: float) -> float:
	for r in RATINGS:
		if q >= float(r[0]):
			return float(r[2]) / 100.0 if str(r[1]) != "D" else 0.3
	return 0.3


func rating_of(q: float) -> String:
	for r in RATINGS:
		if q >= float(r[0]):
			return str(r[1])
	return "D"


## Rating index (section 7): every metric on a log scale 0–100 against the pool's maximum.
## What the company's world index is made of, in words (the tooltip of «Индекс»).
func index_tip(c: Dictionary) -> String:
	var w: Dictionary = balance.get("index", {})
	var p: Array = c.get("_index_parts", [])
	var lines: PackedStringArray = [_t("idx_tip_head") % [_num(float(c.get("_index", 0.0)), 1), int(c.get("_world_place", 0)), int(c.get("_country_place", 0))]]
	if p.size() >= 6:
		var names := ["idx_cap", "idx_rev", "idx_profit", "idx_growth", "idx_rating", "idx_vol"]
		var keys := ["market_cap", "выручка", "profit", "рост", "rating", "volatility"]
		for i in 6:
			var wt := float(w.get(keys[i], 0.0))
			var pts := wt * float(p[i]) * (-1.0 if i == 5 else 1.0)
			lines.append(_t("idx_tip_row") % [_t(names[i]), roundi(float(p[i])), roundi(wt * 100.0), ("+" if pts >= 0.0 else "−") + _num(absf(pts), 1)])
	lines.append("")
	lines.append(_t("idx_tip_how"))
	return "\n".join(lines)


func _index() -> void:
	var w: Dictionary = balance.get("index", {})
	var mx := {"cap": 1.0, "rev": 1.0, "profit": 1.0}
	for c in companies:
		mx["cap"] = maxf(float(mx["cap"]), cap(c))
		mx["rev"] = maxf(float(mx["rev"]), fund(c, "выручка"))
		mx["profit"] = maxf(float(mx["profit"]), fund(c, "profit"))
	var list := companies
	# Each company's index on worker threads; each writes only its own dictionary.
	var chunk := func(from: int, to: int) -> void:
		for i in range(from, to):
			var c: Dictionary = list[i]
			var k := _logn(cap(c), float(mx["cap"]))
			var r := _logn(fund(c, "выручка"), float(mx["rev"]))
			var pr := _logn(maxf(fund(c, "profit"), 0.0), float(mx["profit"]))
			var g := clampf(50.0 + 100.0 * change(c, 52), 0.0, 100.0)
			var q := float(c.get("_q", 0.5)) * 100.0
			var v := clampf(volatility(c) / 0.08, 0.0, 1.0) * 100.0
			var idx := float(w.get("market_cap", 0.4)) * k + float(w.get("выручка", 0.2)) * r \
				+ float(w.get("profit", 0.15)) * pr + float(w.get("рост", 0.1)) * g \
				+ float(w.get("rating", 0.1)) * q - float(w.get("volatility", 0.05)) * v
			c["_index"] = idx
			c["_index_parts"] = [k, r, pr, g, q, v]   # each 0–100, for the index's tooltip
	Parallel.for_each(list.size(), chunk)
	# The engine's own sort of Vector2 (by x, then y) instead of a GDScript comparator: the best index first.
	var keys: Array = []
	for i in list.size():
		keys.append(Vector2(-float((list[i] as Dictionary)["_index"]), i))
	keys.sort()
	var per_country: Dictionary = {}
	for n in keys.size():
		var c: Dictionary = list[int((keys[n] as Vector2).y)]
		c["_world_place"] = n + 1
		var country := str(c.get("_country", ""))
		per_country[country] = int(per_country.get(country, 0)) + 1
		c["_country_place"] = per_country[country]


static func _logn(x: float, mx: float) -> float:
	return 100.0 * log(1.0 + maxf(x, 0.0)) / log(1.0 + maxf(mx, 1.0))


# ---------- formatting ----------

## Millions of dollars → "$37 млрд" / "$850 млн" / "$1.2 трлн".
func money(mln: float) -> String:
	var ru := lang() == "ru"
	var a := absf(mln)
	var neg := "−" if mln < 0.0 else ""
	if a >= 1e6:
		return "%s$%s %s" % [neg, _num(a / 1e6, 2), "трлн" if ru else "T"]
	if a >= 1e3:
		return "%s$%s %s" % [neg, _num(a / 1e3, 1 if a < 1e4 else 0), "млрд" if ru else "B"]
	return "%s$%s %s" % [neg, _num(a, 0), "млн" if ru else "M"]


func money_price(usd: float) -> String:
	# Penny shares (Indonesian, Nigerian…) need more digits, or they all read $0.00.
	var digits := 0 if usd >= 100.0 else (2 if usd >= 1.0 else (3 if usd >= 0.1 else 4))
	return "$" + _num(usd, digits)


func people(n: float) -> String:
	var s := str(int(round(n)))
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = (" " if lang() == "ru" else ",") + out
	return out


func percent(x: float, signed := false) -> String:
	var s := _num(x * 100.0, 1 if absf(x) < 0.1 else 0) + "%"
	if signed and x > 0.0:
		s = "+" + s
	elif x < 0.0:
		s = "−" + s.trim_prefix("-")
	return s


func _num(x: float, digits: int) -> String:
	var s := ("%." + str(digits) + "f") % x
	return s.replace(".", ",") if lang() == "ru" else s


func _t(key: String) -> String:
	if not _par_lang.is_empty():
		# On a worker thread: read-only (recompute() filled the cache); an unexpected key shows as is.
		return str(_tr.get(key, key))
	var code := lang()
	if code != _tr_lang:
		_tr.clear()
		_tr_lang = code
	if not _tr.has(key):
		_tr[key] = mod.tr_key("pax_corporations_" + key)
	return str(_tr[key])
