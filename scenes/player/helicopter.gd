extends Node3D

# Player helicopter: WASD / arrow keys fly it over the map at a fixed
# altitude, and it turns to face the mouse cursor. The airframe, its look
# and its stats come from the hangar (see heli_model.gd and loadout.gd).

const UiStyle := preload("res://scenes/ui/ui_style.gd")
const HeliModel := preload("res://scenes/player/heli_model.gd")
const Loadout := preload("res://scenes/hangar/loadout.gd")

@export var camera: Camera3D
@export var speed: float = 24.0
# How quickly the helicopter reaches the requested speed.
@export var acceleration: float = 5.0
@export var altitude: float = 16.0
# Radius of the area of operations around the rig. Past it a warning
# shows and the helicopter is pushed back; it can't go more than
# `bounds_overshoot` further. Campaign missions set their own radius.
@export var bounds: float = 90.0
@export var bounds_overshoot: float = 20.0
# How far out an assault starts, flying in from friendly territory.
@export var ingress_distance: float = 140.0
@export var turn_speed: float = 6.0
@export var max_tilt_degrees: float = 16.0
# Height of the ground plane used for mouse aiming.
@export var ground_y: float = -0.4

@export_group("Health")
@export var max_health: float = 100.0
@export var explosion_scene: PackedScene
# Seconds between being shot down and the round restarting.
@export var restart_delay: float = 2.0

var velocity: Vector3 = Vector3.ZERO
var time: float = 0.0
var health: float = 0.0
var dead: bool = false
# Kept above zero by AA launchers while they are locking on.
var lock_warning_timer: float = 0.0
# Past the edge of the area of operations.
var out_of_bounds: bool = false
# 0 -> 1 while lifting off the rig's pad at the start of a defence.
var takeoff: float = 1.0

var body: Node3D
var main_rotor: Node3D
var tail_rotor: Node3D
var muzzle: Marker3D
var pods: Array = []
var bomb_bay: Marker3D

var health_bar: ProgressBar
var warning_label: Label
var hit_flash: ColorRect

var rotor_sound: AudioStreamPlayer
var lock_sound: AudioStreamPlayer
var inbound_sound: AudioStreamPlayer


func _ready() -> void:
	add_to_group("player")
	# Airframe and upgrades bought in the hangar.
	Loadout.apply_to_helicopter(self)
	health = max_health
	build_model()
	build_hud()
	build_sounds()
	position.y = altitude
	place_for_mission()


func take_damage(amount: float) -> void:
	if dead:
		return

	health = maxf(health - amount, 0.0)
	health_bar.value = health
	# Small-arms hits only tint the screen a little; missiles flash it red.
	hit_flash.color.a = maxf(hit_flash.color.a, clampf(0.06 + amount / 55.0, 0.06, 0.45))
	Sfx.play_2d("heli_hit")
	# Rifle rounds rattle the cabin; missiles throw it about.
	Global.shake(clampf(0.12 + amount / 40.0, 0.12, 0.55))

	if health <= 0.0:
		shot_down()


# Called every frame by an AA launcher that is locking on.
func warn_lock() -> void:
	lock_warning_timer = 0.2


func shot_down() -> void:
	dead = true

	if explosion_scene != null:
		var explosion := explosion_scene.instantiate() as Node3D
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = global_position
		explosion.scale = Vector3.ONE * 1.5

	body.visible = false
	Global.shake(1.0)
	rotor_sound.stop()
	lock_sound.stop()
	inbound_sound.stop()
	set_physics_process(false)

	await get_tree().create_timer(restart_delay).timeout
	Global.game_over("Your helicopter was shot down")


# Assaults start far out on the friendly side and fly in; defences lift
# off from the rig's own pad.
func place_for_mission() -> void:
	if Global.mission.is_empty():
		return
	var rig: String = Global.mission["rig"]
	if Global.is_assault():
		var side: Vector2 = Global.Campaign.approach_side(rig)
		position = Vector3(side.x, 0.0, side.y) * ingress_distance + Vector3(0, altitude, 0)
		rotation.y = atan2(side.x, side.y)
		bounds = ingress_distance + 35.0
	else:
		position = Vector3(0, 2.5, 9.0)
		takeoff = 0.0
		bounds = 120.0

	var camera_rig := get_tree().get_first_node_in_group("game_camera")
	if camera_rig != null and camera_rig.has_method("snap"):
		camera_rig.snap()


func get_muzzle_position() -> Vector3:
	return muzzle.global_position if muzzle != null else global_position


# Front of rocket pod `index` (cycles through the pods), or the chin gun.
func get_pod_position(index: int) -> Vector3:
	if pods.is_empty():
		return get_muzzle_position()
	return pods[index % pods.size()].global_position


func get_bomb_bay_position() -> Vector3:
	return bomb_bay.global_position if bomb_bay != null else global_position + Vector3.DOWN * 1.5


func get_input_direction() -> Vector3:
	var direction := Vector3.ZERO

	# Physical keys, so this works on any keyboard layout.
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		direction.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		direction.z += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0

	return direction.normalized()


# Point on the ground under the mouse cursor (no physics needed).
func get_mouse_ground_point() -> Variant:
	if camera == null:
		return null

	var mouse_pos := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse_pos)
	var direction := camera.project_ray_normal(mouse_pos)

	return Plane(Vector3.UP, ground_y).intersects_ray(origin, direction)


func _physics_process(delta: float) -> void:
	time += delta

	# Smoothly accelerate toward the input direction.
	var desired := get_input_direction() * speed
	velocity = velocity.lerp(desired, 1.0 - exp(-acceleration * delta))

	position += velocity * delta
	keep_in_bounds(delta)

	# Lift off the pad, then hold altitude with a gentle bob.
	takeoff = minf(takeoff + delta / 2.5, 1.0)
	position.y = lerpf(2.5, altitude, smoothstep(0.0, 1.0, takeoff)) + sin(time * 1.7) * 0.25

	# Turn the nose toward the cursor.
	var aim: Variant = get_mouse_ground_point()

	if aim != null:
		var to_aim: Vector3 = aim - global_position
		if Vector2(to_aim.x, to_aim.z).length() > 1.0:
			var desired_yaw := atan2(-to_aim.x, -to_aim.z)
			rotation.y = lerp_angle(rotation.y, desired_yaw, 1.0 - exp(-turn_speed * delta))

	# Tilt the body into the direction of travel.
	var local_velocity := global_transform.basis.inverse() * velocity
	var tilt := deg_to_rad(max_tilt_degrees)
	body.rotation.x = lerpf(body.rotation.x, tilt * local_velocity.z / speed, 1.0 - exp(-5.0 * delta))
	body.rotation.z = lerpf(body.rotation.z, -tilt * local_velocity.x / speed, 1.0 - exp(-5.0 * delta))


# Soft edge of the area of operations: push back past it, harder the
# further out, and never more than bounds_overshoot beyond.
func keep_in_bounds(delta: float) -> void:
	var flat := Vector2(position.x, position.z)
	var over := flat.length() - bounds
	out_of_bounds = over > 0.0
	if not out_of_bounds:
		return
	var inward := -flat.normalized()
	velocity += Vector3(inward.x, 0.0, inward.y) * minf(over * 1.5, speed) * 3.0 * delta
	if over > bounds_overshoot:
		flat = flat.normalized() * (bounds + bounds_overshoot)
		position.x = flat.x
		position.z = flat.y


func _process(delta: float) -> void:
	update_hud(delta)

	if dead:
		return

	if main_rotor != null:
		main_rotor.rotate_y(delta * 28.0)
	if tail_rotor != null:
		tail_rotor.rotate_x(delta * 40.0)


func update_hud(delta: float) -> void:
	hit_flash.color.a = maxf(hit_flash.color.a - delta * 1.5, 0.0)
	lock_warning_timer = maxf(lock_warning_timer - delta, 0.0)

	var incoming := false
	for missile in get_tree().get_nodes_in_group("aa_missiles"):
		if missile.get("target") == self:
			incoming = true
			break

	if dead:
		warning_label.visible = false
	elif incoming:
		warning_label.text = "MISSILE INBOUND"
		warning_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
		warning_label.visible = fmod(time, 0.25) < 0.15
	elif lock_warning_timer > 0.0:
		warning_label.text = "MISSILE LOCK"
		warning_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
		warning_label.visible = fmod(time, 0.6) < 0.4
	elif out_of_bounds:
		warning_label.text = "LEAVING AREA OF OPERATIONS"
		warning_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		warning_label.visible = fmod(time, 0.8) < 0.55
	else:
		warning_label.visible = false

	# Warning tones: fast beeps for an incoming missile, slower for a lock.
	set_loop_playing(inbound_sound, incoming and not dead)
	set_loop_playing(lock_sound, lock_warning_timer > 0.0 and not incoming and not dead)


func set_loop_playing(player: AudioStreamPlayer, on: bool) -> void:
	if on and not player.playing:
		player.play()
	elif not on and player.playing:
		player.stop()


func make_loop_player(sound: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = Sfx.get_stream(sound)
	player.volume_db = Sfx.mix_db(sound)
	add_child(player)
	return player


func build_sounds() -> void:
	rotor_sound = make_loop_player("rotor_loop")
	lock_sound = make_loop_player("lock_tone")
	inbound_sound = make_loop_player("inbound_tone")
	rotor_sound.play()


func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	hit_flash = ColorRect.new()
	hit_flash.color = Color(1.0, 0.1, 0.05, 0.0)
	hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(hit_flash)

	# Hull bar at the bottom centre.
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -160
	box.offset_right = 160
	box.offset_top = -70
	box.offset_bottom = -24
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)

	var caption := Label.new()
	caption.text = "HULL"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", UiStyle.px(16))
	box.add_child(caption)

	health_bar = ProgressBar.new()
	health_bar.max_value = max_health
	health_bar.value = health
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(320, 14)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 0.7)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.85, 0.45)
	health_bar.add_theme_stylebox_override("background", bg)
	health_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(health_bar)

	# Lock / missile warning above the hull bar.
	warning_label = Label.new()
	warning_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	warning_label.offset_left = -200
	warning_label.offset_right = 200
	warning_label.offset_top = -120
	warning_label.offset_bottom = -80
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.add_theme_font_size_override("font_size", UiStyle.px(30))
	warning_label.visible = false
	layer.add_child(warning_label)


func build_model() -> void:
	var parts: Dictionary = HeliModel.build(self, Loadout.HELICOPTERS[Loadout.selected()]["style"])
	body = parts["body"]
	main_rotor = parts["main_rotor"]
	tail_rotor = parts["tail_rotor"]
	muzzle = parts["muzzle"]
	pods = parts["pods"]
	bomb_bay = parts["bomb_bay"]
