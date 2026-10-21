extends EnemyBase

# Infantry: a soldier with a rifle who walks straight at the base, stopping
# to fire short bursts at the helicopter whenever it comes close. In an
# assault there is no base to reach, so soldiers close in on the helicopter
# and stop to fire at it.
# The model is built from primitives and animated in code: legs stride,
# arms sway with the rifle and the body bobs with each step. Blasts nearby
# make soldiers run from them and dive flat; death is in soldier_death.gd.

const P := preload("res://shared/props/prop_builder.gd")
const SoldierDeath := preload("res://features/mission/effects/soldier_death.gd")
const Tracer := preload("res://features/mission/enemies/projectiles/tank_shell.gd")

@export var speed: float = 5.0
# Height of the ground surface (the soldier's feet).
@export var ground_y: float = -0.4
# Overall size; a bit larger than life so soldiers read from the air.
@export var model_scale: float = 1.8

@export_group("Rifle")
# Damage per round that hits the helicopter (assaults only).
@export var shot_damage: float = 0.4
@export var fire_range_min: float = 12.0
@export var fire_range_max: float = 20.0
@export var burst_cooldown: float = 3.0

var model: Node3D
var body: Node3D
var leg_left: Node3D
var leg_right: Node3D
var arm_left: Node3D
var arm_right: Node3D
var helmet: MeshInstance3D
var rifle: Node3D

var walk_phase: float = 0.0

# Reaction to a nearby blast: run away from it, then dive flat for a moment.
var panic_time: float = 0.0
var prone_time: float = 0.0
var panic_dir: Vector3 = Vector3.ZERO

var fire_range: float = 0.0
var fire_timer: float = 0.0
var burst_left: int = 0


func _ready() -> void:
	super()
	build_model()
	# Out of step with each other, so a group doesn't march in lockstep.
	walk_phase = randf() * TAU
	fire_range = randf_range(fire_range_min, fire_range_max)
	fire_timer = randf_range(1.0, burst_cooldown)


func _physics_process(delta: float) -> void:
	global_position.y = ground_y

	if prone_time > 0.0:
		prone_time -= delta
		return

	if panic_time > 0.0:
		panic_time -= delta
		global_position += panic_dir * speed * 1.8 * delta
		face_direction(panic_dir)
		if panic_time <= 0.0:
			prone_time = randf_range(0.6, 0.9)
		return

	var direction := flat_direction_to_center()
	if is_assault() and objective() != null and objective_distance() <= fire_range:
		face_direction(direction)
		update_rifle(delta)
		return
	# Defending: stop and shoot at the helicopter when it comes close.
	var heli := defence_target(fire_range + 6.0)
	if heli != null:
		var to_heli := heli.global_position - global_position
		face_direction(Vector3(to_heli.x, 0.0, to_heli.z).normalized())
		update_rifle(delta)
		return
	global_position += direction * speed * delta
	face_direction(direction)


# Short bursts at the helicopter overhead.
func update_rifle(delta: float) -> void:
	fire_timer -= delta
	if fire_timer > 0.0:
		return
	if burst_left <= 0:
		burst_left = 3
	burst_left -= 1
	fire_timer = 0.14 if burst_left > 0 else burst_cooldown * randf_range(0.8, 1.3)

	var heli: Node3D = objective() if is_assault() else defence_target(fire_range + 6.0)
	if heli == null:
		return
	var from := rifle.global_position
	var target := heli.global_position + Vector3(randf_range(-3.0, 3.0), randf_range(-1.0, 1.0), randf_range(-3.0, 3.0))
	var tracer := Tracer.new()
	tracer.radius = 0.12
	tracer.color = Color(1.0, 0.9, 0.5)
	MissionContext.spawn_parent(self).add_child(tracer)
	tracer.setup(from, target, 0.3, 0.0, rifle_hit.bind(heli))
	Sfx.play_3d("car_gun", from)


func rifle_hit(at: Vector3, target: Node3D = null) -> void:
	hit_objective(at, shot_damage, 2.5, target)


func _process(delta: float) -> void:
	# Dive forward while prone, get back up afterwards.
	var lean := -1.35 if prone_time > 0.0 else 0.0
	model.rotation.x = move_toward(model.rotation.x, lean, delta * 7.0)
	if prone_time > 0.0:
		return

	# One full stride (two steps) covers about 2.8 m at model_scale 1.
	var pace := 1.8 if panic_time > 0.0 else 1.0
	walk_phase += delta * speed * pace * TAU / (2.8 * model_scale)
	var swing := sin(walk_phase)

	leg_left.rotation.x = swing * 0.6
	leg_right.rotation.x = -swing * 0.6

	# Arms hold the rifle, so they only sway a little.
	arm_left.rotation.x = 0.9 + swing * 0.12
	arm_right.rotation.x = 0.7 - swing * 0.12

	# Bob up on each step and roll slightly side to side.
	body.position.y = absf(swing) * 0.06
	body.rotation.z = swing * 0.04


func die() -> void:
	SoldierDeath.kill(self, last_hit_from, last_hit_force, last_hit_light)
	queue_free()


# A blast went off nearby: run from it, then hit the dirt.
func react_to_blast(from: Vector3) -> void:
	if panic_time > 0.0 or prone_time > 0.0 or is_queued_for_deletion():
		return
	panic_dir = global_position - from
	panic_dir.y = 0.0
	panic_dir = panic_dir.normalized() if panic_dir.length() > 0.05 else -flat_direction_to_center()
	panic_time = randf_range(0.4, 0.8)


func build_model() -> void:
	var uniform := P.material(Color(0.36, 0.39, 0.26), 0.9)
	var gear := P.material(Color(0.3, 0.29, 0.22), 0.9)
	var helmet_paint := P.material(Color(0.28, 0.31, 0.2), 0.7)
	var skin := P.material(Color(0.76, 0.56, 0.42), 0.8)
	var boots := P.material(Color(0.26, 0.21, 0.16), 0.9)
	var metal := P.material(Color(0.18, 0.18, 0.19), 0.5, 0.6)

	# Sizes below are in metres for a 1.8 m soldier, then scaled up.
	model = Node3D.new()
	model.scale = Vector3.ONE * model_scale
	add_child(model)

	body = Node3D.new()
	model.add_child(body)

	# Torso, webbing and backpack.
	P.box(body, Vector3(0.48, 0.62, 0.28), Vector3(0, 1.24, 0), uniform)
	P.box(body, Vector3(0.5, 0.12, 0.3), Vector3(0, 1.0, 0), gear)
	P.box(body, Vector3(0.4, 0.46, 0.2), Vector3(0, 1.3, 0.23), gear)

	# Head and helmet.
	P.sphere(body, 0.13, Vector3(0, 1.7, 0), skin)
	helmet = P.sphere(body, 0.17, Vector3(0, 1.76, 0.01), helmet_paint, Vector3(1.0, 0.65, 1.05))

	# Legs pivot at the hips; each has a boot at the end.
	leg_left = make_limb(Vector3(-0.12, 0.92, 0), Vector3(0.17, 0.82, 0.19), uniform)
	leg_right = make_limb(Vector3(0.12, 0.92, 0), Vector3(0.17, 0.82, 0.19), uniform)
	for leg in [leg_left, leg_right]:
		P.box(leg, Vector3(0.18, 0.12, 0.3), Vector3(0, -0.86, -0.05), boots)

	# Arms pivot at the shoulders, raised forward to hold the rifle.
	arm_left = make_limb(Vector3(-0.31, 1.5, 0), Vector3(0.12, 0.58, 0.13), uniform)
	arm_right = make_limb(Vector3(0.31, 1.5, 0), Vector3(0.12, 0.58, 0.13), uniform)
	for arm in [arm_left, arm_right]:
		P.sphere(arm, 0.07, Vector3(0, -0.6, 0), skin)

	# Rifle carried across the chest, muzzle forward.
	rifle = Node3D.new()
	rifle.position = Vector3(0.05, 1.18, -0.36)
	rifle.rotation_degrees = Vector3(8, 18, 0)
	body.add_child(rifle)
	P.box(rifle, Vector3(0.06, 0.1, 0.75), Vector3.ZERO, metal)
	P.box(rifle, Vector3(0.05, 0.16, 0.08), Vector3(0, -0.1, 0.05), metal)
	P.box(rifle, Vector3(0.07, 0.12, 0.22), Vector3(0, -0.02, 0.42), gear)


# A limb that swings from a pivot at its top end.
func make_limb(pivot: Vector3, size: Vector3, mat: Material) -> Node3D:
	var limb := Node3D.new()
	limb.position = pivot
	body.add_child(limb)
	P.box(limb, size, Vector3(0, -size.y * 0.5, 0), mat)
	return limb
