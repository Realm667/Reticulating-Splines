class_name CityGpuTexturePages
extends RefCounted
## Resident atlas pages. Region placement never changes these textures.

const EDGE := 1024
var art: Texture2DArray
var emission: Texture2DArray
var seasons: Texture2DArray
var atlas_edge := 0
var uploaded_bytes := 0


func publish(data: Dictionary) -> bool:
	atlas_edge = data.edge
	for field in ["art", "emission", "seasons"]:
		if not data.has(field):
			continue
		var images: Array[Image] = []
		images.assign(data[field])
		var texture: Texture2DArray = get(field)
		if texture == null:
			texture = Texture2DArray.new()
			if texture.create_from_images(images) != OK:
				return false
			set(field, texture)
		else:
			for index in images.size():
				texture.update_layer(images[index], data.indices[index])
		uploaded_bytes += images.size() * EDGE * EDGE * 4
	return true


func apply(material: ShaderMaterial, shader: Shader = preload("res://src/view/map/palette_cycle_pages.gdshader")) -> void:
	if shader == preload("res://src/view/map/palette_cycle_pages.gdshader") and material.shader in [
		preload("res://src/view/map/palette_cycle_compact.gdshader"), preload("res://src/view/map/palette_cycle_pages_compact.gdshader")]:
		shader = preload("res://src/view/map/palette_cycle_pages_compact.gdshader")
	material.shader = shader
	material.set_shader_parameter("region_atlas_edge", float(atlas_edge))
	material.set_shader_parameter("region_atlas_pages", art)
	material.set_shader_parameter("region_emission_pages", emission)
	material.set_shader_parameter("region_season_pages", seasons)
	material.set_shader_parameter("environment_has_emission", emission != null)
	material.set_shader_parameter("environment_has_seasons", seasons != null)


func bytes() -> int:
	return int(ceil(float(atlas_edge) / EDGE)) ** 2 * EDGE * EDGE * 4 * (1 + int(emission != null) + int(seasons != null))
