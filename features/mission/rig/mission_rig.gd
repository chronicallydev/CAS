class_name MissionRig
extends Area3D

# The oil rig at the centre of the battlefield.
#
# Defending: it's the player's rig. Enemies that reach its zone are removed
# and damage it, and losing all its health ends the mission.
# Assaulting: it's the enemy's rig. It can't be hurt, so it shows no health
# bar; the enemy generator's forts and waves are the objective instead.

# Emitted whenever the rig takes damage (for HUD warnings).
signal damaged

@onready var health_bar_3d: HealthBar = %HealthBar3D

@export var zone_size: float = 20.0
@export var check_interval: float = 0.2
@export var damage_per_enemy: float = 10.0

var health: float = 100
var max_health: float = 100.0

var check_timer: float = 0.0
var mission: MissionContext


# Called by the mission context. `hull_bonus` is the extra health from the
# rig's hull upgrades when defending an owned rig.
func initialize(mission_context: MissionContext, hull_bonus: float) -> void:
	mission = mission_context
	max_health += hull_bonus
	health = max_health
	health_bar_3d.update_health(health, max_health)

	if mission.is_assault():
		health_bar_3d.visible = false
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if mission == null:
		return

	check_timer += delta

	if check_timer >= check_interval:
		check_timer = 0.0
		check_enemies()

	if health <= 0:
		mission.game_over("The oil rig was destroyed")


func take_damage(amount: float) -> void:
	on_damaged()
	health = maxf(health - amount, 0.0)
	health_bar_3d.update_health(health, max_health)


# Enemies inside the square zone around the rig are removed and deal their
# contact damage.
func check_enemies() -> void:
	var half_size: float = zone_size / 2.0
	var damage_taken: float = 0.0

	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D

		if enemy == null or enemy.is_queued_for_deletion():
			continue

		# Get the enemy's position relative to this zone.
		var local_pos: Vector3 = to_local(enemy.global_position)

		# Check whether the enemy is inside the square on the XZ plane.
		if abs(local_pos.x) <= half_size and abs(local_pos.z) <= half_size:
			enemy.queue_free()
			# Each enemy can set its own contact damage.
			damage_taken += enemy.contact_damage if "contact_damage" in enemy else damage_per_enemy

	if damage_taken > 0.0:
		on_damaged()
		health = maxf(health - damage_taken, 0.0)
		health_bar_3d.update_health(health, max_health)


func on_damaged() -> void:
	damaged.emit()
	Sfx.play_3d("base_hit", global_position + Vector3.UP * 3.0)
	mission.shake(0.06, global_position)
