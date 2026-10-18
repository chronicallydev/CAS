
extends Node3D

@export_group("Spawn Area")
@export var square_size: float = 10.0
@export var vertical_offset: float = 2.0
@export var node_scene: PackedScene


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
# 1.0 = normal difficulty progression, 2.0 = twice as fast.
# This changes difficulty progression, not the rest of the game.
@export_range(0.0, 10.0, 0.1) var game_speed: float = 1.0

# One difficulty level is gained every this many effective seconds.
@export_range(5.0, 300.0, 5.0) var difficulty_ramp_seconds: float = 60.0

# How many additional enemies the alive limit gains per level.
@export_range(1, 1000, 1) var alive_limit_growth: int = 10

# Maximum enemies spawned in a single burst.
@export_range(1, 20, 1) var max_burst_size: int = 4


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

	# Spawn the first enemy immediately.
	spawn_random_node()

	spawn_countdown = get_current_spawn_interval()
	set_process(true)


func _process(delta: float) -> void:
	# Difficulty progresses according to game_speed.
	difficulty_time += delta * maxf(game_speed, 0.0)

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
		initial_interval / (1.0 + float(level))
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


func spawn_random_node() -> void:
	if node_scene == null or max_nodes <= 0:
		return

	# Remove references to enemies that have already been freed.
	for i in range(spawned_nodes.size() - 1, -1, -1):
		if not is_instance_valid(spawned_nodes[i]):
			spawned_nodes.remove_at(i)

	# Enforce the current alive limit.
	# Remove the oldest enemies if the limit has been reached.
	var alive_limit := get_current_alive_limit()

	while spawned_nodes.size() >= alive_limit:
		var oldest_node: Node3D = spawned_nodes.pop_front()

		if is_instance_valid(oldest_node):
			oldest_node.queue_free()

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
	var instance = node_scene.instantiate()

	if not instance is Node3D:
		instance.free()
		push_warning("The root of node_scene must inherit from Node3D.")
		return

	var new_node := instance as Node3D

	add_child(new_node)
	new_node.position = spawn_position

	spawned_nodes.append(new_node)
