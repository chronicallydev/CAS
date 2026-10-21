extends EnemyBase

# SAM truck: drives in to a position, stops, then tracks the player's
# helicopter. While the helicopter is in range it locks on (warning the
# player) and fires a homing rocket, then reloads.

const Missile := preload("res://features/mission/enemies/projectiles/aa_missile.gd")

@export var speed: float = 6.0
# The truck stops somewhere in this distance range from the base.
@export var firing_range_min: float = 30.0
@export var firing_range_max: float = 42.0
@export var ride_height: float = -0.4
@export var turn_speed: float = 3.0

@export_group("Missile")
# Max horizontal distance to the helicopter for a lock.
@export var engage_range: float = 80.0
@export var lock_time: float = 1.5
@export var reload_time: float = 6.0
@export var missile_damage: float = 25.0
@export var missile_speed: float = 26.0
@export var missile_turn_rate: float = 0.9
@export var missile_lifetime: float = 6.0
@export var missile_explosion: PackedScene

@onready var launcher: Node3D = $Launcher
@onready var muzzle: Node3D = $Launcher/Rails/Muzzle

var firing_range: float = 0.0
var in_position: bool = false
var reload_timer: float = 0.0


func _ready() -> void:
	super()
	firing_range = randf_range(firing_range_min, firing_range_max)
	# Stagger the first shot.
	reload_timer = randf_range(1.0, 3.0)


func _physics_process(delta: float) -> void:
	global_position.y = ride_height
	# Hunting the helicopter, follow it once it's well out of reach.
	if in_position and objective_distance() > engage_range * 0.8:
		in_position = false

	if not in_position:
		var direction := flat_direction_to_center()
		global_position += direction * speed * delta
		face_direction(direction)

		if objective_distance() <= firing_range:
			in_position = true
		return

	var heli := helicopter()

	if heli == null:
		lock_timer = 0.0
		return

	# Swing the launcher toward the helicopter.
	var to_heli := heli.global_position - launcher.global_position
	var desired_yaw := atan2(-to_heli.x, -to_heli.z) - global_rotation.y
	launcher.rotation.y = lerp_angle(launcher.rotation.y, desired_yaw, clampf(turn_speed * delta, 0.0, 1.0))

	reload_timer -= delta

	if reload_timer > 0.0:
		lock_timer = 0.0
		return

	if Vector2(to_heli.x, to_heli.z).length() > engage_range:
		lock_timer = 0.0
		return

	# Lock on (flares break it), then fire and reload.
	if update_lock(heli, delta, lock_time):
		reload_timer = reload_time
		fire_at(heli)


func fire_at(heli: Node3D) -> void:
	var missile := Missile.new()
	missile.target = heli
	missile.speed = missile_speed
	missile.turn_rate = missile_turn_rate
	missile.lifetime = missile_lifetime
	missile.damage = missile_damage
	missile.source_name = "SAM TRUCK"
	missile.explosion_scene = missile_explosion
	missile.ground_y = ride_height
	MissionContext.spawn_parent(self).add_child(missile)

	# Leaves the tube along the rails, angled up.
	missile.launch(muzzle.global_position, -muzzle.global_transform.basis.z)
	Sfx.play_3d("missile_launch", muzzle.global_position)
