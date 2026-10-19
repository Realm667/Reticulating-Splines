class_name ApplicationQualityOfLife
extends Node

const MENU_MUSIC_BOX := CityMenuBar.MENU_MUSIC_BOX

var app: CityApplication
var memory: WindowLayoutMemory
var music_box: MusicBoxDialog


func _init(application: CityApplication) -> void:
	app = application


func _ready() -> void:
	memory = WindowLayoutMemory.new()
	memory.storage_path = app.preferences.settings_path + ".layouts.cfg"
	memory.save_failed.connect(app.interface.show_error)
	# Observe the whole application, including windows added later.
	app.add_child(memory)
	app.city_menu_bar.options_menu_requested.connect(_menu)
	music_box = MusicBoxDialog.new(app)
	app.add_child(music_box)
	app.photo_mode = CityPhotoMode.new(app)
	app.add_child(app.photo_mode)
	app.add_child(IdlePresentation.new(app))
	app.knowledge = ApplicationKnowledge.new(app)
	app.add_child(app.knowledge)


func _menu(id: int) -> void:
	if id == MENU_MUSIC_BOX:
		music_box.open()
	elif id == CityMenuBar.MENU_PHOTO_MODE:
		app.photo_mode.open()
