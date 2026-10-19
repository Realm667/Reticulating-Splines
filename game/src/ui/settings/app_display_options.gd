class_name AppDisplayOptions
extends RefCounted
## Window pixel dimensions. Fullscreen always uses the monitor's native size.
@warning_ignore_start("integer_division")

const SIZES: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1280, 720), Vector2i(1280, 800),
	Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]


static func normalize(value: Variant) -> Vector2i:
	return value if value is Vector2i and value in SIZES else Vector2i.ZERO


static func fit(size: Vector2i, available: Vector2i) -> Vector2i:
	return Vector2i(mini(size.x, available.x), mini(size.y, available.y))


static func apply(window: Window, size: Vector2i) -> void:
	if size == Vector2i.ZERO or DisplayServer.get_name() == "headless":
		return
	window.mode = Window.MODE_WINDOWED
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	# Keep native decorations accessible on screens smaller than the saved choice.
	var available := usable.size - Vector2i(32, 64)
	window.size = fit(size, available)
	window.position = usable.position + (usable.size - window.size) / 2
