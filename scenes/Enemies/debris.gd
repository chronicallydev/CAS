extends Node3D

# A piece of flying debris: a chip knocked off by a heavy hit, or a whole
# part (turret, wheel, launcher) thrown off when a vehicle is destroyed.
# Moves with simple hand-written ballistics (no physics bodies): flies,
# tumbles, bounces once or twice on the ground, rests, then sinks away.
# A global cap keeps the number of pieces in check.

const GRAVITY := 28.0
const MAX_DEBRIS := 60

static var count: int = 0
static var chip_mesh: BoxMesh
static var burnt_material: StandardMaterial3D

var velocity: Vector3 = Vector3.ZERO
var spin_axis: Vector3 = Vector3.UP
var spin_speed: float = 0.0
var lifetime: float = 2.0
# Distance from the piece's origin to its lowest point.
var radius: float = 0.2
var ground_y: float = -0.4
var age: float = 0.0
var resting: bool = false


static func can_spawn() -> bool:
	return count < MAX_DEBRIS


# A small painted chip of armour/bodywork.
static func spawn_chip(scene: Node, at: Vector3, out: Vector3, material: Material) -> void:
	if scene == null or not can_spawn():
		return
	if chip_mesh == null:
		chip_mesh = BoxMesh.new()

	var debris: Node3D = load("res://scenes/Enemies/debris.gd").new()
	var piece := MeshInstance3D.new()
	piece.mesh = chip_mesh
	piece.material_override = material
	var size := Vector3(randf_range(0.25, 0.5), randf_range(0.07, 0.16), randf_range(0.25, 0.5))
	piece.scale = size
	debris.add_child(piece)
	debris.radius = size.y * 0.5 + 0.05
	debris.lifetime = randf_range(1.2, 1.8)
	debris.velocity = out * randf_range(5.0, 9.0) + Vector3.UP * randf_range(4.0, 8.0) \
		+ Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	debris.spin_axis = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	debris.spin_speed = randf_range(8.0, 16.0)
	scene.add_child(debris)
	debris.global_position = at


# Throw a real part of a vehicle (keeps its meshes, charred) away from
# `origin`. The part is moved out of the vehicle, so the wreck won't have it.
static func launch_part(part: Node3D, origin: Vector3, big: bool) -> void:
	var scene := part.get_tree().current_scene
	if scene == null:
		return
	if burnt_material == null:
		burnt_material = StandardMaterial3D.new()
		burnt_material.albedo_color = Color(0.25, 0.22, 0.2)
		burnt_material.roughness = 1.0

	var debris: Node3D = load("res://scenes/Enemies/debris.gd").new()
	scene.add_child(debris)
	debris.global_transform = part.global_transform
	part.reparent(debris, true)

	# Char it, and drop anything that isn't a mesh (markers, health bars).
	var low := 0.0
	for child in part.find_children("*", "", true, false) + [part]:
		if child is MeshInstance3D:
			child.material_override = burnt_material
			var box: AABB = debris.global_transform.affine_inverse() * child.global_transform * child.get_aabb()
			low = minf(low, box.position.y)
		elif child is Sprite3D:
			child.queue_free()
	debris.radius = maxf(-low, 0.3)

	var away := part.global_position - origin
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	debris.velocity = away * randf_range(3.0, 7.0) + Vector3.UP * (randf_range(13.0, 18.0) if big else randf_range(8.0, 13.0))
	debris.spin_axis = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()
	debris.spin_speed = randf_range(4.0, 9.0) if big else randf_range(8.0, 14.0)
	debris.lifetime = 6.0
	if big:
		debris.add_smoke_trail()


func _enter_tree() -> void:
	count += 1


func _exit_tree() -> void:
	count -= 1


func add_smoke_trail() -> void:
	var trail := CPUParticles3D.new()
	trail.amount = 16
	trail.lifetime = 1.0
	trail.local_coords = false
	trail.direction = Vector3.UP
	trail.spread = 20.0
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 1.5
	trail.gravity = Vector3(0, 0.5, 0)
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 0.8
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.15, 0.14, 0.13, 0.6)
	mesh.material = material
	trail.mesh = mesh
	add_child(trail)


func _physics_process(delta: float) -> void:
	age += delta

	if not resting:
		velocity.y -= GRAVITY * delta
		global_position += velocity * delta
		if spin_speed > 0.0:
			global_transform.basis = Basis(spin_axis, spin_speed * delta) * global_transform.basis

		var floor_y := ground_y + radius
		if global_position.y <= floor_y:
			global_position.y = floor_y
			if velocity.y < -3.0:
				# Bounce, losing most of the energy.
				velocity.y = -velocity.y * 0.3
				velocity.x *= 0.5
				velocity.z *= 0.5
				spin_speed *= 0.5
			else:
				resting = true
				velocity = Vector3.ZERO
				spin_speed = 0.0

	# Sink into the ground over the last second, then disappear.
	if age > lifetime - 1.0:
		global_position.y -= delta * (0.6 + radius)
	if age >= lifetime:
		queue_free()
