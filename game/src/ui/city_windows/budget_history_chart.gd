class_name BudgetHistoryChart
extends Control
## Read-only view of the same monthly amounts used by the budget table.

const COLORS := [Color("76d5dc"), Color("d8ee70"), Color("efae79"), Color("b6a3ed"), Color("f18fbb"), Color("8ac697")]
const LIGHT_COLORS := [Color("176d86"), Color("526d13"), Color("a34b15"), Color("6949a3"), Color("a52e65"), Color("237248")]

var series: Array[PackedInt64Array] = []
var names := PackedStringArray()
var recorded := 0
var selected_month := -1
var _low := 0.0
var _high := 1.0
var _left := 64.0


func _init() -> void:
	custom_minimum_size = Vector2(300, 180)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme_changed.connect(queue_redraw)
	mouse_exited.connect(func() -> void:
		selected_month = -1
		queue_redraw())


func show_report(report: BudgetReport, group: int, cumulative: bool) -> void:
	series.clear()
	names.clear()
	recorded = report.actual_months
	if cumulative:
		var values := PackedInt64Array()
		var total := 0
		for month in 12:
			for id: int in BudgetReport.GROUPS[group]:
				total += report.history[id][month]
			values.append(total)
		series.append(values)
		names.append(tr("Running total"))
	else:
		for id: int in BudgetReport.GROUPS[group]:
			series.append(report.history[id].duplicate())
			names.append(tr(BudgetReport.NAMES[id]))
	_low = 0.0
	_high = 0.0
	for values in series:
		for value in values:
			_low = minf(_low, value)
			_high = maxf(_high, value)
	if is_equal_approx(_low, _high):
		_high = _low + 1.0
	queue_redraw()


func series_color(index: int) -> Color:
	return (COLORS if AppUiTheme.selected == "dark" else LIGHT_COLORS)[index % COLORS.size()]


func _plot() -> Rect2:
	return Rect2(_left, 28, maxf(1, size.x - _left - 18), maxf(1, size.y - 54))


func _point(month: int, value: int) -> Vector2:
	var plot := _plot()
	return Vector2(plot.position.x + plot.size.x * month / 11.0,
		plot.end.y - plot.size.y * (float(value) - _low) / (_high - _low))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed):
		selected_month = clampi(roundi((event.position.x - _plot().position.x) / _plot().size.x * 11), 0, 11)
		queue_redraw()


func _get_tooltip(at_position: Vector2) -> String:
	var month := clampi(roundi((at_position.x - _plot().position.x) / _plot().size.x * 11), 0, 11)
	return month_detail(month)


func month_detail(month: int) -> String:
	var result := tr(BudgetReport.MONTHS[month]) + " · " + tr("Recorded" if month < recorded else "Projected")
	for index in series.size():
		result += "\n%s: %s" % [names[index], BudgetReport.currency(series[index][month])]
	return result


func _draw() -> void:
	var ink := get_theme_color("ink", "AppPalette")
	var grid := get_theme_color("grid", "AppPalette")
	var font := get_theme_default_font()
	draw_style_box(get_theme_stylebox("panel", "Tree"), Rect2(Vector2.ZERO, size))
	if series.is_empty():
		return
	_left = maxf(64, maxf(font.get_string_size(BudgetReport.currency(roundi(_low)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x,
		font.get_string_size(BudgetReport.currency(roundi(_high)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x) + 14)
	var plot := _plot()
	var key_x := plot.position.x
	for state in ["Recorded", "Projected"]:
		if state == "Recorded":
			draw_line(Vector2(key_x, 13), Vector2(key_x + 22, 13), ink, 2)
		else:
			draw_dashed_line(Vector2(key_x, 13), Vector2(key_x + 22, 13), ink, 2, 4)
		var caption := tr(state)
		draw_string(font, Vector2(key_x + 28, 17), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
		key_x += font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 48
	if recorded < 12:
		var boundary := plot.position.x + plot.size.x * maxf(0, recorded - 0.5) / 11.0
		draw_rect(Rect2(boundary, plot.position.y, plot.end.x - boundary, plot.size.y), Color(ink, 0.045))
	for step in 3:
		var fraction := step / 2.0
		var y := plot.end.y - plot.size.y * fraction
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid)
		var amount := BudgetReport.currency(roundi(lerpf(_low, _high, fraction)))
		draw_string(font, Vector2(4, y + 4), amount, HORIZONTAL_ALIGNMENT_RIGHT, _left - 12, 11, ink)
	var zero_y := _point(0, 0).y
	draw_line(Vector2(plot.position.x, zero_y), Vector2(plot.end.x, zero_y), Color(ink, 0.5))
	for month in 12:
		var x := _point(month, 0).x
		draw_string(font, Vector2(x - 10, plot.end.y + 18), str(month + 1), HORIZONTAL_ALIGNMENT_CENTER, 20, 11, ink)
	for index in series.size():
		var color := series_color(index)
		for month in 12:
			var point := _point(month, series[index][month])
			if month > 0:
				var previous := _point(month - 1, series[index][month - 1])
				if month < recorded:
					draw_line(previous, point, color, 2, true)
				else:
					draw_dashed_line(previous, point, color, 2, 5, true)
			draw_circle(point, 2.5, color)
	if selected_month >= 0:
		var x := _point(selected_month, 0).x
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(ink, 0.45))
		for index in series.size():
			draw_circle(_point(selected_month, series[index][selected_month]), 4, series_color(index))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()
