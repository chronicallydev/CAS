class_name HangarUI
extends CanvasLayer

# Hangar screen UI with three tabs: HANGAR (pick, buy and upgrade
# helicopters), LOADOUT (buy weapon units and mount them on the selected
# helicopter's hardpoints) and WORKSHOP (upgrade weapons). Built in code.
#
# Purchases go through the Loadout service. The UI doesn't save or change
# screens itself: it emits purchase_made, back_pressed and deploy_pressed
# for the hangar context, and heli_viewed so the 3D hangar can show the
# helicopter being looked at with its mounted weapons.

signal back_pressed
signal deploy_pressed
# Something was bought or reset; the profile needs saving.
signal purchase_made
signal heli_viewed(heli: HelicopterData, weapons: Array)

const ORANGE := Color(0.95, 0.45, 0.12)
const SELECT_BG := Color(0.45, 0.08, 0.04, 0.92)
const PANEL_BG := Color(0.07, 0.07, 0.07, 0.82)
const TEXT := Color(0.95, 0.95, 0.93)
const MUTED := Color(0.65, 0.65, 0.62)
const LOCKED := Color(0.45, 0.45, 0.45)

var loadout: Loadout
var profile: PlayerProfile

var tab: String = "hangar"
var viewing_heli: String = ""
var selected_weapon: String = ""

var title_font: Font
var tab_buttons: Dictionary = {}
var money_label: Label
var left_column: VBoxContainer
var right_panel: PanelContainer
var bottom_area: VBoxContainer


func initialize(loadout_service: Loadout) -> void:
	loadout = loadout_service
	profile = loadout.profile
	viewing_heli = loadout.selected_heli().id
	selected_weapon = loadout.catalog.weapons[0].id
	title_font = UiStyle.FONT
	build_ui()
	refresh()
	show_viewed()


# --- Widgets ----------------------------------------------------------------

func label(text: String, size: int, color: Color = TEXT, title: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiStyle.px(size))
	l.add_theme_color_override("font_color", color)
	if title:
		l.add_theme_font_override("font", title_font)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 5 if title else 3)
	return l


func flat(color: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_content_margin_all(10)
	return style


# Black-on-white stencil button, like "TEST FLIGHT" in the reference.
func stencil_button(text: String, size: int, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", title_font)
	b.add_theme_font_size_override("font_size", UiStyle.px(size))
	var normal := flat(Color(0.95, 0.95, 0.93) if enabled else Color(0.4, 0.4, 0.4))
	normal.set_content_margin_all(8)
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


# Plain text button for the top bar.
func text_button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.add_theme_font_override("font", title_font)
	b.add_theme_font_size_override("font_size", UiStyle.px(size))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", ORANGE)
	b.add_theme_color_override("font_pressed_color", ORANGE)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void: Sfx.play_2d("ui_click"))
	return b


# Card button with a dark fill, highlighted in orange when selected.
func card_button(min_size: Vector2, highlighted: bool) -> Button:
	var card := Button.new()
	card.custom_minimum_size = min_size
	var style := flat(SELECT_BG if highlighted else PANEL_BG, ORANGE if highlighted else Color(0, 0, 0, 0), 3 if highlighted else 0)
	card.add_theme_stylebox_override("normal", style)
	var hover: StyleBoxFlat = style.duplicate()
	hover.border_color = ORANGE
	hover.set_border_width_all(2)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return card


func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


# --- Layout -----------------------------------------------------------------

func build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Darken the top for the tab bar.
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	shade.offset_bottom = 74
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var back := text_button("BACK", 34)
	back.position = Vector2(30, 10)
	back.pressed.connect(back_pressed.emit)
	root.add_child(back)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 40)
	tabs.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	tabs.offset_left = -330
	tabs.offset_right = 330
	tabs.offset_top = 10
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(tabs)
	for name in ["hangar", "loadout", "workshop"]:
		var b := text_button(name.to_upper(), 34)
		b.pressed.connect(func() -> void:
			tab = name
			# The loadout is edited on the helicopter you fly.
			if name == "loadout" and viewing_heli != profile.selected_heli:
				viewing_heli = loadout.selected_heli().id
				show_viewed()
			refresh())
		tabs.add_child(b)
		tab_buttons[name] = b

	money_label = label("", 26, TEXT, true)
	money_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	money_label.offset_left = -260
	money_label.offset_right = -24
	money_label.offset_top = 16
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(money_label)

	left_column = VBoxContainer.new()
	left_column.position = Vector2(14, 96)
	left_column.custom_minimum_size = Vector2(300, 0)
	left_column.add_theme_constant_override("separation", 8)
	root.add_child(left_column)

	right_panel = PanelContainer.new()
	right_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right_panel.offset_left = -420
	right_panel.offset_right = -14
	right_panel.offset_top = 96
	# Wider content grows the panel leftwards, never off screen.
	right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_panel.add_theme_stylebox_override("panel", UiStyle.gradient_panel())
	root.add_child(right_panel)

	bottom_area = VBoxContainer.new()
	bottom_area.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom_area.offset_left = -330
	bottom_area.offset_right = 330
	bottom_area.offset_top = -150
	bottom_area.offset_bottom = -10
	bottom_area.alignment = BoxContainer.ALIGNMENT_END
	bottom_area.add_theme_constant_override("separation", 6)
	root.add_child(bottom_area)


# Rebuilds everything that depends on the tab, selection or money.
func refresh() -> void:
	money_label.text = "$ %s" % UiStyle.format_money(profile.money)

	for name in tab_buttons.keys():
		var b: Button = tab_buttons[name]
		var active: bool = name == tab
		b.add_theme_color_override("font_color", MUTED if active else TEXT)
		var underline := StyleBoxFlat.new()
		underline.bg_color = Color(0, 0, 0, 0)
		underline.border_color = ORANGE
		underline.border_width_bottom = 5 if active else 0
		underline.content_margin_bottom = 4
		b.add_theme_stylebox_override("normal", underline)
		b.add_theme_stylebox_override("hover", underline)
		b.add_theme_stylebox_override("pressed", underline)

	build_left_column()
	build_right_panel()
	build_bottom()


# Weapon cards and the reset button; the loadout tab shows the armory.
func build_left_column() -> void:
	clear(left_column)
	if tab == "loadout":
		build_armory()
		return

	for weapon in loadout.catalog.weapons:
		var id := weapon.id
		var card := card_button(Vector2(300, 58), tab == "workshop" and id == selected_weapon)
		card.pressed.connect(func() -> void:
			Sfx.play_2d("ui_click")
			selected_weapon = id
			tab = "workshop"
			refresh())

		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12
		row.add_theme_constant_override("separation", 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(row)

		var tag := label(weapon.weight_class, 15, TEXT, true)
		tag.custom_minimum_size = Vector2(66, 0)
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(tag)

		var divider := ColorRect.new()
		divider.color = Color(1, 1, 1, 0.3)
		divider.custom_minimum_size = Vector2(2, 0)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(divider)

		var info := VBoxContainer.new()
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(info)
		info.add_child(label(weapon.display_name, 17))
		var max_total := loadout.catalog.max_level * weapon.upgrades.size()
		info.add_child(label("Upgrades  %d / %d   |   Owned  %d" % [loadout.weapon_level(id), max_total, loadout.owned_count(id)], 13, MUTED))

		left_column.add_child(card)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	left_column.add_child(spacer)

	# Refunds upgrades only; bought weapon units are kept.
	var refund := loadout.spent_on_upgrades()
	var reset := stencil_button("RESET  (+$%s)" % UiStyle.format_money(refund) if refund > 0 else "RESET", 22, refund > 0)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		loadout.reset_upgrades()
		purchase_made.emit()
		refresh())
	left_column.add_child(reset)


# Loadout tab: one panel per weapon with units owned, whether the shown
# helicopter can use it, and a button to buy another unit. Weapons the
# helicopter can't use are greyed out but can still be bought for others.
func build_armory() -> void:
	for weapon in loadout.catalog.weapons:
		var id := weapon.id
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(300, 0)
		panel.add_theme_stylebox_override("panel", flat(PANEL_BG))
		left_column.add_child(panel)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var usable := loadout.can_use(loadout.heli(viewing_heli), id)
		info.add_child(label(weapon.display_name, 17, TEXT if usable else LOCKED))
		var status := "Mounted %d" % loadout.mounted_count(viewing_heli, id) if usable else "Not for this helicopter"
		info.add_child(label("Owned %d   |   %s" % [loadout.owned_count(id), status], 13, MUTED if usable else LOCKED))

		var buy := stencil_button("+ $%s" % UiStyle.format_money(weapon.price), 16, profile.can_afford(weapon.price))
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buy.pressed.connect(func() -> void: buy_weapon(id))
		row.add_child(buy)


# Details of the helicopter (hangar tab), its hardpoints (loadout tab) or
# a weapon (workshop tab).
func build_right_panel() -> void:
	clear(right_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	right_panel.add_child(column)

	if tab == "loadout":
		build_hardpoints(column)
	elif tab == "hangar":
		var heli := loadout.heli(viewing_heli)
		var title := label(heli.display_name, 34, TEXT, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(title)
		column.add_child(description(heli.description))
		var hardpoints := label("%d hardpoints" % heli.hardpoints.size(), 17, ORANGE)
		hardpoints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(hardpoints)
		var names: Array[String] = []
		for weapon_id in heli.allowed_weapons:
			names.append(loadout.weapon(weapon_id).display_name)
		var usable := description("Weapons: " + ", ".join(names))
		usable.add_theme_font_size_override("font_size", UiStyle.px(14))
		column.add_child(usable)

		# One bar per airframe upgrade, showing this airframe's stat.
		for def in loadout.catalog.airframe_upgrades:
			var value := loadout.heli_stat(heli, def)
			# Recharge times (smaller is better) show as uses per minute.
			if def.mode == UpgradeData.Mode.SPEED_UP:
				value = 60.0 / maxf(value, 0.01)
			column.add_child(stat_row(def.label, value, def.bar_max, def.id))

		column.add_child(heli_action_button())
	else:
		var weapon := loadout.weapon(selected_weapon)
		var title := label(weapon.display_name, 32, TEXT, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(title)
		column.add_child(description(weapon.description))

		for def in weapon.upgrades:
			column.add_child(stat_row(def.label, def.bar_value(loadout.level(def.id)), def.bar_max, def.id))

		column.add_child(deploy_button())


# The selected helicopter's hardpoints, each with < > buttons that step
# through what may go there: empty, then every weapon this helicopter can
# use, is owned and keeps the loadout within the weapon type limit.
func build_hardpoints(column: VBoxContainer) -> void:
	var heli := loadout.heli(viewing_heli)
	var title := label("LOADOUT", 34, TEXT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var subtitle := label(heli.display_name, 17, MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	# Which mouse button fires what.
	var types := loadout.mounted_types(viewing_heli)
	var buttons: Array[String] = []
	for i in types.size():
		buttons.append("%s  %s" % [["LMB", "RMB"][i], loadout.weapon(types[i]).display_name])
	var controls := label("   |   ".join(buttons) if not buttons.is_empty() else "No weapons mounted", 15, ORANGE)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(controls)
	var rule := label("Up to %d weapon types, any number of each" % loadout.catalog.max_weapon_types, 13, MUTED)
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(rule)

	var ids := loadout.mounted(viewing_heli)
	for i in heli.hardpoints.size():
		column.add_child(hardpoint_row(heli.hardpoints[i], i, ids[i]))

	column.add_child(deploy_button())


func hardpoint_row(hardpoint: HardpointData, index: int, weapon_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := label(hardpoint.label, 14, MUTED)
	name_label.custom_minimum_size = Vector2(104, 0)
	row.add_child(name_label)

	var options := loadout.mount_options(viewing_heli, index)
	var can_change := options.size() > 1

	var previous := stencil_button("<", 16, can_change)
	previous.pressed.connect(func() -> void: cycle_mount(index, -1))
	row.add_child(previous)

	var text := loadout.weapon(weapon_id).display_name if weapon_id != "" else "- empty -"
	var weapon_label := label(text, 14, TEXT if weapon_id != "" else LOCKED)
	weapon_label.custom_minimum_size = Vector2(150, 0)
	weapon_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(weapon_label)

	var next := stencil_button(">", 16, can_change)
	next.pressed.connect(func() -> void: cycle_mount(index, 1))
	row.add_child(next)
	return row


func description(text: String) -> Label:
	var d := label(text, 16, Color(0.88, 0.88, 0.85))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(380, 0)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return d


# Stat name, orange bar, level pips and an upgrade button.
func stat_row(name: String, value: float, bar_max: float, upgrade_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_label := label(name, 17)
	name_label.custom_minimum_size = Vector2(108, 0)
	row.add_child(name_label)

	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 3)
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(bars)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(150, 12)
	bar.max_value = 1.0
	bar.step = 0.001
	bar.value = clampf(value / bar_max, 0.0, 1.0)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", flat(Color(0.02, 0.02, 0.02)))
	var fill := flat(ORANGE)
	fill.set_content_margin_all(0)
	bar.add_theme_stylebox_override("fill", fill)
	bars.add_child(bar)

	# Level pips.
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 3)
	var lvl := loadout.level(upgrade_id)
	for i in loadout.catalog.max_level:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(16, 4)
		pip.color = ORANGE if i < lvl else Color(1, 1, 1, 0.2)
		pips.add_child(pip)
	bars.add_child(pips)

	var cost := loadout.upgrade_cost(upgrade_id)
	var text := "MAX" if cost < 0 else "+ $%s" % UiStyle.format_money(cost)
	var button := stencil_button(text, 16, profile.can_afford(cost))
	button.custom_minimum_size = Vector2(98, 0)
	button.pressed.connect(func() -> void: buy_upgrade(upgrade_id))
	row.add_child(button)
	return row


# BUY for an airframe not owned yet, SELECT for an owned one, else DEPLOY.
func heli_action_button() -> Button:
	var price := loadout.heli(viewing_heli).price

	if not loadout.owns_heli(viewing_heli):
		var buy := stencil_button("BUY  $%s" % UiStyle.format_money(price), 28, profile.can_afford(price))
		buy.pressed.connect(func() -> void: buy_heli(viewing_heli))
		return buy
	if profile.selected_heli != viewing_heli:
		var select := stencil_button("SELECT", 28)
		select.pressed.connect(func() -> void:
			loadout.select_heli(viewing_heli)
			purchase_made.emit()
			refresh())
		return select
	return deploy_button()


func deploy_button() -> Button:
	# The helicopter you fly needs at least one weapon.
	var armed := not loadout.mounted_types(profile.selected_heli).is_empty()
	var deploy := stencil_button("DEPLOY" if armed else "MOUNT A WEAPON", 28, armed)
	# Missions are picked on the campaign map.
	deploy.pressed.connect(deploy_pressed.emit)
	return deploy


# "CHANGE HELICOPTER" strip with one card per airframe (hangar tab only).
func build_bottom() -> void:
	clear(bottom_area)
	if tab != "hangar":
		return

	var banner := label("CHANGE HELICOPTER", 30, TEXT, true)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var banner_bg := PanelContainer.new()
	var bg := flat(Color(0.04, 0.04, 0.04, 0.95))
	bg.content_margin_left = 22
	bg.content_margin_right = 22
	bg.content_margin_top = 2
	bg.content_margin_bottom = 2
	banner_bg.add_theme_stylebox_override("panel", bg)
	banner_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	banner_bg.add_child(banner)
	bottom_area.add_child(banner_bg)

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 8)
	bottom_area.add_child(cards)

	for heli in loadout.catalog.helicopters:
		var id := heli.id
		var owned := loadout.owns_heli(id)
		var in_use := profile.selected_heli == id

		var card := card_button(Vector2(210, 70), id == viewing_heli)
		card.pressed.connect(func() -> void:
			Sfx.play_2d("ui_click")
			viewing_heli = id
			show_viewed()
			refresh())

		var info := VBoxContainer.new()
		info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(info)

		var name_label := label(heli.display_name, 17, TEXT if owned else MUTED, true)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(name_label)

		var status := "IN USE" if in_use else ("OWNED" if owned else "$ %s" % UiStyle.format_money(heli.price))
		var status_color := ORANGE if in_use else (MUTED if owned else Color(0.95, 0.8, 0.3))
		var status_label := label("%s   |   %s" % [heli.weight_class, status], 13, status_color)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(status_label)

		cards.add_child(card)


# --- Purchases --------------------------------------------------------------

func buy_upgrade(upgrade_id: String) -> void:
	if not loadout.buy_upgrade(upgrade_id):
		return
	Sfx.play_2d("kill_tick")
	purchase_made.emit()
	refresh()


func buy_heli(id: String) -> void:
	if not loadout.buy_heli(id):
		return
	Sfx.play_2d("combo")
	purchase_made.emit()
	refresh()


func buy_weapon(weapon_id: String) -> void:
	if not loadout.buy_weapon(weapon_id):
		return
	Sfx.play_2d("combo")
	purchase_made.emit()
	refresh()


# Steps hardpoint `index` to the previous (-1) or next (+1) allowed option.
func cycle_mount(index: int, step: int) -> void:
	var options := loadout.mount_options(viewing_heli, index)
	var current: String = loadout.mounted(viewing_heli)[index]
	var at := maxi(options.find(current), 0)
	var choice := options[posmod(at + step, options.size())]
	if not loadout.set_mount(viewing_heli, index, choice):
		return
	Sfx.play_2d("kill_tick")
	purchase_made.emit()
	show_viewed()
	refresh()


# Tells the 3D hangar which helicopter to show, with its mounted weapons.
func show_viewed() -> void:
	heli_viewed.emit(loadout.heli(viewing_heli), loadout.mounted_weapons(viewing_heli))
