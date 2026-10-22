class_name TakeoffIntro
extends Node

# The run's opening shot (about 5 s): the helicopter sits on a helipad
# behind the start, spools up, lifts off to its flying altitude and noses
# over up the screen, the way the whole run goes. It reaches the run's
# start at full speed, then `finished` fires and the player has it.
# Any key or mouse button skips straight to that point.
#
# The helicopter's own flight (_physics_process) is off while it plays;
# pose() places it from the time alone, so skipping is just pose(DURATION).

signal finished

const P := preload("res://shared/props/prop_builder.gd")
const Debris := preload("res://features/mission/effects/debris.gd")

const DURATION := 5.0
# Spooling up on the pad, then the climb, then the run forward (which
# overlaps the end of the climb).
const LIFT_START := 1.2
const LIFT_END := 3.2
const FORWARD_START := 2.2
# Most the nose dips as it picks up speed.
const NOSE_DOWN_DEGREES := 18.0
const PAD_RADIUS := 6.5
# Height of the letterbox bars, as a fraction of the screen.
const BAR_HEIGHT := 0.12

var mission: MissionContext
var heli: Helicopter
var time: float = 0.0
var done: bool = false
# Where the run starts (x, z) and where the pad is, behind it.
var start: Vector3
var pad: Vector3
# How high the helicopter's origin sits above the pad when landed.
var landed_height: float = 0.0
var dust_timer: float = 0.0
var saved_lead: float = 0.0
# HUD layers hidden while it plays, to show again after.
var hidden_layers: Array[CanvasLayer] = []
var bars: CanvasLayer


## Plays the intro for `mission`'s helicopter, which is placed at the
## run's start.
func play(mission_context: MissionContext) -> void:
	mission = mission_context
	heli = mission.helicopter
	start = heli.global_position
	# Far enough back that a steady pick-up reaches full speed at the start.
	var run_up := heli.speed * (DURATION - FORWARD_START) * 0.5
	pad = Vector3(start.x, heli.ground_y, start.z + run_up)
	build_pad()
	landed_height = heli.global_position.y - lowest_point(heli)
	heli.set_physics_process(false)
	heli.rotation.y = 0.0
	saved_lead = mission.camera_rig.cursor_lead
	mission.camera_rig.cursor_lead = 0.0
	hide_hud()
	build_bars()
	pose(0.0)
	mission.camera_rig.snap()


func _process(delta: float) -> void:
	if done:
		return
	time += delta
	if time >= DURATION:
		finish()
		return
	pose(time)
	# Rotor wash kicking up the sand while it's low.
	var height := heli.global_position.y - pad.y
	dust_timer -= delta
	if time > LIFT_START * 0.5 and height < 9.0 and dust_timer <= 0.0:
		dust_timer = 0.12
		var angle := randf() * TAU
		var at := pad + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(2.0, PAD_RADIUS + 2.0)
		Debris.spawn_dust(MissionContext.spawn_parent(heli), at, 1.6)


func _input(event: InputEvent) -> void:
	if done:
		return
	var pressed := (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) and event.is_pressed()
	if pressed and not event.is_echo():
		# Taken here, so the press doesn't also fire or dash.
		get_viewport().set_input_as_handled()
		finish()


# The helicopter at `t` seconds in.
func pose(t: float) -> void:
	var lift := smoothstep(LIFT_START, LIFT_END, t)
	var height := lerpf(landed_height, heli.altitude, lift)
	# Even acceleration from FORWARD_START, reaching full speed at the end.
	var span := DURATION - FORWARD_START
	var u := clampf((t - FORWARD_START) / span, 0.0, 1.0)
	var forward := (start.z - pad.z) * u * u
	heli.global_position = Vector3(pad.x, pad.y + height, pad.z + forward)
	heli.velocity = Vector3(0.0, 0.0, -heli.speed * u)
	# Nose down while it picks up speed, settling as the climb ends; a
	# small rock as it comes off the pad.
	var dip := sin(u * PI) * 0.6 + u * 0.4
	var rock := sin(t * 9.0) * 0.03 * (smoothstep(LIFT_START - 0.4, LIFT_START, t) - lift)
	heli.body.rotation.x = -deg_to_rad(NOSE_DOWN_DEGREES) * dip * lerpf(1.0, 0.45, u)
	heli.body.rotation.z = rock


func finish() -> void:
	if done:
		return
	done = true
	pose(DURATION)
	heli.set_physics_process(true)
	mission.camera_rig.cursor_lead = saved_lead
	for layer in hidden_layers:
		if is_instance_valid(layer):
			layer.visible = true
	if bars != null:
		bars.queue_free()
	finished.emit()
	queue_free()


# --- Pieces --------------------------------------------------------------------

# A round pad with a ring and a big H, dark against the sand so it reads in
# 1-bit, with a few edge lights.
func build_pad() -> void:
	var root := Node3D.new()
	mission.world.add_child(root)
	root.global_position = pad
	var asphalt := P.material(Color(0.16, 0.16, 0.17), 0.9)
	var paint := P.material(Color(0.95, 0.95, 0.92), 0.7)
	P.cylinder(root, PAD_RADIUS, 0.3, Vector3(0, 0.15, 0), asphalt, Vector3.ZERO, 32)
	P.cylinder(root, PAD_RADIUS * 0.82, 0.04, Vector3(0, 0.31, 0), paint, Vector3.ZERO, 32)
	P.cylinder(root, PAD_RADIUS * 0.72, 0.06, Vector3(0, 0.32, 0), asphalt, Vector3.ZERO, 32)
	# The H, its uprights along the run.
	for side in [-1.0, 1.0]:
		P.box(root, Vector3(0.7, 0.08, 4.6), Vector3(side * 1.5, 0.37, 0), paint)
	P.box(root, Vector3(2.4, 0.08, 0.7), Vector3(0, 0.37, 0), paint)
	for k in 8:
		var angle := TAU * k / 8.0
		P.box(root, Vector3(0.35, 0.3, 0.35), Vector3(cos(angle), 0.0, sin(angle)) * (PAD_RADIUS + 0.4) + Vector3(0, 0.15, 0), paint)
	mission.environment.clear_area(Rect2(pad.x - PAD_RADIUS - 6.0, pad.z - PAD_RADIUS - 6.0, (PAD_RADIUS + 6.0) * 2.0, (PAD_RADIUS + 6.0) * 2.0))
	pad.y += 0.3


# Lowest point of the helicopter's model (its skids or wheels).
func lowest_point(node: Node3D) -> float:
	var lowest := INF
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var box := mesh.global_transform * mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
	return lowest if lowest < INF else node.global_position.y - 1.5


func hide_hud() -> void:
	for layer: CanvasLayer in mission.find_children("*", "CanvasLayer", true, false):
		if layer.visible:
			layer.visible = false
			hidden_layers.append(layer)


# Black bars top and bottom, and the skip hint.
func build_bars() -> void:
	bars = CanvasLayer.new()
	bars.layer = 40
	add_child(bars)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0 - BAR_HEIGHT
		bar.anchor_bottom = BAR_HEIGHT if top else 1.0
		bars.add_child(bar)
	var hint := Label.new()
	hint.text = "ANY KEY TO SKIP"
	hint.add_theme_font_size_override("font_size", UiStyle.px(26))
	hint.add_theme_color_override("font_color", Color.WHITE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.anchor_left = 0.5
	hint.anchor_right = 0.97
	hint.anchor_top = 1.0 - BAR_HEIGHT
	hint.anchor_bottom = 1.0
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_child(hint)
