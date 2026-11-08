class_name PaletteAnimationClock
extends RefCounted
# ApplicationFrame advances the clock; ApplicationStaticRender builds the palette texture.

var cycle_ticks := 0
# display time not yet counted as a whole base tick
var elapsed_msec := 0.0
var cycle_texture: ImageTexture
var underground_cycle_texture: ImageTexture
# Surface and underground share one sampler on hardware with 16 texture units.
var map_palette_texture: ImageTexture
# the active palette with the current animation cycle applied, for toolbar icons
var toolbar_palette: Sc2Palette
var _source: Sc2Palette
var _texture_tick := -1
var _fraction := -1.0
var _water_fraction := -1.0
var _current: Image
var _next: Image
var _dark_current: Image
var _dark_next: Image
var _blended: Image
var _dark_blended: Image


# Resolve palette addresses once per tick. All indexed city layers share the
# resulting colors; sprite-frame interpolation remains a separate operation.
func update_textures(palette: Sc2Palette, fraction: float, underground := true, force := false, water_fraction := -1.0) -> bool:
	if palette == null or not palette.is_valid():
		return false
	fraction = clampf(fraction, 0.0, 1.0)
	water_fraction = fraction if water_fraction < 0.0 else clampf(water_fraction, 0.0, 1.0)
	var rebuild := force or _source != palette or _texture_tick != cycle_ticks or (underground and _dark_current == null)
	if not rebuild and fraction == _fraction and water_fraction == _water_fraction:
		return false
	if rebuild:
		_source = palette
		_texture_tick = cycle_ticks
		_current = palette.animation_image(cycle_ticks)
		_next = palette.animation_image(cycle_ticks + 1)
		_blended = _current.duplicate()
		if underground:
			_dark_current = palette.underground_animation_image(cycle_ticks)
			_dark_next = palette.underground_animation_image(cycle_ticks + 1)
			_dark_blended = _dark_current.duplicate()
		else:
			_dark_current = null
			_dark_next = null
			_dark_blended = null
	_fraction = fraction
	_water_fraction = water_fraction
	_blend_colors(_blended, _current, _next, fraction)
	_blend_water(_blended, _current, _next, water_fraction)
	if cycle_texture == null:
		cycle_texture = ImageTexture.create_from_image(_blended)
	else:
		cycle_texture.update(_blended)
	if underground:
		# Remap endpoints first, so color classification cannot switch during a fade.
		_blend_colors(_dark_blended, _dark_current, _dark_next, fraction)
		_blend_water(_dark_blended, _dark_current, _dark_next, water_fraction)
		if underground_cycle_texture == null:
			underground_cycle_texture = ImageTexture.create_from_image(_dark_blended)
		else:
			underground_cycle_texture.update(_dark_blended)
	var combined := CityMapShaderTables.palette_image(_blended, _dark_blended)
	if map_palette_texture == null:
		map_palette_texture = ImageTexture.create_from_image(combined)
	else:
		map_palette_texture.update(combined)
	return true


static func _blend_colors(target: Image, first: Image, second: Image, fraction: float) -> void:
	# Stationary entries stay byte-identical, including those within the ranges.
	for index in range(Sc2Palette.FAST_CYCLE_START, Sc2Palette.FAST_CYCLE_START + Sc2Palette.FAST_CYCLE_COUNT):
		target.set_pixel(index, 0, first.get_pixel(index, 0).lerp(second.get_pixel(index, 0), fraction))
	for index in range(Sc2Palette.SLOW_CYCLE_START, Sc2Palette.SLOW_CYCLE_START + Sc2Palette.SLOW_CYCLE_COUNT):
		target.set_pixel(index, 0, first.get_pixel(index, 0).lerp(second.get_pixel(index, 0), fraction))


static func _blend_water(target: Image, first: Image, second: Image, fraction: float) -> void:
	# Water keeps its original eight colors and cycle order, but the whole
	# surface must not flash when disaster-frame blending is disabled.
	for index in range(200, 208):
		target.set_pixel(index, 0, first.get_pixel(index, 0).lerp(second.get_pixel(index, 0), fraction))
