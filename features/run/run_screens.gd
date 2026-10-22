class_name RunScreens
extends CanvasLayer

# The run's own screens, over the game, in the 1-bit style (white panels,
# heavy black borders, inverted on hover). Built in code; they keep
# running while the game is paused.
#   banner     - big callout mid-screen ("INTERCEPT", "GO"), fades itself
#   go         - chevrons flashing at the top edge: the way ahead is open
#   leftovers  - "2 LEFT" under the top edge while the last few enemies
#                are marked
#   picks      - pick one of three upgrades (click, or 1 / 2 / 3)
#   end screen - shot down or run complete, with the run's numbers and
#                retry (R) / test range (T)

const PAPER := Color.WHITE
const INK := Color.BLACK
# The go chevrons: each one's width and height, and the gap between their
# centres, in pixels.
const GO_SIZE := Vector2(84.0, 44.0)
const GO_SPACING := 118.0

var banner: Label
var banner_tween: Tween
var go_arrows: Control
var go_tween: Tween
var left_label: Label
var left_tween: Tween
var overlay: Control
# The pick buttons' actions while the picks are up, for the number keys.
var pick_actions: Array = []
var end_actions: Dictionary = {}


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	banner = text_label("", 72)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.modulate.a = 0.0
	add_child(banner)
	go_arrows = Control.new()
	go_arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	go_arrows.size = Vector2(GO_SPACING * 2.0 + GO_SIZE.x, GO_SIZE.y)
	go_arrows.draw.connect(draw_go_arrows)
	go_arrows.modulate.a = 0.0
	add_child(go_arrows)
	left_label = text_label("", 44)
	left_label.modulate.a = 0.0
	add_child(left_label)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.physical_keycode
	if not pick_actions.is_empty() and key >= KEY_1 and key < KEY_1 + pick_actions.size():
		pick_actions[key - KEY_1].call()
		get_viewport().set_input_as_handled()
	elif end_actions.has(key):
		end_actions[key].call()
		get_viewport().set_input_as_handled()


# --- Banner --------------------------------------------------------------------

## A big callout mid-screen that punches in and fades out on its own.
func show_banner(text: String) -> void:
	banner.text = text
	banner.reset_size()
	banner.position = Vector2((banner.get_viewport_rect().size.x - banner.size.x) * 0.5, banner.get_viewport_rect().size.y * 0.22)
	banner.pivot_offset = banner.size * 0.5
	if banner_tween != null:
		banner_tween.kill()
	banner.modulate.a = 1.0
	banner.scale = Vector2.ONE * 1.8
	banner_tween = create_tween().set_ignore_time_scale(true)
	banner_tween.tween_property(banner, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	banner_tween.tween_interval(1.1)
	banner_tween.tween_property(banner, "modulate:a", 0.0, 0.35)


# --- Go and leftovers ----------------------------------------------------------

## Chevrons flashing at the top edge for a few seconds: fly on.
func show_go() -> void:
	place_top(go_arrows, 0.045)
	if go_tween != null:
		go_tween.kill()
	go_tween = create_tween().set_ignore_time_scale(true)
	for k in 6:
		go_tween.tween_property(go_arrows, "modulate:a", 1.0, 0.05)
		go_tween.tween_property(go_arrows, "position:y", go_arrows.position.y - 14.0, 0.25).set_ease(Tween.EASE_OUT)
		go_tween.tween_interval(0.2)
		go_tween.tween_property(go_arrows, "modulate:a", 0.0, 0.05)
		go_tween.tween_property(go_arrows, "position:y", go_arrows.position.y, 0.0)
		go_tween.tween_interval(0.15)


func hide_go() -> void:
	if go_tween != null:
		go_tween.kill()
	go_arrows.modulate.a = 0.0


## "n LEFT" under the top edge, punching in when it changes; 0 hides it.
func show_leftovers(count: int) -> void:
	if left_tween != null:
		left_tween.kill()
	if count <= 0:
		left_label.modulate.a = 0.0
		return
	left_label.text = "%d LEFT" % count
	place_top(left_label, 0.1)
	left_label.modulate.a = 1.0
	left_label.pivot_offset = left_label.size * 0.5
	left_label.scale = Vector2.ONE * 1.5
	left_tween = create_tween().set_ignore_time_scale(true)
	left_tween.tween_property(left_label, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


# Centres `label` across the screen, `fraction` of the height down.
func place_top(label: Control, fraction: float) -> void:
	if label is Label:
		label.reset_size()
	var view := label.get_viewport_rect().size
	label.position = Vector2((view.x - label.size.x) * 0.5, view.y * fraction)


# --- Upgrade picks -------------------------------------------------------------

## Shows `options` (RunUpgrades entries); `on_pick` gets the chosen id.
func show_picks(title: String, options: Array, on_pick: Callable) -> void:
	var box := open_overlay(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	box.add_child(row)
	pick_actions.clear()
	for i in options.size():
		var option: Dictionary = options[i]
		var choose := func() -> void:
			close_overlay()
			on_pick.call(option.id)
		pick_actions.append(choose)
		var card := card_button("%d\n\n%s\n\n%s" % [i + 1, option.name, option.text], choose)
		card.custom_minimum_size = Vector2(300, 260)
		row.add_child(card)


# --- End screen ----------------------------------------------------------------

## The run is over: `lines` of numbers, then retry and test range.
func show_end(title: String, lines: Array, on_retry: Callable, on_test_range: Callable) -> void:
	var box := open_overlay(title)
	for line: String in lines:
		var label := text_label(line, 30, INK)
		label.add_theme_constant_override("outline_size", 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	box.add_child(row)
	var close_then := func(action: Callable) -> Callable:
		return func() -> void:
			close_overlay()
			action.call()
	var retry_action: Callable = close_then.call(on_retry)
	var test_range_action: Callable = close_then.call(on_test_range)
	var retry := card_button("RETRY  [R]", retry_action)
	var test_range := card_button("TEST RANGE  [T]", test_range_action)
	for button in [retry, test_range]:
		button.custom_minimum_size = Vector2(320, 80)
		row.add_child(button)
	end_actions = {KEY_R: retry_action, KEY_T: test_range_action}


# --- Pieces --------------------------------------------------------------------

# A full-screen dimmed overlay with a white panel; returns its column.
func open_overlay(title: String) -> VBoxContainer:
	close_overlay()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box_style(PAPER, 6, 36))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	panel.add_child(box)
	var heading := text_label(title, 56, INK)
	heading.remove_theme_color_override("font_outline_color")
	heading.add_theme_constant_override("outline_size", 0)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	return box


func close_overlay() -> void:
	pick_actions.clear()
	end_actions.clear()
	if overlay != null:
		overlay.queue_free()
		overlay = null


func card_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", UiStyle.px(34))
	button.add_theme_stylebox_override("normal", box_style(PAPER, 5, 18))
	button.add_theme_stylebox_override("hover", box_style(INK, 5, 18))
	button.add_theme_stylebox_override("pressed", box_style(INK, 5, 18))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", PAPER)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.pressed.connect(func() -> void:
		Sfx.play_2d("ui_click")
		action.call())
	return button


func box_style(fill: Color, border: int, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = INK if fill == PAPER else PAPER
	style.set_border_width_all(border)
	style.set_content_margin_all(margin)
	return style


func text_label(text: String, size: int, color: Color = PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UiStyle.px(size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# Three upward chevrons: thick white strokes on black ones, so they read
# on any ground in 1-bit.
func draw_go_arrows() -> void:
	for k in 3:
		var centre_x := (GO_SIZE.x * 0.5 + GO_SPACING * k)
		var points := PackedVector2Array([
			Vector2(centre_x - GO_SIZE.x * 0.5, GO_SIZE.y),
			Vector2(centre_x, 0.0),
			Vector2(centre_x + GO_SIZE.x * 0.5, GO_SIZE.y),
		])
		go_arrows.draw_polyline(points, INK, 30.0)
		go_arrows.draw_polyline(points, PAPER, 16.0)
