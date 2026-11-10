class_name NetworkModelRaster
extends RefCounted
## Native indexed raster from spatial components. No subpixel filtering or lighting passes.
@warning_ignore_start("integer_division")
const Geometry = preload("res://src/view/models/network_model_geometry.gd")
const RUBBLE_SHADES := {
	"rubble_timber":["735323","7b5f2b","431f07"],
	"rubble_cut":["8f8f8f","ababab","575757"],
	"rubble_stone":["8f8f8f","ababab","575757"],
	"rubble_dark":["431f07","5f3b13","000000"]}

static func nearest(palette: Sc2Palette, color: Color) -> int:
	var best:=0
	var distance:=INF
	for i in 256:
		var c:=palette.color(i)
		var d:=Vector3(c.r-color.r,c.g-color.g,c.b-color.b).length_squared()
		if d<distance:
			distance=d
			best=i
	return best


static func materials(palette: Sc2Palette, id: int) -> Dictionary:
	var base:=palette.color(161)
	var metal:=Color("670700") if id in range(81,86) or id in [106,107] else base
	var colors: Dictionary={
		"rubble_timber":Color("836333"),"rubble_cut":Color("b39b6b"),
		"rubble_stone":Color("77776b"),"rubble_dark":Color("332b1b"),
		"surface":base,"deck":base,"railing":Color("505050"),"pier":base,
		"pole":Color("101010"),"crossarm":Color("282828"),"cable":Color("101010"),
		"rail":Color("b7b7b7"),"rail_web":Color("282828"),"ballast":Color("101010"),"tie":Color("470000"),
		"shoulder":Color("9b8747"),"road_edge":Color("202020"),"insulator":Color("9f9f9f"),
		"curb":Color("b7b7b7"),"guardrail":Color("202020"),"railing_post":Color("b7b7b7"),
		"masonry_joint":Color("777777"),"tower_brace":Color("470000"),
		"road_paint":Color("b7b7b7"),"truss_hanger":Color("777777"),
		"portal":base,"truss":metal,"tower":metal,"tower_beam":metal,
		"suspension_cable":Color("282828"),"hanger":metal,"roof":base,"lintel":base,
		"ramp":base,"support":base,"signal_pole":Color("383838"),"signal":Color("d02020"),
		"portal_back":Color("202020"),"portal_vault":Color("383838"),"ramp_ground":Color("9b8747")}
	var result: Dictionary={}
	for role: String in colors:
		var c: Color=colors[role]
		result[role]=PackedInt32Array([nearest(palette,c),nearest(palette,c.lightened(.22)),nearest(palette,c.darkened(.25))])
		if role in ["pole","crossarm","cable","ballast"]:
			result[role].fill(nearest(palette,c))
	# Original SC2000 rubble is dominated by this dark brown ramp, with gray
	# broken ends and masonry. Generic lightening made the pile too olive/gray.
	for role: String in RUBBLE_SHADES:
		var shades: Array = RUBBLE_SHADES[role]
		result[role]=PackedInt32Array([nearest(palette,Color(shades[0])),nearest(palette,Color(shades[1])),nearest(palette,Color(shades[2]))])
	if id in range(81,86):
		# The SC2000 suspension towers use a brighter orange-red ramp than
		# the dark red highway truss and rail sleepers.
		for role in ["tower","tower_beam","hanger"]:
			result[role]=PackedInt32Array([nearest(palette,Color("972713")),
				nearest(palette,Color("c7572b")),nearest(palette,Color("7f1707"))])
	if id in [106,107]:
		result.truss=PackedInt32Array([nearest(palette,Color("670700")),
			nearest(palette,Color("972713")),nearest(palette,Color("7f1707"))])
	return result


static func render(id: int, source: Image, palette: Sc2Palette, view := 2, prepared := {}) -> Dictionary:
	if view < 2:
		return reduced(id, source, palette, view, prepared)
	var recipe: Dictionary=Geometry.build(id) if prepared.is_empty() else prepared
	var divisor: int=4>>view
	# Geometry IDs are logical XBLD values. Rendering uses large-view units.
	id=posmod(id,500)
	var extent:=source.get_size()
	var low:=0.0
	for part: Dictionary in recipe.parts:
		for p: Vector3 in part.vertices:
			var q:=Geometry.project(p)/divisor
			low=minf(low,q.y)
	var baseline:=ceili(float(recipe.get("baseline",17.0 if recipe.footprint==2 else 9.0))/divisor)
	var height:=maxi(extent.y,ceili(baseline-low))
	var width:=32*int(recipe.footprint)/divisor
	var pixels:=PackedInt32Array()
	pixels.resize(width*height)
	pixels.fill(-1)
	var depths:=PackedFloat32Array()
	depths.resize(width*height)
	depths.fill(-INF)
	var z_values:=PackedFloat32Array()
	z_values.resize(width*height)
	z_values.fill(NAN)
	var roles:=PackedByteArray()
	roles.resize(width*height)
	var colors: Dictionary=recipe.materials if recipe.has("materials") else materials(palette,id)
	var source_indices: Dictionary={}
	for i in 256:
		var c:=palette.color(i).to_rgba32()
		if not source_indices.has(c):
			source_indices[c]=i
	var origin:=Vector2(float(recipe.get("origin_x",16.0))/divisor,height-baseline)
	var texture_shift:=Vector2i(0,extent.y-height)
	for part: Dictionary in recipe.parts:
		var vertices: PackedVector3Array=part.vertices
		var indices: PackedInt32Array=part.indices
		var role: String=part.role
		var material_role:=role
		if role in ["road_surface","pavement"]:
			material_role="surface"
		if role in ["ballast_surface"]:
			material_role="ballast"
		if role.begins_with("pier"):
			material_role="pier"
		if role.begins_with("portal"):
			material_role="portal"
		if role in ["portal_back","portal_vault"]:
			material_role=role
		var swatch: PackedInt32Array=colors.get(material_role,colors.deck)
		for at in range(0,indices.size(),3):
			var a:=vertices[indices[at]]
			var b:=vertices[indices[at+1]]
			var c:=vertices[indices[at+2]]
			var p:=Geometry.project(a)/divisor+origin
			var q:=Geometry.project(b)/divisor+origin
			var r:=Geometry.project(c)/divisor+origin
			var den: float=(q.y-r.y)*(p.x-r.x)+(r.x-q.x)*(p.y-r.y)
			if absf(den)<.00001:
				continue
			var normal: Vector3=(b-a).cross(c-a).normalized()
			var tone:=1 if normal.x>.25 else (2 if normal.y>.25 else 0)
			for y in range(maxi(0,floori(minf(p.y,minf(q.y,r.y)))),mini(height,ceili(maxf(p.y,maxf(q.y,r.y))))):
				for x in range(maxi(0,floori(minf(p.x,minf(q.x,r.x)))),mini(width,ceili(maxf(p.x,maxf(q.x,r.x))))):
					var point:=Vector2(x+.5,y+.5)
					var u: float=((q.y-r.y)*(point.x-r.x)+(r.x-q.x)*(point.y-r.y))/den
					var v: float=((r.y-p.y)*(point.x-r.x)+(p.x-r.x)*(point.y-r.y))/den
					var w:=1-u-v
					if minf(u,minf(v,w))<-.0001:
						continue
					var world: Vector3=a*u+b*v+c*w
					if role=="rotor_blur" and (x+y)%2==0:
						continue
					if role in ["road_surface","ballast_surface","ramp"] and (world.x<-.5 or world.x>.5 or world.y<-.5 or world.y>.5):
						continue
					var d: float=Geometry.depth(world)
					var i:=y*width+x
					if d<depths[i]-.0001:
						continue
					var index:=int(swatch[tone])
					if role=="rotor_blur":
						index=200+posmod(x*5+y*3,12)
					if absf(normal.z)>.001 and role in ["road_surface","deck","ramp"]:
						index=road_marking(world,recipe.ports,id,index,palette)
					# Authored markings are sampled only on supporting surfaces. Solid
					# structural faces do not inherit transparent holes from sprite art.
					var ty:=y+texture_shift.y
					if absf(normal.z)>.001 and role in ["road_surface","ballast_surface","deck","ramp"] and x<extent.x and ty>=0 and ty<extent.y:
						var authored:=source.get_pixel(x,ty)
						if authored.a>.5 and source_indices.has(authored.to_rgba32()):
							index=source_indices[authored.to_rgba32()]
					depths[i]=d
					z_values[i]=maxf(0,world.z/divisor)
					pixels[i]=index
					roles[i]=1 if role in ["road_surface","ballast_surface","deck","ramp","pavement","ballast"] else 2
					if role in ["headlamp","taillamp","beacon"]:
						roles[i]=3+["headlamp","taillamp","beacon"].find(role)
	var entry:=Sc2SpriteArchive.entry_from_indices(id+1000,width,height,pixels)
	return {"entry":entry,"image":entry.create_image(palette).image,"depth":depths,"height":z_values,"roles":roles,"recipe":recipe}


static func road_marking(point: Vector3, ports: int, id: int, base: int, palette: Sc2Palette) -> int:
	# Native SC2000-style center dashes for sets without admitted original art.
	# This is evaluated only while preparing the small indexed model raster.
	if ports not in [5,10] or id in [90,91,92]:
		return base
	var transverse := point.x if ports == 5 else point.y
	var along := point.y if ports == 5 else point.x
	if absf(transverse) < .025 and fposmod(along+.5,.32) < .18:
		return nearest(palette,Color("d8d8b8"))
	return base


static func reduced(id: int, source: Image, palette: Sc2Palette, view: int, prepared: Dictionary) -> Dictionary:
	# Raster at the design resolution, then select one indexed sample per native
	# texel. Coverage preserves thin rails/cables without introducing blended pixels.
	var divisor := 4 >> view
	var material: Image = source.duplicate()
	material.resize(source.get_width()*divisor, source.get_height()*divisor, Image.INTERPOLATE_NEAREST)
	var full := render(id, material, palette, 2, prepared)
	var original: Sc2SpriteArchive.SpriteEntry = full.entry
	var width := original.width / divisor
	var height := ceili(float(original.height) / divisor)
	var offset := height*divisor-original.height
	var indices := original.decode_indices().pixels
	var pixels := PackedInt32Array()
	pixels.resize(width*height)
	pixels.fill(-1)
	var heights := PackedFloat32Array()
	heights.resize(pixels.size())
	heights.fill(NAN)
	for y in height:
		for x in width:
			var closest := INF
			for sy in divisor:
				var row := y*divisor+sy-offset
				if row < 0 or row >= original.height:
					continue
				for sx in divisor:
					var at := row*original.width+x*divisor+sx
					var distance := Vector2(sx+.5-divisor*.5,sy+.5-divisor*.5).length_squared()
					if indices[at] >= 0 and distance < closest:
						closest = distance
						pixels[y*width+x] = indices[at]
						heights[y*width+x] = full.height[at]/divisor
	var entry := Sc2SpriteArchive.entry_from_indices(id+view*500,width,height,pixels)
	return {"entry":entry,"image":entry.create_image(palette).image,"height":heights}
