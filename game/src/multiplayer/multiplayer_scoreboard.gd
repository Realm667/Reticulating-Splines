class_name MultiplayerScoreboard
extends RefCounted

const VIEWS := ["Overview", "Finances", "Land ownership", "Zoning", "Construction", "Emergency services", "History"]
const COLUMNS := {
	"name": "Player", "city": "City", "online": "Connection", "population": "Population",
	"points": "Points", "funds": "Funds", "balance": "Year-to-date balance", "debt": "Debt", "land": "Owned tiles",
	"builds": "Build actions", "spent": "Build spending", "built": "Developed tiles",
	"residential": "Residential tiles", "commercial": "Commercial tiles", "industrial": "Industrial tiles",
	"bought": "Land purchases", "sold": "Land sales", "units": "Active units", "aid": "Helping neighbours"}
const GROUPS := [
	["name", "city", "online", "population", "funds"],
	["name", "funds", "balance", "debt"],
	["name", "land", "built", "bought", "sold"],
	["name", "residential", "commercial", "industrial"],
	["name", "builds", "spent"],
	["name", "online", "units", "aid"]]
const PERSONAL := ["name", "online", "builds", "spent", "units", "aid"]
const CROWN = preload("res://src/multiplayer/icons/crown.svg")
var table: Tree
var summary: Label
var picker: MultiplayerTabs
var rows: Array = []
var columns: Array = []
var sort_key := "name"
var descending := false
var self_id := ""
var chart: MultiplayerHistoryChart
var metric_picker: MultiplayerTabs
var legend: RichTextLabel
var history: Dictionary = {}
var displayed: Array = []
var goal_kind := "population"
var trend_players: Array = []
var trend_cache: Dictionary = {}

func setup(body: VBoxContainer) -> void:
	picker = MultiplayerTabs.new()
	for title in VIEWS:
		picker.add_item(title)
	body.add_child(picker)
	summary = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(summary)
	table = Tree.new()
	table.hide_root = true
	table.column_titles_visible = true
	table.select_mode = Tree.SELECT_ROW
	table.custom_minimum_size = Vector2(400, 260)
	table.scroll_horizontal_enabled = false
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(table)
	metric_picker = MultiplayerTabs.new()
	for metric: String in MultiplayerHistory.METRICS:
		metric_picker.add_item(COLUMNS[metric])
	body.add_child(metric_picker)
	chart = MultiplayerHistoryChart.new()
	chart.custom_minimum_size = Vector2(400, 240)
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(chart)
	legend = RichTextLabel.new()
	legend.fit_content = true
	legend.custom_minimum_size.y = 42
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(legend)
	metric_picker.item_selected.connect(func(index: int) -> void:
		chart.metric = MultiplayerHistory.METRICS[index]
		rebuild())
	picker.item_selected.connect(func(_index: int) -> void: rebuild())
	table.column_title_clicked.connect(func(index: int, _button: int) -> void:
		var key: String = columns[index]
		descending = not descending if sort_key == key else false
		sort_key = key
		rebuild())

func update(players: Array, shared: bool, identity: String, samples: Dictionary = {}, kind := "population") -> void:
	# Presence carries cursors and selections at a higher rate than statistics.
	# Keep those fields out of the table, and do not replace focused rows for them.
	var values: Array = []
	for player: Dictionary in players:
		var row := {}
		for key: String in COLUMNS:
			if player.has(key):
				row[key] = player[key]
		for key: String in ["id", "color", "host", "ranked"]:
			if player.has(key):
				row[key] = player[key]
		values.append(row)
	var key := [values, shared, identity, kind, TranslationServer.get_locale()]
	goal_kind = kind
	var history_changed := history != samples
	history = samples.duplicate(true) if history_changed else history
	var participants := values.map(func(row: Dictionary) -> Array: return [row.id, row.get("ranked", true)])
	if history_changed or participants != trend_players:
		trend_players = participants
		trend_cache = trends(values, history)
	if key == displayed:
		if history_changed:
			rebuild()
		return
	displayed = key
	rows = values
	self_id = identity
	picker.visible = true
	picker.set_meta("shared", shared)
	summary.text = tr("Statistics are host-confirmed. Select a column heading to sort.")
	if not shared and not rows.is_empty():
		var city: Dictionary = rows[0]
		summary.text = tr("Shared city: %s · Population %s · Funds %s · Year-to-date balance %s · Debt %s") % [city.city, number(city.population), money(city.funds), money(city.balance), money(city.debt)]
	rebuild()

func rebuild() -> void:
	table.custom_minimum_size.y = maxi(80, rows.size() * 28 + 32)
	var show_history := picker.selected == VIEWS.size() - 1
	table.visible = not show_history
	chart.visible = show_history
	metric_picker.visible = show_history
	legend.visible = show_history
	if show_history:
		chart.series = history
		chart.players = rows if picker.get_meta("shared", false) else rows.slice(0, 1)
		chart.queue_redraw()
		legend.clear()
		legend.add_text(tr("Player colours · hover over a line for exact values") + "\n")
		for row: Dictionary in chart.players:
			legend.push_color(Color(CoopSession.valid_color(row.get("color"))) if row.get("ranked", true) else Color(0.6, 0.6, 0.6))
			legend.add_text("● " + str(row.name) + (" · " + tr("Unranked") if not row.get("ranked", true) else "") + "   ")
			legend.pop()
		legend.add_text("\n" + trend_text())
		return
	var selected := str(table.get_selected().get_metadata(0)) if table.get_selected() != null else ""
	var scroll := table.get_scroll()
	columns = (GROUPS[picker.selected] if picker.get_meta("shared", false) else PERSONAL).duplicate()
	if picker.selected == 0 and not rows.is_empty() and rows[0].has("points"):
		columns.append("points")
	if not columns.has(sort_key):
		sort_key = "name"
		descending = false
	table.clear()
	table.columns = columns.size()
	for index in columns.size():
		var key: String = columns[index]
		table.set_column_title(index, tr(COLUMNS[key]) + ((" ▼" if descending else " ▲") if key == sort_key else ""))
		table.set_column_custom_minimum_width(index, 0)
		table.set_column_clip_content(index, true)
		table.set_column_expand(index, true)
		table.set_column_expand_ratio(index, 2 if key in ["name", "city"] else 1)
		table.set_column_title_tooltip_text(index, tr(COLUMNS[key]))
	var ordered := rows.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var av: Variant = a.get(sort_key)
		var bv: Variant = b.get(sort_key)
		if av == bv:
			return str(a.id) < str(b.id)
		if av == null or bv == null:
			return bv == null
		return av > bv if descending else av < bv)
	var root := table.create_item()
	var leaders := {}
	for key: String in columns:
		if key in ["name", "city", "online"]:
			continue
		for row: Dictionary in rows:
			if not row.get("ranked", true):
				continue
			var value: Variant = row.get(key)
			if value == null:
				continue
			if not leaders.has(key) or (value < leaders[key] if key == "debt" else value > leaders[key]):
				leaders[key] = value
	for row_index in ordered.size():
		var row: Dictionary = ordered[row_index]
		var item := table.create_item(root)
		item.set_metadata(0, row.id)
		for index in columns.size():
			var key: String = columns[index]
			var value: Variant = row.get(key)
			var text := tr("Not available") if value == null else str(value)
			if key == "name":
				text += (" · " + tr("You")) if row.id == self_id else ""
				text += (" · " + tr("Host")) if row.get("host", false) else ""
				var badge := Image.create(10, 10, false, Image.FORMAT_RGBA8)
				badge.fill(Color(CoopSession.valid_color(row.get("color"))))
				item.set_icon(index, ImageTexture.create_from_image(badge))
			elif key == "points":
				text = MultiplayerGoal.points(int(value))
				item.set_text_alignment(index, HORIZONTAL_ALIGNMENT_RIGHT)
			elif key == "online":
				text = tr("Connected") if value else tr("Disconnected")
			elif value != null and key != "city":
				text = money(value) if key in ["funds", "balance", "debt", "spent", "bought", "sold"] else number(value)
				item.set_text_alignment(index, HORIZONTAL_ALIGNMENT_RIGHT)
			if not row.get("ranked", true):
				item.set_custom_color(index, Color(0.6, 0.6, 0.6))
				if key == "name":
					text += " · " + tr("Unranked")
			item.set_text(index, text)
			if row.get("ranked", true) and leaders.has(key) and value == leaders[key]:
				item.set_icon(index, PixelArtTexture.wrap(CROWN))
				item.set_icon_max_width(index, 16)
			item.set_custom_bg_color(index, Color(1, 1, 1, 0.035) if row_index % 2 else Color(0, 0, 0, 0.08))
			item.set_tooltip_text(index, tr(COLUMNS[key]) + ": " + text + "\n" + (MultiplayerGoal.score_breakdown(row) if key == "points" else tooltip(key)))
		if row.id == selected:
			item.select(0)
	for child in table.get_children(true):
		if child is HScrollBar:
			child.set_deferred("value", scroll.x)
		elif child is VScrollBar:
			child.set_deferred("value", scroll.y)
	if picker.get_meta("shared", false):
		summary.text = tr("Statistics are host-confirmed. Select a column heading to sort.") + "\n" + trend_text()
		if goal_kind == "timed_score" and picker.selected == 0:
			for row: Dictionary in rows:
				if row.id == self_id:
					summary.text += "\n" + MultiplayerGoal.score_breakdown(row)


static func trends(players: Array, samples: Dictionary) -> Dictionary:
	# Compare exact common calendar months, never different city ages or invented zeros.
	var dated := {}
	var common: Array = []
	for row: Dictionary in players:
		if not row.get("ranked", true):
			continue
		var dates := {}
		for sample: Dictionary in samples.get(row.id, []):
			dates[int(sample.year) * 12 + int(sample.month)] = sample
		common = dates.keys() if dated.is_empty() else common.filter(func(date: int) -> bool: return dates.has(date))
		dated[row.id] = dates
	if common.size() < 2:
		return {}
	common.sort()
	var end: int = common.back()
	var recent := common.filter(func(date: int) -> bool: return date >= end - 12)
	if recent.size() < 2:
		return {}
	var begin: int = recent.front()
	var result := {"months": end - begin, "rows": {}}
	for id: String in dated:
		var first: Dictionary = dated[id][begin]
		var last: Dictionary = dated[id][end]
		result.rows[id] = {"population": int(last.population) - int(first.population), "funds": int(last.funds) - int(first.funds)}
		for metric: String in ["population", "wealth", "points"]:
			var first_best := -9223372036854775807
			var last_best := -9223372036854775807
			var kind := "timed_score" if metric == "points" else metric
			for other: String in dated:
				first_best = maxi(first_best, MultiplayerGoalHud.value(dated[other][begin], kind))
				last_best = maxi(last_best, MultiplayerGoalHud.value(dated[other][end], kind))
			result.rows[id][metric + "_gap"] = (last_best - MultiplayerGoalHud.value(last, kind)) - (first_best - MultiplayerGoalHud.value(first, kind))
	return result


func trend_text() -> String:
	var trend := trend_cache
	if trend.is_empty() or not trend.rows.has(self_id):
		return tr("Comparable monthly history is not available yet.")
	var row: Dictionary = trend.rows[self_id]
	var result := tr("Last %d common months · Your population %s · Funds %s") % [trend.months, signed_number(row.population), signed_number(row.funds, true)]
	var metric := "points" if goal_kind == "timed_score" else "wealth" if goal_kind == "wealth" else "population"
	var label := tr("Points") if metric == "points" else tr("Net wealth") if metric == "wealth" else tr("Population")
	var change: int = row[metric + "_gap"]
	result += "\n" + tr("Change in gap (%s): %s · Negative means catching up.") % [label, ("+" if change > 0 else "") + MultiplayerGoalHud.number(change, "timed_score" if metric == "points" else metric)]
	return result


static func signed_number(value: int, currency := false) -> String:
	return ("+" if value > 0 else "") + (money(value) if currency else number(value))

static func number(value: Variant) -> String:
	var digits := str(absi(int(value)))
	var result := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += "." if TranslationServer.get_locale().begins_with("de") else ","
		result += digits[index]
	return ("−" if int(value) < 0 else "") + result

static func money(value: Variant) -> String:
	return "$" + number(value)

func tooltip(key: String) -> String:
	if key == "points":
		return MultiplayerGoal.score_help()
	if key == "balance":
		return tr("Recorded budget balance in the current city year; excludes construction and land transactions.")
	if key in ["spent", "builds"]:
		return tr("Personal confirmed construction contributions recorded by this multiplayer session.")
	if key in ["bought", "sold"]:
		return tr("Cumulative confirmed land transactions since tracking began. Older untracked totals are unavailable.")
	if key in ["land", "built", "residential", "commercial", "industrial"]:
		return tr("Number of map tiles in this municipality; developed tiles include infrastructure.")
	if key == "aid":
		return tr("Own active emergency units deployed in another municipality.")
	return tr("Current host-confirmed value.")
