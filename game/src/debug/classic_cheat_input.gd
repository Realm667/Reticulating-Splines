class_name ClassicCheatInput
extends RefCounted
## Delay ambiguous shortcuts briefly, then replay them if no code follows.
## The caller owns focus, singleplayer and document lifetime checks.

const FIRST_KEY_MSEC := 400
const NEXT_KEY_MSEC := 1600
const CODES: PackedStringArray = [
	"cass", "fund", "imacheat", "buddamus", "torg", "porntipsguzzardo", "pirntopsguzzardo",
	"pirn", "topsguzzardo", "ardo", "damn", "darn", "heck", "priscilla", "oivaizmir",
	"gilmartin", "noah", "moses", "mrsoleary", "gomorrah", "uspa87419", "vaudeville",
]

var buffer := ""
var deadline := 0
var pending: Array[InputEventKey] = []
var released: Array[InputEventKey] = []
var completed := ""


func clear() -> void:
	buffer = ""
	pending.clear()
	released.clear()
	completed = ""
	deadline = 0


func flush() -> void:
	released.append_array(pending)
	pending.clear()
	buffer = ""
	deadline = 0


func expire(now: int) -> void:
	if not buffer.is_empty() and now >= deadline:
		flush()


func feed(event: InputEventKey, now: int, editor := false) -> bool:
	completed = ""
	expire(now)
	if not event.pressed:
		for pressed in pending:
			if pressed.pressed and pressed.physical_keycode == event.physical_keycode and pressed.keycode == event.keycode:
				pending.append(event.duplicate())
				return true
		return false
	if event.echo:
		# A held movement key must become a held movement key, not a code.
		flush()
		return false
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		flush()
		return false
	var letter := String.chr(event.unicode).to_lower() if event.unicode > 0 else ""
	if letter.is_empty():
		flush()
		return false
	var candidate := buffer + letter
	var prefix := false
	for code in CODES:
		if (not editor or code == "vaudeville") and code.begins_with(candidate):
			prefix = true
			break
	if not prefix:
		flush()
		return false
	buffer = candidate
	pending.append(event.duplicate())
	deadline = now + (FIRST_KEY_MSEC if buffer.length() == 1 else NEXT_KEY_MSEC)
	if buffer in CODES:
		completed = buffer
		pending.clear()
		buffer = ""
		deadline = 0
	return true
