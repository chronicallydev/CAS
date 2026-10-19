extends EnemyBase

# Ripple launcher: a truck with a six-tube box launcher. It drives in, stops
# at range, locks on, then ripple-fires all six missiles in a fan. Each one
# flies out on its own heading for a moment, then curves in slowly (weak
# homing), so the salvo arrives as a curtain from several angles. Out-turning
# one missile is easy; out-turning a curtain isn't. Answer: fly through a
# gap between them, or flare the whole salvo. Built from primitives in code.

const P := preload("res://shared/props/prop_builder.gd")
const HEALTH_BAR := preload("res://shared/health_bar/health_bar_3d.tscn")
const Missile := preload("res://features/mission/enemies/projectiles/aa_missile.gd")

@export var speed: float = 6.0
@export var ride_height: float = -0.4
# Stops somewhere in this distance range from its objective.
@export var firing_range_min: float = 32.0
@export var firing_range_max: float = 44.0

@export_group("Missiles")
# Max horizontal distance to the helicopter for a lock.
@export var engage_range: float = 70.0
@export var lock_time: float = 1.2
@export var reload_time: float = 10.0
@export var salvo_size: int = 6
@export var salvo_interval: float = 0.12
# Total width of the fan, in degrees.
@export var fan_degrees: float = 70.0
@export var missile_damage: float = 12.0
@export var missile_speed: float = 19.0
# Weak homing: the missiles drift in rather than snapping onto you.
@export var missile_turn_rate: float = 0.35
@export var missile_lifetime: float = 7.0
@export var missile_explosion: PackedScene = preload("res://features/mission/vfx/explosion_scene.tscn")

var firing_range: float = 0.0
var in_position: bool = false
var launcher: Node3D
var box: Node3D
var muzzles: Array = []
var reload_timer: float = 0.0
var salvo_left: int = 0
var salvo_timer: float = 0.0
# Heading of the salvo's centre, fixed when it starts so the fan holds.
var salvo_direction: Vector3 = Vector3.FORWARD


func _init() -> void:
	max_health = 6.0
	light_armor = 0.5
	score_value = 60
	display_name = "RIPPLE"
	leaves_wreck = true
	detach_parts = PackedStringArray(["Launcher"])
	contact_damage = 12.0


func _ready() -> void:
	build_model()
	super()
	firing_range = randf_range(firing_range_min, firing_range_max)
	reload_timer = randf_range(1.5, 3.5)


func _physics_process(delta: float) -> void:
	global_position.y = ride_height

	# Drive in, then hold position (follow the helicopter if it gets away).
	if in_position and is_assault() and objective_distance() > engage_range * 0.8:
		in_position = false
	if not in_position:
		var direction := flat_direction_to_center()
		global_position += direction * speed * delta
		face_direction(direction)
		if objective() == null or objective_distance() <= firing_range:
			in_position = true

	var heli := helicopter()
	if heli == null:
		lock_timer = 0.0
		return

	# Swing the launcher toward the helicopter.
	var to_heli := heli.global_position - launcher.global_position
	var yaw := atan2(-to_heli.x, -to_heli.z) - global_rotation.y
	launcher.rotation.y = lerp_angle(launcher.rotation.y, yaw, clampf(2.0 * delta, 0.0, 1.0))

	if salvo_left > 0:
		salvo_timer -= delta
		while salvo_timer <= 0.0 and salvo_left > 0:
			fire_at(heli, salvo_size - salvo_left)
			salvo_left -= 1
			salvo_timer += salvo_interval
		return

	reload_timer -= delta
	if not in_position or reload_timer > 0.0 or distance_to_heli(heli) > engage_range:
		lock_timer = 0.0
		return

	if update_lock(heli, delta, lock_time, true):
		salvo_left = salvo_size
		salvo_timer = 0.0
		reload_timer = reload_time
		var flat := Vector3(to_heli.x, 0.0, to_heli.z)
		salvo_direction = flat.normalized() if flat.length() > 0.1 else -global_transform.basis.z


# Missile `index` of the salvo, launched along its slot in the fan and
# angled up, before its weak homing takes over.
func fire_at(heli: Node3D, index: int) -> void:
	var muzzle: Node3D = muzzles[index % muzzles.size()]
	var t := 0.5 if salvo_size <= 1 else float(index) / (salvo_size - 1)
	var heading := salvo_direction.rotated(Vector3.UP, deg_to_rad(lerpf(-fan_degrees, fan_degrees, t) * 0.5))
	var direction := (heading + Vector3.UP * 0.55).normalized()

	var missile := Missile.new()
	missile.target = heli
	missile.speed = missile_speed
	missile.turn_rate = missile_turn_rate
	missile.lifetime = missile_lifetime
	missile.damage = missile_damage
	missile.source_name = "RIPPLE"
	missile.explosion_scene = missile_explosion
	missile.ground_y = ride_height
	missile.size = 0.8
	# A long unguided boost lets the fan open up before they turn in.
	missile.boost_time = 0.9
	MissionContext.spawn_parent(self).add_child(missile)
	missile.launch(muzzle.global_position, direction)
	Sfx.play_3d("rocket_fire", muzzle.global_position, 2.0, 0.9)


func build_model() -> void:
	var paint := P.material(Color(0.44, 0.42, 0.32), 0.8)
	var dark := P.material(Color(0.15, 0.15, 0.16), 0.6, 0.4)
	var glass := P.material(Color(0.15, 0.22, 0.3), 0.15)
	var tyre := P.material(Color(0.08, 0.08, 0.08), 1.0)
	var cap := P.material(Color(0.8, 0.2, 0.12), 0.6)

	# Truck: cab up front (-Z), flat bed behind, three axles.
	P.box(self, Vector3(2.3, 1.7, 1.9), Vector3(0, 1.35, -2.3), paint)
	P.box(self, Vector3(2.0, 0.6, 0.05), Vector3(0, 1.75, -3.26), glass)
	P.box(self, Vector3(2.5, 0.5, 4.4), Vector3(0, 0.75, 0.6), paint)
	for z in [-2.3, 0.0, 1.9]:
		for x in [-1.2, 1.2]:
			P.cylinder(self, 0.5, 0.45, Vector3(x, 0.5, z), tyre, Vector3(0, 0, 90))

	# Turntable with a raised box of six tubes (two rows of three).
	launcher = Node3D.new()
	launcher.name = "Launcher"
	launcher.position = Vector3(0, 1.0, 1.0)
	add_child(launcher)
	P.box(launcher, Vector3(1.6, 0.5, 1.6), Vector3(0, 0.25, 0), dark)

	box = Node3D.new()
	box.position = Vector3(0, 1.0, 0)
	box.rotation_degrees.x = 30.0
	launcher.add_child(box)
	P.box(box, Vector3(2.1, 1.3, 3.0), Vector3.ZERO, paint)
	for row in 2:
		for column in 3:
			var at := Vector3(-0.65 + column * 0.65, -0.3 + row * 0.6, -1.52)
			P.cylinder(box, 0.24, 0.06, at, cap, Vector3(90, 0, 0), 10)
			var muzzle := Node3D.new()
			muzzle.position = at + Vector3(0, 0, -0.2)
			box.add_child(muzzle)
			muzzles.append(muzzle)

	var bar := HEALTH_BAR.instantiate()
	bar.name = "HealthBar3D"
	bar.position = Vector3(0, 4.6, 0)
	add_child(bar)
