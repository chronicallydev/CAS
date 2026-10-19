class_name MainMenu
extends Control

# Main menu screen: records, difficulty and graphics options, and buttons
# for the campaign map, the hangar, the test range and quitting. The UI is built in code.
#
# This is only the view. The menu context passes in the data to show
# (initialize) and reacts to the *_pressed signals; write_settings() copies
# the chosen options back into GameSettings.

signal play_pressed
signal hangar_pressed
signal test_range_pressed
signal quit_pressed

const ACCENT := Color(1.0, 0.72, 0.25)
const TEXT := Color(0.9, 0.92, 0.88)
const MUTED := Color(0.6, 0.64, 0.6)

var play_button: Button
var difficulty_option: OptionButton
var pixel_check: CheckBox
var blood_check: CheckBox

var profile: PlayerProfile
var campaign: Campaign
var difficulty_names: Array[String] = []


func initialize(player_profile: PlayerProfile, campaign_rules: Campaign, settings: GameSettings, difficulties: Array[DifficultyPreset]) -> void:
	profile = player_profile
	campaign = campaign_rules
	for preset in difficulties:
		difficulty_names.append(preset.display_name)

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_background()
	build_layout()
	read_settings(settings)
	play_button.grab_focus()


func build_background() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.16, 0.19, 0.16))
	gradient.set_color(1, Color(0.05, 0.06, 0.06))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.35)
	texture.fill_to = Vector2(1.1, 1.1)

	var background := TextureRect.new()
	background.texture = texture
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)


func build_layout() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)

	var title := make_label("CAS SIM", 50, ACCENT)
	column.add_child(title)

	var subtitle := make_label("CLOSE AIR SUPPORT", 18, MUTED)
	column.add_child(subtitle)

	if profile.best_wave > 0:
		column.add_child(make_label("BEST   Wave %d   |   %d pts" % [profile.best_wave, profile.best_score], 18, ACCENT))

	column.add_child(make_spacer(6))

	# Settings panel.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.gradient_panel(UiStyle.PANEL_TOP, UiStyle.PANEL_BOTTOM, UiStyle.PANEL_BORDER, 18.0))
	column.add_child(panel)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 8)
	panel.add_child(grid)

	grid.add_child(make_label("Difficulty", 20, TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	difficulty_option = OptionButton.new()
	for i in difficulty_names.size():
		difficulty_option.add_item(difficulty_names[i], i)
	difficulty_option.custom_minimum_size = Vector2(200, 40)
	difficulty_option.add_theme_font_size_override("font_size", UiStyle.px(20))
	grid.add_child(difficulty_option)

	grid.add_child(make_label("Graphics", 20, TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	pixel_check = make_check("Pixel art")
	blood_check = make_check("Blood")
	var graphics := HBoxContainer.new()
	graphics.add_theme_constant_override("separation", 24)
	graphics.add_child(pixel_check)
	graphics.add_child(blood_check)
	grid.add_child(graphics)

	if campaign.owned_count() > 1:
		column.add_child(make_label("%d / %d rigs held" % [campaign.owned_count(), campaign.rig_count()], 16, MUTED))

	play_button = make_button("PLAY", true)
	play_button.pressed.connect(play_pressed.emit)
	play_button.pressed.connect(func() -> void: Sfx.play_2d("ui_click"))
	column.add_child(play_button)

	# Hangar and Quit side by side to keep the menu compact.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)

	var hangar_button := make_button("HANGAR   $%s" % UiStyle.format_money(profile.money), false)
	hangar_button.custom_minimum_size = Vector2(0, 48)
	hangar_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hangar_button.size_flags_stretch_ratio = 2.0
	hangar_button.pressed.connect(func() -> void:
		Sfx.play_2d("ui_click")
		hangar_pressed.emit())
	row.add_child(hangar_button)

	var quit_button := make_button("QUIT", false)
	quit_button.custom_minimum_size = Vector2(0, 48)
	quit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit_button.pressed.connect(quit_pressed.emit)
	row.add_child(quit_button)

	# Sandbox for trying every enemy and weapon; never saves.
	var test_button := make_button("TEST RANGE", false)
	test_button.custom_minimum_size = Vector2(0, 40)
	test_button.add_theme_font_size_override("font_size", UiStyle.px(18))
	test_button.pressed.connect(func() -> void:
		Sfx.play_2d("ui_click")
		test_range_pressed.emit())
	column.add_child(test_button)

	column.add_child(make_spacer(2))
	column.add_child(make_label("WASD fly   |   Mouse aim   |   LMB / RMB fire   |   Ctrl fly low   |   Shift dash   |   F flares   |   Esc menu", 16, MUTED))


func make_label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", UiStyle.px(size))
	label.add_theme_color_override("font_color", color)
	return label


func make_spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func make_check(text: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.add_theme_font_size_override("font_size", UiStyle.px(18))
	# The default icons are too dark on this background.
	check.add_theme_icon_override("unchecked", make_box_icon(false))
	check.add_theme_icon_override("checked", make_box_icon(true))
	return check


# Outlined square; filled with the accent colour when checked.
func make_box_icon(checked: bool) -> ImageTexture:
	var size := 20
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	for y in size:
		for x in size:
			var edge := x < 2 or y < 2 or x >= size - 2 or y >= size - 2
			if edge:
				image.set_pixel(x, y, ACCENT if checked else MUTED)
			elif checked and x >= 5 and y >= 5 and x < size - 5 and y < size - 5:
				image.set_pixel(x, y, ACCENT)

	return ImageTexture.create_from_image(image)


func make_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 48)
	button.add_theme_font_size_override("font_size", UiStyle.px(24))

	var fill := ACCENT if primary else Color(0.2, 0.23, 0.21)
	var text_color := Color(0.08, 0.08, 0.06) if primary else TEXT

	button.add_theme_stylebox_override("normal", make_button_style(fill))
	button.add_theme_stylebox_override("hover", make_button_style(fill.lightened(0.15)))
	button.add_theme_stylebox_override("pressed", make_button_style(fill.darkened(0.15)))
	# Focus draws on top of the other styles, so only add an outline.
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_corner_radius_all(6)
	focus.set_border_width_all(2)
	focus.border_color = Color(1, 1, 1, 0.6)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", make_button_style(Color(0.25, 0.25, 0.25)))
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_color_override("font_disabled_color", MUTED)
	return button


func make_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	return style


func read_settings(settings: GameSettings) -> void:
	difficulty_option.select(clampi(settings.difficulty, 0, difficulty_names.size() - 1))
	pixel_check.button_pressed = settings.pixel_art
	blood_check.button_pressed = settings.blood


# Copies the menu choices into `settings` (before playing or opening the
# hangar; the context saves them).
func write_settings(settings: GameSettings) -> void:
	settings.difficulty = difficulty_option.get_selected_id()
	settings.pixel_art = pixel_check.button_pressed
	settings.blood = blood_check.button_pressed
