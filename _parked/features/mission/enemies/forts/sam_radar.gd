extends EnemyBase

# Search radar of a SAM site: a cabin with a big rotating dish, dug in
# around an enemy rig during an assault. It doesn't shoot. It feeds the
# site's launchers (sam_launcher.gd), which can only lock on while the
# radar is alive, so killing it first silences the whole site. Part of the
# assault objective. Built from primitives in code.

const P := preload("res://shared/props/prop_builder.gd")
const HEALTH_BAR := preload("res://shared/health_bar/health_bar_3d.tscn")

@export var ground_y: float = -0.4

var dish: Node3D
var lamp: MeshInstance3D
var time: float = 0.0


func _init() -> void:
	max_health = 40.0
	light_armor = 0.7
	score_value = 250
	display_name = "RADAR"
	leaves_wreck = true
	detach_parts = PackedStringArray(["Dish"])
	contact_damage = 0.0


func _ready() -> void:
	build_model()
	super()
	add_to_group("forts")


# Launchers ask this before every lock.
func is_active() -> bool:
	return health > 0.0 and not is_queued_for_deletion()


func _physics_process(delta: float) -> void:
	global_position.y = ground_y
	time += delta
	dish.rotate_y(delta * 1.6)
	# Red warning lamp, blinking while the site is hunting.
	lamp.visible = fmod(time, 0.8) < 0.4


func build_model() -> void:
	var concrete := P.material(Color(0.62, 0.6, 0.55), 1.0)
	var paint := P.material(Color(0.4, 0.42, 0.3), 0.8)
	var dark := P.material(Color(0.15, 0.15, 0.16), 0.5, 0.5)
	var mesh := P.material(Color(0.75, 0.76, 0.72), 0.5, 0.4)

	# Pad and equipment cabin.
	P.box(self, Vector3(6.5, 0.3, 6.5), Vector3(0, 0.15, 0), concrete)
	P.box(self, Vector3(3.2, 2.0, 4.0), Vector3(0, 1.3, 0.6), paint)
	P.box(self, Vector3(0.9, 0.9, 0.9), Vector3(1.1, 2.75, 1.8), dark)

	# Mast with the big rotating dish.
	P.cylinder(self, 0.18, 2.4, Vector3(0, 3.5, -0.6), dark)
	dish = Node3D.new()
	dish.name = "Dish"
	dish.position = Vector3(0, 4.8, -0.6)
	add_child(dish)
	P.box(dish, Vector3(4.2, 1.6, 0.15), Vector3(0, 0.2, 0), mesh, Vector3(-12, 0, 0))
	P.box(dish, Vector3(0.2, 0.2, 1.4), Vector3(0, 0.1, -0.7), dark)

	lamp = P.sphere(self, 0.2, Vector3(-1.1, 2.5, 2.2), P.glow_material(Color(1.0, 0.15, 0.1), 4.0))

	var bar := HEALTH_BAR.instantiate()
	bar.name = "HealthBar3D"
	bar.position = Vector3(0, 7.0, 0)
	add_child(bar)
