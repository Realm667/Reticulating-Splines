class_name MusicTrackTitle
extends RefCounted

# Soundtrack titles, keyed by Windows MIDI resource ID, not album track order.
# These proper names stay unchanged across locales. See docs/quality-of-life.md.
const ORIGINAL: Dictionary[int, String] = {
	10000: "Dawn of City",
	10001: "Dancing Megalopolis",
	10002: "The SIM Magic for (ENIAC)",
	10003: "The SIM Magic: Experience MODE",
	10004: "The Construction: MAXIS",
	10005: "The Construction: LAKELAND",
	10006: "Selfish Citizen",
	10007: "Skyscrapers",
	10008: "Tax & Money",
	10009: "Pale City",
	10010: "Growing Up Town ~ Prologue",
	10011: "Growing Up Town ~ Theme",
	10012: "Work Work Work!",
	10013: "Ultimate City",
	10014: "Buildings",
	10015: "Melancholic Mayor",
	10016: "The Construction: HAPPYLAND",
	10017: "Misty Lake",
	10018: "Key of Success",
}


static func resolve(path: String, id := -1, original := false) -> String:
	if original and ORIGINAL.has(id):
		return ORIGINAL[id]
	if not path.is_empty():
		return Mp3Title.read(path)
	return TranslationServer.translate("Track %d") % id
