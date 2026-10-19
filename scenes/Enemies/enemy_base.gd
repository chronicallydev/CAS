extends Node3D

const Wreck := preload("res://scenes/Enemies/wreck.gd")
const VehicleDamage := preload("res://scenes/Enemies/vehicle_damage.gd")
const Debris := preload("res://scenes/Enemies/debris.gd")

# Shared enemy behaviour: group membership and health.
# Weapons call take_damage(); it returns true when the hit killed the enemy.

@export var max_health: float = 1.0
# Damage dealt to the base when this enemy reaches it.
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


func _ready() -> void:
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


# Direction on the ground plane from this enemy to the map centre (the base).
func flat_direction_to_center() -> Vector3:
	var direction := Vector3(-global_position.x, 0.0, -global_position.z)

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
