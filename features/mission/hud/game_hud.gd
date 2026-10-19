class_name GameHud
extends CanvasLayer

# In-game HUD for the wave mode: wave and score readout, wave banners, kill
# pop-ups and the end-of-mission screens. Built in code.
#
# The mission context calls initialize() and opens the end screens
# (show_game_over / show_victory). The HUD never changes screens itself:
# its end-screen buttons emit the *_pressed signals below.

signal retry_pressed
signal map_pressed
signal hangar_pressed
signal menu_pressed

const ACCENT := Color(1.0, 0.72, 0.25)
const TEXT := Color(0.92, 0.93, 0.9)
const MUTED := Color(0.7, 0.72, 0.68)
const DANGER := Color(1.0, 0.35, 0.3)

const Indicators := preload("res://features/mission/hud/offscreen_indicators.gd")

var mission: MissionContext
var state: MissionState
var generator: EnemyGenerator
# The gun controller, for the kill count.
var gun: GunController
# The rig, for its health bar and attack warnings.
var home: MissionRig

var wave_label: Label
var score_label: Label
var status_label: Label
var banner: Label
var banner_sub: Label
var banner_tween: Tween
var game_over_root: Control

var shown_score: float = 0.0

# Kills within this many seconds of each other count as one multi-kill.
const COMBO_WINDOW := 0.6
var combo_count: int = 0
var combo_timer: float = 0.0
var combo_label: Label
var combo_tween: Tween

var indicators: Control
var rig_bar: ProgressBar
var rig_fill: StyleBoxFlat
var rig_warning: Label
# Seconds left of the red flash on the rig bar / the off-screen warning.
var rig_flash: float = 0.0
var rig_alert: float = 0.0


func _ready() -> void:
	layer = 10
	# The game-over screen has to work while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Nothing to show until the mission context calls initialize().
	set_process(false)


func initialize(mission_context: MissionContext) -> void:
	mission = mission_context
	state = mission.state
	generator = mission.generator
	gun = mission.guns
	home = mission.rig

	# Edge arrows go underneath the rest of the HUD.
	indicators = Indicators.new()
	indicators.home = home
	indicators.helicopter = mission.helicopter
	add_child(indicators)

	build_readout()
	build_rig_warning()
	build_banner()
	build_combo_label()

	home.damaged.connect(on_rig_damaged)
	generator.wave_started.connect(on_wave_started)
	generator.wave_cleared.connect(on_wave_cleared)
	generator.fort_destroyed.connect(on_fort_destroyed)
	generator.contact_made.connect(on_contact)

	# Assaulting an enemy rig: there's no friendly rig to watch, and the
	# rig arrow marks the target instead.
	if state.is_assault:
		rig_bar.get_parent().visible = false
		indicators.home_is_target = true

	if state.is_campaign():
		show_mission_start.call_deferred()
	set_process(true)


func _process(delta: float) -> void:
	update_rig(delta)

	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			finish_combo()

	# Count the score up smoothly.
	shown_score = move_toward(shown_score, state.score, maxf(200.0, absf(state.score - shown_score) * 6.0) * delta)
	score_label.text = "SCORE  %s" % UiStyle.format_money(int(shown_score))
	if gun != null:
		score_label.text += "     KILLS  %d" % gun.kills
	var started: bool = generator == null or state.wave > generator.starting_level
	wave_label.text = "WAVE %d" % maxi(state.wave, 1) if state.wave > 0 and started else "GET READY"
	if is_assault():
		var count: int = state.wave - generator.starting_level
		wave_label.text = "WAVE %d / %d" % [count, generator.target_waves] if count > 0 else "GET READY"

	if generator == null or not generator.wave_mode:
		status_label.text = ""
	elif generator.wave_state == generator.WaveState.BREAK:
		status_label.text = "Next wave in %d  |  from the %s" % [ceili(maxf(generator.break_left, 0.0)), Campaign.compass(generator.wave_side)]
	else:
		status_label.text = "Enemies left: %d" % generator.enemies_left()

	if generator != null and generator.awaiting_contact:
		wave_label.text = "INGRESS"
		var heli := mission.helicopter
		var distance := Vector2(heli.global_position.x, heli.global_position.z).length() if heli != null else 0.0
		status_label.text = "Fly to the target: %d m" % roundi(distance)
		return

	if is_assault():
		var forts: int = generator.forts_left()
		if generator.waves_done:
			status_label.text = "Destroy the last defences: %d" % forts if forts > 0 else "Rig secured"
		elif forts > 0:
			status_label.text += "   |   Defences left: %d" % forts



func make_label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", UiStyle.px(size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func build_readout() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(24, 18)
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	wave_label = make_label("WAVE 1", 34, ACCENT)
	score_label = make_label("SCORE  0", 22, TEXT)
	status_label = make_label("", 17, MUTED)
	box.add_child(wave_label)
	box.add_child(score_label)
	box.add_child(status_label)

	# Rig health.
	var rig_row := HBoxContainer.new()
	rig_row.add_theme_constant_override("separation", 8)
	rig_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rig_row)
	rig_row.add_child(make_label("RIG", 17, TEXT))
	rig_bar = ProgressBar.new()
	rig_bar.custom_minimum_size = Vector2(200, 12)
	rig_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rig_bar.max_value = 1.0
	rig_bar.value = 1.0
	rig_bar.show_percentage = false
	rig_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rig_bg := StyleBoxFlat.new()
	rig_bg.bg_color = Color(0.08, 0.08, 0.08, 0.7)
	rig_fill = StyleBoxFlat.new()
	rig_fill.bg_color = Color(0.3, 0.85, 0.45)
	rig_bar.add_theme_stylebox_override("background", rig_bg)
	rig_bar.add_theme_stylebox_override("fill", rig_fill)
	rig_row.add_child(rig_bar)


func build_banner() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -400
	box.offset_right = 400
	box.offset_top = 150
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	banner = make_label("", 64, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	banner_sub = make_label("", 24, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(banner)
	box.add_child(banner_sub)
	box.modulate.a = 0.0


func show_banner(title: String, subtitle: String, color: Color) -> void:
	banner.text = title
	banner.add_theme_color_override("font_color", color)
	banner_sub.text = subtitle

	var box := banner.get_parent() as Control
	if banner_tween != null:
		banner_tween.kill()
	box.modulate.a = 0.0
	box.scale = Vector2.ONE
	banner_tween = create_tween()
	banner_tween.tween_property(box, "modulate:a", 1.0, 0.25)
	banner_tween.tween_interval(2.0)
	banner_tween.tween_property(box, "modulate:a", 0.0, 0.6)


func is_assault() -> bool:
	return generator != null and generator.target_waves > 0


func on_wave_started(number: int, is_boss: bool) -> void:
	var from := "Inbound from the %s" % Campaign.compass(generator.wave_side)
	if is_assault():
		var count: int = number - generator.starting_level
		if generator.is_final_wave(number):
			show_banner("FINAL WAVE", "Heavy armour inbound from the %s" % Campaign.compass(generator.wave_side), DANGER)
		else:
			show_banner("WAVE %d / %d" % [count, generator.target_waves], "%s  |  %d more to take the rig" % [from, generator.target_waves - count], ACCENT)
	elif is_boss:
		show_banner("WAVE %d" % number, "BOSS WAVE  |  heavy armour inbound from the %s" % Campaign.compass(generator.wave_side), DANGER)
	else:
		show_banner("WAVE %d" % number, from, ACCENT)


# Opening banner: fly in to an assault, or lift off for a defence.
func show_mission_start() -> void:
	var rig := state.rig
	if state.is_assault:
		show_banner("INGRESS", "Fly to %s. The defences open fire as you close in." % rig.display_name, ACCENT)
	else:
		show_banner("LIFT OFF", "Enemy column inbound from the %s" % Campaign.compass(generator.wave_side), ACCENT)


func on_contact() -> void:
	show_banner("CONTACT", "Enemy forces moving in from the %s" % Campaign.compass(generator.wave_side), DANGER)


func on_wave_cleared(number: int, bonus: int) -> void:
	var subtitle := "+%s bonus" % UiStyle.format_money(bonus) if bonus > 0 else ""
	if is_assault() and generator.is_final_wave(number):
		var forts: int = generator.forts_left()
		if forts > 0:
			show_banner("WAVES CLEARED", "Destroy the last %d defences to take the rig" % forts, ACCENT)
		else:
			show_banner("RIG SECURED", subtitle, Color(0.5, 0.9, 0.55))
		return
	var title := "WAVE %d CLEARED" % (number - generator.starting_level if is_assault() else number)
	show_banner(title, subtitle, Color(0.5, 0.9, 0.55))


func on_fort_destroyed(left: int) -> void:
	if left > 0:
		show_banner("DEFENCE DESTROYED", "%d left around the rig" % left, Color(0.5, 0.9, 0.55))
	elif generator.waves_done:
		show_banner("RIG SECURED", "All defences destroyed", Color(0.5, 0.9, 0.55))
	else:
		show_banner("ALL DEFENCES DOWN", "Clear the remaining waves to take the rig", Color(0.5, 0.9, 0.55))


# --- Rig status ----------------------------------------------------------

func build_rig_warning() -> void:
	rig_warning = make_label("RIG UNDER ATTACK", 30, DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	rig_warning.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	rig_warning.offset_left = -300
	rig_warning.offset_right = 300
	rig_warning.offset_top = 70
	rig_warning.offset_bottom = 110
	rig_warning.visible = false
	add_child(rig_warning)


func update_rig(delta: float) -> void:
	rig_flash = maxf(rig_flash - delta, 0.0)
	rig_alert = maxf(rig_alert - delta, 0.0)

	if home == null or not is_instance_valid(home):
		return

	var fraction: float = clampf(home.health / maxf(home.max_health, 1.0), 0.0, 1.0)
	rig_bar.value = fraction

	var color := Color(0.3, 0.85, 0.45)
	if fraction < 0.25:
		color = DANGER
	elif fraction < 0.5:
		color = ACCENT
	# Flash toward white for a moment on each hit.
	rig_fill.bg_color = color.lerp(Color.WHITE, rig_flash / 0.4 * 0.7)

	# Only warn while the rig is out of view; on screen you can see it.
	var off_screen: bool = not indicators.is_on_screen(home.global_position)
	rig_warning.visible = rig_alert > 0.0 and off_screen and fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.32


func on_rig_damaged() -> void:
	rig_flash = 0.4
	rig_alert = 2.5
	indicators.rig_alert = 2.5


# --- Kill feedback -------------------------------------------------------

# Called by the gun controller for every kill.
func register_kill(points: int, world_position: Vector3, label: String) -> void:
	var text := "+%d" % points
	if label != "":
		text += " " + label

	var color := TEXT
	if points >= 300:
		color = DANGER
	elif points >= 40:
		color = ACCENT

	spawn_popup(text, world_position, color, points >= 300)

	combo_count += 1
	combo_timer = COMBO_WINDOW


# Floating score text that rises from where the enemy died. Drawn on the
# HUD (not in 3D) so it stays crisp over the pixel-art scene.
func spawn_popup(text: String, world_position: Vector3, color: Color, big: bool = false) -> void:
	var popup := make_label(text, 30 if big else 21, color, HORIZONTAL_ALIGNMENT_CENTER)
	popup.size = Vector2(240, 40)
	popup.pivot_offset = popup.size * 0.5
	add_child(popup)

	# A little sideways spread so several kills in one spot don't overlap.
	var anchor := world_position + Vector3(randf_range(-2.0, 2.0), 3.0, randf_range(-1.0, 1.0))
	var follow := func(rise: float) -> void:
		var camera := get_viewport().get_camera_3d()
		if camera == null or not is_instance_valid(popup):
			return
		popup.position = camera.unproject_position(anchor) - popup.size * 0.5 - Vector2(0, rise)
	follow.call(0.0)

	var tween := popup.create_tween().set_parallel()
	tween.tween_method(follow, 0.0, 48.0, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(popup, "modulate:a", 0.0, 0.4).set_delay(0.6)
	tween.chain().tween_callback(popup.queue_free)


func finish_combo() -> void:
	var count := combo_count
	combo_count = 0

	if count < 2:
		return

	var bonus := 10 * count * (count - 1)
	mission.add_score(bonus)

	var title := "MULTI KILL x%d" % count
	match count:
		2: title = "DOUBLE KILL"
		3: title = "TRIPLE KILL"
		4: title = "QUAD KILL"
	if count >= 8:
		title = "MASSACRE x%d" % count

	combo_label.text = "%s   +%s" % [title, UiStyle.format_money(bonus)]
	Sfx.play_2d("combo")

	if combo_tween != null:
		combo_tween.kill()
	combo_label.modulate.a = 1.0
	combo_label.scale = Vector2.ONE * 1.5
	combo_tween = create_tween()
	combo_tween.tween_property(combo_label, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	combo_tween.tween_interval(1.2)
	combo_tween.tween_property(combo_label, "modulate:a", 0.0, 0.5)


func build_combo_label() -> void:
	combo_label = make_label("", 38, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	combo_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	combo_label.offset_left = -400
	combo_label.offset_right = 400
	combo_label.offset_top = 110
	combo_label.offset_bottom = 160
	combo_label.pivot_offset = Vector2(400, 25)
	combo_label.modulate.a = 0.0
	add_child(combo_label)


# --- Game over -----------------------------------------------------------

# `new_best` is true when the run beat the best score or wave.
func show_game_over(reason: String, new_best: bool) -> void:
	var column := open_end_screen("MISSION FAILED" if state.is_assault else "GAME OVER", DANGER)
	if column == null:
		return

	column.add_child(make_label(reason, 22, TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	add_end_spacer(column, 12)

	column.add_child(make_label("Wave reached:  %d" % state.wave, 28, ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(make_label("Score:  %s" % UiStyle.format_money(state.score), 28, ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	add_payout(column)

	if new_best:
		column.add_child(make_label("NEW BEST!", 26, Color(0.5, 0.9, 0.55), HORIZONTAL_ALIGNMENT_CENTER))
	else:
		column.add_child(make_label("Best:  wave %d  |  %s pts" % [mission.services.profile.best_wave, UiStyle.format_money(mission.services.profile.best_score)], 18, MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	add_end_buttons(column, "RETRY", retry_pressed.emit)


func show_victory(rig_name: String) -> void:
	var column := open_end_screen("RIG CAPTURED", Color(0.5, 0.9, 0.55))
	if column == null:
		return

	column.add_child(make_label("%s is now yours" % rig_name, 24, TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	add_end_spacer(column, 12)
	column.add_child(make_label("Score:  %s" % UiStyle.format_money(state.score), 28, ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	add_payout(column)

	add_end_buttons(column, "CONTINUE", map_pressed.emit)
	Sfx.play_2d("combo")


# Dimmed overlay with a centred column and a big title. Null if one is open.
func open_end_screen(title: String, color: Color) -> VBoxContainer:
	if game_over_root != null:
		return null

	# Don't let a wave banner show through.
	if banner_tween != null:
		banner_tween.kill()
	(banner.get_parent() as Control).modulate.a = 0.0

	game_over_root = Control.new()
	game_over_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(game_over_root)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_root.add_child(center)

	# Everything sits on a gradient panel.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.gradient_panel(UiStyle.PANEL_TOP, UiStyle.PANEL_BOTTOM, UiStyle.PANEL_BORDER, 24.0))
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	column.add_child(make_label(title, 60, color, HORIZONTAL_ALIGNMENT_CENTER))

	game_over_root.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(game_over_root, "modulate:a", 1.0, 0.4)
	return column


func add_end_spacer(column: VBoxContainer, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	column.add_child(spacer)


# Where the money came from: kills, rig income and a capture bonus.
func add_payout(column: VBoxContainer) -> void:
	var payout := state.payout
	var green := Color(0.5, 0.9, 0.55)
	if payout.get("income", 0) > 0 or payout.get("capture", 0) > 0:
		column.add_child(make_label("Kills  $%s" % UiStyle.format_money(payout["kills"]), 18, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		column.add_child(make_label("Rig income  $%s" % UiStyle.format_money(payout["income"]), 18, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		if payout["capture"] > 0:
			column.add_child(make_label("Capture bonus  $%s" % UiStyle.format_money(payout["capture"]), 18, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(make_label("+ $%s earned" % UiStyle.format_money(state.earned), 24, green, HORIZONTAL_ALIGNMENT_CENTER))


# The main action, with the other destinations in a row underneath.
func add_end_buttons(column: VBoxContainer, primary_text: String, primary_action: Callable) -> void:
	add_end_spacer(column, 10)

	var primary := make_button(primary_text, true)
	primary.pressed.connect(primary_action)
	column.add_child(primary)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)

	var add_secondary := func(text: String, action: Callable) -> void:
		var button := make_button(text, false)
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", UiStyle.px(18))
		button.pressed.connect(action)
		row.add_child(button)

	if state.is_campaign() and primary_text != "CONTINUE":
		add_secondary.call("MAP", map_pressed.emit)
	add_secondary.call("HANGAR", hangar_pressed.emit)
	add_secondary.call("MENU", menu_pressed.emit)

	primary.grab_focus()


func make_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 50)
	button.add_theme_font_size_override("font_size", UiStyle.px(22))

	var fill := ACCENT if primary else Color(0.2, 0.23, 0.21)
	var text_color := Color(0.08, 0.08, 0.06) if primary else TEXT

	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = fill.lightened(0.15) if state == "hover" else (fill.darkened(0.15) if state == "pressed" else fill)
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override(state, style)

	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_corner_radius_all(6)
	focus.set_border_width_all(2)
	focus.border_color = Color(1, 1, 1, 0.6)
	button.add_theme_stylebox_override("focus", focus)

	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, text_color)
	return button
