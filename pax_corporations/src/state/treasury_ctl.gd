extends RefCounted
## The treasury: taxes and dividends the companies pay the countries, the player's year.
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const Host := preload("res://mods/pax_corporations/main.gd")

var app: Host   # the host: its modules and data


func _init(host: Host) -> void:
	app = host


## Profit tax rates by country: the player's comes from the game's economy, the rest from config.
func _tax_rates() -> Dictionary:
	var rates := {}
	var farms: Variant = app._game.main.get("хозяйства")
	if farms is Dictionary:
		var h: Dictionary = (farms as Dictionary).get(app._game.home_body(), {})
		if h.has("tax"):
			rates[app._player_country()] = float(h["tax"])
	return rates


## Taxes and dividends on state stakes go on top of what the game already counts — on purpose (section 9):
## a player who ignores the country's corporations falls behind in money.
func _pay_treasuries(paid: Dictionary) -> void:
	var share := float((app.db.balance.get("staff", {}) as Dictionary).get("to_treasury", 1.0))
	var player := app._player_country()
	var mine := 0.0
	for country in paid.keys():
		var t: Dictionary = paid[country]
		var amount := (float(t["taxes"]) + float(t["dividends"])) * share
		if amount == 0.0:
			continue
		if str(country) == player:
			app._game.add_resource(app._game.home_body(), "money", amount)
			mine += amount
			app._paid_week = {"taxes": float(t["taxes"]) * share / float(app.db.dt), "dividends": float(t["dividends"]) * share / float(app.db.dt)}
		else:
			for f in app._game.factions():
				var fd: Dictionary = f
				if str(fd.get("name", "")) == str(country):
					fd["money"] = float(fd.get("money", 0.0)) + amount
					break
	app.treasury_weeks.append(mine / float(app.db.dt))   # per week, also when a step covered several (a long skip)
	app.digest.add_treasury(mine)
	while app.treasury_weeks.size() > 52:
		app.treasury_weeks.pop_front()


func treasury_year() -> float:
	var s := 0.0
	for v in app.treasury_weeks:
		s += float(v)
	return s * 52.0 / maxf(1.0, float(app.treasury_weeks.size()))
