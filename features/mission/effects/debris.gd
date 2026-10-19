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
# Kick up dust (and a thud) the first time it lands hard.
var dust_on_land: bool = false
var landed: bool = false
var land_sound: String = "body_thud"

# First touch of the ground.
signal touched_ground(at: Vector3)


static func can_spawn() -> bool:
	return count < MAX_DEBRIS


# A small painted chip of armour/bodywork.
static func spawn_chip(scene: Node, at: Vector3, out: Vector3, material: Material) -> void:
	if scene == null or not can_spawn():
		return
	if chip_mesh == null:
		chip_mesh = BoxMesh.new()

	var debris: Node3D = load("res://features/mission/effects/debris.gd").new()
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


static func get_burnt_material() -> StandardMaterial3D:
	if burnt_material == null:
		burnt_material = StandardMaterial3D.new()
		burnt_material.albedo_color = Color(0.25, 0.22, 0.2)
		burnt_material.roughness = 1.0
	return burnt_material


# Turn any node into flying debris: it's moved into a new debris piece
# (keeping where it is), then flies with `velocity` and tumbles.
static func throw_node(node: Node3D, velocity: Vector3, spin: float, life: float, charred: bool, dust_on_land: bool = false) -> Node3D:
	var scene := MissionContext.spawn_parent(node)
	if scene == null:
		return null

	var debris: Node3D = load("res://features/mission/effects/debris.gd").new()
	scene.add_child(debris)
	debris.global_transform = node.global_transform
	node.reparent(debris, true)

	# Optionally char it, and drop anything that isn't a mesh (health bars).
	var low := 0.0
	for child in node.find_children("*", "", true, false) + [node]:
		if child is MeshInstance3D:
			if charred:
				child.material_override = get_burnt_material()
			var box: AABB = debris.global_transform.affine_inverse() * child.global_transform * child.get_aabb()
			low = minf(low, box.position.y)
		elif child is Sprite3D:
			child.queue_free()
	debris.radius = maxf(-low, 0.12)

	debris.velocity = velocity
	debris.spin_axis = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()
	debris.spin_speed = spin
	debris.lifetime = life
	debris.dust_on_land = dust_on_land
	return debris


# Throw a real part of a vehicle (charred) away from `origin`. The part is
# moved out of the vehicle, so the wreck won't have it.
static func launch_part(part: Node3D, origin: Vector3, big: bool) -> void:
	var away := part.global_position - origin
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var velocity := away * randf_range(3.0, 7.0) + Vector3.UP * (randf_range(13.0, 18.0) if big else randf_range(8.0, 13.0))
	var spin := randf_range(4.0, 9.0) if big else randf_range(8.0, 14.0)
	var debris := throw_node(part, velocity, spin, 6.0, true, true)
	if debris != null and big:
		debris.add_smoke_trail()


static var dust_mesh: SphereMesh

# A puff of sand kicked up where something hits the ground.
static func spawn_dust(scene: Node, at: Vector3, size: float = 1.0) -> void:
	if scene == null:
		return
	if dust_mesh == null:
		dust_mesh = SphereMesh.new()
		dust_mesh.radius = 0.35
		dust_mesh.height = 0.7
		dust_mesh.radial_segments = 6
		dust_mesh.rings = 3
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		dust_mesh.material = material

	var dust := CPUParticles3D.new()
	dust.one_shot = true
	dust.explosiveness = 0.95
	dust.amount = 10
	dust.lifetime = 0.7
	dust.local_coords = false
	dust.mesh = dust_mesh
	dust.direction = Vector3.UP
	dust.spread = 80.0
	dust.initial_velocity_min = 1.5 * size
	dust.initial_velocity_max = 3.5 * size
	dust.gravity = Vector3(0, -2.0, 0)
	dust.damping_min = 3.0
	dust.damping_max = 5.0
	dust.scale_amount_min = 0.7 * size
	dust.scale_amount_max = 1.3 * size
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.78, 0.66, 0.5, 0.8))
	ramp.set_color(1, Color(0.78, 0.66, 0.5, 0.0))
	dust.color_ramp = ramp
	scene.add_child(dust)
	dust.global_position = at
	dust.emitting = true
	scene.get_tree().create_timer(1.2).timeout.connect(dust.queue_free)


func _enter_tree() -> void:
	count += 1


func _exit_tree() -> void:
	count -= 1


# Blood dripping from a torn limb while it flies; stops when it lands.
func add_blood_trail(mesh: Mesh) -> void:
	var trail := CPUParticles3D.new()
	trail.amount = 24
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.mesh = mesh
	trail.direction = Vector3.UP
	trail.spread = 60.0
	trail.initial_velocity_min = 1.0
	trail.initial_velocity_max = 3.0
	trail.gravity = Vector3(0, -20, 0)
	trail.scale_amount_min = 0.8
	trail.scale_amount_max = 1.6
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail)
	touched_ground.connect(func(_at: Vector3) -> void: trail.emitting = false)


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
			if not landed:
				landed = true
				touched_ground.emit(Vector3(global_position.x, ground_y, global_position.z))
				if dust_on_land:
					spawn_dust(MissionContext.spawn_parent(self), global_position, clampf(radius * 2.0, 0.5, 1.5))
					Sfx.play_3d(land_sound, global_position)
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
