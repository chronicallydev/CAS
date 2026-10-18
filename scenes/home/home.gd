
extends Area3D

@onready var health_bar_3d: HealthBar = %HealthBar3D

@export var zone_size: float = 20.0
@export var check_interval: float = 0.2
@export var damage_per_enemy: float = 10.0

var health: float = 100
var max_health: float = 100.0

var check_timer: float = 0.0


func _ready() -> void:
	health_bar_3d.update_health(health, max_health)


func _physics_process(delta: float) -> void:
	check_timer += delta

	if check_timer >= check_interval:
		check_timer = 0.0
		check_enemies()
		
	if health <= 0:
		get_tree().reload_current_scene()


func take_damage(amount: float) -> void:
	health = maxf(health - amount, 0.0)
	health_bar_3d.update_health(health, max_health)


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
		if abs(local_pos.x) <= half_size \
		and abs(local_pos.z) <= half_size:
			enemy.queue_free()
			# Each enemy can set its own contact damage.
			damage_taken += enemy.contact_damage if "contact_damage" in enemy else damage_per_enemy

	if damage_taken > 0.0:
		health = maxf(
			health - damage_taken,
			0.0
		)

		health_bar_3d.update_health(health, max_health)
