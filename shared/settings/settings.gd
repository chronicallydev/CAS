extends Node

# Player settings, autoloaded as "Settings": the language and fullscreen,
# kept in user://options.cfg across launches.
#
# The language is the TranslationServer's locale. English is the source
# text; Ukrainian comes from UkrainianStrings. Labels whose whole text is
# a key translate themselves; text built in code goes through tr() (or
# Settings.t() in static code).
#
# Fullscreen starts on in an exported desktop build and off in the editor
# and on the web (a browser only goes fullscreen from a click). F11 or
# Alt+Enter toggles it anywhere. `-- --windowed` on the command line keeps
# a run windowed without touching the saved choice (for test runs).

signal changed

# Not settings.cfg: that's the parked profile save (_parked/.../save_service.gd).
const PATH := "user://options.cfg"
# Locale code -> its name in its own language, for the menu.
const LANGUAGES := {"en": "ENGLISH", "uk": "УКРАЇНСЬКА"}

var language: String = "en"
var fullscreen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	TranslationServer.add_translation(UkrainianStrings.build())
	language = "uk" if OS.get_locale_language() == "uk" else "en"
	fullscreen = not OS.has_feature("editor") and not OS.has_feature("web")
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		language = file.get_value("game", "language", language)
		fullscreen = file.get_value("display", "fullscreen", fullscreen)
	if not LANGUAGES.has(language):
		language = "en"
	TranslationServer.set_locale(language)
	if "--windowed" in OS.get_cmdline_user_args():
		return
	apply_window()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_F11 or (event.physical_keycode == KEY_ENTER and event.alt_pressed):
		set_fullscreen(not fullscreen)
		get_viewport().set_input_as_handled()


## `text` in the current language, for static code with no tr() of its own.
static func t(text: String) -> String:
	return String(TranslationServer.translate(text))


func set_language(code: String) -> void:
	language = code
	TranslationServer.set_locale(code)
	save()
	changed.emit()


## Switches to the next language in LANGUAGES.
func cycle_language() -> void:
	var codes := LANGUAGES.keys()
	set_language(codes[(codes.find(language) + 1) % codes.size()])


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_window()
	save()
	changed.emit()


func apply_window() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func save() -> void:
	var file := ConfigFile.new()
	file.set_value("game", "language", language)
	file.set_value("display", "fullscreen", fullscreen)
	file.save(PATH)
