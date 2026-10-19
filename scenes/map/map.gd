extends Control

# Campaign map screen: pick a rig, then assault it (enemy rig linked to
# one you own) or defend it (owned rig). Owned rigs can be upgraded here.
# Built in code, styled like the hangar.

const Campaign := preload("res://scenes/map/campaign.gd")
const MapView := preload("res://scenes/map/map_view.gd")

const ORANGE := Color(0.95, 0.45, 0.12)
const PANEL_BG := Color(0.07, 0.07, 0.07, 0.88)
const TEXT := Color(0.95, 0.95, 0.93)
const MUTED := Color(0.65, 0.65, 0.62)
const GOOD := Color(0.45, 0.9, 0.5)
const DANGER := Color(1.0, 0.4, 0.32)

var title_font: Font
var map_view: Control
var info: VBoxContainer
var money_label: Label
var income_label: Label
var selected: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_font = SystemFont.new()
	title_font.font_names = PackedStringArray(["Impact", "Arial Black", "Arial"])
	title_font.font_weight = 800
	build_ui()
	select(default_selection())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Global.go_to_menu()


# The last mission's rig, else the first rig you can attack.
func default_selection() -> String:
	var last: String = Global.mission.get("rig", "")
	if last != "" and Campaign.RIGS.has(last):
		return last
	for id in Campaign.RIG_ORDER:
		if Campaign.can_attack(id):
			return id
	return Campaign.HOME


# --- Helpers (match the hangar's look) ------------------------------------

func label(text: String, size: int, color: Color = TEXT, title: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if title:
		l.add_theme_font_override("font", title_font)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 5 if title else 3)
	return l


func flat(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_content_margin_all(10)
	return style


func stencil_button(text: String, size: int, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", title_font)
	b.add_theme_font_size_override("font_size", size)
	var normal := flat(Color(0.95, 0.95, 0.93) if enabled else Color(0.4, 0.4, 0.4))
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = ORANGE
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover if enabled else normal)
	b.add_theme_stylebox_override("pressed", hover if enabled else normal)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", normal)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(key, Color(0.06, 0.06, 0.06) if enabled else Color(0.2, 0.2, 0.2))
	b.disabled = not enabled
	b.pressed.connect(func() -> void: Sfx.play_2d("ui_click"))
	return b


func text_button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.add_theme_font_override("font", title_font)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", ORANGE)
	b.add_theme_color_override("font_pressed_color", ORANGE)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	b.add_theme_constant_override("outline_size", 6)
	b.pressed.connect(func() -> void: Sfx.play_2d("ui_click"))
	return b


# Muted text that wraps inside the info panel instead of widening it.
func wrapped(text: String, size: int) -> Label:
	var l := label(text, size, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(330, 0)
	return l


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
	var background := ColorRect.new()
	background.color = Color(0.09, 0.08, 0.07)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	# Top bar.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 30)
	column.add_child(bar)

	var back := text_button("BACK", 30)
	back.pressed.connect(Global.go_to_menu)
	bar.add_child(back)

	var hangar := text_button("HANGAR", 30)
	hangar.pressed.connect(Global.go_to_hangar)
	bar.add_child(hangar)

	var title := label("THEATRE MAP", 34, ORANGE, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(title)

	var wallet := VBoxContainer.new()
	wallet.add_theme_constant_override("separation", -4)
	bar.add_child(wallet)
	money_label = label("", 28, TEXT, true)
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	income_label = label("", 16, GOOD)
	income_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wallet.add_child(money_label)
	wallet.add_child(income_label)

	# Map and info panel.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	column.add_child(body)

	map_view = MapView.new()
	map_view.title_font = title_font
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.rig_selected.connect(select)
	body.add_child(map_view)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(370, 0)
	var panel_style := flat(PANEL_BG)
	panel_style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", panel_style)
	body.add_child(panel)

	info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	panel.add_child(info)

	column.add_child(label("Green: your rigs   ·   Orange: rigs you can attack   ·   Red: out of reach   ·   Every rig you own pays out after each mission", 13, MUTED))


func select(id: String) -> void:
	selected = id
	map_view.selected = id
	refresh()


func refresh() -> void:
	money_label.text = "$%s" % format_money(Global.money)
	income_label.text = "+$%s per mission  ·  %d / %d rigs" % [format_money(Campaign.total_income()), Global.owned_rigs.size(), Campaign.RIGS.size()]
	build_info()


func build_info() -> void:
	clear(info)
	var rig: Dictionary = Campaign.RIGS[selected]
	var owned := Campaign.is_owned(selected)
	var attackable := Campaign.can_attack(selected)

	var status := "FRIENDLY" if owned else ("FRONT LINE" if attackable else "ENEMY TERRITORY")
	var status_color := GOOD if owned else (ORANGE if attackable else DANGER)
	info.add_child(label(status, 14, status_color, true))
	info.add_child(label(rig["name"].to_upper(), 28, TEXT, true))

	info.add_child(wrapped(rig["description"], 15))

	info.add_child(HSeparator.new())

	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 24)
	stats.add_theme_constant_override("v_separation", 2)
	info.add_child(stats)

	var add_stat := func(name: String, value: String, color: Color = TEXT) -> void:
		stats.add_child(label(name, 16, MUTED))
		stats.add_child(label(value, 16, color, true))

	add_stat.call("Threat level", str(rig["level"] + 1))
	add_stat.call("Garrison", Campaign.profile(selected)["label"])
	if owned:
		add_stat.call("Income", "$%s / mission" % format_money(Campaign.income(selected)), GOOD)
		add_stat.call("Rig hull", "%d" % int(100.0 + Campaign.hull_bonus(selected)))
	else:
		add_stat.call("To capture", "Clear %d waves" % rig["waves"])
		add_stat.call("Capture bonus", "$%s" % format_money(Campaign.capture_bonus(selected)), GOOD)
		add_stat.call("Income", "$%s / mission" % format_money(rig["income"]), GOOD)

	info.add_child(HSeparator.new())

	if owned:
		info.add_child(label("RIG UPGRADES", 17, ORANGE, true))
		for key in ["output", "hull"]:
			info.add_child(upgrade_row(key))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(spacer)

	var action: Button
	if owned:
		action = stencil_button("DEFEND", 26)
		info.add_child(wrapped("Endless waves. Earn kill money until you fall.", 13))
	elif attackable:
		action = stencil_button("ATTACK", 26)
		info.add_child(wrapped("Clear every wave to take the rig. Kill money is yours either way.", 13))
	else:
		action = stencil_button("OUT OF REACH", 26, false)
		info.add_child(wrapped("Capture a linked rig first.", 13))
	action.custom_minimum_size = Vector2(0, 46)
	action.pressed.connect(func() -> void: Global.start_mission(selected))
	info.add_child(action)


func upgrade_row(key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var level := Campaign.level(selected, key)
	var name := label(Campaign.RIG_UPGRADES[key]["label"], 16)
	name.custom_minimum_size = Vector2(90, 0)
	row.add_child(name)

	# Level pips.
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 4)
	pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in Campaign.MAX_LEVEL:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(16, 16)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.color = ORANGE if i < level else Color(0.3, 0.3, 0.3)
		pips.add_child(pip)
	row.add_child(pips)

	var button: Button
	if level >= Campaign.MAX_LEVEL:
		button = stencil_button("MAX", 16, false)
	else:
		var cost := Campaign.upgrade_cost(selected, key)
		button = stencil_button("$%s" % format_money(cost), 16, Global.money >= cost)
		button.pressed.connect(func() -> void:
			if Campaign.buy_upgrade(selected, key):
				Sfx.play_2d("combo")
				refresh())
	button.custom_minimum_size = Vector2(110, 0)
	row.add_child(button)
	return row
