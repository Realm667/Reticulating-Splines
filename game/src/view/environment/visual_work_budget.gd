class_name VisualWorkBudget
extends RefCounted
## Cooperative background allowance. One indivisible upload may exceed it;
## allowing that upload prevents a large artwork atlas from starving forever.

@warning_ignore_start("integer_division")

const UPLOAD_LIMIT := 4 * 1024 * 1024
var allowance_usec := 1500
var deadline := 0
var frame_started := 0
var upload_bytes := 0
var region_usec := 250.0


func begin_frame(delta: float) -> void:
	if delta > 0.020:
		allowance_usec = maxi(250, allowance_usec / 2)
	elif delta < 0.017:
		allowance_usec = mini(2000, allowance_usec + 50)
	frame_started = Time.get_ticks_usec()
	deadline = frame_started + allowance_usec
	upload_bytes = 0


func remaining() -> int:
	return maxi(0, deadline - Time.get_ticks_usec())


func available() -> bool:
	return remaining() > 0 and upload_bytes < UPLOAD_LIMIT


func region_limit() -> int:
	return clampi(int(remaining() / maxf(region_usec, 1.0)), 1, 4)


func record_regions(count: int, usec: int) -> void:
	if count > 0:
		region_usec = lerpf(region_usec, float(usec) / count, 0.25)
