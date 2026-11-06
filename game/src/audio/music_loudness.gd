class_name MusicLoudness
extends RefCounted
## Bounded, gated RMS estimate shared by decoded recordings and rendered MIDI.
## A single gain per track preserves musical dynamics and never changes the file.

const TARGET_RMS := 0.1
const PEAK_CEILING := 0.70
const MAX_GAIN := 2.0
const WINDOW_SECONDS := 2.4
const CACHE_SIZE := 256

static var _gains: Dictionary[String, float] = {}
static var _lock := Mutex.new()


static func file_key(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return "%s:%d:%d" % [path, FileAccess.get_modified_time(path), file.get_length()] if file != null else ""


static func gain_for(key: String, measure: Callable) -> float:
	_lock.lock()
	var saved := _gains.get(key, -1.0) as float
	_lock.unlock()
	if saved >= 0.0:
		return saved
	var gain := measure.call() as float
	if not key.is_empty():
		_lock.lock()
		if _gains.size() >= CACHE_SIZE:
			_gains.erase(_gains.keys()[0])
		_gains[key] = gain
		_lock.unlock()
	return gain


static func recording_gain(stream: AudioStream, path: String) -> float:
	var key := file_key(path)
	return gain_for("recording:" + key if not key.is_empty() else "", _measure_recording.bind(stream))


static func _measure_recording(stream: AudioStream) -> float:
	var playback := stream.instantiate_playback()
	if playback == null:
		return 1.0
	var reader := func(position: float, frames: int) -> PackedVector2Array:
		playback.start(position)
		var samples := playback.mix_audio(1.0, frames)
		playback.stop()
		return samples
	return estimate(stream.get_length(), AudioServer.get_mix_rate(), reader)


static func estimate(duration: float, sample_rate: float, read_window: Callable) -> float:
	if duration <= 0.0 or sample_rate <= 0.0:
		return 1.0
	var span := minf(duration, WINDOW_SECONDS)
	var block_frames := maxi(1, roundi(sample_rate * 0.4))
	var block_power := PackedFloat64Array()
	var peak := 0.0
	# Spread the windows across the piece. Short cues fit in a single window.
	var window_count := clampi(ceili(duration / WINDOW_SECONDS), 1, 4)
	for index in window_count:
		var fraction := float(index) / maxf(1.0, window_count - 1)
		var samples := read_window.call((duration - span) * fraction, roundi(sample_rate * span)) as PackedVector2Array
		var energy := 0.0
		var count := 0
		for frame in samples:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
			energy += frame.length_squared() * 0.5
			count += 1
			if count == block_frames:
				block_power.append(energy / count)
				energy = 0.0
				count = 0
		if count > 0:
			block_power.append(energy / count)
	return _track_gain(block_power, peak)


static func _track_gain(block_power: PackedFloat64Array, peak: float) -> float:
	if block_power.is_empty() or not is_finite(peak) or peak <= 0.0001:
		return 1.0
	var strongest := float(block_power[0])
	for power in block_power:
		strongest = maxf(strongest, power)
	# Ignore silence and tails more than 15 dB below the strongest block.
	var gate := maxf(strongest * 0.0316, 0.0000032)
	var sum := 0.0
	var count := 0
	for power in block_power:
		if power >= gate:
			sum += power
			count += 1
	var rms_gain := TARGET_RMS / sqrt(sum / count) if count > 0 else 1.0
	return minf(MAX_GAIN, minf(rms_gain, PEAK_CEILING / peak))
