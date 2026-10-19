extends Node3D

# Homing anti-air rocket. It boosts straight out of the tube, then steers
# toward its target with a limited turn rate, so sharp manoeuvres make it
# overshoot. It detonates near the target, on the ground, or when its
# motor burns out.

var target: Node3D
var speed: float = 26.0
# Max turn rate in radians per second.
var turn_rate: float = 0.9
# Seconds before the motor burns out and the rocket self-destructs.
var lifetime: float = 6.0
# Detonates when this close to the target.
var proximity: float = 2.5
var damage: float = 25.0
var explosion_scene: PackedScene
var ground_y: float = -0.4
# Model size: Stinger missiles are small, SAM-site missiles big.
var size: float = 1.0
# Who fired it, for damage stats (e.g. "STINGER").
var source_name: String = "MISSILE"

# Unguided boost phase right after launch.
var boost_time: float = 0.35
var velocity: Vector3
var age: float = 0.0
var trail: CPUParticles3D


func _ready() -> void:
	add_to_group("aa_missiles")
	build_visuals()
	for child in get_children():
		if child != trail and child is Node3D:
			child.scale *= size
			child.position *= size


# Call after adding to the tree.
func launch(from: Vector3, direction: Vector3) -> void:
	global_position = from
	velocity = direction.normalized() * speed
	face(velocity.normalized())


func _physics_process(delta: float) -> void:
	age += delta

	var has_target: bool = is_instance_valid(target) and not target.get("dead")

	if has_target and age > boost_time:
		var current := velocity.normalized()
		var desired := (target.global_position - global_position).normalized()
		var angle := current.angle_to(desired)
		var max_turn := turn_rate * delta
		var new_dir := desired
		if angle > max_turn:
			new_dir = current.slerp(desired, max_turn / angle).normalized()
		velocity = new_dir * speed

	global_position += velocity * delta
	face(velocity.normalized())

	if has_target and global_position.distance_to(target.global_position) <= proximity:
		if target.has_method("take_damage"):
			target.take_damage(damage, source_name)
		detonate()
	elif age >= lifetime or global_position.y <= ground_y:
		detonate()


func face(direction: Vector3) -> void:
	var up := Vector3.UP
	if absf(direction.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	look_at(global_position + direction, up)


func detonate() -> void:
	if explosion_scene != null and get_parent() != null:
		var explosion := explosion_scene.instantiate() as Node3D
		get_parent().add_child(explosion)
		explosion.global_position = global_position
		explosion.scale = Vector3.ONE * 0.7

	# Leave the smoke trail behind to fade out.
	if trail != null and get_parent() != null:
		trail.emitting = false
		trail.reparent(get_parent())
		get_tree().create_timer(trail.lifetime).timeout.connect(trail.queue_free)

	queue_free()


func build_visuals() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.9)

	# Body (forward is -Z).
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.18
	body_mesh.bottom_radius = 0.18
	body_mesh.height = 1.6
	body_mesh.material = white
	body.mesh = body_mesh
	body.rotation_degrees.x = 90.0
	add_child(body)

	# Red nose.
	var nose := MeshInstance3D.new()
	var nose_mesh := CylinderMesh.new()
	nose_mesh.top_radius = 0.0
	nose_mesh.bottom_radius = 0.18
	nose_mesh.height = 0.4
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.15, 0.1)
	nose_mesh.material = red
	nose.mesh = nose_mesh
	nose.rotation_degrees.x = -90.0
	nose.position = Vector3(0, 0, -1.0)
	add_child(nose)

	# Motor glow.
	var flame := MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.3
	flame_mesh.height = 0.6
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(1.0, 0.7, 0.3)
	flame_mesh.material = flame_mat
	flame.mesh = flame_mesh
	flame.position = Vector3(0, 0, 0.9)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)

	# Smoke trail in world space.
	trail = CPUParticles3D.new()
	trail.amount = 90
	trail.lifetime = 1.6
	trail.local_coords = false
	trail.position = Vector3(0, 0, 1.0)
	trail.direction = Vector3(0, 0, 1)
	trail.spread = 8.0
	trail.initial_velocity_min = 0.3
	trail.initial_velocity_max = 0.8
	trail.gravity = Vector3(0, 0.4, 0)
	trail.scale_amount_min = 0.8
	trail.scale_amount_max = 1.4
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 0.25
	smoke_mesh.height = 0.5
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.albedo_color = Color(0.9, 0.9, 0.9, 0.45)
	smoke_mesh.material = smoke_mat
	trail.mesh = smoke_mesh
	add_child(trail)
