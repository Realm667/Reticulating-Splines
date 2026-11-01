class_name MusicBoxOrder
extends RefCounted
## Presentation-only random order and Previous/Next history for a collection.

var random := RandomNumberGenerator.new()
var pool: Array = []
var remaining: Array = []
var history: Array = []
var cursor := -1


func _init() -> void:
	random.randomize()


func reset() -> void:
	pool.clear()
	remaining.clear()
	history.clear()
	cursor = -1


func next_track(ids: Array, current: Variant, direction: int) -> Variant:
	if ids.is_empty():
		return null
	if pool != ids:
		reset()
		pool = ids.duplicate()
		_refill(current)
		remaining.erase(current)
	if current in pool and (cursor < 0 or not is_same(history[cursor], current)):
		history.resize(cursor + 1)
		history.append(current)
		cursor = history.size() - 1
		remaining.erase(current)
	if direction < 0 and cursor >= 0:
		cursor = maxi(0, cursor - 1)
		return history[cursor]
	if cursor + 1 < history.size():
		cursor += 1
		return history[cursor]
	if remaining.is_empty():
		_refill(current)
	var next: Variant = remaining.pop_front()
	history.append(next)
	if history.size() > 512:
		history.pop_front()
	cursor = history.size() - 1
	return next


func _refill(current: Variant) -> void:
	remaining = pool.duplicate()
	for i in range(remaining.size() - 1, 0, -1):
		var j := random.randi_range(0, i)
		var value: Variant = remaining[i]
		remaining[i] = remaining[j]
		remaining[j] = value
	if remaining.size() > 1 and is_same(remaining[0], current):
		remaining[0] = remaining[1]
		remaining[1] = current
