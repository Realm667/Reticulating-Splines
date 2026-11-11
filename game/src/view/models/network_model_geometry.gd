class_name NetworkModelGeometry
extends RefCounted
## Display-only network geometry. Coordinates are tiles (u/v), native pixels (z).

const T = preload("res://src/tools/shared/building_tile_ids.gd")
const PORTS := [5, 10, 10, 5, 10, 5, 3, 6, 12, 9, 11, 7, 14, 13, 15]
const STEPS := [Vector2(0,-0.5), Vector2(0.5,0), Vector2(0,0.5), Vector2(-0.5,0)]
const GROUND_ROLES := ["road_surface","ballast_surface","rail","rail_web","tie","tie_side","shoulder","road_edge"]
const POWER_CABLE_HEIGHT := 8.5
const POWER_CABLE_HALF_SPAN := .125

# Geometry templates are independent of sprite IDs and material/tileset names.
# Crossings compose these templates instead of owning another complete model.
const TEMPLATES := ["surface", "cable_network", "portal", "elevated_deck", "ramp", "suspension", "lift_gate", "truss", "crossing", "rubble"]


class Library extends RefCounted:
	## Worker-owned geometry pool. Materials never participate in geometry keys.
	const LIMIT := 256
	var requests: Dictionary = {}
	var meshes: Dictionary = {}
	var builds := 0
	var hits := 0
	var factory: Callable
	var classifier: Callable


	func _init(make_geometry: Callable, classify: Callable) -> void:
		factory=make_geometry
		classifier=classify


	func acquire(id: int, corners := PackedFloat32Array(), flipped := false) -> Dictionary:
		var request_key:=var_to_bytes([id,corners,flipped]).hex_encode()
		if requests.has(request_key):
			hits+=1
			return requests[request_key]
		var data: Dictionary=factory.call(id,corners,flipped)
		var pose_turns := 0
		if data.family=="road" and data.ports in [5,10]:
			var canonical := ""
			var canonical_parts: Array=[]
			for turn in 4:
				var candidate := NetworkModelGeometry.posed_parts(data.parts,turn)
				var candidate_key := geometry_key(candidate)
				if canonical.is_empty() or candidate_key<canonical:
					canonical=candidate_key
					canonical_parts=candidate
					pose_turns=posmod(-turn,4)
			data.parts=canonical_parts
		# Source IDs and tilesets do not own meshes: structurally equal recipes
		# share one immutable model record even when their materials differ.
		var key:=geometry_key(data.parts)
		if not meshes.has(key):
			if meshes.size()>=LIMIT:
				# A complete view contains a bounded set of templates/variants.
				# Published records retain their references if this local pool clears.
				requests.clear()
				meshes.clear()
			meshes[key]={"key":key,"template":classifier.call(data.family),"parts":data.parts}
			builds+=1
		else:
			hits+=1
		var result: Dictionary={"mesh":meshes[key],"ports":data.ports,"footprint":data.footprint,"pose_turns":pose_turns}
		requests[request_key]=result
		return result

	static func geometry_key(parts: Array) -> String:
		var context:=HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		for part: Dictionary in parts:
			context.update(str(part.role).to_utf8_buffer())
			context.update((part.vertices as PackedVector3Array).to_byte_array())
			context.update((part.indices as PackedInt32Array).to_byte_array())
			if part.has("min_view") or part.has("max_view"):
				context.update(var_to_bytes([part.get("min_view",0),part.get("max_view",2)]))
		return context.finish().hex_encode()


static func posed_parts(parts: Array, turns: int) -> Array:
	var result: Array=parts.duplicate(true)
	for part: Dictionary in result:
		var vertices: PackedVector3Array=part.vertices.duplicate()
		for index in vertices.size():
			var p := vertices[index]
			for turn in posmod(turns,4):
				p=Vector3(-p.y,p.x,p.z)
			if is_zero_approx(p.x): p.x=0
			if is_zero_approx(p.y): p.y=0
			vertices[index]=p
		part.vertices=vertices
	return result


static func template(kind: String) -> String:
	match kind:
		"rubble":
			return "rubble"
		"road", "rail":
			return "surface"
		"power", "power_bridge":
			return "cable_network"
		"tunnel", "rail_portal":
			return "portal"
		"road_bridge", "rail_bridge", "highway", "highway_section":
			return "elevated_deck"
		"onramp":
			return "ramp"
		"lift_tower":
			return "lift_gate"
		"suspension":
			return "suspension"
		"highway_bridge":
			return "truss"
		"ground_crossing":
			return "crossing"
	return ""


static func rotate_ports(mask: int, turns: int) -> int:
	for turn in posmod(turns,4):
		mask=((mask<<1)|(mask>>3))&15
	return mask


static func canonical_ports(mask: int) -> Vector2i:
	var smallest:=mask
	var rotation:=0
	for turn in range(1,4):
		var candidate:=rotate_ports(mask,turn)
		if candidate<smallest:
			smallest=candidate
			rotation=turn
	return Vector2i(smallest,rotation)


static func family(id: int) -> String:
	if id in range(T.RUBBLE_1,T.RUBBLE_4+1):
		return "rubble"
	if id >= T.POWER_LINE_STRAIGHT_1 and id <= T.POWER_LINE_CROSSROADS:
		return "power"
	if id >= T.ROAD_STRAIGHT_1 and id <= T.ROAD_CROSSROADS:
		return "road"
	if id >= T.RAIL_STRAIGHT_1 and id <= T.RAIL_SLOPE_8:
		return "rail"
	if id >= T.TUNNEL_ENTRANCE_1 and id <= T.TUNNEL_ENTRANCE_4:
		return "tunnel"
	if id >= T.ROAD_POWER_CROSSING_1 and id <= T.RAIL_POWER_CROSSING_2:
		return "ground_crossing"
	if id >= T.HIGHWAY_STRAIGHT_1 and id <= T.HIGHWAY_POWER_CROSSING_2:
		return "highway"
	if id >= T.SUSPENSION_BRIDGE_1 and id <= T.SUSPENSION_BRIDGE_5:
		return "suspension"
	if id == T.RAISING_BRIDGE_TOWER:
		return "lift_tower"
	if id in [T.ROAD_BRIDGE, T.RAISING_BRIDGE_CLOSED, T.RAISING_BRIDGE_OPEN]:
		return "road_bridge"
	if id in [T.RAIL_BRIDGE, T.RAIL_BRIDGE_PYLON]:
		return "rail_bridge"
	if id == T.POWER_BRIDGE:
		return "power_bridge"
	if id >= T.HIGHWAY_ONRAMP_1 and id <= T.HIGHWAY_ONRAMP_4:
		return "onramp"
	if id >= T.HIGHWAY_SLOPE_1 and id <= T.HIGHWAY_INTERSECTION:
		return "highway_section"
	if id in [T.HIGHWAY_BRIDGE, T.REINFORCED_HIGHWAY_BRIDGE]:
		return "highway_bridge"
	if id >= T.RAIL_SUBWAY_ENTRANCE_1 and id <= T.RAIL_SUBWAY_ENTRANCE_4:
		return "rail_portal"
	return ""


static func project(point: Vector3) -> Vector2:
	return Vector2(16.0 * (point.x - point.y), 8.0 * (point.x + point.y) - point.z)


static func depth(point: Vector3) -> float:
	return point.x + point.y + point.z / 8.0


static func reflect(point: Vector3, water: float) -> Vector3:
	return Vector3(point.x, point.y, 2.0 * water - point.z)


static func surface_height(point: Vector2, corners: PackedFloat32Array) -> float:
	# Corners are NW, NE, SE, SW, identical to the terrain corner contract.
	var u := point.x + 0.5
	var v := point.y + 0.5
	return lerpf(lerpf(corners[0], corners[1], u), lerpf(corners[3], corners[2], u), v)


static func face(parts: Array, role: String, points: PackedVector3Array) -> void:
	assert(points.size() >= 3)
	var triangles := PackedInt32Array()
	for i in range(1, points.size() - 1):
		triangles.append_array(PackedInt32Array([0, i, i + 1]))
	parts.append({"role": role, "vertices": points, "indices": triangles})


static func box(parts: Array, role: String, low: Vector3, high: Vector3) -> void:
	assert(low.x < high.x and low.y < high.y and low.z < high.z)
	var p := PackedVector3Array([
		Vector3(low.x,low.y,low.z), Vector3(high.x,low.y,low.z),
		Vector3(high.x,high.y,low.z), Vector3(low.x,high.y,low.z),
		Vector3(low.x,low.y,high.z), Vector3(high.x,low.y,high.z),
		Vector3(high.x,high.y,high.z), Vector3(low.x,high.y,high.z)])
	for indices in [[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7],[3,2,1,0]]:
		var points := PackedVector3Array()
		for index in indices:
			points.append(p[index])
		face(parts,role,points)


static func slab(parts: Array, role: String, top: PackedVector3Array, thickness := 2.0, open_edges := PackedInt32Array()) -> void:
	face(parts,role,top)
	var bottom:=PackedVector3Array()
	for p in top:
		bottom.append(p-Vector3(0,0,thickness))
	for i in top.size():
		if open_edges.has(i):
			continue
		var j: int=(i+1)%top.size()
		face(parts,role,PackedVector3Array([bottom[i],bottom[j],top[j],top[i]]))


static func strip(parts: Array, role: String, a: Vector3, b: Vector3, width: float) -> void:
	var delta := Vector2(b.x-a.x,b.y-a.y)
	assert(delta.length_squared() > 0.000001)
	var side := Vector2(-delta.y,delta.x).normalized() * width * 0.5
	face(parts,role,PackedVector3Array([
		a+Vector3(side.x,side.y,0),b+Vector3(side.x,side.y,0),
		b-Vector3(side.x,side.y,0),a-Vector3(side.x,side.y,0)]))


static func beam(parts: Array, role: String, a: Vector3, b: Vector3, pixels := 1.05) -> void:
	var delta:=project(b)-project(a)
	if delta.length_squared()<.000001:
		return
	var side:=Vector2(-delta.y,delta.x).normalized()*pixels*.5
	# A thin camera-facing ribbon gives cables a stable native-pixel width.
	var offset:=Vector3(side.x/32,-side.x/32,-side.y)
	face(parts,role,PackedVector3Array([a+offset,b+offset,b-offset,a-offset]))


static func ribbon(parts: Array, role: String, path: PackedVector3Array, width: float) -> void:
	var left:=PackedVector3Array()
	var right:=PackedVector3Array()
	for i in path.size():
		var a: Vector3=path[maxi(0,i-1)]
		var b: Vector3=path[mini(path.size()-1,i+1)]
		var along:=Vector2(b.x-a.x,b.y-a.y).normalized()
		var side:=Vector3(-along.y,along.x,0)*width*.5
		left.append(path[i]+side)
		right.append(path[i]-side)
	for i in range(path.size()-1):
		slab(parts,role,PackedVector3Array([left[i],left[i+1],right[i+1],right[i]]),.8,
			PackedInt32Array([1,3]) if role=="pavement" else PackedInt32Array())


static func portal(parts: Array, scale := 1.0, arched := true) -> void:
	var first:=parts.size()
	if not arched:
		for side in [-1,1]:
			box(parts,"portal_pier",Vector3(side*.40-.08,-.5,0),Vector3(side*.40+.08,.5,10))
		box(parts,"portal_roof",Vector3(-.48,-.5,9),Vector3(.48,.5,12))
		box(parts,"portal_back",Vector3(-.32,-.5,0),Vector3(.32,-.48,9))
		for at in [-.30,-.1,.1,.3]:
			box(parts,"portal_ring",Vector3(-.48,at-.018,11.8),Vector3(.48,at+.018,12.05))
		return
	for side in [-1,1]:
		var x: float=side*.39
		box(parts,"portal_pier",Vector3(x-.09,-.5,0),Vector3(x+.09,.5,6))
	var rear:=PackedVector3Array([Vector3(-.48,-.5,0)])
	for segment in 8:
		var a: float=segment*PI/8
		var b: float=(segment+1)*PI/8
		var outer_a:=Vector3(-.48*cos(a),.5,6+6*sin(a))
		var outer_b:=Vector3(-.48*cos(b),.5,6+6*sin(b))
		var inner_a:=Vector3(-.30*cos(a),.5,6+5*sin(a))
		var inner_b:=Vector3(-.30*cos(b),.5,6+5*sin(b))
		var back:=Vector3(0,-1,0)
		face(parts,"portal_ring",PackedVector3Array([outer_a,outer_b,inner_b,inner_a]))
		face(parts,"portal_roof",PackedVector3Array([outer_b,outer_a,outer_a+back,outer_b+back]))
		face(parts,"portal_vault",PackedVector3Array([inner_a,inner_b,inner_b+back,inner_a+back]))
		rear.append(outer_a+back)
	rear.append(Vector3(.48,-.5,6))
	rear.append(Vector3(.48,-.5,0))
	face(parts,"portal_back",rear)
	for at in [-.40,-.16,.08,.32]:
		for segment in 8:
			var a := segment*PI/8
			var b := (segment+1)*PI/8
			face(parts,"portal_ring",PackedVector3Array([
				Vector3(-.49*cos(a),at-.02,6+6.2*sin(a)),Vector3(-.49*cos(b),at-.02,6+6.2*sin(b)),
				Vector3(-.49*cos(b),at+.02,6+6.2*sin(b)),Vector3(-.49*cos(a),at+.02,6+6.2*sin(a))]))
	for index in range(first,parts.size()):
		var vertices: PackedVector3Array=parts[index].vertices
		for i in vertices.size():
			vertices[i].z*=scale
		parts[index].vertices=vertices
	box(parts,"signal",Vector3(-.375,.505,3.6*scale),Vector3(-.315,.56,5.2*scale))
	box(parts,"signal_go",Vector3(-.375,.505,1.6*scale),Vector3(-.315,.56,3.2*scale))


static func ground_routes(mask: int, corners: PackedFloat32Array, rail: bool) -> Array:
	assert(corners.size() == 4)
	var result: Array = []
	var center := Vector3(0,0,surface_height(Vector2.ZERO,corners))
	var ends: Array[Vector2]=[]
	for direction in 4:
		if mask & (1 << direction):
			ends.append(STEPS[direction])
	var segments: Array=[]
	if ends.size()==2:
		# Original corners use diagonal chords, including the narrow projected
		# horizontal/vertical rail variants. Preserve this deliberate simplification.
		segments.append([ends[0],ends[1]])
	else:
		for edge: Vector2 in ends:
			segments.append([Vector2.ZERO,edge])
	var sleeper_distance := .125
	for segment: Array in segments:
		var first_part := result.size()
		var start: Vector2=segment[0]
		var finish: Vector2=segment[1]
		var a:=Vector3(start.x,start.y,surface_height(start,corners))
		var b:=Vector3(finish.x,finish.y,surface_height(finish,corners))
		var width:=0.62 if rail else 0.88
		if not rail:
			strip(result,"road_surface",a,b,width)
			if mask in [5,10]:
				var direction := (finish-start).normalized()
				var side := Vector3(-direction.y,direction.x,0)
				for sign_value in [-1,1]:
					strip(result,"shoulder",a+side*.465*sign_value+Vector3(0,0,.03),b+side*.465*sign_value+Vector3(0,0,.03),.035)
					strip(result,"road_edge",a+side*.44*sign_value+Vector3(0,0,.06),b+side*.44*sign_value+Vector3(0,0,.06),.025)
		if rail:
			if ends.size()!=2:
				sleeper_distance=.125
			var along := (finish-start).normalized()
			var corner := ends.size()==2 and not is_zero_approx(along.x) and not is_zero_approx(along.y)
			var across := Vector3(-along.y,along.x,0) * (.21*sqrt(.5) if corner else .21)
			# SC2000 leaves terrain visible between individual timber sleepers.
			var length := start.distance_to(finish)
			var pitch := .25*sqrt(.5) if corner else .25
			if corner and is_zero_approx(project(b).x-project(a).x):
				# Preserve SC2000's four-pixel rhythm in the foreshortened turn.
				pitch*=2.0
			var limit := length+.5*sqrt(.5) if corner else length
			if corner:
				sleeper_distance=-.375*sqrt(.5)
				if is_zero_approx(project(b).x-project(a).x) and project(b).y<project(a).y:
					sleeper_distance-=pitch*.5
			while sleeper_distance<limit:
				var p:=a.lerp(b,sleeper_distance/length)+Vector3(0,0,.7)
				var half_tie := Vector3(-along.y,along.x,0)*.25 if corner else across*1.6
				strip(result,"tie",p-half_tie,p+half_tie,.10)
				var top: Dictionary=result.pop_back()
				if corner:
					var outline := PackedVector2Array()
					for vertex: Vector3 in top.vertices:
						outline.append(Vector2(vertex.x,vertex.y))
					var square := PackedVector2Array([Vector2(-.5,-.5),Vector2(.5,-.5),Vector2(.5,.5),Vector2(-.5,.5)])
					for clipped: PackedVector2Array in Geometry2D.intersect_polygons(outline,square):
						var vertices := PackedVector3Array()
						for xy: Vector2 in clipped:
							var t := (xy-start).dot(along)/length
							vertices.append(Vector3(xy.x,xy.y,lerpf(a.z,b.z,t)+.7))
						var first_face := result.size()
						slab(result,"tie",vertices,.7)
						for index in range(first_face+1,result.size()):
							result[index].role="tie_side"
				else:
					slab(result,"tie",top.vertices,.7)
				sleeper_distance+=pitch
			sleeper_distance-=length
			for sign_value in [-1,1]:
				var rail_start: Vector3=a+across*sign_value
				var rail_end: Vector3=b+across*sign_value
				if corner:
					# The offset lines meet the tile edges at the straight track gauge.
					# This lengthens the outside rail and shortens the inside rail.
					var grade := Vector3(along.x,along.y,(b.z-a.z)/length)
					var start_offset := across.x/along.x if absf(start.x)==.5 else across.y/along.y
					var end_offset := across.x/along.x if absf(finish.x)==.5 else across.y/along.y
					rail_start-=grade*start_offset*sign_value
					rail_end-=grade*end_offset*sign_value
				beam(result,"rail_web",rail_start+Vector3(0,0,.8),rail_end+Vector3(0,0,.8),2.0)
				if corner and not is_zero_approx(project(b).x-project(a).x):
					result[-1].max_view=1
				# The original edge-on corner poses have dark heads, with no gray glint.
				var head_role := "rail_web" if is_zero_approx(project(b).x-project(a).x) else "rail"
				beam(result,head_role,rail_start+Vector3(0,0,1.1),rail_end+Vector3(0,0,1.1),.85)
				if corner and head_role=="rail":
					result[-1].max_view=1
					# The source paints the lit front web below the dark running edge.
					var cap := Vector3(.085,.085,1.3)
					beam(result,"rail_web",rail_start+cap,rail_end+cap,1.05)
					result[-1].min_view=2
					var glint := Vector3(.135,.135,1.3)
					beam(result,"rail",rail_start+glint,rail_end+glint,.85)
					result[-1].min_view=2
		# A road or sleeper also follows the grade across its width.
		var along := (finish-start).normalized()
		for part_index in range(first_part,result.size()):
			var vertices: PackedVector3Array=result[part_index].vertices
			for k in vertices.size():
				var p:=vertices[k]
				var xy:=Vector2(p.x,p.y)
				var middle:=start+along*(xy-start).dot(along)
				var rise:=surface_height(xy,corners)-surface_height(middle,corners)
				if absf(rise)>.0001:
					p.z+=rise
				vertices[k]=p
			result[part_index].vertices=vertices
	return result


static func bridge_span(height: float, water: float, tower := false, rail := false) -> Array:
	assert(height > water)
	var parts: Array = []
	if not rail:
		box(parts,"deck",Vector3(-.5,-.5,height-2),Vector3(.5,.5,height))
	for side in [] if rail else [-1,1]:
		var u: float = side * 0.46
		var railing_role := "railing" if tower else "bridge_railing"
		# SC2000 draws a narrow top rail with gaps between the supports.
		var rail_bottom := height if tower else height+1.5
		box(parts,railing_role,Vector3(u-0.02,-0.5,rail_bottom),Vector3(u+0.02,0.5,height+2))
		for at in [-.42,0,.42]:
			box(parts,"railing_post" if tower else railing_role,Vector3(u-.03,at-.025,height),Vector3(u+.03,at+.025,height+2))
	if tower:
		for side in [-1,1]:
			var u: float = side * 0.37
			box(parts,"gate_pier",Vector3(u-0.08,-0.44,water),Vector3(u+0.08,0.44,height+9))
		box(parts,"lintel",Vector3(-0.29,-0.44,height+6),Vector3(0.29,0.44,height+9))
		box(parts,"roof",Vector3(-0.45,-0.44,height+9),Vector3(0.45,0.44,height+10))
		for front in [-.445,.445]:
			box(parts,"masonry_joint",Vector3(-.45,front-.008,height+8.3),Vector3(.45,front+.008,height+8.65))
		for segment in 8:
			var a: float=segment*PI/8
			var b: float=(segment+1)*PI/8
			var left: float=-.30*cos(a)
			var right: float=-.30*cos(b)
			var za: float=height+2+4*sin(a)
			var zb: float=height+2+4*sin(b)
			for v in [-.44,.44]:
				face(parts,"lintel",PackedVector3Array([Vector3(left,v,height+6),Vector3(right,v,height+6),Vector3(right,v,zb),Vector3(left,v,za)]))
			face(parts,"lintel",PackedVector3Array([Vector3(left,-.44,za),Vector3(right,-.44,zb),Vector3(right,.44,zb),Vector3(left,.44,za)]))
	else:
		box(parts,"pier",Vector3(-0.07,-0.10,water),Vector3(0.07,0.10,height-.3 if rail else height-2))
	if rail:
		# Open timber-and-steel construction, with no concrete deck between ties.
		for side in [-1,1]:
			box(parts,"rail_web",Vector3(side*.25-.045,-.5,height+.15),Vector3(side*.25+.045,.5,height+.7))
			strip(parts,"rail",Vector3(side*.25,-.5,height+.85),Vector3(side*.25,.5,height+.85),.11)
		for sleeper in 4:
			var y: float=-.5+(sleeper+.5)/4
			box(parts,"tie",Vector3(-.40,y-.05,height-.35),Vector3(.40,y+.05,height+.25))
	return parts


static func highway_truss(parts: Array, reinforced: bool) -> void:
	# Longitudinal trusses stand at the outside edges and in the median.
	# Pavement has its own material: projected tower pixels are not road texture.
	for lane in [Vector2(-.5,.45),Vector2(.55,1.5)]:
		slab(parts,"pavement",PackedVector3Array([Vector3(lane.x,-1.5,24),Vector3(lane.y,-1.5,24),
			Vector3(lane.y,.5,24),Vector3(lane.x,.5,24)]),2.0,PackedInt32Array([0,2]))
		for dash in 6:
			var v := -1.45+dash*.32
			strip(parts,"road_paint",Vector3((lane.x+lane.y)*.5,v,24.05),Vector3((lane.x+lane.y)*.5,v+.16,24.05),.045)
	for u in [-.48,.5,1.48]:
		beam(parts,"curb",Vector3(u,-1.5,24.2),Vector3(u,.5,24.2),.85)
	var vs := [-1.5,-1.05,.05,.5]
	var zs := [24.0,34.0,34.0,24.0]
	for u in [-.48,.5,1.48]:
		for segment in 3:
			beam(parts,"truss",Vector3(u,vs[segment],zs[segment]),Vector3(u,vs[segment+1],zs[segment+1]),1.8)
		beam(parts,"truss",Vector3(u,-1.5,22.3),Vector3(u,.5,22.3),1.6)
		for v in [-1.05,.05]:
			box(parts,"truss",Vector3(u-.025,v-.035,24),Vector3(u+.025,v+.035,34))
		beam(parts,"truss_hanger",Vector3(u,-.5,24),Vector3(u,-.5,34),.8)
		beam(parts,"truss",Vector3(u,-1.05,24),Vector3(u,.05,34),1.25)
	# Cross-road members stay above the complete vehicle envelope or below deck.
	for v in [-1.05,.05]:
		beam(parts,"truss",Vector3(-.48,v,34),Vector3(1.48,v,34),1.65)
		beam(parts,"truss",Vector3(-.48,v,22.3),Vector3(1.48,v,22.3),1.65)
	beam(parts,"truss",Vector3(-.48,-1.05,34),Vector3(1.48,.05,34),1.3)
	beam(parts,"truss",Vector3(1.48,-1.05,34),Vector3(-.48,.05,34),1.3)
	if not reinforced:
		for u in [0.0,1.0]:
			box(parts,"truss",Vector3(u-.065,-.56,0),Vector3(u+.065,-.44,22))
			box(parts,"pier",Vector3(u-.11,-.61,0),Vector3(u+.11,-.39,.8))


static func highway_details(parts: Array, top: PackedVector3Array, ports: int, low: Vector2, high: Vector2, footprint: int) -> void:
	# The original highway has light curb tops, dark rail faces and spaced posts.
	var along_u := ports==10
	for sign_value in [-1,1]:
		var across := lerpf(low.y,high.y,.02 if sign_value<0 else .98) if along_u else lerpf(low.x,high.x,.04 if sign_value<0 else .96)
		var first := Vector2(low.x,across) if along_u else Vector2(across,low.y)
		var last := Vector2(high.x,across) if along_u else Vector2(across,high.y)
		var a := Vector3(first.x,first.y,deck_height(first,top,low,high))
		var b := Vector3(last.x,last.y,deck_height(last,top,low,high))
		var inset := Vector3(0,-sign_value*.045,0) if along_u else Vector3(-sign_value*.045,0,0)
		beam(parts,"curb",a+inset+Vector3(0,0,.12),b+inset+Vector3(0,0,.12),1.0)
		beam(parts,"guardrail",a+Vector3(0,0,.9),b+Vector3(0,0,.9),1.0)
		for post in footprint*3:
			var p := a.lerp(b,(post+.5)/(footprint*3))
			box(parts,"railing_post",p+Vector3(-.02,-.02,0),p+Vector3(.02,.02,1.0))
	if footprint==2:
		var a := Vector2(low.x,(low.y+high.y)*.5) if along_u else Vector2((low.x+high.x)*.5,low.y)
		var b := Vector2(high.x,a.y) if along_u else Vector2(a.x,high.y)
		beam(parts,"curb",Vector3(a.x,a.y,deck_height(a,top,low,high)+.25),Vector3(b.x,b.y,deck_height(b,top,low,high)+.25),.7)


static func highway_corner(parts: Array, top: PackedVector3Array) -> void:
	# SC2000's corner is two tapered carriageways, separated by open ground.
	# Keep the same three footprint corners and their terrain-derived heights.
	for interval in [Vector2(.04,.44),Vector2(.56,1)]:
		var a := top[1].lerp(top[0],interval.x)
		var b := top[1].lerp(top[2],interval.x)
		var c := top[1].lerp(top[2],interval.y)
		var d := top[1].lerp(top[0],interval.y)
		slab(parts,"pavement",PackedVector3Array([a,b,c,d]),2,PackedInt32Array([1,3]))
		for edge in [[a,b],[d,c]]:
			beam(parts,"guardrail",edge[0]+Vector3(0,0,.9),edge[1]+Vector3(0,0,.9),1.0)
		for radial in [interval.x+.035,interval.y-.035]:
			beam(parts,"curb",top[1].lerp(top[0],radial)+Vector3(0,0,.12),top[1].lerp(top[2],radial)+Vector3(0,0,.12),1.0)
		var first := a.lerp(d,.5)+Vector3(0,0,.05)
		var last := b.lerp(c,.5)+Vector3(0,0,.05)
		for dash in 6:
			strip(parts,"road_paint",first.lerp(last,dash/6.0),first.lerp(last,(dash+.55)/6.0),.045)


static func highway_junction(parts: Array, top: PackedVector3Array, low: Vector2, high: Vector2) -> void:
	var outline := PackedVector3Array()
	for uv: Vector2 in [Vector2(.1,0),Vector2(.9,0),Vector2(1,.1),Vector2(1,.9),
		Vector2(.9,1),Vector2(.1,1),Vector2(0,.9),Vector2(0,.1)]:
		var p := Vector2(lerpf(low.x,high.x,uv.x),lerpf(low.y,high.y,uv.y))
		outline.append(Vector3(p.x,p.y,deck_height(p,top,low,high)))
	slab(parts,"pavement",outline,2,PackedInt32Array([0,1,2,3,4,5,6,7]))
	# The original interchange has three curved dark separators. These are
	# surface inlays, so crossing traffic keeps its established support plane.
	for across in [-.40,.5,1.40]:
		for segment in 8:
			var a := segment/8.0
			var b := (segment+1)/8.0
			var first := Vector2(across+.10*sin(a*PI),lerpf(low.y+.18,high.y-.18,a))
			var last := Vector2(across+.10*sin(b*PI),lerpf(low.y+.18,high.y-.18,b))
			strip(parts,"median_marking",Vector3(first.x,first.y,deck_height(first,top,low,high)+.03),Vector3(last.x,last.y,deck_height(last,top,low,high)+.03),.14)
			beam(parts,"curb",Vector3(first.x-.08,first.y,deck_height(first,top,low,high)+.04),Vector3(last.x-.08,last.y,deck_height(last,top,low,high)+.04),.7)
	highway_paint(parts,top,5,low,high,2)


static func deck_height(point: Vector2, top: PackedVector3Array, low: Vector2, high: Vector2) -> float:
	var u := (point.x-low.x)/(high.x-low.x)
	var v := (point.y-low.y)/(high.y-low.y)
	return lerpf(lerpf(top[0].z,top[1].z,u),lerpf(top[3].z,top[2].z,u),v)


static func highway_paint(parts: Array, top: PackedVector3Array, ports: int, low: Vector2, high: Vector2, footprint: int) -> void:
	# Markings belong to the supporting surface, not the projected sprite silhouette.
	if top.size()==3:
		for lane in [.25,.75]:
			var a := top[1].lerp(top[0],lane)
			var b := top[1].lerp(top[2],lane)
			for dash in 6:
				var t := dash/6.0
				var end := (dash+.5)/6.0
				var first := a*pow(1-t,2)+top[1]*2*t*(1-t)+b*t*t
				var last := a*pow(1-end,2)+top[1]*2*end*(1-end)+b*end*end
				strip(parts,"road_paint",first+Vector3(0,0,.05),last+Vector3(0,0,.05),.045)
		return
	for axis: int in ([5,10] if ports==15 else [ports]):
		var along_u := axis==10
		for lane in footprint:
			var across := lerpf(low.y,high.y,(lane+.5)/footprint) if along_u else lerpf(low.x,high.x,(lane+.5)/footprint)
			for dash in footprint*3:
				var t := (dash+.1)/(footprint*3)
				var end := (dash+.6)/(footprint*3)
				var a := Vector2(lerpf(low.x,high.x,t),across) if along_u else Vector2(across,lerpf(low.y,high.y,t))
				var b := Vector2(lerpf(low.x,high.x,end),across) if along_u else Vector2(across,lerpf(low.y,high.y,end))
				strip(parts,"road_paint",Vector3(a.x,a.y,deck_height(a,top,low,high)+.05),Vector3(b.x,b.y,deck_height(b,top,low,high)+.05),.045)


static func power_routes(mask: int, corners: PackedFloat32Array, pole_height := 12.0, pole_position := Vector2.ZERO) -> Array:
	var parts: Array = []
	var base := surface_height(Vector2.ZERO,corners)
	var attachment_height := minf(pole_height,POWER_CABLE_HEIGHT)
	box(parts,"pole",Vector3(pole_position.x-.045,pole_position.y-.045,base),Vector3(pole_position.x+.045,pole_position.y+.045,base+pole_height))
	if pole_position!=Vector2.ZERO:
		beam(parts,"crossarm",Vector3(pole_position.x,pole_position.y,base+attachment_height),Vector3(0,0,base+attachment_height),1.1)
	# Each cable pair needs a transverse arm at its actual attachment height.
	# Junctions share the mast and carry one arm for each occupied axis.
	if mask & 5:
		box(parts,"crossarm",Vector3(-0.18,-0.025,base+attachment_height-.5),Vector3(0.18,0.025,base+attachment_height))
		for u in [-.125,.125]:
			box(parts,"insulator",Vector3(u-.025,-.025,base+attachment_height-.25),Vector3(u+.025,.025,base+attachment_height+.25))
	if mask & 10:
		box(parts,"crossarm",Vector3(-0.025,-0.18,base+attachment_height-.5),Vector3(0.025,0.18,base+attachment_height))
		for v in [-.125,.125]:
			box(parts,"insulator",Vector3(-.025,v-.025,base+attachment_height-.25),Vector3(.025,v+.025,base+attachment_height+.25))
	for direction in 4:
		if not mask & (1 << direction):
			continue
		var edge: Vector2 = STEPS[direction]
		var across := Vector2(-edge.y,edge.x).normalized() * POWER_CABLE_HALF_SPAN
		for cable in [-1,1]:
			var previous := Vector3(across.x*cable,across.y*cable,base+attachment_height)
			for sample in range(1,5):
				var t := sample/4.0
				var planar: Vector2 = edge*t + across*cable
				var z := lerpf(base,surface_height(edge,corners),t)+attachment_height
				var point := Vector3(planar.x,planar.y,z)
				beam(parts,"cable",previous,point)
				previous=point
	return parts


static func power_crossing(mask: int, corners: PackedFloat32Array) -> Array:
	# Crossing masts stand beside the carried road/track, not in its centre.
	var parts := power_routes(mask,corners,POWER_CABLE_HEIGHT)
	parts=parts.filter(func(part: Dictionary) -> bool:return part.role=="cable")
	for direction in 4:
		if not mask&(1<<direction):
			continue
		var p: Vector2=STEPS[direction]*.96
		var z := surface_height(p,corners)
		box(parts,"pole",Vector3(p.x-.025,p.y-.025,z),Vector3(p.x+.025,p.y+.025,z+POWER_CABLE_HEIGHT))
		var across := Vector2(-p.y,p.x).normalized()*.18
		beam(parts,"crossarm",Vector3(p.x-across.x,p.y-across.y,z+POWER_CABLE_HEIGHT),Vector3(p.x+across.x,p.y+across.y,z+POWER_CABLE_HEIGHT),1.0)
	return parts


static func rubble(id: int, corners: PackedFloat32Array) -> Array:
	# One pile recipe, four quarter-turn poses. SC2000 debris is predominantly
	# broken brown timbers with scattered gray masonry, rather than gray gravel.
	var centers: Array[Vector2] = [
		Vector2(-.30,-.10),Vector2(-.21,.14),Vector2(-.12,-.24),Vector2(.02,-.30),
		Vector2(.22,-.17),Vector2(.31,.03),Vector2(.20,.23),Vector2(-.02,.30),
		Vector2(-.26,.27),Vector2(-.33,.06),Vector2(.09,-.13),Vector2(-.10,.04),
		Vector2(.08,.13),Vector2(-.05,-.11),Vector2(.23,.05),Vector2(-.13,.20),
		Vector2(.28,-.29),Vector2(-.29,-.27),Vector2(.04,.02)]
	var parts: Array=[]
	var turn := (id-T.RUBBLE_1)*PI*.5
	# Loose dark debris closes the pile below the distinct rigid fragments.
	var rim := PackedVector3Array()
	for p: Vector2 in [Vector2(-.48,-.48),Vector2(0,-.5),Vector2(.48,-.48),Vector2(.5,0),
		Vector2(.48,.48),Vector2(0,.5),Vector2(-.48,.48),Vector2(-.5,0)]:
		rim.append(Vector3(p.x,p.y,rubble_ground(p,corners)+.12))
	var summit := Vector3(0,0,rubble_ground(Vector2.ZERO,corners)+1.9)
	for step in 8:
		face(parts,"rubble_dark",PackedVector3Array([rim[step],rim[(step+1)%8],summit]))
	for index in centers.size():
		var center := centers[index].rotated(turn)*1.15
		var fragment: Array=[]
		if index==centers.size()-1:
			box(fragment,"rubble_timber",Vector3(-.02,-.02,0),Vector3(.02,.02,2.7))
		elif index%3!=0:
			var length := .18+(index%4)*.03
			box(fragment,"rubble_timber",Vector3(-length*.5,-.028,0),Vector3(length*.5,.028,.65))
			for end in [-1,1]:
				var x: float = end*(length*.5+.0001)
				face(fragment,"rubble_cut",PackedVector3Array([
					Vector3(x,-.028,0),Vector3(x,.028,0),Vector3(x,.028,.65),Vector3(x,-.028,.65)]))
		else:
			var radius := .044+(index%4)*.007
			var height := .95+(index%4)*.2
			var points := PackedVector3Array([
				Vector3(-radius,-radius,0),Vector3(radius,-radius,0),
				Vector3(radius,radius,0),Vector3(-radius,radius,0),
				Vector3(-radius*.8,-radius*.7,height*.72),Vector3(radius*.65,-radius*.8,height),
				Vector3(radius*.9,radius*.8,height*.82),Vector3(-radius*.65,radius*.9,height*.66)])
			for indices in [[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]:
				var polygon := PackedVector3Array()
				for vertex in indices:
					polygon.append(points[vertex])
				face(fragment,"rubble_stone",polygon)
		var yaw := turn+(index%4)*PI*.25
		var u := center.x+.5
		var v := center.y+.5
		# Same two terrain triangles as the native patch. Each fragment uses a
		# rigid orthonormal frame resting on its own supporting terrain plane.
		var gx := (corners[1]-corners[0]) if u>=v else (corners[2]-corners[3])
		var gy := (corners[2]-corners[1]) if u>=v else (corners[3]-corners[0])
		var ground := rubble_ground(center,corners)
		var normal := Vector3(-gx/32.0,-gy/32.0,1).normalized()
		var along := Vector3(cos(yaw),sin(yaw),(gx*cos(yaw)+gy*sin(yaw))/32.0).normalized()
		var across := normal.cross(along).normalized()
		var pile := maxf(0.0,1.7*(1.0-center.length_squared()/.20))
		for part: Dictionary in fragment:
			for k in part.vertices.size():
				var local: Vector3=part.vertices[k]
				var physical := along*local.x*32.0+across*local.y*32.0+normal*local.z
				part.vertices[k]=Vector3(center.x+physical.x/32.0,center.y+physical.y/32.0,ground+pile+physical.z)
		parts.append_array(fragment)
	return parts


static func rubble_ground(point: Vector2, corners: PackedFloat32Array) -> float:
	var u := point.x+.5
	var v := point.y+.5
	return corners[0]*(1-u)+corners[1]*(u-v)+corners[2]*v if u>=v else corners[0]*(1-v)+corners[2]*u+corners[3]*(v-u)


static func build(id: int, corners := PackedFloat32Array(), flipped := false) -> Dictionary:
	if corners.is_empty():
		corners=profile(id)
	var kind := family(id)
	var parts: Array = []
	var mask := 5
	var footprint := 1
	match kind:
		"rubble":
			mask=0
			parts=rubble(id,corners)
		"road", "rail", "power":
			var first: int = T.ROAD_STRAIGHT_1 if kind=="road" else (T.RAIL_STRAIGHT_1 if kind=="rail" else T.POWER_LINE_STRAIGHT_1)
			mask=PORTS[id-first] if id-first<PORTS.size() else (10 if (id-first)%2 else 5)
			parts=power_routes(mask,corners) if kind=="power" else ground_routes(mask,corners,kind=="rail")
			if kind=="rail" and id in range(T.RAIL_SLOPE_5,T.RAIL_SLOPE_8+1):
				for direction in 4:
					if not mask&(1<<direction):
						continue
					var p: Vector2=STEPS[direction]*.82
					var across := Vector2(-p.y,p.x).normalized()*.25
					for side in [-1,1]:
						var at: Vector2=p+across*side
						var z := surface_height(at,corners)
						beam(parts,"rail_web",Vector3(at.x,at.y,z-2),Vector3(at.x,at.y,z+.8),.8)
			if kind=="road" and id>=T.ROAD_JUNCTION_1:
				for p in [Vector2(.43,-.43),Vector2(-.43,.43)]:
					box(parts,"signal_pole",Vector3(p.x-.02,p.y-.02,0),Vector3(p.x+.02,p.y+.02,5))
					box(parts,"signal",Vector3(p.x-.04,p.y-.04,5),Vector3(p.x+.04,p.y+.04,6))
		"ground_crossing":
			var first_axis := 5 if (id-T.ROAD_POWER_CROSSING_1)%2==0 else 10
			mask=15
			if id<=T.ROAD_POWER_CROSSING_2:
				parts=ground_routes(first_axis,corners,false)
				parts.append_array(power_crossing(15^first_axis,corners))
			elif id<=T.ROAD_RAIL_CROSSING_2:
				parts=ground_routes(first_axis,corners,false)
				parts.append_array(ground_routes(15^first_axis,corners,true))
			else:
				parts=ground_routes(first_axis,corners,true)
				parts.append_array(power_crossing(15^first_axis,corners))
		"road_bridge", "lift_tower", "rail_bridge":
			parts=bridge_span(12,0,kind=="lift_tower",kind=="rail_bridge")
			if id in [T.RAISING_BRIDGE_CLOSED,T.RAISING_BRIDGE_OPEN,T.RAIL_BRIDGE_PYLON]:
				parts=parts.filter(func(p: Dictionary) -> bool:return p.role!="pier")
			# SC2000 lifts the same horizontal span by one level; it does not tilt.
			if id == T.RAISING_BRIDGE_OPEN:
				for part: Dictionary in parts:
					for i in part.vertices.size():
						part.vertices[i].z += 12.0
		"suspension":
			parts=bridge_span(12,0,false,false)
			# Replace the generic under-deck support with the family-specific tower.
			parts=parts.filter(func(p: Dictionary) -> bool:return p.role!="pier")
			var piece := id-T.SUSPENSION_BRIDGE_1
			# SC2000's repeating five-piece cable rises toward the tower, then
			# descends across three pieces. Adjacent edge heights are identical.
			var heights := [14.0,34.0,54.0,42.0,30.0,14.0]
			for side in [-1,1]:
				var u: float = side*0.38
				var a:=Vector3(u,-0.5,heights[piece+1])
				var b:=Vector3(u,0.5,heights[piece])
				beam(parts,"suspension_cable",a,b,2.0)
				for step in range(1,5):
					var p:=a.lerp(b,step/5.0)
					# Vertical ribbons are oriented in the transverse plane, not zero-area strips.
					beam(parts,"hanger",p,Vector3(p.x,p.y,12))
				if piece==2:
					box(parts,"tower",Vector3(u-.06,-.08,0),Vector3(u+.06,.08,54))
			if piece==2:
				box(parts,"tower_beam",Vector3(-.44,-.08,51),Vector3(.44,.08,54))
				box(parts,"tower_beam",Vector3(-.38,-.08,30),Vector3(.38,.08,32))
				beam(parts,"tower_brace",Vector3(-.34,-.085,33),Vector3(.34,-.085,50),.7)
		"power_bridge":
			for side in [-1,1]:
				beam(parts,"cable",Vector3(side*POWER_CABLE_HALF_SPAN,-.5,12+POWER_CABLE_HEIGHT),Vector3(side*POWER_CABLE_HALF_SPAN,.5,12+POWER_CABLE_HEIGHT))
		"highway", "highway_bridge", "highway_section":
			footprint=2 if kind!="highway" else 1
			mask = (5 if id % 2 else 10) if kind == "highway" else (10 if id % 2 else 5)
			var low:=Vector2(-.5,-.5 if footprint==1 else -1.5)
			var high:=Vector2(.5 if footprint==1 else 1.5,.5)
			var top:=PackedVector3Array([
				Vector3(low.x,low.y,12+corners[0]),Vector3(high.x,low.y,12+corners[1]),
				Vector3(high.x,high.y,12+corners[2]),Vector3(low.x,high.y,12+corners[3])])
			var open_edges := PackedInt32Array([0,2] if mask==5 else [1,3])
			if id>=T.HIGHWAY_CURVE_1 and id<=T.HIGHWAY_CURVE_4:
				var turn:=id-T.HIGHWAY_CURVE_1
				top=PackedVector3Array([top[turn%4],top[(turn+1)%4],top[(turn+2)%4]])
				open_edges=PackedInt32Array([0,1])
			elif id==T.HIGHWAY_INTERSECTION:
				open_edges=PackedInt32Array([0,1,2,3])
			if kind=="highway_bridge":
				highway_truss(parts,id==T.REINFORCED_HIGHWAY_BRIDGE)
			elif id==T.HIGHWAY_INTERSECTION:
				highway_junction(parts,top,low,high)
			elif top.size()==3:
				highway_corner(parts,top)
			elif id>=T.HIGHWAY_SLOPE_1 and id<=T.HIGHWAY_SLOPE_4:
				var along_u: bool=(id-T.HIGHWAY_SLOPE_1)%2==0
				for interval in [Vector2(0,.44),Vector2(.56,1)]:
					var lane:=PackedVector3Array()
					if along_u:
						lane=PackedVector3Array([top[0].lerp(top[3],interval.x),top[1].lerp(top[2],interval.x),top[1].lerp(top[2],interval.y),top[0].lerp(top[3],interval.y)])
					else:
						lane=PackedVector3Array([top[0].lerp(top[1],interval.x),top[0].lerp(top[1],interval.y),top[3].lerp(top[2],interval.y),top[3].lerp(top[2],interval.x)])
					slab(parts,"pavement",lane,2.0,open_edges)
			else:
				slab(parts,"pavement",top,2.0,open_edges)
			if kind!="highway_bridge" and top.size()!=3 and id!=T.HIGHWAY_INTERSECTION:
				highway_paint(parts,top,15 if id==T.HIGHWAY_INTERSECTION else mask,low,high,footprint)
			if kind=="highway" or id<=T.HIGHWAY_SLOPE_4:
				highway_details(parts,top,mask,low,high,footprint)
			if id in [T.HIGHWAY_STRAIGHT_1,T.HIGHWAY_STRAIGHT_2]:
				box(parts,"support",Vector3(-.04,-.04,0),Vector3(.04,.04,10))
			elif kind!="highway_bridge":
				for index in ([0,1,2,3] if id==T.HIGHWAY_INTERSECTION else [0,2]):
					var p: Vector3=top[index]
					var x:=lerpf(p.x,(low.x+high.x)*.5,.10)
					var y:=lerpf(p.y,(low.y+high.y)*.5,.10)
					box(parts,"support",Vector3(x-.025,y-.025,p.z-12),Vector3(x+.025,y+.025,p.z-2))
			if id in [T.HIGHWAY_ROAD_CROSSING_1,T.HIGHWAY_ROAD_CROSSING_2,T.HIGHWAY_RAIL_CROSSING_1,T.HIGHWAY_RAIL_CROSSING_2]:
				mask=15
				parts.append_array(ground_routes(10 if id%2 else 5,corners,id>=T.HIGHWAY_RAIL_CROSSING_1))
			elif id in [T.HIGHWAY_POWER_CROSSING_1,T.HIGHWAY_POWER_CROSSING_2]:
				parts.append_array(power_crossing(10 if id%2 else 5,corners))
		"onramp":
			var quarter:=id-T.HIGHWAY_ONRAMP_1
			var highway: int=[0,0,2,2][quarter]
			var road: int=[1,3,3,1][quarter]
			mask=(1<<highway)|(1<<road)
			var a: Vector2=STEPS[road]
			var b: Vector2=STEPS[highway]
			var c:=a-a.normalized()*.32
			var d:=b-b.normalized()*.32
			var path:=PackedVector3Array([Vector3(a.x,a.y,0)])
			for step in range(1,9):
				var t:=step/8.0
				var p: Vector2=a*pow(1-t,3)+c*3*t*pow(1-t,2)+d*3*t*t*(1-t)+b*pow(t,3)
				var next:=Vector3(p.x,p.y,t*12)
				path.append(next)
			ribbon(parts,"pavement",path,.65)
			var outside := signf(a.cross(b))
			for step in range(path.size()-1):
				var p: Vector3=path[step]
				var q: Vector3=path[step+1]
				var direction := Vector2(q.x-p.x,q.y-p.y).normalized()
				var side := Vector3(-direction.y,direction.x,0)
				beam(parts,"guardrail",p+side*.325*outside+Vector3(0,0,.9),q+side*.325*outside+Vector3(0,0,.9),1.0)
				for edge in [-1,1]:
					beam(parts,"curb",p+side*.29*edge+Vector3(0,0,.12),q+side*.29*edge+Vector3(0,0,.12),.75)
			for dash in range(0,path.size()-1,2):
				strip(parts,"road_paint",path[dash]+Vector3(0,0,.05),path[dash+1]+Vector3(0,0,.05),.045)
		"tunnel", "rail_portal":
			parts=ground_routes(5,corners,kind=="rail_portal")
			portal(parts,.5 if kind=="rail_portal" else 1,kind=="rail_portal")
			var turn: int=[3,0,1,2][(id-(T.TUNNEL_ENTRANCE_1 if kind=="tunnel" else T.RAIL_SUBWAY_ENTRANCE_1))%4]
			for part in parts:
				for i in part.vertices.size():
					var p: Vector3=part.vertices[i]
					var original:=Vector2(p.x,p.y)
					for rotation in turn:
						p=Vector3(-p.y,p.x,p.z)
					if part.role in GROUND_ROLES:
						p.z+=surface_height(Vector2(p.x,p.y),corners)-surface_height(original,corners)
					part.vertices[i]=p
	# Posts and portal/ramp shells inherit their actual mounting elevation.
	for part: Dictionary in parts:
		if kind=="highway" and part.role=="support":
			for i in part.vertices.size():
				part.vertices[i].z+=surface_height(Vector2.ZERO,corners)
		if part.role in ["signal_pole","signal"] or kind in ["onramp","tunnel","rail_portal"]:
			if part.role in GROUND_ROLES:
				continue
			for i in part.vertices.size():
				var p: Vector3=part.vertices[i]
				p.z+=surface_height(Vector2(p.x,p.y),corners)
				part.vertices[i]=p
	if flipped:
		for part in parts:
			for i in part.vertices.size():
				var p: Vector3=part.vertices[i]
				part.vertices[i]=Vector3(p.y+footprint-1,p.x-footprint+1,p.z)
	return {"family":kind,"parts":parts,"ports":mask,"footprint":footprint}


static func profile(id: int) -> PackedFloat32Array:
	var shape:=0
	for first in [T.POWER_LINE_SLOPE_1,T.ROAD_SLOPE_1,T.RAIL_SLOPE_1,T.RAIL_SLOPE_5,T.HIGHWAY_SLOPE_1]:
		if id>=first and id<first+4:
			shape=id-first+1
	var masks: Array=[0,9,3,6,12]
	var heights:=PackedFloat32Array()
	for i in 4:
		heights.append(12.0 if int(masks[shape])&(1<<i) else 0.0)
	return heights
