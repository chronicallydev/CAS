extends Node3D

# Top-down camera that smoothly follows a target at a fixed angle.

@export var target: Node3D
# Camera position relative to the point on the ground under the target.
@export var offset: Vector3 = Vector3(0.0, 50.0, 24.0)
@export var follow_speed: float = 5.0


func _ready() -> void:
	# Move after the target has moved this physics frame.
	process_physics_priority = 10

	if target != null:
		global_position = ground_point() + offset
	look_at(global_position - offset)


func ground_point() -> Vector3:
	var point := target.global_position
	point.y = 0.0
	return point


func _physics_process(delta: float) -> void:
	if target == null:
		return

	var desired := ground_point() + offset
	global_position = global_position.lerp(desired, 1.0 - exp(-follow_speed * delta))
	look_at(global_position - offset)
