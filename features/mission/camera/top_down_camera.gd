class_name TopDownCamera
extends Node3D

# Top-down camera that smoothly follows a target at a fixed angle, with
# trauma-based screen shake (call add_trauma, or MissionContext.shake).

@export var target: Node3D
# Camera position relative to the point on the ground under the target.
@export var offset: Vector3 = Vector3(0.0, 42.0, 42.0)
# 5.0 was the old, laggier follow.
@export var follow_speed: float = 12.0
# Orthographic suits the pixel-art look; size is the visible height.
@export var orthographic: bool = true
@export var ortho_size: float = 60.0

@export_group("Look-ahead")
# The view leans toward the mouse cursor so more of where you aim is on
# screen: metres of lead with the cursor at the top or bottom edge.
@export var cursor_lead: float = 9.0
# ...and toward where the target is flying: seconds of its velocity.
@export var velocity_lead: float = 0.12

@export_group("Shake")
# Largest sideways offset of the view at full trauma, in metres.
@export var max_shake: float = 1.6
# Trauma lost per second.
@export var shake_decay: float = 1.8
# How fast a directional kick (add_kick) springs back.
@export var kick_return: float = 14.0

var trauma: float = 0.0
var time: float = 0.0
# Directional jolt on the ground plane (x, z), springing back to zero.
var kick: Vector2 = Vector2.ZERO

@onready var camera: Camera3D = get_node_or_null("Camera")


func _ready() -> void:
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


# Pushes the view `amount` metres toward `direction` (on the ground).
func add_kick(direction: Vector3, amount: float) -> void:
	kick += Vector2(direction.x, direction.z).normalized() * amount
	kick = kick.limit_length(3.0)


func _physics_process(delta: float) -> void:
	if target == null:
		return

	var desired := ground_point() + get_lead() + offset
	global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))
	look_at(global_position - offset)


# Ground offset ahead of the target. The cursor part comes from the mouse's
# place on screen, not on the ground, so it can't feed back on itself as the
# camera moves.
func get_lead() -> Vector3:
	var lead := Vector3.ZERO
	var target_velocity: Variant = target.get("velocity")
	if target_velocity is Vector3:
		lead += Vector3(target_velocity.x, 0.0, target_velocity.z) * velocity_lead

	var view := get_viewport().get_visible_rect().size
	if view.y > 0.0:
		# -1..1 from the centre to the top/bottom edge; screen down is +z.
		var mouse := (get_viewport().get_mouse_position() - view * 0.5) / (view.y * 0.5)
		mouse = mouse.limit_length(1.0)
		lead += Vector3(mouse.x, 0.0, mouse.y) * cursor_lead
	return lead


func _process(delta: float) -> void:
	time += delta
	trauma = maxf(trauma - shake_decay * delta, 0.0)
	kick = kick.lerp(Vector2.ZERO, 1.0 - exp(-kick_return * delta))

	if camera == null:
		return

	# Squared trauma: small knocks stay subtle, big ones really kick.
	var strength := trauma * trauma * max_shake
	camera.h_offset = strength * (sin(time * 41.0) * 0.6 + sin(time * 67.0 + 1.3) * 0.4)
	camera.v_offset = strength * (sin(time * 37.0 + 2.1) * 0.6 + sin(time * 59.0 + 0.4) * 0.4)
	# The camera looks along -z, so ground +x is screen right and ground +z
	# is screen down.
	camera.h_offset += kick.x
	camera.v_offset -= kick.y
