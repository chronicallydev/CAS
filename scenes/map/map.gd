extends Node3D

# Campaign map screen: pick a rig on the 3D map, then assault it (enemy
# rig linked to one you own) or defend it (owned rig). Owned rigs can be
# upgraded in the briefing panel. The UI is built in code: a tab bar with
# a rigs-held dial, and a gradient briefing panel down the right side.

const UiStyle := preload("res://scenes/ui/ui_style.gd")
const Campaign := preload("res://scenes/map/campaign.gd")
const MapWorld := preload("res://scenes/map/map_world.gd")
const Markers := preload("res://scenes/map/map_markers.gd")

const GOLD := UiStyle.GOLD
const TEXT := Color(0.93, 0.93, 0.9)
const MUTED := Color(0.66, 0.66, 0.63)
const GOOD := Color(0.45, 0.9, 0.5)
const DANGER := Color(1.0, 0.4, 0.32)

var title_font: Font
var world: MapWorld
var markers: Markers
var ui_root: Control
var info: VBoxContainer
var money_label: Label
var income_label: Label
var dial: Control
var selected: String = ""


func _ready() -> void:
	title_font = UiStyle.FONT
	world = MapWorld.new()
	add_child(world)
	build_ui()
	select(default_selection())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Global.go_to_menu()
	elif event is InputEventMouseMotion:
		var index := rig_at(event.position)
		if index != markers.hovered:
			markers.hovered = index
			world.set_hovered(index)
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if index >= 0 else Input.CURSOR_ARROW)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var index := rig_at(event.position)
		if index >= 0:
			Sfx.play_2d("ui_click")
			select(Campaign.RIG_ORDER[index])


func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


# Rig under a screen point: its badge first, then the region it owns.
func rig_at(point: Vector2) -> int:
	var badge := markers.badge_at(point)
	if badge >= 0:
		return badge
	return world.region_at_screen(point)


# The last mission's rig, else the first rig you can attack.
func default_selection() -> String:
	var last: String = Global.mission.get("rig", "")
	if last != "" and Campaign.RIGS.has(last):
		return last
	for id in Campaign.RIG_ORDER:
		if Campaign.can_attack(id):
			return id
	return Campaign.HOME


# --- Helpers -------------------------------------------------------------------

func label(text: String, size: int, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiStyle.px(size))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# Dark button with a gold border, like the reference's briefing button.
func command_button(text: String, size: int, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", UiStyle.px(size))
	var border := GOLD if enabled else Color(0.4, 0.4, 0.4, 0.6)
	var normal := UiStyle.gradient_panel(Color(0.2, 0.19, 0.16, 0.95), Color(0.08, 0.08, 0.08, 0.95), border, 6.0)
	var hover := UiStyle.gradient_panel(Color(0.42, 0.33, 0.18, 0.95), Color(0.16, 0.13, 0.08, 0.95), GOLD.lightened(0.3), 6.0)
	for style in [normal, hover]:
		style.content_margin_left = 14
		style.content_margin_right = 14
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover if enabled else normal)
	b.add_theme_stylebox_override("pressed", hover if enabled else normal)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var text_color := GOLD.lightened(0.15) if enabled else Color(0.5, 0.5, 0.5)
	for key in ["font_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(key, text_color)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.75))
	b.disabled = not enabled
	b.pressed.connect(func() -> void: Sfx.play_2d("ui_click"))
	return b


# Top-bar tab; the current one is boxed in gold.
func tab_button(text: String, active: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 0)
	b.add_theme_font_size_override("font_size", UiStyle.px(18))
	var empty := StyleBoxEmpty.new()
	var boxed := UiStyle.gradient_panel(Color(0.36, 0.28, 0.15, 0.9), Color(0.14, 0.11, 0.07, 0.9), GOLD, 4.0)
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, boxed if active else empty)
	b.add_theme_stylebox_override("focus", empty)
	b.add_theme_color_override("font_color", GOLD if active else TEXT)
	b.add_theme_color_override("font_hover_color", GOLD.lightened(0.2))
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.pressed.connect(func() -> void: Sfx.play_2d("ui_click"))
	return b


# Section title with a fading gold underline.
func section(title: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(label(title, 18, TEXT))
	box.add_child(UiStyle.header_line(Color(GOLD, 0.7)))
	return box


# Muted body text that wraps inside the panel. [gold]...[/gold] marks the
# highlighted words, like the names in a mission briefing.
func briefing(text: String) -> RichTextLabel:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rich.custom_minimum_size = Vector2(330, 0)
	rich.add_theme_font_size_override("normal_font_size", UiStyle.px(13))
	rich.add_theme_color_override("default_color", MUTED)
	rich.text = text.replace("[gold]", "[color=#%s]" % GOLD.to_html(false)).replace("[/gold]", "[/color]")
	return rich


# A name on the left and values right-aligned in fixed columns.
func table_row(name: String, values: Array, color: Color = TEXT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := label(name, 13, color)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	for value in values:
		var v := label(value, 13, color)
		v.custom_minimum_size = Vector2(70, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(v)
	return row


func format_money(value: int) -> String:
	var text := str(value)
	var out := ""
	while text.length() > 3:
		out = "," + text.right(3) + out
		text = text.left(text.length() - 3)
	return text + out


func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


# --- Layout ------------------------------------------------------------------

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)

	markers = Markers.new()
	markers.world = world
	markers.title_font = title_font
	ui_root.add_child(markers)

	build_top_bar()

	# Briefing panel down the right side.
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -394
	panel.offset_right = -18
	panel.offset_top = 96
	panel.offset_bottom = -18
	panel.add_theme_stylebox_override("panel", UiStyle.gradient_panel(UiStyle.PANEL_TOP, UiStyle.PANEL_BOTTOM, UiStyle.PANEL_BORDER, 16.0))
	ui_root.add_child(panel)

	info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	panel.add_child(info)

	# Legend in the bottom-left corner.
	var legend := PanelContainer.new()
	legend.add_theme_stylebox_override("panel", UiStyle.gradient_panel(UiStyle.PANEL_TOP, UiStyle.PANEL_BOTTOM, UiStyle.PANEL_BORDER, 6.0))
	legend.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	legend.offset_left = 18
	legend.offset_bottom = -18
	legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(legend)
	var legend_row := HBoxContainer.new()
	legend_row.add_theme_constant_override("separation", 16)
	legend_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend.add_child(legend_row)
	for entry in [["MENU [Esc]", TEXT], ["Your territory", GOOD], ["Front line", DANGER], ["Out of reach", MUTED]]:
		legend_row.add_child(label(entry[0], 13, entry[1]))


func build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 56
	bar.add_theme_stylebox_override("panel", UiStyle.gradient_panel(Color(0.02, 0.02, 0.03, 0.97), Color(0.11, 0.11, 0.12, 0.92), Color(0, 0, 0, 0), 0.0))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	row.add_child(tab_button("MAP", true))
	var hangar := tab_button("HANGAR", false)
	hangar.pressed.connect(Global.go_to_hangar)
	row.add_child(hangar)
	var menu := tab_button("MENU", false)
	menu.pressed.connect(Global.go_to_menu)
	row.add_child(menu)

	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)

	# Income tag, then the wallet.
	var income_box := PanelContainer.new()
	income_box.add_theme_stylebox_override("panel", UiStyle.gradient_panel(Color(0.2, 0.38, 0.2, 0.95), Color(0.08, 0.2, 0.09, 0.95), Color(GOOD, 0.7), 4.0))
	income_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	income_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(income_box)
	income_label = label("", 13, Color.WHITE)
	income_box.add_child(income_label)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(20, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)

	money_label = label("", 24, TEXT)
	row.add_child(money_label)

	# Rigs-held dial with a territory bar under it, centred on the bar.
	dial = RigsDial.new()
	dial.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	dial.offset_left = -170
	dial.offset_right = 170
	dial.offset_top = 0
	dial.offset_bottom = 84
	ui_root.add_child(dial)


func select(id: String) -> void:
	selected = id
	var index := Campaign.RIG_ORDER.find(id)
	markers.selected = index
	world.set_selected(index)
	refresh()


func refresh() -> void:
	money_label.text = "$%s" % format_money(Global.money)
	income_label.text = "INCOME +$%s / MISSION" % format_money(Campaign.total_income())
	dial.queue_redraw()
	build_info()


func build_info() -> void:
	clear(info)
	var rig: Dictionary = Campaign.RIGS[selected]
	var owned := Campaign.is_owned(selected)
	var attackable := Campaign.can_attack(selected)

	# Hexagon icon and the rig's name, centred.
	var icon := RigIcon.new()
	icon.custom_minimum_size = Vector2(0, 54)
	icon.color = GOOD if owned else DANGER
	icon.owned = owned
	info.add_child(icon)

	var title := label(rig["name"].to_upper(), 26, TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(title)

	var status := "FRIENDLY" if owned else ("FRONT LINE" if attackable else "ENEMY TERRITORY")
	var status_color := GOOD if owned else (DANGER if attackable else MUTED)
	var meta := label("%s  |  THREAT LVL %d" % [status, rig["level"] + 1], 13, status_color)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(meta)

	info.add_child(section("DEFENCE BRIEFING" if owned else "MISSION BRIEFING"))
	info.add_child(briefing("[gold]%s:[/gold] %s\n[gold]Garrison: %s.[/gold]" % [rig["name"].to_upper(), rig["description"], Campaign.profile(selected)["label"]]))

	info.add_child(section("OBJECTIVES"))
	info.add_child(table_row("", ["COUNT", "BONUS"], MUTED))
	if owned:
		info.add_child(table_row("Hold the rig", ["Endless", "Kills"]))
	else:
		var forts: Array = rig["forts"]
		info.add_child(table_row("Clear the garrison", ["%d waves" % rig["waves"], "$%s" % format_money(Campaign.capture_bonus(selected))]))
		info.add_child(table_row("Destroy bunkers", [str(forts[0]), "Required"]))
		info.add_child(table_row("Destroy flak guns", [str(forts[1]), "Required"]))
		info.add_child(table_row("Kill the commander", ["Final", "Capture"]))

	info.add_child(section("REWARD"))
	var income: int = Campaign.income(selected) if owned else rig["income"]
	info.add_child(table_row("Oil income", ["+$%s / mission" % format_money(income)], GOOD))
	if owned:
		info.add_child(table_row("Rig hull", ["%d" % int(100.0 + Campaign.hull_bonus(selected))]))
		info.add_child(section("UPGRADES"))
		for key in ["output", "hull"]:
			info.add_child(upgrade_row(key))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(spacer)

	var action: Button
	if owned:
		action = command_button("DEFEND RIG", 22)
	elif attackable:
		action = command_button("LAUNCH ASSAULT", 22)
	else:
		var hint := label("Capture a linked rig first.", 13, MUTED)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(hint)
		action = command_button("OUT OF REACH", 22, false)
	action.custom_minimum_size = Vector2(0, 42)
	action.pressed.connect(func() -> void: Global.start_mission(selected))
	info.add_child(action)


func upgrade_row(key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var level := Campaign.level(selected, key)
	var name := label(Campaign.RIG_UPGRADES[key]["label"], 13)
	name.custom_minimum_size = Vector2(80, 0)
	row.add_child(name)

	# Level pips.
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 3)
	pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in Campaign.MAX_LEVEL:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(12, 12)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.color = GOLD if i < level else Color(0.3, 0.3, 0.3)
		pips.add_child(pip)
	row.add_child(pips)

	var button: Button
	if level >= Campaign.MAX_LEVEL:
		button = command_button("MAX", 13, false)
	else:
		var cost := Campaign.upgrade_cost(selected, key)
		button = command_button("$%s" % format_money(cost), 13, Global.money >= cost)
		button.pressed.connect(func() -> void:
			if Campaign.buy_upgrade(selected, key):
				Sfx.play_2d("combo")
				refresh())
	button.custom_minimum_size = Vector2(100, 28)
	row.add_child(button)
	return row


# --- Drawn widgets ---------------------------------------------------------------

# The rig's hexagon badge at the top of the briefing panel.
class RigIcon extends Control:
	const Markers := preload("res://scenes/map/map_markers.gd")
	var color: Color
	var owned: bool

	func _draw() -> void:
		var centre := size / 2.0
		draw_colored_polygon(Markers.hexagon(centre, 26.0), Color(0.04, 0.04, 0.04))
		draw_colored_polygon(Markers.hexagon(centre, 23.0), color.darkened(0.15))
		draw_polyline(Markers.close(Markers.hexagon(centre, 20.0)), Color(1, 1, 1, 0.25), 1.0)
		Markers.draw_derrick(self, centre, 1.3, owned)


# "2/7 RIGS HELD" dial over a bar of the territory held, like a campaign
# countdown clock.
class RigsDial extends Control:
	const Campaign := preload("res://scenes/map/campaign.gd")
	const UiStyle := preload("res://scenes/ui/ui_style.gd")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := UiStyle.FONT
		var held: int = Global.owned_rigs.size()
		var total: int = Campaign.RIGS.size()
		var centre := Vector2(size.x / 2.0 - 64.0, 30.0)

		# Tag to the right of the dial.
		var tag := Rect2(centre + Vector2(22, -14), Vector2(150, 28))
		draw_rect(tag, Color(0.2, 0.2, 0.21, 0.97))
		draw_rect(tag, Color(1, 1, 1, 0.14), false, 1.0)
		draw_string(font, tag.position + Vector2(20, 20), "RIGS HELD", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.93, 0.93, 0.9))

		# Dial: dark disc, a ring filled by the share held, the count.
		draw_circle(centre, 30.0, Color(0.03, 0.03, 0.04))
		draw_arc(centre, 25.0, 0.0, TAU, 48, Color(0.32, 0.32, 0.32), 3.0)
		draw_arc(centre, 25.0, -PI / 2.0, -PI / 2.0 + TAU * held / total, 48, Color(0.93, 0.93, 0.9), 3.0)
		var text := "%d/%d" % [held, total]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(font, centre + Vector2(-width / 2.0, 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)

		# Territory bar: one cell per rig, green held and red enemy.
		var bar := Rect2(Vector2(size.x / 2.0 - 150.0, 64.0), Vector2(300.0, 10.0))
		draw_rect(bar.grow(2.0), Color(0.03, 0.03, 0.03, 0.95))
		var cell := bar.size.x / total
		for i in total:
			var owned := Global.owned_rigs.has(Campaign.RIG_ORDER[i])
			var color := Color(0.3, 0.75, 0.38) if owned else Color(0.62, 0.14, 0.12)
			draw_rect(Rect2(bar.position + Vector2(cell * i + 1.0, 0), Vector2(cell - 2.0, bar.size.y)), color)
