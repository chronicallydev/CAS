extends Node3D

# A dead soldier's body. Either collapses where it stood (light weapons)
# or is thrown by a blast, tumbles, lands flat, slides, lies there for a
# while and sinks away. Hand-written motion, no physics bodies.

const Debris := preload("res://features/mission/effects/debris.gd")
const GRAVITY := 28.0
# Height of a body lying on the ground (half its thickness, scaled).
const LYING_HEIGHT := 0.25

# Where the body came to rest and the flat direction it was moving.
signal landed(at: Vector3, heading: Vector3)

var ground_y: float = -0.4
var lifetime: float = 7.0
var age: float = 0.0

var thrown: bool = false
var velocity: Vector3 = Vector3.ZERO
var spin_axis: Vector3 = Vector3.RIGHT
var spin_speed: float = 0.0

# Collapsing: tips over around the feet toward fall_dir.
var fall_dir: Vector3 = Vector3.BACK
var fall_time: float = 0.45
var start_basis: Basis

var on_ground: bool = false
var slide: Vector3 = Vector3.ZERO


# Turn a soldier's model into a corpse. `away` is the flat direction to
# fall or fly in; `force` 0 collapses in place, more throws it further.
static func spawn(model: Node3D, away: Vector3, force: float, ground: float) -> Node3D:
	var scene := MissionContext.spawn_parent(model)
	if scene == null:
		return null

	var corpse: Node3D = load("res://features/mission/effects/corpse.gd").new()
	corpse.ground_y = ground
	scene.add_child(corpse)
	# The model's origin is at the feet, which is the pivot for falling over.
	corpse.global_transform = model.global_transform.orthonormalized()
	model.reparent(corpse, true)
	corpse.fall_dir = away
	corpse.start_basis = corpse.global_transform.basis

	if force > 0.3:
		corpse.thrown = true
		corpse.velocity = away * clampf(3.0 + force * 1.5, 3.0, 14.0) \
			+ Vector3.UP * clampf(4.0 + force * 2.0, 5.0, 20.0)
		corpse.spin_axis = Vector3.UP.cross(away).normalized()
		if corpse.spin_axis.length() < 0.1:
			corpse.spin_axis = Vector3.RIGHT
		corpse.spin_speed = clampf(4.0 + force, 4.0, 14.0)
	return corpse


func _physics_process(delta: float) -> void:
	age += delta

	if not on_ground:
		if thrown:
			fly(delta)
		else:
			collapse()
	elif slide.length() > 0.05:
		global_position += slide * delta
		slide = slide.move_toward(Vector3.ZERO, 12.0 * delta)

	# Sink into the ground over the last second, then disappear.
	if age > lifetime - 1.0:
		global_position.y -= delta * 0.8
	if age >= lifetime:
		queue_free()


func collapse() -> void:
	# Tip over around the feet, accelerating like a falling plank.
	var t := clampf(age / fall_time, 0.0, 1.0)
	var axis := Vector3.UP.cross(fall_dir).normalized()
	if axis.length() < 0.1:
		axis = Vector3.RIGHT
	global_transform.basis = Basis(axis, t * t * PI * 0.5) * start_basis
	if t >= 1.0:
		land()


func fly(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	global_position += velocity * delta
	global_transform.basis = Basis(spin_axis, spin_speed * delta) * global_transform.basis

	if global_position.y <= ground_y + LYING_HEIGHT and velocity.y < 0.0:
		# Land flat, facing the way it was flying, and skid a little.
		var heading := Vector3(velocity.x, 0, velocity.z)
		var yaw := atan2(-heading.x, -heading.z) if heading.length() > 0.1 else randf() * TAU
		var tilt := -PI * 0.5 if randf() < 0.5 else PI * 0.5
		global_transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
		global_position.y = ground_y + LYING_HEIGHT
		slide = heading * 0.45
		land()


func land() -> void:
	var heading := Vector3(velocity.x, 0, velocity.z) if thrown else fall_dir
	landed.emit(Vector3(global_position.x, ground_y, global_position.z), heading)
	on_ground = true
	var scene := MissionContext.spawn_parent(self)
	Debris.spawn_dust(scene, global_position, 1.2 if thrown else 0.8)
	Sfx.play_3d("body_thud", global_position)


# Blacken every mesh (burnt by a big blast).
func char_meshes() -> void:
	for mesh in find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = Debris.get_burnt_material()
