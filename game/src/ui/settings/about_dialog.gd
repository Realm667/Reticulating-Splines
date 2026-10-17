class_name AboutDialog
extends AcceptDialog

@warning_ignore_start("integer_division")

var artwork: AboutArtwork
var project_text: RichTextLabel
var license_picker: OptionButton
var license_text: RichTextLabel
var license_documents: Array[String] = []
var license_sources: Array[String] = []
var original_credits_index := -1
var source_credits := ""


func _ready() -> void:
	# keep the scene visible in the editor, but closed until requested in game
	hide()
	get_label().hide()
	$Content/Version.text = tr("Version %s") % ProjectSettings.get_setting("application/config/version")
	artwork = $Content/Tabs/About/Scene/Artwork
	project_text = $Content/Tabs/About/Summary
	license_picker = $Content/Tabs/Licenses/LicensePicker
	license_text = $Content/Tabs/Licenses/LicenseText
	license_picker.item_selected.connect(_select_license)
	project_text.meta_clicked.connect(_open_link)
	license_text.meta_clicked.connect(_open_link)
	about_to_popup.connect(_fit_to_viewport)
	visibility_changed.connect(_update_animation)
	$Content/Tabs.tab_changed.connect(_on_tab_changed)
	_build_licenses()
	_refresh_project()


func set_assets(assets: OriginalGameAssets) -> void:
	artwork.set_assets(assets)
	source_credits = "" if assets == null else assets.original_credits
	license_documents[original_credits_index] = _original_credits_document(OriginalTextLocalization.text(128, source_credits))
	if license_picker.selected == original_credits_index:
		_select_license(original_credits_index)
	$Content/Tabs/About/Scene/MissingArtwork.visible = not artwork.available


func _on_tab_changed(_index: int) -> void:
	_update_animation(false)


func _update_animation(restart := true) -> void:
	artwork.set_active(visible and $Content/Tabs.current_tab == 0, restart)


func _build_licenses() -> void:
	_add_license("OpenSC2K — MIT", FileAccess.get_file_as_string("res://assets/licenses/OpenSC2K-MIT.txt"))
	_add_license("Reticulating Splines — CC BY 4.0", FileAccess.get_file_as_string("res://assets/licenses/Reticulating-Splines-assets.txt") + "\n\n" + FileAccess.get_file_as_string("res://assets/licenses/CC-BY-4.0.txt"))
	_add_license("sc2kfix — MIT", FileAccess.get_file_as_string("res://assets/licenses/sc2kfix-MIT.txt"))
	_add_license("Weather recordings — CC0", FileAccess.get_file_as_string("res://assets/licenses/Weather-Audio-CC0.txt"))
	_add_license("Godot Engine — MIT", Engine.get_license_text())
	var engine_notices := "Godot Engine third-party components\n\n"
	for component in Engine.get_copyright_info():
		engine_notices += str(component.name) + "\n"
		for part in component.parts:
			engine_notices += "\n".join(part.copyright) + "\nLicense: " + str(part.license) + "\n"
		engine_notices += "\n"
	var engine_licenses := Engine.get_license_info()
	for license_name in engine_licenses:
		engine_notices += str(license_name) + "\n" + str(engine_licenses[license_name]) + "\n\n"
	_add_license("Godot Engine — dependency notices", engine_notices)
	_add_license("Montserrat — SIL OFL 1.1", FileAccess.get_file_as_string("res://assets/fonts/montserrat/OFL.txt"))
	_add_license("Rajdhani — SIL OFL 1.1", FileAccess.get_file_as_string("res://assets/fonts/rajdhani/OFL.txt"))
	_add_license("Anton — SIL OFL 1.1", FileAccess.get_file_as_string("res://assets/fonts/anton/OFL.txt"))
	_add_license("UnifrakturMaguntia — SIL OFL 1.1", FileAccess.get_file_as_string("res://assets/fonts/unifrakturmaguntia/OFL.txt"))
	_add_license("Grenze Gotisch — SIL OFL 1.1", FileAccess.get_file_as_string("res://assets/fonts/grenzegotisch/OFL.txt"))
	_add_license("Chomsky — SIL OFL 1.1", FileAccess.get_file_as_string("res://assets/fonts/chomsky/OFL.txt"))
	_add_license("Pretendard — SIL OFL 1.1", FileAccess.get_file_as_string("res://assets/fonts/pretendard/OFL.txt"))
	_add_license("Pixelated MS Sans Serif — CC BY-SA 3.0", _license_files("classic-font", ["NOTICE.txt", "LICENSE.txt"]))
	_add_license("FluidSynth — LGPL 2.1 or later", _license_files("fluidsynth", ["NOTICE.txt", "LGPL-2.1.txt", "fluidsynth-AUTHORS.txt"]))
	_add_license("FluidSynth — included library notices", _license_files("fluidsynth", [
		"libsndfile-COPYING.txt", "libsndfile-AUTHORS.txt", "libsndfile-GSM610-COPYRIGHT.txt", "libogg-COPYING.txt",
		"libvorbis-COPYING.txt", "flac-COPYING.Xiph.txt", "opus-COPYING.txt", "signalsmith-basics-LICENSE.txt",
		"signalsmith-linear-LICENSE.txt", "signalsmith-dsp-LICENSE.txt", "signalsmith-hilbert-iir-LICENSE.txt",
		"gcem-NOTICE.txt", "Apache-2.0.txt",
	]))

	if OS.get_name() == "Linux":
		_add_license("FluidR3 Mono SoundFont — MIT", _license_files("fluidr3mono", ["FluidR3Mono-License.txt"]))

	_add_license("QuickJS-ng — MIT", "QuickJS-ng %s JavaScript engine of the script runtime\nhttps://github.com/quickjs-ng/quickjs\n\n%s"
		% [ScriptRuntime.engine_version(), FileAccess.get_file_as_string("res://assets/licenses/quickjs/QuickJS-ng-LICENSE.txt").strip_edges()])

	_add_license("Rust crates and ported code — MIT, 0BSD", _license_files("rust", [
		"miniz_oxide-LICENSE-MIT.txt", "adler2-LICENSE-0BSD.txt", "FastNoiseLite-LICENSE.txt",
	]))

	_add_license("Research and original game", """RESEARCH

sc2json — MIT
https://github.com/sc2kfix/sc2json
Save-file and compression research.

SC2k-docs — OpenCity2k contributors — CC BY-SA 4.0
https://github.com/OpenCity2k/SC2k-docs
File-format and simulation research. OpenSC2K's implementations and descriptions may differ.

sc2k-reverse wiki — contributors — CC BY-SA 4.0
https://wiki.sc2kfix.net/
Function and structure research.
https://creativecommons.org/licenses/by-sa/4.0/

ORIGINAL GAME

""" + (
		"SimCity 2000 and its imported graphics, text, sound, and music belong to their respective rights holders. "
		+ "They are not covered by OpenSC2K's MIT license."
	) + """

""" + (
		"OpenSC2K is an independent project. It is not affiliated with, sponsored by, or endorsed by Electronic "
		+ "Arts or Maxis. SimCity and related names and marks belong to their respective owners."
		+ "\n"
	))
	original_credits_index = license_documents.size()
	_add_license("Original SimCity 2000 credits", _original_credits_document(OriginalTextLocalization.text(128)))
	_select_license(0)


## The license files of one folder in res://assets/licenses, each under its name.
func _license_files(folder: String, names: Array) -> String:
	var parts := PackedStringArray()

	for file_name in names:
		var text := FileAccess.get_file_as_string("res://assets/licenses".path_join(folder).path_join(file_name))
		parts.append("%s\n\n%s" % [file_name, text.strip_edges()])

	return "\n\n\n".join(parts)


func _original_credits_document(credits: String) -> String:
	var introduction := tr("Original SimCity 2000 credits") + "\n\n" + tr("These credits recognize the creators of the original SimCity 2000, not contributors to Reticulating Splines. Their inclusion does not imply affiliation or endorsement.") + "\n\n"
	if credits.is_empty():
		return introduction + tr("The original credits are unavailable. Import a complete supported game installation to view them.")
	return introduction + tr("Credits from the imported SimCity 2000 for Windows 95 installation:") + "\n\n" + credits.replace(
		"\r\n",
		"\n",
	).strip_edges()


func _add_license(label: String, text: String) -> void:
	license_sources.append(label)
	license_picker.add_item(tr(label))
	license_documents.append(text)


func _select_license(index: int) -> void:
	license_text.text = license_documents[index]
	license_text.scroll_to_line(0)


func _open_link(meta: Variant) -> void:
	var url := str(meta)
	if url.begins_with("https://"):
		OS.shell_open(url)


func _fit_to_viewport() -> void:
	if get_parent() == null:
		return
	var viewport_size := Vector2i(get_parent().get_viewport().get_visible_rect().size)
	var height_limit := maxi(1, int(viewport_size.y * 0.9) - get_theme_constant("title_height"))
	max_size = Vector2i(0, height_limit)
	size = Vector2i(mini(760, int(viewport_size.x * 0.95)), mini(550, height_limit))
	position = (viewport_size - size) / 2


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and original_credits_index >= 0:
		_refresh_project()
		license_documents[original_credits_index] = _original_credits_document(OriginalTextLocalization.text(128, source_credits))
		if license_picker.selected == original_credits_index:
			_select_license(original_credits_index)


func _refresh_project() -> void:
	for index in license_sources.size():
		license_picker.set_item_text(index, tr(license_sources[index]))
	$Content/Tabs.set_tab_title(0, tr("Project information"))
	$Content/Tabs.set_tab_title(1, tr("Licenses and credits"))
	$Content/Version.text = tr("Version %s") % ProjectSettings.get_setting("application/config/version")
	project_text.text = "[b]Reticulating Splines[/b]\n" + tr("Reticulating Splines is developed by Daniel Gimmer (Realm667), based on OpenSC2K by Nicholas Ochoa.")
	project_text.text += "\n\n[b]" + tr("What Reticulating Splines adds") + "[/b]\n" + tr("New graphics and audio, day and night, seasons and weather, a modern interface, a music box for your own music, and cooperative and competitive multiplayer. Visual effects do not change the original single-player simulation.")
	project_text.text += "\n\n[b]" + tr("Development and acknowledgements") + "[/b]\n[url=https://github.com/Realm667/Reticulating-Splines]Reticulating Splines · GitHub[/url]\n" + tr("Development of Reticulating Splines: Daniel Gimmer (Realm667). Thanks to Nicholas Ochoa and the OpenSC2K contributors for the foundation, and to everyone supporting this project with feedback, research and testing.")
	project_text.text += "\n\n[b]OpenSC2K[/b]\nCopyright © 2026 Nicholas Ochoa\n[url=https://github.com/nicholas-ochoa/OpenSC2K]OpenSC2K · GitHub[/url]\n" + tr("Based on OpenSC2K under the MIT License, including fixes and research from sc2kfix. Built with Godot and Rust. Interface typography: Montserrat, with Pretendard for Korean.")
	project_text.text += "\n[url=https://github.com/sc2kfix/sc2kfix]sc2kfix · GitHub[/url]\n\n" + tr("See Licenses and credits for the full license texts, third-party notices and imported original-game credits. License texts are reproduced in their original language.")
	project_text.text += "\n\n[b]" + tr("Independent and unofficial") + "[/b]\n" + tr("Reticulating Splines is not affiliated with or endorsed by Electronic Arts or Maxis. SimCity 2000 and its original graphics, texts, sounds and music belong to their respective rights holders and are not covered by the project's MIT License. Import your own supported game installation to use the original assets.")
