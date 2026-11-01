class_name RegionProjection
extends RefCounted
## Shared compass and isometric placement for neighbors and region navigation.


static func rotate(point: Vector2, compass: int) -> Vector2:
	for turn in compass & 3:
		point = Vector2(point.y, -point.x)
	return point


static func project(point: Vector2, half_size: Vector2, compass := 0) -> Vector2:
	var turned := rotate(point, compass)
	return Vector2((turned.x - turned.y) * half_size.x, (turned.x + turned.y) * half_size.y)


static func neighbor_indices(compass: int) -> PackedInt32Array:
	var rotation := compass & 3
	return PackedInt32Array([(rotation + 2) & 3, (rotation - 1) & 3, rotation, (rotation + 1) & 3])
