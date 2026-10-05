extends RefCounted
## The technology level T of the research companies (ideas doc, section 14; config balance.json «техуровень»):
## AI, science and space each have their own world frontier F — the biggest T of the type. The start comes from public
## comparisons («старт»: the leader = 100; a company not listed — by its revenue). Every week:
##   T ← T·(1 + 0.003·Q·dt) + 0.01·(F − T)·D·dt
## Q — own research strength 0..1, the sum of factors with the type's weights: research (the share of staff at
## research centres / data centres / spaceports, against the world best), compute (the nodes of the type's tree
## branch + own chips or an ally's), people (the country's education, conditions.gd), money (revenue, log, against the
## leader), the country's science (its НО a week against the best). D — catching-up diffusion: 1, 0.3 under
## sanctions. A scientific breakthrough in the country: T +5 %.
## Steps by T/F: the world leader, the frontier (≥ 0.8), catching up (0.6–0.8), behind (0.4–0.6), far behind.
## Behind in months = ln(F/T) / g_F, g_F — the frontier's monthly growth over the last half year; the leader shows
## its lead over the second.
## What it does: the country's research-tree mechanics × (0.5 + 0.5·T/F of its best company of the industry)
## (tree.gd via db.tech_ratio); technologies of the new time with AI nodes need the AI frontier (capabilities.gd);
## a step up — the share +5 %, down — −5 %, the world leader — +0.1 % drift a week; prestige: the leader +2, the
## frontier +1 (arena.gd via db.tech_prestige); a new world leader and steps of the player's companies — news.

const Data := preload("res://mods/pax_corporations/src/core/corp_data.gd")
const TYPES := ["ии", "наука", "космос"]
const STEPS := ["leader", "frontier", "catching", "behind", "far"]
const RESEARCH_POINTS := {"ии": ["нии", "датацентр"], "наука": ["нии"], "космос": ["нии", "космодром"]}
## The tree branch (node id prefix) that is «compute» for the type.
const COMPUTE := {"ии": "t", "наука": "b", "космос": "n"}

var t: Dictionary = {}           # company id -> T
var step_of: Dictionary = {}     # company id -> step key (to see changes)
var front: Dictionary = {}       # type -> F
var f_hist: Dictionary = {}      # type -> [F weekly, last 104]
var c_hist: Dictionary = {}      # company id -> [T weekly, last 104] (the player's companies)
var leaders: Dictionary = {}     # type -> company id
var parts: Dictionary = {}       # company id -> {factor: value} of Q (last week)
var news: Array = []
var db: Data
var game: PaxGame
var tree: Object
var conditions: Object
var events: Object
var investments: Object         # investments.gd — foreign investors speed up catching up


func setup(d: Data, g: PaxGame, tr: Object, cond: Object, ev: Object) -> void:
	db = d
	game = g
	tree = tr
	conditions = cond
	events = ev


func _cfg() -> Dictionary:
	return db.balance.get("tech_level", {})


static func type_of(c: Dictionary) -> String:
	var s := str(c.get("sector", ""))
	return s if s in TYPES else ""


func members(kind: String) -> Array:
	return db.companies.filter(func(c): return str(c.get("sector", "")) == kind)


## A company's T (set from the start values the first time it is asked for).
func level(c: Dictionary) -> float:
	var cid := str(c["id"])
	if not t.has(cid):
		t[cid] = _start(c)
	return float(t[cid])


func _start(c: Dictionary) -> float:
	var st: Dictionary = _cfg().get("старт", {})
	if st.has(str(c["id"])):
		return float(st[str(c["id"])])
	# Not in the ratings (a newborn, a founded one): by revenue against the type's biggest, 35..75.
	var kind := type_of(c)
	var top := 1.0
	for o in members(kind):
		top = maxf(top, db.fund(o, "выручка"))
	return lerpf(35.0, 75.0, clampf(log(1.0 + maxf(db.fund(c, "выручка"), 0.0)) / log(1.0 + top), 0.0, 1.0))


func frontier(kind: String) -> float:
	if not front.has(kind):
		var f := 1.0
		for c in members(kind):
			f = maxf(f, level(c))
		front[kind] = f
	return float(front[kind])


func ratio(c: Dictionary) -> float:
	return level(c) / maxf(frontier(type_of(c)), 1e-6)


func step_key(c: Dictionary) -> String:
	var kind := type_of(c)
	if not leaders.has(kind):
		var lead: Dictionary = {}
		for o in members(kind):
			if lead.is_empty() or level(o) > level(lead):
				lead = o
		if not lead.is_empty():
			leaders[kind] = str(lead["id"])
	if str(leaders.get(kind, "")) == str(c["id"]):
		return "leader"
	var r := ratio(c)
	if r >= 0.8:
		return "frontier"
	if r >= 0.6:
		return "catching"
	if r >= 0.4:
		return "behind"
	return "far"


## The frontier's monthly growth over the last half year (a floor so the months stay finite).
func monthly_growth(kind: String) -> float:
	var h: Array = f_hist.get(kind, [])
	if h.size() >= 8:
		var back := mini(26, h.size() - 1)
		var a := float(h[h.size() - 1 - back])
		var b := float(h[h.size() - 1])
		if a > 0.0 and b > a:
			return maxf(log(b / a) / (float(back) / 4.33), 0.004)
	return float(_cfg().get("frontier_growth_month", 0.012))


## Behind the frontier in months (the leader: its lead over the second, as a positive number).
func months(c: Dictionary) -> float:
	var kind := type_of(c)
	var g := monthly_growth(kind)
	if step_key(c) == "leader":
		var second := 0.0
		for o in members(kind):
			if str(o["id"]) != str(c["id"]):
				second = maxf(second, level(o))
		return log(level(c) / maxf(second, 1e-6)) / g if second > 0.0 else 0.0
	return log(frontier(kind) / maxf(level(c), 1e-6)) / g


## The country's best company of the type ({} if none).
func best_of(country: String, kind: String) -> Dictionary:
	var best: Dictionary = {}
	for c in members(kind):
		if str(c.get("_country", "")) == country and (best.is_empty() or level(c) > level(best)):
			best = c
	return best


func median(kind: String) -> float:
	var vals: Array = []
	for c in members(kind):
		vals.append(level(c))
	if vals.is_empty():
		return 0.0
	vals.sort()
	return float(vals[vals.size() / 2])


# ---------- weekly ----------

func step(day: int) -> void:
	news.clear()
	var cfg := _cfg()
	var dt := float(db.dt)
	var player := db.player_country
	var ratios := {}
	var prestige := {}
	for kind in TYPES:
		var list := members(str(kind))
		if list.is_empty():
			continue
		var f := frontier(str(kind))
		var w: Dictionary = (cfg.get("weights", {}) as Dictionary).get(kind, {})
		var maxes := _maxes(str(kind), list)
		for c in list:
			var cd: Dictionary = c
			var q := _q(cd, str(kind), w, maxes)
			var country := str(cd.get("_country", ""))
			var d := 1.0
			var sig: Dictionary = (events.get("signals") as Dictionary).get(country, {}) if events != null else {}
			if float(sig.get("санкции", 0.0)) > 0.5:
				d = float(cfg.get("diffusion_sanctions", 0.3))
			# A foreign investor brings its know-how: catching up is faster by +0.5·E (investments.gd).
			if investments != null:
				d *= 1.0 + float(cfg.get("diffusion_investor", 0.5)) * float(investments.call("strength_in", str(cd["id"])))
			var tv := level(cd)
			tv = tv * (1.0 + float(cfg.get("growth_per_Q", 0.003)) * q * dt) + float(cfg.get("diffusion", 0.01)) * (f - tv) * d * dt
			if float(sig.get("breakthrough", 0.0)) > 0.5:
				tv *= 1.0 + float(cfg.get("breakthrough", 0.05))
			t[str(cd["id"])] = tv
		# The new frontier and leader.
		var lead: Dictionary = {}
		for c in list:
			if lead.is_empty() or level(c) > level(lead):
				lead = c
		front[kind] = level(lead)
		var was := str(leaders.get(kind, ""))
		leaders[kind] = str(lead["id"])
		if not was.is_empty() and was != str(lead["id"]):
			var entry := {"день": day, "вид": "tech_level", "что": "leader", "type": str(kind)}
			(lead["_chronicle"] as Array).append(entry)
			news.append({"c": lead, "entry": entry, "tone": "good", "size": 0.9, "big": true})
		var h: Array = f_hist.get(kind, [])
		h.append(level(lead))
		while h.size() > 104:
			h.pop_front()
		f_hist[kind] = h
		# Steps: changes jolt the shares; the leader drifts up; prestige and the research trees' strength.
		for c in list:
			var cd: Dictionary = c
			var cid := str(cd["id"])
			var now := step_key(cd)
			var before := str(step_of.get(cid, now))
			step_of[cid] = now
			var e := db.econ(cd)
			if now != before and not e.is_empty():
				var up := STEPS.find(now) < STEPS.find(before)
				e["шок"] = float(e.get("шок", 0.0)) + log(1.0 + (0.05 if up else -0.05))
				if str(cd.get("_country", "")) == player or int(cd.get("_world_place", 999)) <= 100:
					var entry2 := {"день": day, "вид": "tech_level", "что": now, "type": str(kind)}
					(cd["_chronicle"] as Array).append(entry2)
					news.append({"c": cd, "entry": entry2, "tone": "good" if up else "bad", "size": 0.5})
			if now == "leader" and not e.is_empty():
				e["шок"] = float(e.get("шок", 0.0)) + float(cfg.get("leader_drift", 0.001)) * dt
			var country := str(cd.get("_country", ""))
			var key := country + "|" + str(kind)
			ratios[key] = maxf(float(ratios.get(key, 0.0)), ratio(cd))
			var pts := 2.0 if now == "leader" else (1.0 if now == "frontier" else 0.0)
			prestige[country] = maxf(float(prestige.get(country, 0.0)), pts) if pts > 0.0 else float(prestige.get(country, 0.0))
			if country == player:
				var ch: Array = c_hist.get(cid, [])
				ch.append(level(cd))
				while ch.size() > 104:
					ch.pop_front()
				c_hist[cid] = ch
	db.tech_ratio = ratios
	db.tech_prestige = prestige


## The world bests the factors are measured against.
func _maxes(kind: String, list: Array) -> Dictionary:
	var rs := 0.0
	var rev := 1.0
	var no := 0.0
	for c in list:
		rs = maxf(rs, _research_share(c, kind))
		rev = maxf(rev, db.fund(c, "выручка"))
	if tree != null:
		var all: Dictionary = tree.get("no")
		for k in all.keys():
			no = maxf(no, float((all[k] as Dictionary).get("per_week", 0.0)))
	return {"research": maxf(rs, 1e-6), "revenue": rev, "no": maxf(no, 1e-6)}


func _research_share(c: Dictionary, kind: String) -> float:
	var pts: Array = c.get("sites", [])
	var e := db.econ(c)
	var shares: Array = e.get("site_shares", [])
	var s := 0.0
	for i in pts.size():
		var sh := float(shares[i]) if i < shares.size() else 1.0 / float(maxi(pts.size(), 1))
		var tp := str((pts[i] as Dictionary).get("type", ""))
		if tp in (RESEARCH_POINTS.get(kind, []) as Array):
			s += sh
		elif tp == "штаб":
			s += 0.3 * sh
	return s


## Q and its parts: {research, compute, people, money, science} each 0..1 × the type's weight.
func _q(c: Dictionary, kind: String, w: Dictionary, maxes: Dictionary) -> float:
	var country := str(c.get("_country", ""))
	var f := {}
	f["research"] = clampf(_research_share(c, kind) / float(maxes["research"]), 0.0, 1.0)
	var nodes := 0
	if tree != null:
		var opened: Dictionary = (tree.get("opened") as Dictionary).get(country + "|" + kind, {})
		for id in opened.keys():
			if str(id).begins_with(str(COMPUTE.get(kind, "t"))):
				nodes += 1
	var chips := 1.0 if _has_chips(country) else 0.4
	f["compute"] = clampf(0.6 * float(nodes) / 7.0 + 0.4 * chips, 0.0, 1.0)
	f["people"] = float(((conditions.get("country_vars") as Dictionary).get(country, {}) as Dictionary).get("образование", 0.5)) if conditions != null else 0.5
	f["money"] = clampf(log(1.0 + maxf(db.fund(c, "выручка"), 0.0)) / log(1.0 + float(maxes["revenue"])), 0.0, 1.0)
	var no_week := 0.0
	if tree != null:
		no_week = float(((tree.get("no") as Dictionary).get(country, {}) as Dictionary).get("per_week", 0.0))
	f["science"] = clampf(no_week / float(maxes["no"]), 0.0, 1.0)
	var q := 0.0
	var out := {}
	for k in f.keys():
		var v := float(f[k]) * float(w.get(k, 0.2))
		out[k] = v
		q += v
	parts[str(c["id"])] = {"factors": f, "contribution": out}
	return clampf(q, 0.0, 1.0)


func _has_chips(country: String) -> bool:
	for c in db.companies:
		if str((c as Dictionary).get("_country", "")) == country and str((c as Dictionary).get("sector", "")) == "semiconductors":
			return true
	return false


## What holds the company back most: the factor with the biggest weight × (1 − value).
func brake(c: Dictionary) -> String:
	var p: Dictionary = (parts.get(str(c["id"]), {}) as Dictionary).get("factors", {})
	var w: Dictionary = (_cfg().get("weights", {}) as Dictionary).get(type_of(c), {})
	var best := ""
	var worst := -1.0
	for k in p.keys():
		var loss := float(w.get(k, 0.2)) * (1.0 - float(p[k]))
		if loss > worst:
			worst = loss
			best = str(k)
	if best == "compute" and not _has_chips(str(c.get("_country", ""))):
		return "compute_chips"
	return best


# ---------- save ----------

func save_state() -> Dictionary:
	return {"T": t, "steps": step_of, "frontier": front, "history_F": f_hist, "история": c_hist, "лидеры": leaders}


func load_state(state: Dictionary) -> void:
	for k in ["T", "steps", "frontier", "history_F", "история", "лидеры"]:
		if not (state.get(k) is Dictionary):
			continue
	t = (state.get("T", {}) as Dictionary).duplicate(true) if state.get("T") is Dictionary else {}
	step_of = (state.get("steps", {}) as Dictionary).duplicate(true) if state.get("steps") is Dictionary else {}
	front = (state.get("frontier", {}) as Dictionary).duplicate(true) if state.get("frontier") is Dictionary else {}
	f_hist = (state.get("history_F", {}) as Dictionary).duplicate(true) if state.get("history_F") is Dictionary else {}
	c_hist = (state.get("история", {}) as Dictionary).duplicate(true) if state.get("история") is Dictionary else {}
	leaders = (state.get("лидеры", {}) as Dictionary).duplicate(true) if state.get("лидеры") is Dictionary else {}
