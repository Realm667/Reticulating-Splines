class_name QuarterTerrain
extends RefCounted
## Saved corner geometry. Local Models preferences never determine build rules.
@warning_ignore_start("integer_division")

const FEATURE := "rs.quarter-terrain.v1"
const HEADER := 16
const EDGES := [[0,1],[1,2],[2,3],[3,0]]
const STEPS := [1,2,4,8]
const GRADES := [2,4,8,0]


static func enabled(document: Sc2File) -> bool:
	return document != null and document.find_chunk("XQTR") != null


static func enable(city: CityState) -> String:
	if city == null or not ExpandedRules.enabled(city.document):
		return "Quarter-height terrain requires Expanded rules."
	if enabled(city.document):
		return ""
	var data := PackedByteArray()
	data.resize(HEADER+city.map_size*city.map_size*8)
	data[0]=81
	data[1]=84
	data[2]=82
	data[3]=49
	data[4]=city.map_size>>8
	data[5]=city.map_size&255
	data[6]=1
	data[7]=4
	for i in city.map_size*city.map_size:
		var base: int=(city.altitude_words[i]&31)*4
		var mask: int=IsometricConstants.TERRAIN_SURFACE_CORNER_MASKS[city.terrain[i]&15] if (city.terrain[i]&15)<15 else 0
		for k in 4:
			var q:=base+(4 if mask&(1<<k) else 0)
			data[HEADER+i*8+k*2]=q>>8
			data[HEADER+i*8+k*2+1]=q&255
	var chunk:=Sc2Chunk.new()
	chunk.chunk_id="XQTR"
	chunk.set_decoded_payload(data)
	city.document.chunks.append(chunk)
	city.document.invalidate_chunk_cache()
	city.document.sc2x_metadata.required_features.append(FEATURE)
	city.resync_mirrors(PackedStringArray(["XQTR"]))
	return ""


static func reset_from_legacy(document: Sc2File) -> void:
	if not enabled(document):
		return
	var chunk:=document.find_chunk("XQTR")
	var data:=chunk.decoded_payload.duplicate()
	var altitude:=NativeCityArrays.altitude_words(document.find_chunk("ALTM").decoded_payload)
	var terrain:=document.find_chunk("XTER").decoded_payload
	for i in document.map_size*document.map_size:
		var mask: int=IsometricConstants.TERRAIN_SURFACE_CORNER_MASKS[terrain[i]&15] if (terrain[i]&15)<15 else 0
		for k in 4:
			var q: int=(altitude[i]&31)*4+(4 if mask&(1<<k) else 0)
			data[HEADER+i*8+k*2]=q>>8
			data[HEADER+i*8+k*2+1]=q&255
	data[8]=0
	chunk.set_decoded_payload(data)


static func configure(city: CityState,step: int,grade: int) -> void:
	if not enabled(city.document) or step not in STEPS or grade not in GRADES:
		return
	var chunk:=city.document.find_chunk("XQTR")
	var data:=chunk.decoded_payload.duplicate()
	data[6]=step
	data[7]=grade
	chunk.set_decoded_payload(data)


static func height(city: CityState,tile: Vector2i,local:=Vector2.ZERO) -> float:
	var i:=city.index_of(tile.x,tile.y)
	if i<0:
		return 0.0
	if city.quarter_heights.is_empty():
		return city.land_altitude(tile.x,tile.y)
	var p:=i*4
	var u:=local.x+.5
	var v:=local.y+.5
	return lerpf(lerpf(city.quarter_heights[p],city.quarter_heights[p+1],u),
		lerpf(city.quarter_heights[p+3],city.quarter_heights[p+2],u),v)/4.0


static func edge_height(city: CityState,tile: Vector2i,direction: int) -> float:
	var step: Vector2=CityLifePaths.DIRECTIONS[direction]
	return height(city,tile,step*.5)


static func base_q(city: CityState,tile: Vector2i) -> int:
	var i:=city.index_of(tile.x,tile.y)
	if i<0:
		return 0
	if city.quarter_heights.is_empty():
		return city.land_altitude(tile.x,tile.y)*4
	return mini(mini(city.quarter_heights[i*4],city.quarter_heights[i*4+1]),mini(city.quarter_heights[i*4+2],city.quarter_heights[i*4+3]))
