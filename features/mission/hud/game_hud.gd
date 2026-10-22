class_name GameHud
extends CanvasLayer

# In-game HUD: score and kill readout, kill pop-ups, multi-kills and the
# edge arrows to off-screen enemies. Built in code.
#
# The mission context calls initialize(). The helicopter draws its own hull
# bar, ability readout and lock warnings.

# The HUD is 1-bit (see PixelArt): everything is white text with a black
# outline, told apart by size rather than colour.
const ACCENT := Color.WHITE
const TEXT := Color.WHITE
const MUTED := Color.WHITE
const DANGER := Color.WHITE

const Indicators := preload("res://features/mission/hud/offscreen_indicators.gd")

var mission: MissionContext
# The gun controller, for the kill count.
var gun: GunController

var title_label: Label
var score_label: Label
# The run's upgrades, top right (see show_upgrades).
var upgrades_label: Label

var shown_score: float = 0.0

# Kills within this many seconds of each other count as one multi-kill.
const COMBO_WINDOW := 0.6
var combo_count: int = 0
var combo_timer: float = 0.0
var combo_label: Label
var combo_tween: Tween

var indicators: Control
var dodge_fx: DodgeFx
var missile_warning: MissileWarning


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Nothing to show until the mission context calls initialize().
	set_process(false)


func initialize(mission_context: MissionContext) -> void:
	mission = mission_context
	gun = mission.guns

	# Edge arrows go underneath the rest of the HUD.
	indicators = Indicators.new()
	indicators.helicopter = mission.helicopter
	add_child(indicators)

	# Chevrons round the helicopter for missiles homing on it.
	missile_warning = MissileWarning.new()
	missile_warning.helicopter = mission.helicopter
	add_child(missile_warning)

	# Chain dodge feedback, over the arrows and under the readouts.
	dodge_fx = DodgeFx.new()
	add_child(dodge_fx)
	dodge_fx.setup(mission)

	build_readout()
	build_combo_label()
	set_process(true)


func _process(delta: float) -> void:
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			finish_combo()

	# Count the score up smoothly.
	shown_score = move_toward(shown_score, mission.score, maxf(200.0, absf(mission.score - shown_score) * 6.0) * delta)
	score_label.text = "%s  %s" % [tr("SCORE"), UiStyle.format_money(int(shown_score))]
	if gun != null:
		score_label.text += "     %s  %d" % [tr("KILLS"), gun.kills]


func make_label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", UiStyle.px(size))
	label.add_theme_constant_override("line_spacing", UiStyle.line_gap(UiStyle.px(size)))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func build_readout() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(24, 18)
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	title_label = make_label("TEST RANGE", 34, ACCENT)
	score_label = make_label("SCORE  0", 22, TEXT)
	for label in [title_label, score_label]:
		label.add_theme_stylebox_override("normal", UiStyle.plate(6.0))
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(title_label)
	box.add_child(score_label)

	upgrades_label = make_label("", 22, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	upgrades_label.add_theme_stylebox_override("normal", UiStyle.plate(6.0))
	upgrades_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	upgrades_label.offset_left = -24
	upgrades_label.offset_right = -24
	upgrades_label.offset_top = 18
	upgrades_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	upgrades_label.visible = false
	add_child(upgrades_label)


# --- Kill feedback -------------------------------------------------------

# Called by the gun controller for every kill.
func register_kill(points: int, world_position: Vector3, label: String) -> void:
	var text := "+%d" % points
	if label != "":
		text += " " + tr(label)

	var color := TEXT
	if points >= 300:
		color = DANGER
	elif points >= 40:
		color = ACCENT

	spawn_popup(text, world_position, color, points >= 300)

	combo_count += 1
	combo_timer = COMBO_WINDOW


# Floating score text that rises from where the enemy died. Drawn on the
# HUD (not in 3D) so it stays crisp over the pixel-art scene. `real_time`
# keeps it moving through slow motion.
func spawn_popup(text: String, world_position: Vector3, color: Color, big: bool = false, real_time: bool = false) -> void:
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

	var tween := popup.create_tween().set_parallel().set_ignore_time_scale(real_time)
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

	var title := tr("MULTI KILL x%d") % count
	match count:
		2: title = tr("DOUBLE KILL")
		3: title = tr("TRIPLE KILL")
		4: title = tr("QUAD KILL")
	if count >= 8:
		title = tr("MASSACRE x%d") % count

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


## Lists the run's upgrades top right, one a line ("NAME x2" for a stack).
func show_upgrades(names: Array) -> void:
	upgrades_label.text = "\n".join(names)
	upgrades_label.visible = not names.is_empty()
	upgrades_label.reset_size()
