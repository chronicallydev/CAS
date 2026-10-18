extends Node3D

# Player helicopter: WASD / arrow keys fly it over the map at a fixed
# altitude, and it turns to face the mouse cursor. The model is built from
# primitives in code.

const P := preload("res://scenes/environment/prop_builder.gd")

@export var camera: Camera3D
@export var speed: float = 24.0
# How quickly the helicopter reaches the requested speed.
@export var acceleration: float = 5.0
@export var altitude: float = 16.0
# The helicopter stays inside this distance from the centre on X and Z.
@export var bounds: float = 65.0
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

var body: Node3D
var main_rotor: Node3D
var tail_rotor: Node3D
var muzzle: Marker3D

var health_bar: ProgressBar
var warning_label: Label
var hit_flash: ColorRect


func _ready() -> void:
	add_to_group("player")
	health = max_health
	build_model()
	build_hud()
	position.y = altitude


func take_damage(amount: float) -> void:
	if dead:
		return

	health = maxf(health - amount, 0.0)
	health_bar.value = health
	hit_flash.color.a = 0.45

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
	set_physics_process(false)

	await get_tree().create_timer(restart_delay).timeout
	get_tree().reload_current_scene()


func get_muzzle_position() -> Vector3:
	return muzzle.global_position if muzzle != null else global_position


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
	position.x = clampf(position.x, -bounds, bounds)
	position.z = clampf(position.z, -bounds, bounds)
	position.y = altitude + sin(time * 1.7) * 0.25

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
	else:
		warning_label.visible = false


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
	caption.add_theme_font_size_override("font_size", 16)
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
	warning_label.add_theme_font_size_override("font_size", 30)
	warning_label.visible = false
	layer.add_child(warning_label)


func build_model() -> void:
	body = Node3D.new()
	add_child(body)

	var olive := P.material(Color(0.33, 0.37, 0.26), 0.6, 0.2)
	var dark := P.material(Color(0.18, 0.19, 0.2), 0.5, 0.5)
	var glass := P.material(Color(0.12, 0.2, 0.28), 0.1, 0.6)

	# Fuselage and cockpit (nose points along -Z).
	P.sphere(body, 1.0, Vector3(0, 0, 0), olive, Vector3(1.3, 1.15, 2.5))
	P.sphere(body, 1.0, Vector3(0, 0.25, -1.6), glass, Vector3(0.95, 0.8, 1.1))

	# Tail boom, fin and stabiliser.
	P.beam(body, Vector3(0, 0.2, 1.8), Vector3(0, 0.55, 6.6), 0.4, olive)
	P.box(body, Vector3(0.15, 1.5, 0.9), Vector3(0, 1.15, 6.6), olive, Vector3(-15, 0, 0))
	P.box(body, Vector3(2.0, 0.1, 0.6), Vector3(0, 0.5, 5.8), olive)

	# Tail rotor.
	tail_rotor = Node3D.new()
	tail_rotor.position = Vector3(0.25, 1.1, 6.8)
	body.add_child(tail_rotor)
	P.box(tail_rotor, Vector3(0.05, 1.8, 0.2), Vector3.ZERO, dark)
	P.box(tail_rotor, Vector3(0.05, 0.2, 1.8), Vector3.ZERO, dark)

	# Main rotor: mast, four blades and a faint blur disc.
	P.cylinder(body, 0.15, 0.7, Vector3(0, 1.4, 0), dark)
	main_rotor = Node3D.new()
	main_rotor.position = Vector3(0, 1.8, 0)
	body.add_child(main_rotor)
	P.box(main_rotor, Vector3(9.5, 0.06, 0.4), Vector3.ZERO, dark)
	P.box(main_rotor, Vector3(0.4, 0.06, 9.5), Vector3.ZERO, dark)

	var blur := P.material(Color(0.2, 0.2, 0.2, 0.12), 1.0)
	blur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var disc := P.cylinder(body, 4.75, 0.02, Vector3(0, 1.8, 0), blur, Vector3.ZERO, 32)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Skids.
	for x in [-0.95, 0.95]:
		P.pipe(body, Vector3(x, -1.45, -1.8), Vector3(x, -1.45, 1.6), 0.08, dark)
		P.beam(body, Vector3(x, -1.45, -0.9), Vector3(x * 0.6, -0.7, -0.9), 0.1, dark)
		P.beam(body, Vector3(x, -1.45, 0.9), Vector3(x * 0.6, -0.7, 0.9), 0.1, dark)

	# Stub wings with rocket pods.
	P.box(body, Vector3(3.8, 0.12, 0.8), Vector3(0, -0.15, 0.2), olive)
	for x in [-1.7, 1.7]:
		P.cylinder(body, 0.22, 1.4, Vector3(x, -0.45, 0.1), dark, Vector3(90, 0, 0))

	# Chin gun and the muzzle point weapons fire from.
	P.sphere(body, 0.3, Vector3(0, -0.95, -1.9), dark)
	P.cylinder(body, 0.07, 1.1, Vector3(0, -1.0, -2.45), dark, Vector3(90, 0, 0))
	muzzle = Marker3D.new()
	muzzle.position = Vector3(0, -1.0, -3.0)
	body.add_child(muzzle)
