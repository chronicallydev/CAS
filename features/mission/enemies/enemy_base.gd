class_name EnemyBase
extends Node3D

const Wreck := preload("res://features/mission/effects/wreck.gd")
const VehicleDamage := preload("res://features/mission/effects/vehicle_damage.gd")
const Debris := preload("res://features/mission/effects/debris.gd")

# Shared enemy behaviour: group membership, health and what to attack.
# Weapons call take_damage(); it returns true when the hit killed the enemy.
# The enemy finds its mission (and through it the helicopter) with
# MissionContext.of() when it enters the tree. Every enemy hunts the
# helicopter.

@export var max_health: float = 1.0
# Damage dealt when this enemy rams its target.
@export var contact_damage: float = 10.0
# Fraction of light-weapon (minigun) damage blocked by armour. 0 = none, 1 = immune.
@export_range(0.0, 1.0, 0.01) var light_armor: float = 0.0
# Points awarded when the player destroys this enemy.
@export var score_value: int = 10
# Shown in the score pop-up, e.g. "+50 TANK". Empty = just the points.
@export var display_name: String = ""
# Vehicles leave a burning wreck when destroyed.
@export var leaves_wreck: bool = false
# Child nodes thrown off when destroyed (e.g. "Turret"). With several, each
# has a chance to come off, so wrecks vary.
@export var detach_parts: PackedStringArray = []

var health: float = 0.0

# Optional health bar child (see health_bar_3d.tscn).
var health_bar: Node
# Holes, sparks, smoke and fire for vehicles (see vehicle_damage.gd).
var damage_fx: Node

# The last hit, for death effects: where it came from, how strong the blast
# was (0 for light weapons) and whether it was a light weapon.
var last_hit_from: Vector3 = Vector3.ZERO
var last_hit_force: float = 0.0
var last_hit_light: bool = false

# The mission this enemy fights in (null if run outside one).
var mission: MissionContext

# Lock-on weapons (SAM trucks): seconds spent locking on to the helicopter.
# While above zero the HUD's edge arrow pulses red.
var lock_timer: float = 0.0


func _ready() -> void:
	mission = MissionContext.of(self)
	add_to_group("enemies")
	health = max_health
	health_bar = get_node_or_null("HealthBar3D")
	if leaves_wreck:
		damage_fx = VehicleDamage.new()
		add_child(damage_fx)
	update_health_bar()


func take_damage(amount: float, light_weapon: bool = false) -> bool:
	if health <= 0.0 or is_queued_for_deletion():
		return false

	if light_weapon:
		amount *= 1.0 - clampf(light_armor, 0.0, 1.0)

	health -= amount
	if damage_fx != null:
		damage_fx.update_damage_state(health / maxf(max_health, 0.001))
	update_health_bar()

	if health <= 0.0:
		die()
		return true

	return false


func die() -> void:
	if leaves_wreck:
		launch_parts()
		Wreck.create_from(self)
	queue_free()


func update_health_bar() -> void:
	if health_bar != null and health_bar.has_method("update_health"):
		health_bar.update_health(health, max_health)


# What this enemy is after: the helicopter, while it's alive.
func objective() -> Node3D:
	return helicopter()


# The objective's spot on the ground (the map centre if there is none).
func objective_ground() -> Vector3:
	var target := objective()
	if target == null:
		return Vector3.ZERO
	return Vector3(target.global_position.x, 0.0, target.global_position.z)


# Ground distance from this enemy to its objective.
func objective_distance() -> float:
	var target := objective_ground()
	return Vector2(global_position.x - target.x, global_position.z - target.z).length()


# Deal damage to `target` (default: the objective). Shots at the helicopter
# only count if they land close to where it is now, so it can dodge by
# moving.
func hit_objective(at: Vector3, amount: float, hit_radius: float = 3.0, target: Node3D = null) -> void:
	if target == null:
		target = objective()
	if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
		return
	if target is Helicopter and target.global_position.distance_to(at) > hit_radius:
		return
	target.take_damage(amount, display_name if display_name != "" else "INFANTRY")


# The player's helicopter, if it's alive.
func helicopter() -> Helicopter:
	if mission == null or mission.helicopter == null or mission.helicopter.dead:
		return null
	return mission.helicopter


# Advances a lock on the helicopter by `delta`. Returns true once
# `lock_time` is reached, and starts over. Warns the player while locking;
# flares (Helicopter.can_be_locked) break the lock.
func update_lock(heli: Helicopter, delta: float, lock_time: float) -> bool:
	if heli == null or not heli.can_be_locked():
		lock_timer = 0.0
		return false
	lock_timer += delta
	heli.warn_lock()
	if lock_timer >= lock_time:
		lock_timer = 0.0
		return true
	return false


# Horizontal distance to the helicopter.
func distance_to_heli(heli: Node3D) -> float:
	return Vector2(heli.global_position.x - global_position.x, heli.global_position.z - global_position.z).length()


# Direction on the ground plane from this enemy to its objective.
func flat_direction_to_center() -> Vector3:
	var target := objective_ground()
	var direction := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)

	if direction.length() > 0.01:
		return direction.normalized()

	return Vector3.ZERO


# Turn to face a ground-plane direction.
func face_direction(direction: Vector3) -> void:
	if direction.length() > 0.01:
		look_at(global_position + direction, Vector3.UP)


# Visible damage for a hit that didn't destroy this enemy. `from` is where
# the shot came from.
func register_hit(from: Vector3, light_weapon: bool) -> void:
	if damage_fx != null:
		damage_fx.register_hit(from, light_weapon, light_weapon and light_armor >= 0.9)


func launch_parts() -> void:
	for part_name in detach_parts:
		var part := get_node_or_null(NodePath(part_name)) as Node3D
		if part == null:
			continue
		if detach_parts.size() > 1 and randf() > 0.6:
			continue
		Debris.launch_part(part, global_position, detach_parts.size() == 1)


func set_last_hit(from: Vector3, force: float, light_weapon: bool) -> void:
	last_hit_from = from
	last_hit_force = force
	last_hit_light = light_weapon
