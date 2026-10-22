class_name DodgeFx
extends Control

# Feedback for the chain dodge (ChainDodge), on the HUD and in the world.
# Everything animates in real time, so it stays lively while the world
# crawls in slow motion. Black and white only, to match the 1-bit game.
#   perfect dodge - a time-stop thump and a clang, sparks off each
#                   dodged missile, a frame of inverted screen (1-bit),
#                   a shockwave ring from the helicopter, letterbox bars
#                   sliding in, and a "PERFECT" callout over the helicopter
#                   that punches in bigger with every link
#   slow motion   - brackets blink round the next missile coming in, and
#                   dodged missiles turn white (they're the player's now)
#   time resumes  - a suck-back whoosh, the bars slide out
#   chain ends    - a "CHAIN xN" banner mid-screen
#   deflect kill  - a hit stop, an inverted frame and a callout where it hit
#   enemy reflect - an enemy helicopter sent a missile back: the same in
#                   reverse (ink callout, black ring first, lower time stop)
#                   and a beat of slow motion to see it coming

const PAPER := Color.WHITE
const INK := Color.BLACK
# Letterbox bars, as a fraction of the screen height each.
const BAR_HEIGHT := 0.09
# Thickness of the bars' bright inner edge in slow motion (canvas units).
const EDGE_WIDTH := 8.0
# How far the shockwave ring spreads (metres) and for how long (real seconds).
const RING_RADIUS := 16.0
const RING_TIME := 0.45
# How far the deflect sparks fly (metres) and for how long (real seconds).
const SPARK_REACH := 6.0
const SPARK_TIME := 0.3

var mission: MissionContext
var chain_dodge: ChainDodge
var top_bar: ColorRect
var bottom_bar: ColorRect
var bars_tween: Tween
# The callout over the helicopter: it follows it on screen.
var callout: Label
var callout_tween: Tween
var banner: Label
var banner_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(mission_context: MissionContext) -> void:
	mission = mission_context
	chain_dodge = mission.helicopter.chain_dodge
	chain_dodge.perfect_dodge.connect(_on_perfect_dodge)
	chain_dodge.slow_ended.connect(_on_slow_ended)
	chain_dodge.chain_ended.connect(_on_chain_ended)

	top_bar = make_bar()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bottom_bar = make_bar()
	bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	set_bars(0.0)

	callout = make_text(60)
	callout.modulate.a = 0.0
	banner = make_text(64)
	banner.modulate.a = 0.0


func _process(_delta: float) -> void:
	place_callout()
	queue_redraw()


# --- Events ------------------------------------------------------------------

func _on_perfect_dodge(chain: int, missiles: Array) -> void:
	var heli := mission.helicopter
	Sfx.play_2d("time_stop", 0.0, 1.0 + minf(chain - 1, 6) * 0.07)
	Sfx.play_2d("deflect_clang", 0.0, 1.0 + minf(chain - 1, 6) * 0.05)
	mission.shake(0.3)
	# A frame of inverted screen. The flash counts game time, so scale it
	# to last 0.06 real seconds.
	if PixelArt.is_monochrome():
		PixelArt.invert_flash(0.06 * Engine.time_scale)
	for missile in missiles:
		whiten(missile)
		spawn_sparks(missile.global_position)
	spawn_ring(heli.global_position, chain)
	slide_bars(1.0, 0.12)

	var prefix := ""
	if missiles.size() > 1:
		prefix = "DOUBLE " if missiles.size() == 2 else "MULTI "
	var text := tr(prefix + "PERFECT") if chain == 1 else tr(prefix + "PERFECT x%d") % chain
	punch(callout, text, 1.0 + minf(chain - 1, 5) * 0.12)


func _on_slow_ended() -> void:
	Sfx.play_2d("time_resume")
	slide_bars(0.0, 0.2)


func _on_chain_ended(chain: int) -> void:
	if chain < 2:
		return
	banner.text = tr("CHAIN x%d") % chain
	banner.reset_size()
	banner.position = (size - banner.size) * Vector2(0.5, 0.28)
	banner.pivot_offset = banner.size * 0.5
	Sfx.play_2d("combo", 0.0, 0.8 + minf(chain, 8) * 0.05)
	if banner_tween != null:
		banner_tween.kill()
	banner.modulate.a = 1.0
	banner.scale = Vector2.ONE * 2.0
	banner_tween = create_tween().set_ignore_time_scale(true)
	banner_tween.tween_property(banner, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	banner_tween.tween_interval(1.0)
	banner_tween.tween_property(banner, "modulate:a", 0.0, 0.3)


## An enemy helicopter at `at` sent a deflected missile back: the inverse
## of a perfect dodge (ink text, black ring first, a lower time stop) and a
## moment of slow motion to see it coming. `rallies` counts the returns.
func enemy_reflect(at: Vector3, rallies: int) -> void:
	Sfx.play_2d("time_stop", 0.0, 0.7 + minf(rallies - 1, 4) * 0.06)
	mission.hit_stop(0.2, 0.15)
	mission.shake(0.3, at)
	spawn_ring(at, rallies, true)
	var label := make_text(36)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_outline_color", PAPER)
	label.text = tr("REVERSED") if rallies == 1 else tr("RALLY x%d") % (rallies + 1)
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	var anchor := at + Vector3.UP * 3.0
	var follow := func(rise: float) -> void:
		var camera := get_viewport().get_camera_3d()
		if camera == null or not is_instance_valid(label):
			return
		label.position = camera.unproject_position(anchor) - label.size * 0.5 - Vector2(0, rise)
	follow.call(0.0)
	label.scale = Vector2.ONE * 2.0
	var tween := label.create_tween().set_ignore_time_scale(true).set_parallel()
	tween.tween_property(label, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_method(follow, 0.0, 50.0, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.chain().tween_callback(label.queue_free)


## A deflected missile killed `kills` enemies at `at`.
func deflect_kill(at: Vector3, kills: int) -> void:
	mission.hit_stop(0.12)
	mission.shake(0.5, at)
	if PixelArt.is_monochrome():
		PixelArt.invert_flash(0.05)
	spawn_ring(at, 1)
	var text := tr("DEFLECT KILL") if kills == 1 else tr("DEFLECT KILL x%d") % kills
	var label := make_text(34)
	var anchor := at + Vector3.UP * 3.0
	var follow := func(rise: float) -> void:
		var camera := get_viewport().get_camera_3d()
		if camera == null or not is_instance_valid(label):
			return
		label.position = camera.unproject_position(anchor) - label.size * 0.5 - Vector2(0, rise)
	label.text = text
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	follow.call(0.0)
	label.scale = Vector2.ONE * 1.8
	var tween := label.create_tween().set_ignore_time_scale(true).set_parallel()
	tween.tween_property(label, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_method(follow, 0.0, 60.0, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.chain().tween_callback(label.queue_free)


# --- Pieces ------------------------------------------------------------------

func make_bar() -> ColorRect:
	var bar := ColorRect.new()
	# Dark blue with a colour palette: time has gone cold.
	bar.color = INK if OneBit.mono() else OneBit.PICO.dark_blue
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	return bar


# White text with a thick black outline: reads on any dither.
func make_text(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", UiStyle.px(font_size))
	label.add_theme_color_override("font_color", PAPER)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


# 0 = bars hidden, 1 = fully in.
func set_bars(amount: float) -> void:
	var height := size.y * BAR_HEIGHT * amount
	top_bar.offset_bottom = height
	bottom_bar.offset_top = -height


func slide_bars(to: float, seconds: float) -> void:
	if bars_tween != null:
		bars_tween.kill()
	var from := top_bar.offset_bottom / maxf(size.y * BAR_HEIGHT, 1.0)
	bars_tween = create_tween().set_ignore_time_scale(true)
	bars_tween.tween_method(set_bars, from, to, seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


# Pops `label` in big and settles it, then fades it after a moment.
func punch(label: Label, text: String, size_scale: float) -> void:
	label.text = text
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	place_callout()
	if callout_tween != null:
		callout_tween.kill()
	label.modulate.a = 1.0
	label.scale = Vector2.ONE * size_scale * 2.2
	label.rotation = deg_to_rad(randf_range(-6.0, 6.0))
	callout_tween = create_tween().set_ignore_time_scale(true)
	callout_tween.set_parallel()
	callout_tween.tween_property(label, "scale", Vector2.ONE * size_scale, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	callout_tween.tween_property(label, "rotation", 0.0, 0.18)
	callout_tween.chain().tween_interval(0.7)
	callout_tween.chain().tween_property(label, "modulate:a", 0.0, 0.25)


# Keeps the callout above the helicopter on screen.
func place_callout() -> void:
	var camera := get_viewport().get_camera_3d()
	var heli := mission.helicopter if mission != null else null
	if camera == null or heli == null or callout.modulate.a <= 0.0:
		return
	var at := camera.unproject_position(heli.global_position)
	callout.position = at - callout.size * 0.5 - Vector2(0, 110)


# A flat ring spreading from `at` in the world, so it gets the game's
# pixels and outlines: a white ring and a black one just behind it, or
# black first for the enemy's (`ink_first`).
func spawn_ring(at: Vector3, chain: int, ink_first: bool = false) -> void:
	var radius := RING_RADIUS * (1.0 + minf(chain - 1, 4) * 0.15)
	for i in 2:
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.88
		mesh.outer_radius = 1.0
		mesh.rings = 48
		ring.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = PAPER if (i == 0) != ink_first else INK
		ring.material_override = material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mission.world.add_child(ring)
		ring.global_position = at
		ring.scale = Vector3.ONE * 0.5
		var tween := ring.create_tween().set_ignore_time_scale(true)
		tween.tween_interval(i * 0.06)
		tween.tween_property(ring, "scale", Vector3(radius, 0.6, radius), RING_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		tween.tween_callback(ring.queue_free)


# Sparks bursting off each dodged missile, in real time like the ring: the
# deflect's own hit, apart from the time stop.
func spawn_sparks(at: Vector3) -> void:
	var mesh := OneBit.role_puff("spark", 0.5, 0.35)
	var count := 6
	for i in count:
		var spark := MeshInstance3D.new()
		spark.mesh = mesh
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mission.world.add_child(spark)
		spark.global_position = at
		var angle := TAU * (i + randf_range(-0.3, 0.3)) / count
		var out := Vector3(cos(angle), randf_range(0.0, 0.4), sin(angle)) * randf_range(SPARK_REACH * 0.6, SPARK_REACH)
		var tween := spark.create_tween().set_ignore_time_scale(true).set_parallel()
		tween.tween_property(spark, "global_position", at + out, SPARK_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(spark, "scale", Vector3.ONE * 0.2, SPARK_TIME).from(Vector3.ONE * 1.4)
		tween.chain().tween_callback(spark.queue_free)


# Dodged missiles turn white: they're the player's now.
func whiten(missile: Node3D) -> void:
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = PAPER
	for mesh: MeshInstance3D in missile.model.find_children("*", "MeshInstance3D", false, false):
		if mesh != missile.flame:
			mesh.material_override = white


# Brackets blinking round the next missile coming in, while time is slowed,
# and with a colour palette a bright edge on the letterbox bars, so slow
# motion reads even out of the corner of the eye.
func _draw() -> void:
	if chain_dodge == null or not chain_dodge.is_slowed():
		return
	if not OneBit.mono() and top_bar.offset_bottom > 1.0:
		draw_rect(Rect2(0, top_bar.offset_bottom, size.x, EDGE_WIDTH), OneBit.PICO.blue)
		draw_rect(Rect2(0, size.y + bottom_bar.offset_top - EDGE_WIDTH, size.x, EDGE_WIDTH), OneBit.PICO.blue)
	var missile := chain_dodge.next_missile()
	var camera := get_viewport().get_camera_3d()
	if missile == null or camera == null:
		return
	if Time.get_ticks_msec() % 240 > 150:
		return
	var center := camera.unproject_position(missile.global_position)
	var half := 30.0
	var arm := 12.0
	for pass_index in 2:
		var width := 9.0 if pass_index == 0 else 4.0
		var color := INK if pass_index == 0 else PAPER
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var tip: Vector2 = center + corner * half
			draw_line(tip, tip - Vector2(corner.x * arm, 0), color, width)
			draw_line(tip, tip - Vector2(0, corner.y * arm), color, width)
