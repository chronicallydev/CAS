extends Node3D

# Top-down camera that smoothly follows a target at a fixed angle, with
# trauma-based screen shake (call add_trauma, or Global.shake).

@export var target: Node3D
# Camera position relative to the point on the ground under the target.
@export var offset: Vector3 = Vector3(0.0, 42.0, 42.0)
@export var follow_speed: float = 5.0
# Orthographic suits the pixel-art look; size is the visible height.
@export var orthographic: bool = true
@export var ortho_size: float = 60.0

@export_group("Shake")
# Largest sideways offset of the view at full trauma, in metres.
@export var max_shake: float = 1.6
# Trauma lost per second.
@export var shake_decay: float = 1.8

var trauma: float = 0.0
var time: float = 0.0

@onready var camera: Camera3D = get_node_or_null("Camera")


func _ready() -> void:
	add_to_group("game_camera")
	if camera != null and orthographic:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = ortho_size
	# Move after the target has moved this physics frame.
	process_physics_priority = 10

	if target != null:
		global_position = ground_point() + offset
	look_at(global_position - offset)


func ground_point() -> Vector3:
	var point := target.global_position
	point.y = 0.0
	return point


# Jump straight to the target (e.g. when it's placed far from the start).
func snap() -> void:
	if target != null:
		global_position = ground_point() + offset
		look_at(global_position - offset)


# Point the camera is looking at, on the ground.
func get_focus() -> Vector3:
	return global_position - offset


func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


func _physics_process(delta: float) -> void:
	if target == null:
		return

	var desired := ground_point() + offset
	global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))
	look_at(global_position - offset)


func _process(delta: float) -> void:
	time += delta
	trauma = maxf(trauma - shake_decay * delta, 0.0)

	if camera == null:
		return

	# Squared trauma: small knocks stay subtle, big ones really kick.
	var strength := trauma * trauma * max_shake
	camera.h_offset = strength * (sin(time * 41.0) * 0.6 + sin(time * 67.0 + 1.3) * 0.4)
	camera.v_offset = strength * (sin(time * 37.0 + 2.1) * 0.6 + sin(time * 59.0 + 0.4) * 0.4)
