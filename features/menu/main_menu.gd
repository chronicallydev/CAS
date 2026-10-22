class_name MainMenu
extends Node

# The main menu (the main scene): play a run, the test range, the language
# and fullscreen (Settings), and quit (not on the web, where a page can't
# close itself). Built in code in the run screens' 1-bit style (RunScreens);
# mouse, or arrow keys and Enter.

const RUN := "res://features/run/run.tscn"
const TEST_RANGE := "res://features/test_range/test_range.tscn"
# The game's working title; not translated.
const TITLE := "CAS SIM"
const PAPER := RunScreens.PAPER
const INK := RunScreens.INK
const BUTTON_SIZE := Vector2(760, 96)

var language_button: Button
var fullscreen_button: Button
var buttons: Array[Button] = []


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Music.play("menu")
	Music.duck(false)
	build()
	Settings.changed.connect(update_texts)
	update_texts()
	buttons[0].grab_focus.call_deferred()


func build() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var background := ColorRect.new()
	background.color = INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	center.add_child(column)

	var title := RunScreens.text_label(TITLE, 110)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(title)
	var tagline := RunScreens.text_label("A roguelike about dodging missiles", 30)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	column.add_child(gap)

	add_button(column, "PLAY", func() -> void: get_tree().change_scene_to_file(RUN))
	add_button(column, "TEST RANGE", func() -> void: get_tree().change_scene_to_file(TEST_RANGE))
	language_button = add_button(column, "", Settings.cycle_language)
	fullscreen_button = add_button(column, "", func() -> void: Settings.set_fullscreen(not Settings.fullscreen))
	if not OS.has_feature("web"):
		add_button(column, "QUIT", func() -> void: get_tree().quit())

	var footer := RunScreens.text_label("F11 - FULLSCREEN", 26)
	footer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	footer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	footer.offset_top = -80
	footer.offset_bottom = -30
	layer.add_child(footer)


# A white box with black text that inverts while it has focus; the mouse
# gives it focus too, so the keys and the mouse never point at two at once.
func add_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", RunScreens.box_style(PAPER, 8, 12))
	for state in ["hover", "pressed", "focus", "hover_pressed"]:
		button.add_theme_stylebox_override(state, RunScreens.box_style(INK, 8, 12))
	var label := RunScreens.text_label(text, 40, INK)
	label.add_theme_constant_override("outline_size", 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(label)
	button.mouse_entered.connect(button.grab_focus)
	button.focus_entered.connect(func() -> void: label.add_theme_color_override("font_color", PAPER))
	button.focus_exited.connect(func() -> void: label.add_theme_color_override("font_color", INK))
	button.pressed.connect(func() -> void:
		Sfx.play_2d("ui_click")
		action.call())
	parent.add_child(button)
	buttons.append(button)
	return button


func update_texts() -> void:
	set_button_text(language_button, tr("LANGUAGE: %s") % Settings.LANGUAGES[Settings.language])
	set_button_text(fullscreen_button, tr("FULLSCREEN: ON") if Settings.fullscreen else tr("FULLSCREEN: OFF"))


func set_button_text(button: Button, text: String) -> void:
	var label: Label = button.get_child(0)
	label.text = text
