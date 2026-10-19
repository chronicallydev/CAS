extends Node3D

# Unguided rocket from the wing pods: flies straight to a point on the
# ground at a fixed speed with a smoke trail, then calls on_hit.

var target: Vector3
var speed: float = 60.0
var on_hit: Callable
var trail: CPUParticles3D


# Call after adding to the tree.
func launch(from: Vector3, to: Vector3, rocket_speed: float, hit_callback: Callable) -> void:
	global_position = from
	target = to
	speed = rocket_speed
	on_hit = hit_callback
	if from.distance_to(to) > 0.01:
		look_at(to, Vector3.UP)


func _ready() -> void:
	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.09
	mesh.bottom_radius = 0.09
	mesh.height = 1.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.82, 0.82, 0.78)
	mesh.material = material
	body.mesh = mesh
	body.rotation_degrees.x = 90.0
	add_child(body)

	var flame := MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.18
	flame_mesh.height = 0.36
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(1.0, 0.75, 0.3)
	flame_mesh.material = flame_mat
	flame.mesh = flame_mesh
	flame.position = Vector3(0, 0, 0.55)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)

	trail = CPUParticles3D.new()
	trail.amount = 40
	trail.lifetime = 0.7
	trail.local_coords = false
	trail.position = Vector3(0, 0, 0.6)
	trail.direction = Vector3(0, 0, 1)
	trail.spread = 6.0
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 0.6
	trail.gravity = Vector3(0, 0.3, 0)
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var smoke := SphereMesh.new()
	smoke.radius = 0.18
	smoke.height = 0.36
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.albedo_color = Color(0.85, 0.85, 0.85, 0.4)
	smoke.material = smoke_mat
	trail.mesh = smoke
	add_child(trail)


func _physics_process(delta: float) -> void:
	var to_target := target - global_position
	var step := speed * delta

	if to_target.length() <= step:
		global_position = target
		arrive()
	else:
		global_position += to_target.normalized() * step


func arrive() -> void:
	if on_hit.is_valid():
		on_hit.call(target)

	# Leave the smoke trail behind to fade out.
	if trail != null and get_parent() != null:
		trail.emitting = false
		trail.reparent(get_parent())
		get_tree().create_timer(trail.lifetime).timeout.connect(trail.queue_free)

	queue_free()
