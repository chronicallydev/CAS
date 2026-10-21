class_name TestRangePanel
extends CanvasLayer

# The test range's side panel, down the right edge. Built in code.
#   STATS      - (top, always in view) damage taken by source, damage dealt
#                and DPS, and the enemy under the cursor
#   SPAWN      - unit and count; middle-click or G drops them at the cursor
#   HELICOPTER - reset the range, god mode, instant flares and no reloads
#   LOOK       - retro palette, dither amount and pixel resolution (set on
#                the PixelArt autoload), the white hit flash and chunky
#                explosions; all last across resets
#   MOVEMENT   - live sliders for the flight model and dash; kept across
#                resets. COPY puts the changed values on the clipboard, to
#                bake into cobra.tres / helicopter.gd.
#
# The X (or Tab) closes it; the PANEL button (or Tab) brings it back.

const TEXT := Color(0.93, 0.93, 0.9)
const MUTED := Color(0.66, 0.66, 0.63)
const GOLD := UiStyle.GOLD
const GOOD := Color(0.45, 0.9, 0.5)
const DANGER := Color(1.0, 0.4, 0.32)

## What to spawn: an index into TestRangeContext.units(), and how many.
var selected_unit: int = 0
var spawn_count: int = 1
const COUNTS := [1, 3, 5, 10]
## Heights of the low-res image to pick from (PixelArt.target_height).
const RESOLUTIONS := [120.0, 144.0, 160.0, 180.0, 200.0, 240.0, 288.0]

## The movement sliders: [property, label, min, max, step], grouped by
## where the value lives. The airframe group comes from cobra.tres (the
## mission copies it onto the helicopter); the rest are helicopter.gd exports.
const MOVEMENT := [
	["Airframe (cobra.tres)", [
		["speed", "Top speed", 8.0, 60.0, 0.5],
		["acceleration", "Acceleration", 1.0, 20.0, 0.1],
		["turn_speed", "Agility", 1.0, 20.0, 0.1],
		["dash_cooldown", "Dash cooldown", 0.2, 10.0, 0.1],
	]],
	["Handling (helicopter.gd)", [
		["brake_ratio", "Stop time ratio", 0.1, 3.0, 0.05],
		["path_turn_scale", "Path turn / agility", 10.0, 200.0, 1.0],
		["reverse_angle", "Reverse angle", 60.0, 180.0, 1.0],
		["turn_scale", "Nose turn / agility", 0.5, 10.0, 0.1],
		["max_tilt_degrees", "Tilt", 0.0, 70.0, 0.5],
		["thrust_lean", "Thrust lean", 0.0, 4.0, 0.05],
	]],
	["Dash (helicopter.gd)", [
		["dash_distance", "Distance", 2.0, 40.0, 0.5],
		["dash_time", "Duration", 0.05, 0.6, 0.01],
		["dash_charges", "Charges", 1.0, 5.0, 1.0],
		["dash_exit_speed", "Exit speed", 0.5, 2.0, 0.05],
		["dash_carry", "Exit carry", 0.0, 1.0, 0.01],
	]],
]

var range_context: TestRangeContext
var panel: PanelContainer
# Shown in the panel's place while it is closed.
var open_button: Button
var setup_box: VBoxContainer
var stats_label: RichTextLabel
var _stats_timer: float = 0.0


func initialize(context: TestRangeContext) -> void:
	range_context = context
	layer = 20
	build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		set_open(not panel.visible)
		get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	panel.visible = open
	open_button.visible = not open


func _process(delta: float) -> void:
	_stats_timer -= delta
	if _stats_timer <= 0.0 and stats_label != null and panel.visible and range_context.mission != null:
		_stats_timer = 0.2
		update_stats()


# --- Widgets ----------------------------------------------------------------

func label(text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiStyle.px(size))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func button(text: String, action: Callable, size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", UiStyle.px(size))
	b.pressed.connect(func() -> void:
		Sfx.play_2d("ui_click")
		action.call())
	return b


func check(text: String, on: bool, action: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", UiStyle.px(14))
	c.toggled.connect(action)
	return c


func section(title: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(label(title, 18, GOLD))
	box.add_child(UiStyle.header_line(Color(GOLD, 0.7)))
	return box


# "Name   < value >" with arrows that call `step` with -1 / +1.
func stepper(name: String, value: String, step: Callable, name_width: float = 110.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_label := label(name, 14, MUTED)
	name_label.custom_minimum_size = Vector2(name_width, 0)
	row.add_child(name_label)
	row.add_child(button("<", func() -> void: step.call(-1)))
	var value_label := label(value)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value_label)
	row.add_child(button(">", func() -> void: step.call(1)))
	return row


# "Name  [----o----]  value". Calls `changed` with the new value; the name
# turns gold once the value differs from `original`.
func slider(name: String, value: float, original: float, min_value: float, max_value: float, step: float, changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_label := label(name, 13, GOLD if not is_equal_approx(value, original) else MUTED)
	name_label.custom_minimum_size = Vector2(130, 0)
	row.add_child(name_label)

	var bar := HSlider.new()
	bar.min_value = min_value
	bar.max_value = max_value
	bar.step = step
	bar.value = value
	bar.focus_mode = Control.FOCUS_NONE
	# The wheel scrolls the panel, not the value.
	bar.scrollable = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)

	var value_label := label(format_value(value, step), 13)
	value_label.custom_minimum_size = Vector2(46, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	bar.value_changed.connect(func(new_value: float) -> void:
		value_label.text = format_value(new_value, step)
		name_label.add_theme_color_override("font_color", GOLD if not is_equal_approx(new_value, original) else MUTED)
		changed.call(new_value))
	return row


func format_value(value: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % roundi(value)
	if step >= 0.1:
		return "%.1f" % value
	return "%.2f" % value


func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


# --- Layout -----------------------------------------------------------------

func build_ui() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -380
	panel.offset_right = -10
	panel.offset_top = 10
	# Leave the weapon readout in the bottom-right corner visible.
	panel.offset_bottom = -76
	panel.add_theme_stylebox_override("panel", UiStyle.gradient_panel(UiStyle.PANEL_TOP, UiStyle.PANEL_BOTTOM, UiStyle.PANEL_BORDER, 10.0))
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)

	# Title with the close button on the right.
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := label("TEST RANGE", 26, TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(button("X", set_open.bind(false), 16))
	var hint := label("Middle-click or G: spawn   |   Tab: panel   |   Esc: quit", 13, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)

	# Live stats first, so they stay in view without scrolling.
	column.add_child(section("STATS"))
	stats_label = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.scroll_active = false
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_label.add_theme_font_size_override("normal_font_size", UiStyle.px(13))
	stats_label.add_theme_color_override("default_color", TEXT)
	column.add_child(stats_label)
	column.add_child(button("RESET STATS", range_context.reset_stats))

	# Everything that depends on the range's state is rebuilt by refresh().
	setup_box = VBoxContainer.new()
	setup_box.add_theme_constant_override("separation", 6)
	column.add_child(setup_box)

	# Top-right corner, where the panel was.
	open_button = button("PANEL  [Tab]", set_open.bind(true), 16)
	open_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	open_button.offset_left = -150
	open_button.offset_right = -10
	open_button.offset_top = 10
	open_button.offset_bottom = 44
	open_button.visible = false
	add_child(open_button)


## Rebuilds the spawn and helicopter sections.
func refresh() -> void:
	clear(setup_box)
	build_spawn(setup_box)
	build_helicopter(setup_box)
	build_look(setup_box)
	build_movement(setup_box)


func build_spawn(box: VBoxContainer) -> void:
	box.add_child(section("SPAWN"))
	var units := range_context.units()
	box.add_child(stepper("Unit", units[selected_unit][0], func(step: int) -> void:
		selected_unit = posmod(selected_unit + step, units.size())
		refresh()))
	box.add_child(stepper("Count", str(spawn_count), func(step: int) -> void:
		spawn_count = COUNTS[posmod(COUNTS.find(spawn_count) + step, COUNTS.size())]
		refresh()))
	box.add_child(button("CLEAR ENEMIES", range_context.clear_enemies))


func build_helicopter(box: VBoxContainer) -> void:
	box.add_child(section("HELICOPTER"))
	box.add_child(button("RESET RANGE", range_context.rebuild, 16))

	box.add_child(check("God mode (hits count, no damage)", range_context.god_mode, func(on: bool) -> void:
		range_context.god_mode = on
		range_context.apply_cheats()))
	box.add_child(check("Instant flares, no reloads", range_context.infinite_ammo, func(on: bool) -> void:
		range_context.infinite_ammo = on
		range_context.apply_cheats()))


func build_look(box: VBoxContainer) -> void:
	box.add_child(section("LOOK"))
	box.add_child(stepper("Palette", RetroPalettes.LIST[PixelArt.palette].name, func(step: int) -> void:
		PixelArt.palette += step
		refresh()))
	box.add_child(slider("Dither", PixelArt.dither, 0.5, 0.0, 1.0, 0.05, func(value: float) -> void:
		PixelArt.dither = value))
	var height := PixelArt.target_height
	box.add_child(stepper("Resolution", "%dp" % roundi(height), func(step: int) -> void:
		var index := RESOLUTIONS.find(height)
		if index == -1:
			index = RESOLUTIONS.find(240.0)
		PixelArt.target_height = RESOLUTIONS[clampi(index + step, 0, RESOLUTIONS.size() - 1)]
		refresh()))
	box.add_child(check("White hit flash", HitFlash.enabled, func(on: bool) -> void:
		HitFlash.enabled = on))
	box.add_child(check("Chunky 12 fps explosions", ExplosionScene.chunky, func(on: bool) -> void:
		ExplosionScene.chunky = on))


func build_movement(box: VBoxContainer) -> void:
	box.add_child(section("MOVEMENT"))
	var c := range_context
	var heli := c.mission.helicopter
	for group in MOVEMENT:
		box.add_child(label(group[0], 15, TEXT))
		for entry in group[1]:
			var property: String = entry[0]
			var value: float = heli.get(property)
			var original: float = c.movement_defaults.get(property, value)
			box.add_child(slider(entry[1], value, original, entry[2], entry[3], entry[4], func(new_value: float) -> void:
				c.tune(property, new_value)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var reset := button("RESET MOVEMENT", func() -> void:
		c.reset_movement()
		refresh())
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(reset)
	var copy := button("COPY CHANGES", copy_movement)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)


## Puts the tuned values on the clipboard, grouped by the file they belong
## in, and prints them to the output too.
func copy_movement() -> void:
	var c := range_context
	var lines: Array[String] = []
	for group in MOVEMENT:
		var changed: Array[String] = []
		for entry in group[1]:
			var property: String = entry[0]
			if not c.movement_overrides.has(property):
				continue
			var value: float = c.movement_overrides[property]
			var original: float = c.movement_defaults[property]
			if is_equal_approx(value, original):
				continue
			changed.append("%s = %s   # was %s" % [property, format_value(value, entry[4]), format_value(original, entry[4])])
		if not changed.is_empty():
			lines.append("# " + group[0])
			lines.append_array(changed)
	var text := "\n".join(lines) if not lines.is_empty() else "# No movement changes"
	DisplayServer.clipboard_set(text)
	print(text)


func update_stats() -> void:
	var c := range_context
	var lines: Array[String] = []
	lines.append("[color=#%s]Damage taken:[/color] %.1f" % [GOLD.to_html(false), c.damage_taken_total])
	var sources := c.damage_by_source.keys()
	sources.sort_custom(func(a: String, b: String) -> bool: return c.damage_by_source[a] > c.damage_by_source[b])
	for source in sources:
		lines.append("   %s  %.1f" % [source, c.damage_by_source[source]])
	lines.append("[color=#%s]Damage dealt:[/color] %.1f   DPS %.1f" % [GOLD.to_html(false), c.damage_dealt_total, c.dps()])

	var heli := c.mission.helicopter
	var flares := "ready" if heli.flare_cooldown_left <= 0.0 else "%.1fs" % heli.flare_cooldown_left
	lines.append("Hull %d / %d   Flares %s" % [heli.health, heli.max_health, flares])
	# What the movement numbers add up to.
	var spool := heli.speed / maxf(heli.get_acceleration_rate(), 0.01)
	var stop := heli.speed / maxf(heli.get_brake_rate(), 0.01)
	lines.append("Speed %.1f / %.1f   0-full %.2fs   stop %.2fs" % [heli.velocity.length(), heli.speed, spool, stop])
	lines.append("Path turn %d°/s   dash %.1f m/s" % [roundi(heli.turn_speed * heli.path_turn_scale), heli.dash_distance / maxf(heli.dash_time, 0.01)])

	var enemy := c.enemy_under_cursor()
	if enemy == null:
		lines.append("[color=#%s]Hover an enemy for details[/color]" % MUTED.to_html(false))
	else:
		var name: String = enemy.get("display_name") if enemy.get("display_name") != "" else "INFANTRY"
		lines.append("[color=#%s]%s[/color]  HP %.1f / %.1f   Armour %d%%" % [DANGER.to_html(false), name, enemy.health, enemy.max_health, roundi(enemy.light_armor * 100.0)])
		if enemy.lock_timer > 0.0:
			lines.append("   LOCKING ON  %.1fs" % enemy.lock_timer)
	stats_label.text = "\n".join(lines)
