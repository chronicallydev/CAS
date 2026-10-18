extends Node3D

@export var target_marker: Marker3D
@export var orbit_radius: float = 3.0
@export var orbit_speed: float = 15.0
@export var height_offset: float = 0.0

var angle: float = 0.0


func _ready() -> void:
	print("camera controller init")
	if target_marker == null:
		push_warning("Assign a Marker3D to Target Marker.")
		set_process(false)
		return

	var offset = global_position - target_marker.global_position
	angle = atan2(offset.z, offset.x)


func _physics_process(delta: float) -> void:
	angle += deg_to_rad(orbit_speed) * delta

	var center = target_marker.global_position

	global_position = center + Vector3(
		cos(angle) * orbit_radius,
		height_offset,
		sin(angle) * orbit_radius
	)
	look_at(target_marker.global_position + Vector3(0, 2, 0))
