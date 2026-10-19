extends Node3D

# Hangar screen: pick and buy helicopters, upgrade the airframe (HANGAR tab)
# and the weapons (WORKSHOP tab), then deploy. A 3D hangar with the chosen
# helicopter on a turntable sits behind the UI. Everything is built in code.

const P := preload("res://scenes/environment/prop_builder.gd")
const HeliModel := preload("res://scenes/player/heli_model.gd")
const Loadout := preload("res://scenes/hangar/loadout.gd")

const ORANGE := Color(0.95, 0.45, 0.12)
const SELECT_BG := Color(0.45, 0.08, 0.04, 0.92)
const PANEL_BG := Color(0.07, 0.07, 0.07, 0.82)
const TEXT := Color(0.95, 0.95, 0.93)
const MUTED := Color(0.65, 0.65, 0.62)
const LOCKED := Color(0.45, 0.45, 0.45)

var tab: String = "hangar"
var viewing_heli: String = ""
var selected_weapon: String = "cannon"

var turntable: Node3D
var heli_parts: Dictionary = {}

var ui: CanvasLayer
var title_font: Font
var tab_buttons: Dictionary = {}
var money_label: Label
var left_column: VBoxContainer
var right_panel: PanelContainer
var bottom_area: VBoxContainer


func _ready() -> void:
	viewing_heli = Loadout.selected()
	title_font = make_title_font()
	build_world()
	build_ui()
	show_heli(viewing_heli)
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Global.go_to_menu()


func _process(delta: float) -> void:
	turntable.rotate_y(delta * 0.25)
	if heli_parts.has("main_rotor"):
		heli_parts["main_rotor"].rotate_y(delta * 1.5)
		heli_parts["tail_rotor"].rotate_x(delta * 2.5)


# --- 3D hangar -------------------------------------------------------------

func build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.08, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.7, 0.55)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var camera := Camera3D.new()
	camera.fov = 46.0
	camera.position = Vector3(8.0, 4.6, 16.0)
	add_child(camera)
	camera.look_at(Vector3(1.8, 1.7, 0))
	camera.current = true

	build_shell()
	build_props()
	build_lights()

	turntable = Node3D.new()
	add_child(turntable)
	# Painted landing circle under the helicopter.
	P.cylinder(self, 4.2, 0.02, Vector3(0, 0.01, 0), P.material(Color(0.85, 0.65, 0.15), 0.8), Vector3.ZERO, 48)
	P.cylinder(self, 3.9, 0.03, Vector3(0, 0.02, 0), P.material(Color(0.5, 0.45, 0.38), 0.95), Vector3.ZERO, 48)


# Quonset hut: a half cylinder of rusty corrugated steel with ribs.
func build_shell() -> void:
	var floor_mat := P.material(Color(0.55, 0.48, 0.4), 0.95)
	P.box(self, Vector3(34, 0.2, 44), Vector3(0, -0.1, 0), floor_mat)

	var radius := 13.0
	var length := 44.0
	var arch_mat := P.material(Color(0.5, 0.2, 0.14), 0.85, 0.3)
	arch_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var arch := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 48
	mesh.cap_top = false
	mesh.cap_bottom = false
	arch.mesh = mesh
	arch.material_override = arch_mat
	arch.rotation_degrees.x = 90.0
	arch.position = Vector3(0, -1.0, 0)
	add_child(arch)

	# Ribs every few metres and a back wall.
	var rib_mat := P.material(Color(0.32, 0.14, 0.1), 0.7, 0.4)
	for z in range(-20, 21, 5):
		var prev := Vector3.ZERO
		for i in 25:
			var a := PI * float(i) / 24.0
			var point := Vector3(cos(a) * (radius - 0.15), -1.0 + sin(a) * (radius - 0.15), z)
			if i > 0:
				P.beam(self, prev, point, 0.25, rib_mat)
			prev = point
	var wall_mat := P.material(Color(0.6, 0.55, 0.48), 0.9)
	P.box(self, Vector3(28, 14, 0.3), Vector3(0, 6, -21.5), wall_mat)

	# Skylights along the roof.
	var glass := P.material(Color(0.55, 0.65, 0.75), 0.2, 0.3)
	glass.emission_enabled = true
	glass.emission = Color(0.6, 0.7, 0.8)
	glass.emission_energy_multiplier = 0.6
	for z in [-14.0, -6.0, 2.0]:
		for side in [-1.0, 1.0]:
			var a: float = PI * (0.5 + side * 0.18)
			var pos: Vector3 = Vector3(cos(a) * (radius - 0.1), -1.0 + sin(a) * (radius - 0.1), z)
			var light := P.box(self, Vector3(2.4, 0.1, 3.5), pos, glass)
			light.rotation.z = a - PI * 0.5


func build_props() -> void:
	var crate := P.material(Color(0.42, 0.36, 0.22), 0.9)
	var crate_dark := P.material(Color(0.3, 0.32, 0.22), 0.9)
	var barrel := P.material(Color(0.28, 0.33, 0.25), 0.7, 0.3)
	var steel := P.material(Color(0.35, 0.36, 0.38), 0.5, 0.6)
	var white := P.material(Color(0.9, 0.9, 0.88), 0.6)
	var red := P.material(Color(0.8, 0.15, 0.1), 0.6)

	# Stacks of ammo crates.
	for i in 4:
		P.box(self, Vector3(1.6, 0.9, 1.0), Vector3(-9.5 + (i % 2) * 1.7, 0.45 + (i / 2) * 0.92, -8.0), crate if i % 3 else crate_dark)
	for i in 3:
		P.box(self, Vector3(1.2, 0.8, 0.9), Vector3(9.0, 0.4 + i * 0.82, -10.0 + i * 0.1), crate_dark)

	# Barrels.
	for i in 6:
		P.cylinder(self, 0.4, 1.1, Vector3(-10.5 + (i % 3) * 0.85, 0.55, -2.5 + (i / 3) * 0.85), barrel)

	# Missile rack like in a real hangar.
	P.box(self, Vector3(2.4, 0.15, 0.8), Vector3(-6.0, 0.6, -10.0), steel)
	for i in 4:
		var x := -6.9 + i * 0.6
		P.cylinder(self, 0.14, 2.4, Vector3(x, 1.9, -10.0), white)
		P.cylinder(self, 0.15, 0.4, Vector3(x, 3.2, -10.0), red)

	# Shelving with boxes along the back.
	for x in [3.0, 6.5]:
		for shelf in 3:
			P.box(self, Vector3(3.0, 0.08, 1.0), Vector3(x, 0.6 + shelf * 1.1, -12.0), steel)
			P.box(self, Vector3(0.7, 0.6, 0.6), Vector3(x - 0.8 + shelf * 0.5, 0.95 + shelf * 1.1, -12.0), crate)
		for side in [-1.5, 1.5]:
			P.box(self, Vector3(0.08, 3.4, 0.08), Vector3(x + side, 1.7, -12.0), steel)

	# Work lamp on a tripod.
	var lamp := Vector3(-4.5, 0, 3.5)
	for i in 3:
		var a := TAU * i / 3.0
		P.beam(self, lamp + Vector3(cos(a) * 0.6, 0, sin(a) * 0.6), lamp + Vector3(0, 1.6, 0), 0.05, steel)
	P.cylinder(self, 0.04, 1.2, lamp + Vector3(0, 2.2, 0), steel)
	P.box(self, Vector3(0.7, 0.45, 0.2), lamp + Vector3(0, 2.9, 0), steel, Vector3(-20, 30, 0))


func build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-60, -30, 0)
	add_child(sun)

	var spot := SpotLight3D.new()
	spot.light_color = Color(1.0, 0.92, 0.8)
	spot.light_energy = 6.0
	spot.spot_range = 20.0
	spot.spot_angle = 35.0
	spot.shadow_enabled = true
	spot.position = Vector3(0, 10, 2)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	add_child(spot)

	for pos in [Vector3(-8, 6, -6), Vector3(8, 6, -6), Vector3(0, 5, 8)]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.75, 0.5)
		lamp.light_energy = 1.2
		lamp.omni_range = 14.0
		lamp.position = pos
		add_child(lamp)


func show_heli(id: String) -> void:
	for child in turntable.get_children():
		child.queue_free()
	var style: Dictionary = Loadout.HELICOPTERS[id]["style"]
	var holder := Node3D.new()
	# Sit the skids on the floor.
	holder.position.y = (style["fuselage"].y + 0.3) * float(style.get("scale", 1.0)) + 0.05
	turntable.add_child(holder)
	heli_parts = HeliModel.build(holder, style)


# --- UI ---------------------------------------------------------------------

func make_title_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Impact", "Arial Black", "Arial"])
	font.font_weight = 800
	return font


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
	b.add_theme_font_size_override("font_size", size)
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
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", ORANGE)
	b.add_theme_color_override("font_pressed_color", ORANGE)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void: Sfx.play_2d("ui_click"))
	return b


func build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	# Darken the top for the tab bar.
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	shade.offset_bottom = 74
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var back := text_button("BACK", 34)
	back.position = Vector2(30, 10)
	back.pressed.connect(Global.go_to_menu)
	root.add_child(back)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 40)
	tabs.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	tabs.offset_left = -200
	tabs.offset_right = 200
	tabs.offset_top = 10
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(tabs)
	for name in ["hangar", "workshop"]:
		var b := text_button(name.to_upper(), 34)
		b.pressed.connect(func() -> void:
			tab = name
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
	right_panel.add_theme_stylebox_override("panel", flat(PANEL_BG))
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


func refresh() -> void:
	money_label.text = "$ %s" % format_money(Global.money)

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


func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


# Weapon cards (both tabs) and the reset button.
func build_left_column() -> void:
	clear(left_column)

	for id in Loadout.WEAPON_ORDER:
		var weapon: Dictionary = Loadout.WEAPONS[id]
		var highlighted: bool = tab == "workshop" and id == selected_weapon

		var card := Button.new()
		card.custom_minimum_size = Vector2(300, 58)
		var style := flat(SELECT_BG if highlighted else PANEL_BG, ORANGE if highlighted else Color(0, 0, 0, 0), 3 if highlighted else 0)
		card.add_theme_stylebox_override("normal", style)
		var hover: StyleBoxFlat = style.duplicate()
		hover.border_color = ORANGE
		hover.set_border_width_all(2)
		card.add_theme_stylebox_override("hover", hover)
		card.add_theme_stylebox_override("pressed", hover)
		card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
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

		var tag := label(weapon["class"], 15, TEXT, true)
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
		info.add_child(label(weapon["name"], 17))
		var total := 0
		for key in weapon["upgrades"]:
			total += Loadout.level(key)
		info.add_child(label("Upgrades  %d / %d" % [total, Loadout.MAX_LEVEL * weapon["upgrades"].size()], 13, MUTED))

		left_column.add_child(card)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	left_column.add_child(spacer)

	var refund := Loadout.spent_on_upgrades()
	var reset := stencil_button("RESET  (+$%s)" % format_money(refund) if refund > 0 else "RESET", 22, refund > 0)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		Global.money += Loadout.spent_on_upgrades()
		Global.upgrades = {}
		Global.save_settings()
		refresh())
	left_column.add_child(reset)


func build_right_panel() -> void:
	clear(right_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	right_panel.add_child(column)

	if tab == "hangar":
		var heli: Dictionary = Loadout.HELICOPTERS[viewing_heli]
		var title := label(heli["name"], 34, TEXT, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(title)
		column.add_child(description(heli["description"]))

		var stats := Loadout.heli_stats(viewing_heli)
		for bar in Loadout.HELI_BARS:
			column.add_child(stat_row(bar[0], stats[bar[1]], bar[2], bar[1]))

		column.add_child(heli_action_button())
	else:
		var weapon: Dictionary = Loadout.WEAPONS[selected_weapon]
		var title := label(weapon["name"], 32, TEXT, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(title)
		column.add_child(description(weapon["description"]))

		var bars := Loadout.weapon_bars(selected_weapon)
		for i in bars.size():
			column.add_child(stat_row(bars[i][0], bars[i][1], bars[i][2], weapon["upgrades"][i]))

		column.add_child(deploy_button())


func description(text: String) -> Label:
	var d := label(text, 16, Color(0.88, 0.88, 0.85))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(380, 0)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return d


# Stat name, orange bar, level pips and an upgrade button.
func stat_row(name: String, value: float, bar_max: float, upgrade_key: String) -> Control:
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
	var lvl := Loadout.level(upgrade_key)
	for i in Loadout.MAX_LEVEL:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(16, 4)
		pip.color = ORANGE if i < lvl else Color(1, 1, 1, 0.2)
		pips.add_child(pip)
	bars.add_child(pips)

	var cost := Loadout.upgrade_cost(upgrade_key)
	var text := "MAX" if cost < 0 else "+ $%s" % format_money(cost)
	var button := stencil_button(text, 16, cost >= 0 and Global.money >= cost)
	button.custom_minimum_size = Vector2(98, 0)
	button.pressed.connect(func() -> void: buy_upgrade(upgrade_key))
	row.add_child(button)
	return row


func heli_action_button() -> Button:
	var owned: bool = Global.owned_helis.has(viewing_heli)
	var price: int = Loadout.HELICOPTERS[viewing_heli]["price"]

	if not owned:
		var buy := stencil_button("BUY  $%s" % format_money(price), 28, Global.money >= price)
		buy.pressed.connect(func() -> void: buy_heli(viewing_heli))
		return buy
	if Global.selected_heli != viewing_heli:
		var select := stencil_button("SELECT", 28)
		select.pressed.connect(func() -> void:
			Global.selected_heli = viewing_heli
			Global.save_settings()
			refresh())
		return select
	return deploy_button()


func deploy_button() -> Button:
	var deploy := stencil_button("DEPLOY", 28)
	deploy.pressed.connect(Global.start_game)
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

	for id in Loadout.HELI_ORDER:
		var heli: Dictionary = Loadout.HELICOPTERS[id]
		var owned: bool = Global.owned_helis.has(id)
		var viewing: bool = id == viewing_heli

		var card := Button.new()
		card.custom_minimum_size = Vector2(210, 70)
		var style := flat(SELECT_BG if viewing else PANEL_BG, ORANGE if viewing else Color(0, 0, 0, 0), 3 if viewing else 0)
		card.add_theme_stylebox_override("normal", style)
		var hover: StyleBoxFlat = style.duplicate()
		hover.border_color = ORANGE
		hover.set_border_width_all(2)
		card.add_theme_stylebox_override("hover", hover)
		card.add_theme_stylebox_override("pressed", hover)
		card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		card.pressed.connect(func() -> void:
			Sfx.play_2d("ui_click")
			viewing_heli = id
			show_heli(id)
			refresh())

		var info := VBoxContainer.new()
		info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(info)

		var name_label := label(heli["name"], 17, TEXT if owned else MUTED, true)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(name_label)

		var status := "IN USE" if Global.selected_heli == id else ("OWNED" if owned else "$ %s" % format_money(heli["price"]))
		var status_color := ORANGE if Global.selected_heli == id else (MUTED if owned else Color(0.95, 0.8, 0.3))
		var status_label := label("%s   ·   %s" % [heli["class"], status], 13, status_color)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(status_label)

		cards.add_child(card)


# --- Purchases --------------------------------------------------------------

func buy_upgrade(key: String) -> void:
	var cost := Loadout.upgrade_cost(key)
	if cost < 0 or Global.money < cost:
		return
	Global.money -= cost
	Global.upgrades[key] = Loadout.level(key) + 1
	Global.save_settings()
	Sfx.play_2d("kill_tick")
	refresh()


func buy_heli(id: String) -> void:
	var price: int = Loadout.HELICOPTERS[id]["price"]
	if Global.owned_helis.has(id) or Global.money < price:
		return
	Global.money -= price
	Global.owned_helis.append(id)
	Global.selected_heli = id
	Global.save_settings()
	Sfx.play_2d("combo")
	refresh()


func format_money(value: int) -> String:
	var text := str(value)
	var out := ""
	while text.length() > 3:
		out = "," + text.right(3) + out
		text = text.left(text.length() - 3)
	return text + out
