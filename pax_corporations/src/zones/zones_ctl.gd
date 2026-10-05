extends RefCounted
## Economic unions for the player's country: joining (its chance and reasons), leaving, founding a new one.
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const Host := preload("res://mods/pax_corporations/main.gd")

var app: Host   # the host: its modules and data


func _init(host: Host) -> void:
	app = host


## A zone's window (the corporations' «Zones» screen, dashboard.gd) — from the map's zone layer or the home.
func open_zone(id: String) -> void:
	if not is_instance_valid(app._window):
		return
	app._window.show_window()
	app._window.open_zone(id)


## The player's country's attitude of a country (0..1), for the unions' conditions.
func zone_relation(country: String) -> float:
	return app.investments.relation(country) if app.investments != null else 0.5


## Why the player's country cannot join ("" — it can).
func zone_join_block(id: String) -> String:
	var z := Host.Zones.zone(id)
	if z.is_empty():
		return "zones_why_not_union"
	return Host.Zones.join_block(app._player_country(), z, zone_relation)


## Why the player cannot join, in full words ("" — he can): which customs union holds him, how warm the members are.
func zone_join_reason(id: String) -> String:
	var z := Host.Zones.zone(id)
	var why := zone_join_block(id)
	match why:
		"":
			return ""
		"zones_why_customs":
			var cu := Host.Zones.customs_union_of(app._player_country())
			return app.tr_key("pax_corporations_zones_why_customs2") % Host.Zones.name_of(cu, app.db.lang())
		"zones_why_relations":
			var sum := 0.0
			var n := 0
			for m in Host.Zones.members(z):
				sum += zone_relation(str(m))
				n += 1
			return app.tr_key("pax_corporations_zones_why_relations2") % [roundi(sum / maxf(float(n), 1.0) * 100.0), roundi(float(Host.Zones.cfg.get("accession_relations", 0.5)) * 100.0)]
		"zones_why_not_union":
			return app.tr_key("pax_corporations_zones_why_not_union2") % Host.Zones.name_of(z, app.db.lang())
	return app.tr_key("pax_corporations_" + why)


func zone_join(id: String) -> String:
	var z := Host.Zones.zone(id)
	var why := zone_join_block(id)
	if not why.is_empty():
		return app.tr_key("pax_corporations_" + why)
	var me := app._player_country()
	Host.Zones.join(me, z)
	for m in Host.Zones.members(z):
		if str(m) != me:
			app.arena.call("_relations", str(m), 0.03)
	app.db.version += 1
	var line := app.tr_key("pax_corporations_zones_joined") % Host.Zones.name_of(z, app.db.lang())
	app._order_says(line)
	return line


## Leaving: the country's companies lose the single market at once (a share shock), the partners cool.
func zone_leave(id: String) -> String:
	var z := Host.Zones.zone(id)
	var me := app._player_country()
	if z.is_empty() or not (me in Host.Zones.members(z)):
		return ""
	var shock := float(Host.Zones.cfg.get("exit_shock", -0.05))
	for c in app.db.companies:
		if str(c.get("_country", "")) == me:
			var e := app.db.econ(c)
			if not e.is_empty():
				e["шок"] = float(e.get("шок", 0.0)) + log(1.0 + shock)
	for m in Host.Zones.members(z):
		if str(m) != me:
			app.arena.call("_relations", str(m), -0.1)
	Host.Zones.leave(me, z)
	app.db.version += 1
	var line := app.tr_key("pax_corporations_zones_left") % [Host.Zones.name_of(z, app.db.lang()), app.db.percent(absf(shock))]
	app._order_says(line)
	return line


## Would this country join the player's new union? [yes, reason]: a member of another union refuses at once; below
## «вступление_от» it refuses; from «вступление_точно» it agrees; between — by chance growing with its attitude.
func zone_join_answer(country: String) -> Array:
	for z in Host.Zones.zones_of(country):
		if bool((z as Dictionary).get("союз", true)):
			return [false, app.tr_key("pax_corporations_zones_why_in_union") % Host.Zones.name_of(z, app.db.lang())]
	var rel := zone_relation(country)
	var lo := float(Host.Zones.cfg.get("accession_from", 0.35))
	var hi := float(Host.Zones.cfg.get("accession_sure", 0.7))
	var chance := clampf((rel - lo) / maxf(hi - lo, 0.01), 0.0, 1.0)
	if chance >= 1.0:
		return [true, app.tr_key("pax_corporations_zones_why_friends") % roundi(rel * 100.0)]
	if chance <= 0.0:
		return [false, app.tr_key("pax_corporations_zones_why_cold") % roundi(rel * 100.0)]
	if randf() < chance:
		return [true, app.tr_key("pax_corporations_zones_why_lucky") % [roundi(rel * 100.0), roundi(chance * 100.0)]]
	return [false, app.tr_key("pax_corporations_zones_why_unlucky") % [roundi(rel * 100.0), roundi(chance * 100.0)]]


## The chance a country agrees, 0..1 (−1 — it is in another union), for the list.
func zone_join_chance(country: String) -> float:
	for z in Host.Zones.zones_of(country):
		if bool((z as Dictionary).get("союз", true)):
			return -1.0
	var lo := float(Host.Zones.cfg.get("accession_from", 0.35))
	var hi := float(Host.Zones.cfg.get("accession_sure", 0.7))
	return clampf((zone_relation(country) - lo) / maxf(hi - lo, 0.01), 0.0, 1.0)


## A new union with the partners who agree. Returns {ok, line, agreed: [names], refused: [[name, reason]], id}.
func zone_found(partners: Array, title: String) -> Dictionary:
	var me := app._player_country()
	var ok: Array = []
	var no: Array = []
	for p in partners:
		var ans := zone_join_answer(str(p))
		if bool(ans[0]):
			ok.append(str(p))
		else:
			no.append([str(p), str(ans[1])])
	if ok.is_empty():
		return {"ok": false, "line": app.tr_key("pax_corporations_zones_found_none"), "agreed": [], "refused": no, "id": ""}
	var z := Host.Zones.found(me, ok, title.strip_edges() if not title.strip_edges().is_empty() else app.tr_key("pax_corporations_zones_found_name") % me)
	for c in ok:
		app.arena.call("_relations", str(c), 0.03)
	app.db.version += 1
	var line := app.tr_key("pax_corporations_zones_founded") % [Host.Zones.name_of(z, app.db.lang()), ", ".join(PackedStringArray(ok))]
	if not no.is_empty():
		line += " " + app.tr_key("pax_corporations_zones_found_refused") % ", ".join(PackedStringArray(no.map(func(x): return str(x[0]))))
	app._order_says(line)
	if is_instance_valid(app._window):
		app._window.zone_sel = str(z["id"])
	return {"ok": true, "line": line, "agreed": ok, "refused": no, "id": str(z["id"])}
