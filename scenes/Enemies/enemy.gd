extends "res://scenes/Enemies/enemy_base.gd"

# Infantry: a soldier with a rifle who walks straight at the base.
# The model is built from primitives and animated in code: legs stride,
# arms sway with the rifle and the body bobs with each step.

const P := preload("res://scenes/environment/prop_builder.gd")

@export var speed: float = 5.0
# Height of the ground surface (the soldier's feet).
@export var ground_y: float = -0.4
# Overall size; a bit larger than life so soldiers read from the air.
@export var model_scale: float = 1.8

var model: Node3D
var body: Node3D
var leg_left: Node3D
var leg_right: Node3D
var arm_left: Node3D
var arm_right: Node3D

var walk_phase: float = 0.0


func _ready() -> void:
	super()
	build_model()
	# Out of step with each other, so a group doesn't march in lockstep.
	walk_phase = randf() * TAU


func _physics_process(delta: float) -> void:
	var direction := flat_direction_to_center()
	global_position += direction * speed * delta
	global_position.y = ground_y
	face_direction(direction)


func _process(delta: float) -> void:
	# One full stride (two steps) covers about 2.8 m at model_scale 1.
	walk_phase += delta * speed * TAU / (2.8 * model_scale)
	var swing := sin(walk_phase)

	leg_left.rotation.x = swing * 0.6
	leg_right.rotation.x = -swing * 0.6

	# Arms hold the rifle, so they only sway a little.
	arm_left.rotation.x = 0.9 + swing * 0.12
	arm_right.rotation.x = 0.7 - swing * 0.12

	# Bob up on each step and roll slightly side to side.
	body.position.y = absf(swing) * 0.06
	body.rotation.z = swing * 0.04


func build_model() -> void:
	var uniform := P.material(Color(0.36, 0.39, 0.26), 0.9)
	var gear := P.material(Color(0.3, 0.29, 0.22), 0.9)
	var helmet := P.material(Color(0.28, 0.31, 0.2), 0.7)
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
	P.sphere(body, 0.17, Vector3(0, 1.76, 0.01), helmet, Vector3(1.0, 0.65, 1.05))

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
	var rifle := Node3D.new()
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
