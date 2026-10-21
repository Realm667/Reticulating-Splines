class_name KnowledgeWindow
extends QolDialog

signal action_requested(action: String)
signal preferences_changed(mode: int, top: bool)
signal reset_requested
signal mute_requested(id: String)
var search: LineEdit
var topics: OptionButton
var items: ItemList
var card: KnowledgeCard
var tips_mode: OptionButton
var position_choice: OptionButton
var recent: Array[String] = []
var ids: Array[String] = []


func _init() -> void:
	super()
	wrap_controls = false
	title = "Tips & Knowledge"
	min_size = Vector2i(320, 220)
	size = Vector2i(700, 520)
	var preferences := HFlowContainer.new()
	column.add_child(preferences)
	tips_mode = OptionButton.new()
	for text in ["Tips off", "Start and loading only", "Also during play"]:
		tips_mode.add_item(text)
	tips_mode.select(2)
	tips_mode.tooltip_text = "Automatic tips"
	preferences.add_child(tips_mode)
	position_choice = OptionButton.new()
	position_choice.add_item("Bottom right")
	position_choice.add_item("Top right")
	position_choice.tooltip_text = "Tip position"
	preferences.add_child(position_choice)
	button(preferences, "Reset hidden topics", reset_requested.emit)
	tips_mode.item_selected.connect(_preferences_changed)
	position_choice.item_selected.connect(_preferences_changed)
	var filters := row()
	search = LineEdit.new()
	search.placeholder_text = "Search knowledge"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(search)
	topics = OptionButton.new()
	for text in ["All topics", "Recently shown", "Growth", "Utilities", "Finances"]:
		topics.add_item(text)
	filters.add_child(topics)
	search.text_changed.connect(func(_text: String) -> void: refresh())
	topics.item_selected.connect(func(_index: int) -> void: refresh())
	items = ItemList.new()
	items.custom_minimum_size.y = 110
	items.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(items)
	items.item_selected.connect(func(index: int) -> void: select_entry(ids[index]))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	card = KnowledgeCard.new()
	card.embedded = true
	card.library = true
	card.unbounded_body = true
	content.add_child(card)
	card.action_requested.connect(action_requested.emit)
	card.mute_requested.connect(mute_requested.emit)
	card.pin.hide()
	button(column, "Close", hide)


func _preferences_changed(_index: int) -> void:
	preferences_changed.emit(tips_mode.selected, position_choice.selected == 1)


func open(history: Array[String], selected := "start") -> void:
	recent = history.duplicate()
	theme = AppUiTheme.current()
	refresh()
	select_entry(selected)
	var viewport_size := Vector2i(get_parent().get_viewport().get_visible_rect().size)
	popup_centered(Vector2i(mini(700, viewport_size.x - 24), mini(560, viewport_size.y - 50)))


func refresh() -> void:
	ids.clear()
	items.clear()
	var entries: Array = KnowledgeCatalog.ENTRIES
	if topics.selected == 1:
		entries = []
		for id in recent:
			entries.append(KnowledgeCatalog.entry(id))
	for entry: Array in entries:
		if topics.selected == 1 and not recent.has(entry[0]):
			continue
		if topics.selected == 2 and entry[4] not in ["growth", "demand", "land"]:
			continue
		if topics.selected == 3 and entry[4] not in ["power", "water", "traffic"]:
			continue
		if topics.selected == 4 and entry[4] not in ["budget", "ordinances"]:
			continue
		var text := tr(entry[1]) + " " + tr(entry[2]) + " " + tr(entry[3])
		if not search.text.is_empty() and text.findn(search.text) < 0:
			continue
		ids.append(entry[0])
		items.add_item(tr(entry[1]))
		items.set_item_tooltip(items.item_count - 1, tr(entry[1]))
	if card != null:
		if ids.is_empty():
			card.hide()
		else:
			select_entry(card.id if ids.has(card.id) else ids[0])


func select_entry(id: String) -> void:
	if not ids.has(id):
		return
	card.show_entry(id, true)
	if ids.has(id):
		items.select(ids.find(id))
		items.ensure_current_is_visible.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and items != null:
		refresh()
