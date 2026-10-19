class_name PickupDropper
extends Node

# Rolls for a pickup on every kill and drops it where the enemy died. The
# mission context connects GunController.kill_registered to on_kill().
# Tougher kills (more points) are likelier to drop something, and cash
# pickups are worth more for them.

const Pickup := preload("res://features/mission/pickups/pickup.gd")

# Chance per kill, before the bonus for big kills.
@export_range(0.0, 1.0, 0.01) var cash_chance: float = 0.14
@export_range(0.0, 1.0, 0.01) var recharge_chance: float = 0.05
@export_range(0.0, 1.0, 0.01) var frenzy_chance: float = 0.03
# Kills worth at least this many points roll with doubled chances.
@export var big_kill_points: int = 40
# Cash pickup value: base plus this much per point the kill was worth.
@export var cash_base: int = 20
@export var cash_per_point: float = 0.6


func on_kill(points: int, world_position: Vector3, _label: String) -> void:
	var boost := 2.0 if points >= big_kill_points else 1.0
	var roll := randf()
	if roll < frenzy_chance * boost:
		drop(Pickup.Kind.FRENZY, 0, world_position)
	elif roll < (frenzy_chance + recharge_chance) * boost:
		drop(Pickup.Kind.RECHARGE, 0, world_position)
	elif roll < (frenzy_chance + recharge_chance + cash_chance) * boost:
		drop(Pickup.Kind.CASH, cash_base + int(points * cash_per_point), world_position)


func drop(kind: int, value: int, at: Vector3) -> void:
	var pickup := Pickup.new()
	pickup.kind = kind
	pickup.value = value
	MissionContext.spawn_parent(self).add_child(pickup)
	pickup.global_position = Vector3(at.x, 0.0, at.z)
