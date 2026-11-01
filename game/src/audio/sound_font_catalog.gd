class_name SoundFontCatalog
extends RefCounted
## Bundled, system and custom General MIDI banks. Packed banks are verified and
## extracted to the local soundfont-cache for FluidSynth; see docs/fluidsynth.md.

## The preference values.
const SYSTEM := "system"
const CUSTOM := "custom"
const FLUID := "fluidr3mono"
const MUSESCORE := "musescore_general"
const GENERALUSER := "generaluser_gs"
const BUNDLED := {
	FLUID: "FluidR3Mono_GM.sf3", MUSESCORE: "MuseScore_General.sf3", GENERALUSER: "GeneralUser-GS.sf2",
}
static var _installed: Dictionary = {}
const DEFAULT := SYSTEM

const EXTENSIONS := ["sf2", "sf3", "dls"]

## macOS and Windows include a Roland GS set licensed for their own MIDI
## synthesizers; Linux distributions can install a SoundFont package.
const MACOS_SOUND_SET := "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"
const WINDOWS_SOUND_SET := "System32/drivers/gm.dls"
const LINUX_SOUND_SETS := [
	"/usr/share/sounds/sf2/default-GM.sf2", "/usr/share/sounds/sf3/default-GM.sf3",
	"/usr/share/soundfonts/default.sf2", "/usr/share/sounds/sf2/FluidR3_GM.sf2",
	"/usr/share/soundfonts/FluidR3_GM.sf2",
]

## The MIT SoundFont beside the executable of the Linux package. An installed
## distribution SoundFont comes first.
const BUNDLED_SOUND_SET := "FluidR3Mono_GM.sf3"


## The sound set of this operating system, or an empty string when it has none.
static func system_path() -> String:
	return NativeSoundFonts.first_existing(sound_set_paths(OS.get_name(), OS.get_executable_path().get_base_dir()))


## The sound sets to try on an operating system, in order.
static func sound_set_paths(os_name: String, executable_folder: String) -> PackedStringArray:
	return NativeSoundFonts.sound_set_paths(os_name, executable_folder, OS.get_environment("SystemRoot"))


static func is_bundled(path: String) -> bool:
	return NativeSoundFonts.is_bundled(path)


static func label(choice: String) -> String:
	if BUNDLED.has(choice):
		return {FLUID: "FluidR3Mono", MUSESCORE: "MuseScore General", GENERALUSER: "GeneralUser GS"}[choice]
	return NativeSoundFonts.label(choice, OS.get_name(), "" if choice == CUSTOM else system_path())


## Every choice, in menu order.
static func choices() -> PackedStringArray:
	return PackedStringArray([SYSTEM, FLUID, MUSESCORE, GENERALUSER, CUSTOM])


## A stored preference, or the default when the stored value is unknown, such
## as a choice that earlier versions offered.
static func normalize(choice: String) -> String:
	return choice if BUNDLED.has(choice) else NativeSoundFonts.normalize(choice)


## The SoundFont paths to try, in order. A custom SoundFont that fails falls
## back to the system sound set. An empty list means that no SoundFont exists.
static func candidates(choice: String, custom_path: String) -> PackedStringArray:
	var result := PackedStringArray()
	if BUNDLED.has(choice):
		var path := bundled_path(choice)
		if not path.is_empty():
			result.append(path)
	else:
		result = NativeSoundFonts.candidates(choice, custom_path, system_path())
	var system := system_path()
	if not system.is_empty() and system not in result:
		result.append(system)
	var fallback := bundled_path(FLUID)
	if not fallback.is_empty() and fallback not in result:
		result.append(fallback)
	return result


## Packed resources need a physical file for FluidSynth, including on Android.
## Cache filenames include the pinned content hash; existing files are verified once.
static func bundled_path(choice: String) -> String:
	if _installed.has(choice) and FileAccess.file_exists(_installed[choice]):
		return _installed[choice]
	if not BUNDLED.has(choice):
		return ""
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/soundfonts/manifest.json"))
	if not manifest is Dictionary:
		return ""
	for entry: Dictionary in manifest.get("fonts", []):
		if entry.id != choice:
			continue
		var source := "res://assets/soundfonts/" + str(entry.file)
		if not OS.has_feature("template"):
			var direct := ProjectSettings.globalize_path(source)
			if not NativeSoundFonts.first_existing(PackedStringArray([direct])).is_empty() and FileAccess.get_sha256(direct) == entry.sha256:
				_installed[choice] = direct
				return direct
		var folder := AppPaths.path("soundfont-cache")
		if DirAccess.make_dir_recursive_absolute(folder) != OK:
			return ""
		var target := folder.path_join(str(entry.sha256) + "." + str(entry.file).get_extension())
		if FileAccess.file_exists(target) and FileAccess.get_sha256(target) == entry.sha256:
			_installed[choice] = target
			return target
		var bytes := FileAccess.get_file_as_bytes(source)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		if hash.finish().hex_encode() != entry.sha256:
			return ""
		var file := FileAccess.open(target + ".tmp", FileAccess.WRITE)
		if file == null:
			return ""
		file.store_buffer(bytes)
		file.close()
		if DirAccess.rename_absolute(target + ".tmp", target) != OK:
			return ""
		_installed[choice] = target
		return target
	return ""


static func description(choice: String) -> String:
	match choice:
		FLUID:
			return TranslationServer.translate("FluidR3Mono: compact classic General MIDI wavetable sound. MIT license.")
		MUSESCORE:
			return TranslationServer.translate("MuseScore General: fuller acoustic instruments, based on FluidR3Mono. MIT license.")
		GENERALUSER:
			return TranslationServer.translate("GeneralUser GS: expressive GM/GS sound for retro games. Its own license permits software use; some sample origins are uncertain.")
		CUSTOM:
			return TranslationServer.translate("Custom SoundFont: uses your selected SF2, SF3 or DLS file.")
	return TranslationServer.translate("System SoundFont: uses the operating system sound set, with FluidR3Mono as fallback.")


static func display_name(path: String) -> String:
	for choice in _installed:
		if _installed[choice] == path:
			return label(choice)
	return path.get_file()
