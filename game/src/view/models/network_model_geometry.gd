class_name NetworkModelGeometry
extends RefCounted
## Display-only network geometry. Coordinates are tiles (u/v), native pixels (z).

const T = preload("res://src/tools/shared/building_tile_ids.gd")
const PORTS := [5, 10, 10, 5, 10, 5, 3, 6, 12, 9, 11, 7, 14, 13, 15]
const STEPS := [Vector2(0,-0.5), Vector2(0.5,0), Vector2(0,0.5), Vector2(-0.5,0)]
const GROUND_ROLES := ["road_surface","ballast_surface","rail","rail_web","tie","shoulder","road_edge"]

# Geometry templates are independent of sprite IDs and material/tileset names.
# Crossings compose these templates instead of owning another complete model.
const TEMPLATES := ["surface", "cable_network", "portal", "elevated_deck", "ramp", "suspension", "lift_gate", "truss", "crossing"]


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
		# Source IDs and tilesets do not own meshes: structurally equal recipes
		# share one immutable model record even when their materials differ.
		var context:=HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		for part: Dictionary in data.parts:
			context.update(str(part.role).to_utf8_buffer())
			context.update((part.vertices as PackedVector3Array).to_byte_array())
			context.update((part.indices as PackedInt32Array).to_byte_array())
		var key:=context.finish().hex_encode()
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
		var result: Dictionary={"mesh":meshes[key],"ports":data.ports,"footprint":data.footprint}
		requests[request_key]=result
		return result


static func template(kind: String) -> String:
	match kind:
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


static func slab(parts: Array, role: String, top: PackedVector3Array, thickness := 2.0) -> void:
	face(parts,role,top)
	var bottom:=PackedVector3Array()
	for p in top:
		bottom.append(p-Vector3(0,0,thickness))
	for i in top.size():
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
		slab(parts,role,PackedVector3Array([left[i],left[i+1],right[i+1],right[i]]),.8)


static func portal(parts: Array, scale := 1.0) -> void:
	var first:=parts.size()
	for side in [-1,1]:
		var x: float=side*.39
		box(parts,"portal_pier",Vector3(x-.09,-.5,0),Vector3(x+.09,.5,6))
	var rear:=PackedVector3Array([Vector3(-.48,-.5,0)])
	for segment in 8:
		var a: float=segment*PI/8
		var b: float=(segment+1)*PI/8
		var outer_a:=Vector3(-.48*cos(a),.5,6+6*sin(a))
		var outer_b:=Vector3(-.48*cos(b),.5,6+6*sin(b))
		var inner_a:=Vector3(-.30*cos(a),.5,6+3*sin(a))
		var inner_b:=Vector3(-.30*cos(b),.5,6+3*sin(b))
		var back:=Vector3(0,-1,0)
		face(parts,"portal_ring",PackedVector3Array([outer_a,outer_b,inner_b,inner_a]))
		face(parts,"portal_roof",PackedVector3Array([outer_b,outer_a,outer_a+back,outer_b+back]))
		face(parts,"portal_vault",PackedVector3Array([inner_a,inner_b,inner_b+back,inner_a+back]))
		rear.append(outer_a+back)
	rear.append(Vector3(.48,-.5,6))
	rear.append(Vector3(.48,-.5,0))
	face(parts,"portal_back",rear)
	for index in range(first,parts.size()):
		var vertices: PackedVector3Array=parts[index].vertices
		for i in vertices.size():
			vertices[i].z*=scale
		parts[index].vertices=vertices


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
		segments.append([ends[0],ends[1]])
	else:
		for edge: Vector2 in ends:
			segments.append([Vector2.ZERO,edge])
	for segment: Array in segments:
		var first_part := result.size()
		var start: Vector2=segment[0]
		var finish: Vector2=segment[1]
		var a:=Vector3(start.x,start.y,surface_height(start,corners))
		var b:=Vector3(finish.x,finish.y,surface_height(finish,corners))
		var width:=0.62 if rail else (0.65 if ends.size()==2 and mask not in [5,10] else 0.88)
		if not rail:
			strip(result,"road_surface",a,b,width)
			if mask in [5,10]:
				var direction := (finish-start).normalized()
				var side := Vector3(-direction.y,direction.x,0)
				for sign_value in [-1,1]:
					strip(result,"shoulder",a+side*.465*sign_value+Vector3(0,0,.03),b+side*.465*sign_value+Vector3(0,0,.03),.035)
					strip(result,"road_edge",a+side*.44*sign_value+Vector3(0,0,.06),b+side*.44*sign_value+Vector3(0,0,.06),.025)
		if rail:
			var along := (finish-start).normalized()
			var across := Vector3(-along.y,along.x,0) * 0.21
			# SC2000 leaves terrain visible between individual timber sleepers.
			var sleepers:=maxi(2,ceili(start.distance_to(finish)/.20))
			for sleeper in sleepers:
				var p:=a.lerp(b,(sleeper+.5)/sleepers)+Vector3(0,0,.1)
				strip(result,"tie",p-across*1.45,p+across*1.45,.055)
			for sign_value in [-1,1]:
				strip(result,"rail_web",a+across*sign_value+Vector3(0,0,.16),b+across*sign_value+Vector3(0,0,.16),.075)
				strip(result,"rail",a+across*sign_value+Vector3(0,0,0.3),b+across*sign_value+Vector3(0,0,0.3),0.045)
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
	box(parts,"deck",Vector3(-0.32 if rail else -.5,-0.5,height-2),Vector3(0.32 if rail else .5,0.5,height))
	for side in [] if rail else [-1,1]:
		var u: float = side * 0.46
		box(parts,"railing",Vector3(u-0.02,-0.5,height),Vector3(u+0.02,0.5,height+2))
		for at in [-.42,0,.42]:
			box(parts,"railing_post",Vector3(u-.03,at-.025,height),Vector3(u+.03,at+.025,height+2))
	if tower:
		for side in [-1,1]:
			var u: float = side * 0.37
			box(parts,"pier",Vector3(u-0.08,-0.44,water),Vector3(u+0.08,0.44,height+9))
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
		box(parts,"pier",Vector3(-0.07,-0.10,water),Vector3(0.07,0.10,height-2))
	if rail:
		for side in [-1,1]:
			strip(parts,"rail_web",Vector3(side*.21,-.5,height+.16),Vector3(side*.21,.5,height+.16),.075)
			strip(parts,"rail",Vector3(side*0.21,-0.5,height+0.3),Vector3(side*0.21,0.5,height+0.3),0.045)
		for sleeper in 5:
			var y: float=-.5+(sleeper+.5)/5
			strip(parts,"tie",Vector3(-.30,y,height+.1),Vector3(.30,y,height+.1),.055)
	return parts


static func highway_details(parts: Array, top: PackedVector3Array, ports: int, low: Vector2, high: Vector2, footprint: int) -> void:
	# The original highway has light curb tops, dark rail faces and spaced posts.
	var along_u := ports==10
	for sign_value in [-1,1]:
		var across := lerpf(low.y,high.y,.02 if sign_value<0 else .98) if along_u else lerpf(low.x,high.x,.04 if sign_value<0 else .96)
		var first := Vector2(low.x,across) if along_u else Vector2(across,low.y)
		var last := Vector2(high.x,across) if along_u else Vector2(across,high.y)
		var a := Vector3(first.x,first.y,deck_height(first,top,low,high))
		var b := Vector3(last.x,last.y,deck_height(last,top,low,high))
		beam(parts,"curb",a+Vector3(0,0,.12),b+Vector3(0,0,.12),.7)
		beam(parts,"guardrail",a+Vector3(0,0,.9),b+Vector3(0,0,.9),.55)
		for post in footprint*3:
			var p := a.lerp(b,(post+.5)/(footprint*3))
			box(parts,"railing_post",p+Vector3(-.02,-.02,0),p+Vector3(.02,.02,1.0))
	if footprint==2:
		var a := Vector2(low.x,(low.y+high.y)*.5) if along_u else Vector2((low.x+high.x)*.5,low.y)
		var b := Vector2(high.x,a.y) if along_u else Vector2(a.x,high.y)
		beam(parts,"curb",Vector3(a.x,a.y,deck_height(a,top,low,high)+.25),Vector3(b.x,b.y,deck_height(b,top,low,high)+.25),.7)


static func deck_height(point: Vector2, top: PackedVector3Array, low: Vector2, high: Vector2) -> float:
	var u := (point.x-low.x)/(high.x-low.x)
	var v := (point.y-low.y)/(high.y-low.y)
	return lerpf(lerpf(top[0].z,top[1].z,u),lerpf(top[3].z,top[2].z,u),v)


static func power_routes(mask: int, corners: PackedFloat32Array, pole_height := 8.0, pole_position := Vector2.ZERO) -> Array:
	var parts: Array = []
	var base := surface_height(Vector2.ZERO,corners)
	box(parts,"pole",Vector3(pole_position.x-.035,pole_position.y-.035,base),Vector3(pole_position.x+.035,pole_position.y+.035,base+pole_height))
	if pole_position!=Vector2.ZERO:
		beam(parts,"crossarm",Vector3(pole_position.x,pole_position.y,base+pole_height),Vector3(0,0,base+pole_height),1.1)
	# Each cable pair needs a transverse arm at its actual attachment height.
	# Junctions share the mast and carry one arm for each occupied axis.
	if mask & 5:
		box(parts,"crossarm",Vector3(-0.28,-0.035,base+pole_height-.5),Vector3(0.28,0.035,base+pole_height))
		for u in [-.2,.2]:
			box(parts,"insulator",Vector3(u-.025,-.025,base+pole_height-.25),Vector3(u+.025,.025,base+pole_height+.25))
	if mask & 10:
		box(parts,"crossarm",Vector3(-0.035,-0.28,base+pole_height-.5),Vector3(0.035,0.28,base+pole_height))
		for v in [-.2,.2]:
			box(parts,"insulator",Vector3(-.025,v-.025,base+pole_height-.25),Vector3(.025,v+.025,base+pole_height+.25))
	for direction in 4:
		if not mask & (1 << direction):
			continue
		var edge: Vector2 = STEPS[direction]
		var across := Vector2(-edge.y,edge.x).normalized() * 0.2
		for cable in [-1,1]:
			var previous := Vector3(across.x*cable,across.y*cable,base+pole_height)
			for sample in range(1,5):
				var t := sample/4.0
				var planar: Vector2 = edge*t + across*cable
				var z := lerpf(base,surface_height(edge,corners),t)+pole_height-sin(t*PI)*.6
				var point := Vector3(planar.x,planar.y,z)
				beam(parts,"cable",previous,point)
				previous=point
	return parts


static func build(id: int, corners := PackedFloat32Array(), flipped := false) -> Dictionary:
	if corners.is_empty():
		corners=profile(id)
	var kind := family(id)
	var parts: Array = []
	var mask := 5
	var footprint := 1
	match kind:
		"road", "rail", "power":
			var first: int = T.ROAD_STRAIGHT_1 if kind=="road" else (T.RAIL_STRAIGHT_1 if kind=="rail" else T.POWER_LINE_STRAIGHT_1)
			mask=PORTS[id-first] if id-first<PORTS.size() else (10 if (id-first)%2 else 5)
			parts=power_routes(mask,corners) if kind=="power" else ground_routes(mask,corners,kind=="rail")
			if kind=="road" and id>=T.ROAD_JUNCTION_1:
				for p in [Vector2(.43,-.43),Vector2(-.43,.43)]:
					box(parts,"signal_pole",Vector3(p.x-.02,p.y-.02,0),Vector3(p.x+.02,p.y+.02,5))
					box(parts,"signal",Vector3(p.x-.04,p.y-.04,5),Vector3(p.x+.04,p.y+.04,6))
		"ground_crossing":
			var first_axis := 5 if (id-T.ROAD_POWER_CROSSING_1)%2==0 else 10
			mask=15
			if id<=T.ROAD_POWER_CROSSING_2:
				parts=ground_routes(first_axis,corners,false)
				parts.append_array(power_routes(15^first_axis,corners,8,Vector2(.43,-.43)))
			elif id<=T.ROAD_RAIL_CROSSING_2:
				parts=ground_routes(first_axis,corners,false)
				parts.append_array(ground_routes(15^first_axis,corners,true))
			else:
				parts=ground_routes(first_axis,corners,true)
				parts.append_array(power_routes(15^first_axis,corners,8,Vector2(.43,-.43)))
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
				beam(parts,"suspension_cable",a,b)
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
				beam(parts,"cable",Vector3(side*.2,-.5,20),Vector3(side*.2,.5,20))
		"highway", "highway_bridge", "highway_section":
			footprint=2 if kind!="highway" else 1
			mask = (5 if id % 2 else 10) if kind == "highway" else (10 if id % 2 else 5)
			var low:=Vector2(-.5,-.5 if footprint==1 else -1.5)
			var high:=Vector2(.5 if footprint==1 else 1.5,.5)
			var top:=PackedVector3Array([
				Vector3(low.x,low.y,12+corners[0]),Vector3(high.x,low.y,12+corners[1]),
				Vector3(high.x,high.y,12+corners[2]),Vector3(low.x,high.y,12+corners[3])])
			if id>=T.HIGHWAY_CURVE_1 and id<=T.HIGHWAY_CURVE_4:
				var turn:=id-T.HIGHWAY_CURVE_1
				top=PackedVector3Array([top[turn%4],top[(turn+1)%4],top[(turn+2)%4]])
			if id>=T.HIGHWAY_SLOPE_1 and id<=T.HIGHWAY_SLOPE_4:
				var along_u: bool=(id-T.HIGHWAY_SLOPE_1)%2==0
				for interval in [Vector2(0,.44),Vector2(.56,1)]:
					var lane:=PackedVector3Array()
					if along_u:
						lane=PackedVector3Array([top[0].lerp(top[3],interval.x),top[1].lerp(top[2],interval.x),top[1].lerp(top[2],interval.y),top[0].lerp(top[3],interval.y)])
					else:
						lane=PackedVector3Array([top[0].lerp(top[1],interval.x),top[0].lerp(top[1],interval.y),top[3].lerp(top[2],interval.y),top[3].lerp(top[2],interval.x)])
					slab(parts,"deck",lane)
			else:
				slab(parts,"deck",top)
			if kind=="highway" or id<=T.HIGHWAY_SLOPE_4:
				highway_details(parts,top,mask,low,high,footprint)
			if id in [T.HIGHWAY_STRAIGHT_1,T.HIGHWAY_STRAIGHT_2]:
				box(parts,"support",Vector3(-.04,-.04,0),Vector3(.04,.04,10))
			elif id!=T.REINFORCED_HIGHWAY_BRIDGE:
				for index in [0,2]:
					var p: Vector3=top[index]
					var x:=lerpf(p.x,(low.x+high.x)*.5,.10)
					var y:=lerpf(p.y,(low.y+high.y)*.5,.10)
					box(parts,"support",Vector3(x-.025,y-.025,p.z-12),Vector3(x+.025,y+.025,p.z-2))
			if id in [T.HIGHWAY_ROAD_CROSSING_1,T.HIGHWAY_ROAD_CROSSING_2,T.HIGHWAY_RAIL_CROSSING_1,T.HIGHWAY_RAIL_CROSSING_2]:
				mask=15
				parts.append_array(ground_routes(10 if id%2 else 5,corners,id>=T.HIGHWAY_RAIL_CROSSING_1))
			elif id in [T.HIGHWAY_POWER_CROSSING_1,T.HIGHWAY_POWER_CROSSING_2]:
				parts.append_array(power_routes(10 if id%2 else 5,corners,8,Vector2(.43,-.43)))
			if kind=="highway_bridge":
				for u in [-.45,1.45]:
					var chord: Array=[12.0,28.0,36.0,28.0,12.0]
					for segment in 4:
						var y0: float=-1.5+segment*.5
						var y1: float=y0+.5
						var a:=Vector3(u,y0,12)
						var b:=Vector3(u,y1,12)
						var ca:=Vector3(u,y0,chord[segment])
						var cb:=Vector3(u,y1,chord[segment+1])
						beam(parts,"truss",ca,cb,1.35)
						beam(parts,"truss",a,ca,1.35)
						beam(parts,"truss",a,cb,1.1)
						beam(parts,"truss",a,b,1.35)
				beam(parts,"truss",Vector3(-.45,-.5,36),Vector3(1.45,-.5,36),1.35)
				for v in [-1.0,0.0]:
					beam(parts,"truss",Vector3(-.45,v,28),Vector3(1.45,v,28),.8)
		"onramp":
			face(parts,"ramp_ground",PackedVector3Array([
				Vector3(-.5,-.5,0),Vector3(.5,-.5,0),Vector3(.5,.5,0),Vector3(-.5,.5,0)]))
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
			ribbon(parts,"ramp",path,.65)
		"tunnel", "rail_portal":
			parts=ground_routes(5,corners,kind=="rail_portal")
			portal(parts,.5 if kind=="rail_portal" else 1)
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
	for first in [T.POWER_LINE_SLOPE_1,T.ROAD_SLOPE_1,T.RAIL_SLOPE_1,T.HIGHWAY_SLOPE_1]:
		if id>=first and id<first+4:
			shape=id-first+1
	var masks: Array=[0,9,3,6,12]
	var heights:=PackedFloat32Array()
	for i in 4:
		heights.append(12.0 if int(masks[shape])&(1<<i) else 0.0)
	return heights
