extends Node3D

# Shared enemy behaviour: group membership and health.
# Weapons call take_damage(); it returns true when the hit killed the enemy.

@export var max_health: float = 1.0
# Damage dealt to the base when this enemy reaches it.
@export var contact_damage: float = 10.0
# Fraction of light-weapon (minigun) damage blocked by armour. 0 = none, 1 = immune.
@export_range(0.0, 1.0, 0.01) var light_armor: float = 0.0

var health: float = 0.0

# Optional health bar child (see health_bar_3d.tscn).
var health_bar: Node


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	health_bar = get_node_or_null("HealthBar3D")
	update_health_bar()


func take_damage(amount: float, light_weapon: bool = false) -> bool:
	if health <= 0.0 or is_queued_for_deletion():
		return false

	if light_weapon:
		amount *= 1.0 - clampf(light_armor, 0.0, 1.0)

	health -= amount
	update_health_bar()

	if health <= 0.0:
		die()
		return true

	return false


func die() -> void:
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
