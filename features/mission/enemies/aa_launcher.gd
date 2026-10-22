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
@export var missile_damage: float = 34.0
# See aa_missile.gd: it boosts, settles to a sustain speed above the
# helicopter's, and turns no harder than turn_rate (radians per second).
@export var missile_boost_speed: float = 62.0
@export var missile_sustain_speed: float = 44.0
@export var missile_turn_rate: float = 1.8
@export var missile_lifetime: float = 8.0
# Popped out of the tube this slowly; the motor lights after eject_time.
@export var missile_eject_speed: float = 9.0
@export var missile_eject_time: float = 1.0
@export var missile_explosion: PackedScene
# Flares don't break this launcher's lock (the heavy rocket truck).
@export var lock_ignores_flares: bool = false

@onready var launcher: Node3D = $Launcher
@onready var rails: Node3D = $Launcher/Rails
@onready var muzzle: Node3D = $Launcher/Rails/Muzzle

# Rails point this far above the line to the helicopter, within the
# elevation limits: the rocket pops up out of the tube and tips over
# toward the helicopter before its motor lights.
@export var loft_degrees: float = 25.0
@export var min_elevation_degrees: float = 30.0
@export var max_elevation_degrees: float = 70.0

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

	var to_heli := aim_at(heli, delta)

	reload_timer -= delta

	if reload_timer > 0.0 or not can_fire() or not on_screen():
		lock_timer = 0.0
		return

	if Vector2(to_heli.x, to_heli.z).length() > engage_range:
		lock_timer = 0.0
		return

	# Lock on (flares break it unless lock_ignores_flares), then fire and
	# reload.
	if update_lock(heli, delta, lock_time, lock_ignores_flares):
		reload_timer = reload_time
		fire_at(heli)


# Swings and elevates the launcher toward where the helicopter will be
# when the rocket gets there. Returns the offset to the helicopter now.
func aim_at(heli: Node3D, delta: float) -> Vector3:
	var to_heli := heli.global_position - launcher.global_position
	var lead: Vector3 = to_heli + heli.velocity * (to_heli.length() / missile_boost_speed)
	var weight := clampf(turn_speed * delta, 0.0, 1.0)
	var desired_yaw := atan2(-lead.x, -lead.z) - global_rotation.y
	launcher.rotation.y = lerp_angle(launcher.rotation.y, desired_yaw, weight)

	var elevation := atan2(lead.y, Vector2(lead.x, lead.z).length()) + deg_to_rad(loft_degrees)
	elevation = clampf(elevation, deg_to_rad(min_elevation_degrees), deg_to_rad(max_elevation_degrees))
	rails.rotation.x = lerp_angle(rails.rotation.x, elevation, weight)
	return to_heli


# False while the launcher shouldn't start a lock (on top of reloading).
func can_fire() -> bool:
	return true


# The rocket to fire, set up but not yet in the tree.
func make_missile() -> Node3D:
	var missile := Missile.new()
	missile.boost_speed = missile_boost_speed
	missile.sustain_speed = missile_sustain_speed
	missile.turn_rate = missile_turn_rate
	missile.lifetime = missile_lifetime
	missile.eject_speed = missile_eject_speed
	missile.eject_time = missile_eject_time
	missile.damage = missile_damage
	missile.source_name = "SAM TRUCK"
	return missile


func fire_at(heli: Node3D) -> void:
	var missile := make_missile()
	missile.target = heli
	missile.explosion_scene = missile_explosion
	missile.ground_y = ride_height
	MissionContext.spawn_parent(self).add_child(missile)

	# Leaves the tube along the rails, angled up (the missile plays the
	# launch blast and sound).
	missile.launch(muzzle.global_position, -muzzle.global_transform.basis.z)

	# The launcher kicks back and settles.
	var rest := launcher.position
	var kick := launcher.transform.basis.z * 0.4
	var recoil := create_tween()
	recoil.tween_property(launcher, "position", rest + kick, 0.05)
	recoil.tween_property(launcher, "position", rest, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
