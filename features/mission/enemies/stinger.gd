extends "res://features/mission/enemies/infantry.gd"

# Stinger gunner: an infantry soldier carrying a shoulder-fired SAM instead
# of a rifle. He marches with the other infantry, so he's easy to miss in a
# crowd. When the helicopter comes in range he stops, locks on quickly and
# fires a small, fast, agile missile. Low damage, but several gunners
# firing together hurt. Answer: sweep crowds early, or drop flares.

const Missile := preload("res://features/mission/enemies/projectiles/aa_missile.gd")

@export_group("Stinger")
# Max horizontal distance to the helicopter to start a lock.
@export var engage_range: float = 55.0
@export var lock_time: float = 0.7
@export var reload_time: float = 8.0
@export var missile_damage: float = 9.0
@export var missile_speed: float = 34.0
@export var missile_turn_rate: float = 1.7
@export var missile_lifetime: float = 4.0
@export var missile_explosion: PackedScene

var reload_timer: float = 0.0
var launcher_muzzle: Node3D


func _init() -> void:
	max_health = 1.0
	score_value = 30
	display_name = "STINGER"
	contact_damage = 6.0


func _ready() -> void:
	super()
	# Stagger the first shot so a squad doesn't fire as one.
	reload_timer = randf_range(1.5, 4.0)


func _physics_process(delta: float) -> void:
	reload_timer -= delta
	var heli := helicopter()
	var can_aim := heli != null and reload_timer <= 0.0 and prone_time <= 0.0 and panic_time <= 0.0 \
			and distance_to_heli(heli) <= engage_range

	if not can_aim:
		# Otherwise behave like any soldier: march, panic, dive.
		lock_timer = 0.0
		super(delta)
		return

	global_position.y = ground_y
	var to_heli := heli.global_position - global_position
	face_direction(Vector3(to_heli.x, 0.0, to_heli.z).normalized())
	if update_lock(heli, delta, lock_time):
		reload_timer = reload_time
		fire_at(heli)


# No rifle: in an assault the gunner just holds position at fire range.
func update_rifle(_delta: float) -> void:
	pass


func fire_at(heli: Node3D) -> void:
	var from := launcher_muzzle.global_position
	var missile := Missile.new()
	missile.target = heli
	missile.speed = missile_speed
	missile.turn_rate = missile_turn_rate
	missile.lifetime = missile_lifetime
	missile.damage = missile_damage
	missile.source_name = "STINGER"
	missile.explosion_scene = missile_explosion
	missile.ground_y = ground_y
	missile.size = 0.55
	missile.boost_time = 0.2
	MissionContext.spawn_parent(self).add_child(missile)
	missile.launch(from, (heli.global_position - from).normalized())
	Sfx.play_3d("missile_launch", from, -3.0, 1.35)


# The soldier, with the rifle swapped for a launcher tube on the shoulder.
# It stays the `rifle` node, so it drops like a rifle when he dies.
func build_model() -> void:
	super()
	var olive := P.material(Color(0.3, 0.34, 0.22), 0.8)
	var dark := P.material(Color(0.12, 0.12, 0.12), 0.6, 0.4)
	for child in rifle.get_children():
		child.queue_free()
	rifle.position = Vector3(0.2, 1.62, 0.05)
	rifle.rotation_degrees = Vector3(12, 0, 0)
	P.cylinder(rifle, 0.08, 1.3, Vector3(0, 0, -0.1), olive, Vector3(90, 0, 0), 10)
	P.box(rifle, Vector3(0.06, 0.16, 0.22), Vector3(-0.1, 0.05, -0.2), dark)
	P.box(rifle, Vector3(0.05, 0.18, 0.08), Vector3(0, -0.14, 0.05), dark)
	launcher_muzzle = Marker3D.new()
	launcher_muzzle.position = Vector3(0, 0, -0.85)
	rifle.add_child(launcher_muzzle)
