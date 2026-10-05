extends RefCounted
## News to the game's feed and toasts: one per frame, only the latest after a skip, quiet while time is skipped.
## Part of main.gd (split out of it; the host keeps one-line wrappers with the same names).

const Host := preload("res://mods/pax_corporations/main.gd")

var app: Host   # the host: its modules and data
var _quiet_until := 0


func _init(host: Host) -> void:
	app = host


## The skip is over: no notifications — what happened is in the «Corporations» news and the letters' tab.
func _flush_skip_news() -> void:
	app._skip_news.clear()
	app._skip_letters = 0


## Who hears what: the player's country and favourites — everything (only the biggest when there is a lot);
## the world top-100 — only big events; the world crisis — always; the rest stays in the chronicles.
func _deliver_news(day: int) -> void:
	var player := app._player_country()
	var favs := app._favorites()
	# Everything the modules said this week, before the feed filters: the AI's batch and the newspaper (narrator.gd).
	app.narrator.collect(app.events.news + app.politics.news + app.debt.news + app.rivals.news + app.lifecycle.news + app.antitrust.news + app.orders.news + app.influence.news + app.frames.news + app.tree.news + app.investments.news + app.conditions.news + app.capabilities.news + app.techlevel.news + app.state_goals.news,
		app.letters.fresh, player, favs, day)
	var picked: Array = []
	var always: Array = []
	for n in app.events.news + app.politics.news + app.debt.news + app.rivals.news + app.lifecycle.news + app.antitrust.news + app.orders.news + app.influence.news + app.frames.news + app.tree.news + app.investments.news + app.conditions.news + app.capabilities.news + app.techlevel.news + app.state_goals.news:
		var item: Dictionary = n
		if bool(item.get("always", false)):
			always.append(item)
			continue
		var c: Dictionary = item["c"]
		var country := str(c.get("_country", ""))
		var mine := country == player or favs.has(str(c["id"])) or favs.has("страна:" + country)
		if mine or (int(c.get("_world_place", 999)) <= 100 and bool(item.get("big", false))):
			picked.append(item)
	# Strikes and layoffs of the player's and favourite companies this week.
	for item in app.db.companies:
		var c: Dictionary = item
		var country := str(c.get("_country", ""))
		if not (country == player or favs.has(str(c["id"])) or favs.has("страна:" + country)):
			continue
		var chron: Array = c.get("_chronicle", [])
		for i in range(chron.size() - 1, -1, -1):   # newest first; this week's entries are at the end
			var ed: Dictionary = chron[i]
			if int(ed.get("день", -1)) < day:
				break
			if int(ed.get("день", -1)) == day and str(ed.get("вид", "")) in ["strike", "layoffs", "уступка"]:
				picked.append({"c": c, "entry": ed, "tone": "good" if str(ed["вид"]) == "уступка" else "bad",
					"size": float(ed.get("доля", 0.1))})
	picked.sort_custom(func(a, b): return float(a["size"]) > float(b["size"]))
	for item in always + picked:
		app.digest.add(item)   # the summary gets everything that matters; the feed only the biggest few
	var limit := int((app.db.balance.get("события", {}) as Dictionary).get("news_per_week", 3))
	# Posted one per frame from _process: each post builds a card in the game's feed (~7 ms).
	var week_news: Array = always + picked.slice(0, limit)
	if app._pending.size() > 0:
		# A skip in progress: nothing goes to the feed now — only the latest few at its end (the summary has the rest).
		app._skip_news.append_array(week_news)
		if app._skip_news.size() > Host.NEWS_AFTER_SKIP * 3:
			app._skip_news = app._skip_news.slice(app._skip_news.size() - Host.NEWS_AFTER_SKIP)
		app._skip_letters += app.letters.fresh.size()
		return
	app._post_queue.append_array(week_news)
	if app._post_queue.size() > Host.NEWS_AFTER_SKIP:
		app._post_queue = app._post_queue.slice(app._post_queue.size() - Host.NEWS_AFTER_SKIP)
	if not app.letters.fresh.is_empty():
		var first: Dictionary = app.letters.fresh[0]
		_toast(app.tr_key("pax_corporations_letters_new") % [app.letters.fresh.size(), str(first.get("company", ""))])


func _post(item: Dictionary) -> void:
	var c: Dictionary = item["c"]
	var entry: Dictionary = item["entry"]
	var title := app.tr_key("pax_corporations_market_title") if c.is_empty() else app.db.name_of(c)
	var text := app._window.chron_text(c, entry) if is_instance_valid(app._window) else ""
	var province := int(app.db.hq_of(c).get("province", 0)) if not c.is_empty() else 0
	var feed: Variant = app._game.main.get("вести")
	if feed is Object and (feed as Object).has_method("весть"):
		(feed as Object).call("весть", str(item.get("tone", "neutral")), title, text, province, "")
	else:
		_toast("[b]%s[/b] — %s" % [title, text])


## A notification — not during a time skip, the wait for its results, or 4 s after (the news tell what happened).
func _toast(text: String) -> void:
	if app._game == null:
		return
	var busy := app._game_skipping()
	for flag in ["_ждём_последствий"]:
		var v: Variant = app._game.main.get(flag)
		busy = busy or (v is bool and v)
	var res: Variant = app._game.main.get("итоги_ждём")
	busy = busy or (res is Dictionary and not (res as Dictionary).is_empty())
	if busy:
		_quiet_until = Time.get_ticks_msec() + 4000
		return
	if Time.get_ticks_msec() < _quiet_until:
		return
	app._game.toast(text)
