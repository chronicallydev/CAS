
extends Node3D

enum Difficulty { EASY, NORMAL, HARD, BRUTAL, CUSTOM }

# Multipliers for each preset. CUSTOM uses the values set in the Inspector.
const PRESETS := {
	Difficulty.EASY: { "health": 0.75, "speed": 0.8, "damage": 0.5, "spawn_rate": 0.7, "progression": 0.7 },
	Difficulty.NORMAL: { "health": 1.0, "speed": 1.0, "damage": 1.0, "spawn_rate": 1.0, "progression": 1.0 },
	Difficulty.HARD: { "health": 1.5, "speed": 1.2, "damage": 1.5, "spawn_rate": 1.3, "progression": 1.3 },
	Difficulty.BRUTAL: { "health": 2.0, "speed": 1.4, "damage": 2.0, "spawn_rate": 1.7, "progression": 1.6 },
}

@export_group("Spawn Area")
@export var square_size: float = 10.0
@export var vertical_offset: float = 2.0
@export var node_scene: PackedScene


@export_group("Enemy Types")
# Each enabled type that has reached its unlock level is picked with a
# chance proportional to its weight.
@export var infantry_enabled: bool = true
@export_range(0.0, 10.0, 0.05) var infantry_weight: float = 0.65
@export_range(0, 100, 1) var infantry_min_level: int = 0

@export var car_enabled: bool = true
@export var car_scene: PackedScene
@export_range(0.0, 10.0, 0.05) var car_weight: float = 0.25
@export_range(0, 100, 1) var car_min_level: int = 1

@export var tank_enabled: bool = true
@export var tank_scene: PackedScene
@export_range(0.0, 10.0, 0.05) var tank_weight: float = 0.1
@export_range(0, 100, 1) var tank_min_level: int = 2


@export_group("Spawn Settings")
# Starting delay between spawn bursts.
@export_range(0.05, 60.0, 0.05) var spawn_interval: float = 1.0

# The interval will never go below this value.
@export_range(0.05, 60.0, 0.05) var min_spawn_interval: float = 0.15

# Absolute maximum number of enemies alive at once.
@export_range(1, 10000, 1) var max_nodes: int = 50

# Number of enemies allowed at the start of the game.
@export_range(1, 10000, 1) var starting_max_nodes: int = 10


@export_group("Difficulty")
# Sets the multipliers below. Pick CUSTOM to use the Custom Modifiers values.
@export var difficulty: Difficulty = Difficulty.NORMAL

# Difficulty level the game starts at (0 = the beginning).
@export_range(0, 100, 1) var starting_level: int = 0

# 1.0 = normal difficulty progression, 2.0 = twice as fast.
# This changes difficulty progression, not the rest of the game.
@export_range(0.0, 10.0, 0.1) var game_speed: float = 1.0

# One difficulty level is gained every this many effective seconds.
@export_range(5.0, 300.0, 5.0) var difficulty_ramp_seconds: float = 60.0

# How many additional enemies the alive limit gains per level.
@export_range(1, 1000, 1) var alive_limit_growth: int = 10

# Maximum enemies spawned in a single burst.
@export_range(1, 20, 1) var max_burst_size: int = 4


@export_group("Custom Modifiers")
# Only used when difficulty is CUSTOM.
@export_range(0.1, 10.0, 0.05) var enemy_health_multiplier: float = 1.0
@export_range(0.1, 5.0, 0.05) var enemy_speed_multiplier: float = 1.0
# Damage enemies deal to the base (contact and tank shells).
@export_range(0.0, 10.0, 0.05) var enemy_damage_multiplier: float = 1.0
# 2.0 = enemies spawn twice as often.
@export_range(0.1, 10.0, 0.05) var spawn_rate_multiplier: float = 1.0
# 2.0 = difficulty levels are gained twice as fast.
@export_range(0.0, 10.0, 0.05) var progression_multiplier: float = 1.0


var spawned_nodes: Array[Node3D] = []

var difficulty_time: float = 0.0
var spawn_countdown: float = 0.0


func _ready() -> void:
	if node_scene == null:
		push_warning("Assign a node scene in the Inspector.")
		set_process(false)
		return

	if square_size <= 0.0:
		push_warning("Square size must be greater than zero.")
		set_process(false)
		return

	if max_nodes <= 0:
		push_warning("Maximum number of nodes must be greater than zero.")
		set_process(false)
		return

	if difficulty != Difficulty.CUSTOM:
		apply_preset(difficulty)

	difficulty_time = float(starting_level) * maxf(difficulty_ramp_seconds, 1.0)

	# Spawn the first enemy immediately.
	spawn_random_node()

	spawn_countdown = get_current_spawn_interval()
	set_process(true)


func apply_preset(preset: Difficulty) -> void:
	var values: Dictionary = PRESETS[preset]
	enemy_health_multiplier = values["health"]
	enemy_speed_multiplier = values["speed"]
	enemy_damage_multiplier = values["damage"]
	spawn_rate_multiplier = values["spawn_rate"]
	progression_multiplier = values["progression"]


func _process(delta: float) -> void:
	# Difficulty progresses according to game_speed and the difficulty setting.
	difficulty_time += delta * maxf(game_speed, 0.0) * maxf(progression_multiplier, 0.0)

	spawn_countdown -= delta

	if spawn_countdown > 0.0:
		return

	# Spawn a group of enemies based on the current difficulty.
	var burst_size := get_current_burst_size()

	for i in range(burst_size):
		spawn_random_node()

	# Recalculate the interval for the next burst.
	spawn_countdown = get_current_spawn_interval()


func get_difficulty_level() -> int:
	var ramp_time := maxf(difficulty_ramp_seconds, 1.0)

	return int(floor(difficulty_time / ramp_time))


func get_current_spawn_interval() -> float:
	var level := get_difficulty_level()

	var minimum_interval := maxf(min_spawn_interval, 0.05)
	var initial_interval := maxf(spawn_interval, minimum_interval)

	# Each difficulty level makes spawning faster.
	return maxf(
		minimum_interval,
		initial_interval / (1.0 + float(level)) / maxf(spawn_rate_multiplier, 0.1)
	)


func get_current_burst_size() -> int:
	var level := get_difficulty_level()

	# Start with one enemy, then increase burst size each level.
	return clampi(
		1 + level,
		1,
		maxi(max_burst_size, 1)
	)


func get_current_alive_limit() -> int:
	var level := get_difficulty_level()

	# Increase the number of enemies allowed alive as the game progresses.
	var starting_limit := clampi(starting_max_nodes, 1, max_nodes)

	return mini(
		max_nodes,
		starting_limit + level * alive_limit_growth
	)


# Returns null when no enemy type is enabled and unlocked yet.
func pick_enemy_scene() -> PackedScene:
	var level := get_difficulty_level()
	var options: Array = []
	var total_weight := 0.0

	for entry in [
		[infantry_enabled, node_scene, infantry_weight, infantry_min_level],
		[car_enabled, car_scene, car_weight, car_min_level],
		[tank_enabled, tank_scene, tank_weight, tank_min_level],
	]:
		if entry[0] and entry[1] != null and entry[2] > 0.0 and level >= entry[3]:
			options.append(entry)
			total_weight += entry[2]

	if options.is_empty():
		return null

	var roll := randf() * total_weight

	for entry in options:
		if roll < entry[2]:
			return entry[1]
		roll -= entry[2]

	return options.back()[1]


# Scale an enemy's stats by the difficulty multipliers before it enters the tree.
func apply_modifiers(enemy: Node) -> void:
	if "max_health" in enemy:
		enemy.max_health *= enemy_health_multiplier
	if "speed" in enemy:
		enemy.speed *= enemy_speed_multiplier
	if "contact_damage" in enemy:
		enemy.contact_damage *= enemy_damage_multiplier
	if "shot_damage" in enemy:
		enemy.shot_damage *= enemy_damage_multiplier
	if "shell_damage" in enemy:
		enemy.shell_damage *= enemy_damage_multiplier


func spawn_random_node() -> void:
	if max_nodes <= 0:
		return

	var scene := pick_enemy_scene()

	if scene == null:
		return

	# Remove references to enemies that have already been freed.
	for i in range(spawned_nodes.size() - 1, -1, -1):
		if not is_instance_valid(spawned_nodes[i]):
			spawned_nodes.remove_at(i)

	# Enforce the current alive limit.
	# Skip spawning until some enemies have been killed.
	if spawned_nodes.size() >= get_current_alive_limit():
		return

	# Choose a random position along one of the square's edges.
	var half_size: float = square_size / 2.0
	var coordinate: float = randf_range(-half_size, half_size)
	var edge: int = randi_range(0, 3)

	var spawn_position: Vector3

	match edge:
		0: # Top edge
			spawn_position = Vector3(coordinate, vertical_offset, -half_size)
		1: # Bottom edge
			spawn_position = Vector3(coordinate, vertical_offset, half_size)
		2: # Left edge
			spawn_position = Vector3(-half_size, vertical_offset, coordinate)
		3: # Right edge
			spawn_position = Vector3(half_size, vertical_offset, coordinate)

	# Instantiate the enemy.
	var instance = scene.instantiate()

	if not instance is Node3D:
		instance.free()
		push_warning("The root of each enemy scene must inherit from Node3D.")
		return

	var new_node := instance as Node3D

	apply_modifiers(new_node)
	add_child(new_node)
	new_node.position = spawn_position

	spawned_nodes.append(new_node)
