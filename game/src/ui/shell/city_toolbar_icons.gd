extends RefCounted
## Scalable, flat category symbols. City sprite packs do not change these UI icons.

const CATEGORIES: Array[Texture2D] = [
	preload("res://src/ui/shell/icons/bulldozer.svg"),
	preload("res://src/ui/shell/icons/landscape.svg"),
	preload("res://src/ui/shell/icons/dispatch.svg"),
	preload("res://src/ui/shell/icons/power.svg"),
	preload("res://src/ui/shell/icons/water.svg"),
	preload("res://src/ui/shell/icons/rewards.svg"),
	preload("res://src/ui/shell/icons/roads.svg"),
	preload("res://src/ui/shell/icons/rail.svg"),
	preload("res://src/ui/shell/icons/ports.svg"),
	preload("res://src/ui/shell/icons/residential.svg"),
	preload("res://src/ui/shell/icons/commercial.svg"),
	preload("res://src/ui/shell/icons/industrial.svg"),
	preload("res://src/ui/shell/icons/education.svg"),
	preload("res://src/ui/shell/icons/services.svg"),
	preload("res://src/ui/shell/icons/recreation.svg"),
	preload("res://src/ui/shell/icons/signs.svg"),
	preload("res://src/ui/shell/icons/query.svg"),
	preload("res://src/ui/shell/icons/center.svg"),
]

const NAVIGATION: Dictionary[int, Texture2D] = {
	405: preload("res://src/ui/shell/icons/rotate_left.svg"),
	433: preload("res://src/ui/shell/icons/rotate_right.svg"),
	462: preload("res://src/ui/shell/icons/zoom_out.svg"),
	486: preload("res://src/ui/shell/icons/zoom_in.svg"),
}
