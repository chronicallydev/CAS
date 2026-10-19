extends Node3D

# Slow top-attack missile: climbs above the launch point, cruises toward the
# target and then dives onto it from above. Tracks a locked enemy if given one.

signal impacted(position: Vector3)

@export var speed: float = 15.0
# Max turn rate in radians per second (doubled while diving).
@export var turn_rate: float = 2.5
# How far above the launch point the missile cruises.
@export var climb_height: float = 15.0
# Horizontal distance to the target at which the dive starts.
@export var dive_distance: float = 10.0
@export var max_lifetime: float = 20.0
# Top speed reached during the final dive, and how fast it gets there.
@export var dive_speed: float = 60.0
@export var dive_acceleration: float = 45.0

var current_speed: float = 0.0
var target_node: Node3D
var target_position: Vector3
var velocity: Vector3
var cruise_altitude: float = 0.0
var diving: bool = false
var age: float = 0.0

var trail: CPUParticles3D
var flame: MeshInstance3D


func _ready() -> void:
	build_visuals()


# Call after the missile has been added to the tree.
func launch(from: Vector3, target_pos: Vector3, target: Node3D = null) -> void:
	global_position = from
	target_position = target_pos
	target_node = target
	cruise_altitude = from.y + climb_height

	# Soft launch: mostly upward, leaning toward the target.
	var flat_dir := Vector3(target_pos.x - from.x, 0.0, target_pos.z - from.z)
	if flat_dir.length() > 0.01:
		flat_dir = flat_dir.normalized()
	current_speed = speed
	velocity = (Vector3.UP + flat_dir * 0.5).normalized() * current_speed
	face(velocity.normalized())


func _physics_process(delta: float) -> void:
	age += delta

	# Follow the locked enemy while it is alive.
	if is_instance_valid(target_node) and not target_node.is_queued_for_deletion():
		target_position = target_node.global_position

	var to_target := target_position - global_position
	var flat_distance := Vector2(to_target.x, to_target.z).length()

	if not diving and flat_distance <= dive_distance:
		diving = true

	var aim: Vector3
	if diving:
		aim = target_position
	else:
		aim = Vector3(target_position.x, cruise_altitude, target_position.z)

	var current := velocity.normalized()
	var desired := (aim - global_position).normalized()
	var max_turn := turn_rate * (2.0 if diving else 1.0) * delta
	var angle := current.angle_to(desired)

	var new_dir := desired
	if angle > max_turn:
		new_dir = current.slerp(desired, max_turn / angle).normalized()

	# Accelerate once pointing down in the final dive.
	if diving and new_dir.y < -0.5:
		current_speed = move_toward(current_speed, maxf(dive_speed, speed), dive_acceleration * delta)
		if flame != null:
			flame.scale = Vector3.ONE * remap(current_speed, speed, maxf(dive_speed, speed + 0.01), 1.0, 2.2)

	velocity = new_dir * current_speed
	global_position += velocity * delta
	face(new_dir)

	# At high speed the missile can step past the target in one frame.
	var hit_distance := maxf(1.0, current_speed * delta)
	var hit_target := global_position.distance_to(target_position) <= hit_distance
	var hit_ground := diving and global_position.y <= target_position.y

	if hit_target or hit_ground or age >= max_lifetime:
		detonate()


func face(direction: Vector3) -> void:
	var up := Vector3.UP
	if absf(direction.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	look_at(global_position + direction, up)


func detonate() -> void:
	impacted.emit(global_position)

	# Leave the smoke trail behind so it fades out instead of vanishing.
	if trail != null and get_parent() != null:
		trail.emitting = false
		trail.reparent(get_parent())
		get_tree().create_timer(trail.lifetime).timeout.connect(trail.queue_free)

	queue_free()


func build_visuals() -> void:
	# Body (forward is -Z, so the tail is at +Z).
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.25
	body_mesh.bottom_radius = 0.25
	body_mesh.height = 2.0
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.3, 0.35, 0.2)
	body_mesh.material = body_material
	body.mesh = body_mesh
	body.rotation_degrees.x = 90.0
	add_child(body)

	# Rocket motor glow.
	flame = MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.35
	flame_mesh.height = 0.7
	var flame_material := StandardMaterial3D.new()
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.albedo_color = Color(1.0, 0.6, 0.2)
	flame_material.emission_enabled = true
	flame_material.emission = Color(1.0, 0.5, 0.1)
	flame_material.emission_energy_multiplier = 4.0
	flame_mesh.material = flame_material
	flame.mesh = flame_mesh
	flame.position = Vector3(0.0, 0.0, 1.1)
	add_child(flame)

	# Smoke trail in world space.
	trail = CPUParticles3D.new()
	trail.amount = 80
	trail.lifetime = 2.0
	trail.local_coords = false
	trail.position = Vector3(0.0, 0.0, 1.3)
	trail.direction = Vector3(0.0, 0.0, 1.0)
	trail.spread = 10.0
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 1.0
	trail.gravity = Vector3(0.0, 0.5, 0.0)
	trail.scale_amount_min = 0.8
	trail.scale_amount_max = 1.5
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 0.3
	smoke_mesh.height = 0.6
	var smoke_material := StandardMaterial3D.new()
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_material.albedo_color = Color(0.8, 0.8, 0.8, 0.4)
	smoke_mesh.material = smoke_material
	trail.mesh = smoke_mesh
	add_child(trail)
