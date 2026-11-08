class_name PictureNoticeDialog
extends AcceptDialog

var picture_view: TextureRect
var message_label: Label


func _ready() -> void:
	hide()
	theme = AppUiTheme.current()
	get_label().visible = false
	picture_view = $Layout/PictureFrame/Picture
	message_label = $Layout/Message
	get_ok_button().theme_type_variation = &"PrimaryButton"
	get_ok_button().custom_minimum_size = Vector2(110, 36)
	$Layout/PictureFrame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	message_label.add_theme_font_size_override("font_size", 16)


func configure(
	dialog_name: String,
	dialog_title: String,
	image_name: String,
	message_name: String,
	picture: Image,
	message_text: String
) -> void:
	name = dialog_name
	title = dialog_title
	picture_view.name = image_name
	message_label.name = message_name
	set_picture(picture)
	message_label.text = _normalized_text(message_text)


func set_picture(picture: Image) -> void:
	picture_view.texture = null if picture == null else PixelArtTexture.wrap(ImageTexture.create_from_image(picture))
	picture_view.get_parent().visible = picture_view.texture != null


func show_message(message_text: String, normalize_newlines := false) -> void:
	message_label.text = (
		_normalized_text(message_text) if normalize_newlines else message_text
	)
	var available := Vector2i(get_parent().get_viewport().get_visible_rect().size)
	var limit := Vector2i(maxi(1, available.x - 32), maxi(1, available.y - 64))
	min_size = Vector2i(440, 220).min(limit)
	max_size = limit
	var narrow := limit.x < 520
	picture_view.get_parent().visible = picture_view.texture != null and limit.x >= 400
	message_label.custom_minimum_size.x = 190 if narrow else 280
	picture_view.get_parent().custom_minimum_size.x = 110 if narrow else 180
	picture_view.custom_minimum_size.x = 110 if narrow else 180
	$Layout.custom_minimum_size.x = 330 if narrow else 480
	if limit.x < 400:
		message_label.custom_minimum_size.x = maxi(120, limit.x - 60)
		$Layout.custom_minimum_size.x = message_label.custom_minimum_size.x
	popup_centered(Vector2i(620, 250).min(limit))


func _normalized_text(value: String) -> String:
	return value.replace("\r\n", "\n").replace("\r", "\n")
