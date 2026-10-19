
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

@export var aa_enabled: bool = true
@export var aa_scene: PackedScene
@export_range(0.0, 10.0, 0.05) var aa_weight: float = 0.08
@export_range(0, 100, 1) var aa_min_level: int = 1


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


@export_group("Waves")
# Waves of enemies with breaks in between. Off = the old endless ramp.
@export var wave_mode: bool = true
@export_range(1, 100, 1) var first_wave_enemies: int = 6
# Extra enemies each wave (scaled by the progression multiplier).
@export_range(0.0, 20.0, 0.5) var enemies_per_wave: float = 3.0
# Seconds between spawns in wave 1; shrinks a little every wave.
@export_range(0.1, 10.0, 0.05) var wave_spawn_interval: float = 1.4
# Break between waves, in seconds.
@export_range(0.0, 60.0, 0.5) var breather_time: float = 6.0
# Most enemies allowed on the map at once during a wave.
@export_range(1, 200, 1) var wave_max_alive: int = 30
@export_range(0, 50, 1) var boss_every: int = 5
@export_range(1.0, 20.0, 0.5) var boss_health_multiplier: float = 5.0
# Bonus points for clearing a wave, multiplied by the wave number.
@export_range(0, 10000, 10) var wave_clear_bonus: int = 100

const Campaign := preload("res://scenes/map/campaign.gd")
const Bunker := preload("res://scenes/Enemies/bunker.gd")
const FlakGun := preload("res://scenes/Enemies/flak_gun.gd")

# Assault missions: waves to clear to win. 0 = endless.
var target_waves: int = 0
# Assaults: the last wave has been cleared (forts may still stand).
var waves_done: bool = false
var assault_won: bool = false
# Spawn-square edges enemies never come from (e.g. the sea side).
var blocked_edges: Array = []

signal wave_started(wave: int, is_boss: bool)
signal wave_cleared(wave: int, bonus: int)
# A fort around an assaulted rig was destroyed; `left` are still standing.
signal fort_destroyed(left: int)

enum WaveState { BREAK, ACTIVE }

var spawned_nodes: Array[Node3D] = []

var difficulty_time: float = 0.0
var spawn_countdown: float = 0.0

var wave: int = 0
var wave_state: WaveState = WaveState.BREAK
var break_left: float = 0.0
var wave_queue: Array = []
var wave_spawn_timer: float = 0.0
var wave_had_enemies: bool = false


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

	if Global.use_menu_settings:
		apply_menu_settings()

	if not Global.mission.is_empty():
		apply_mission()

	if difficulty != Difficulty.CUSTOM:
		apply_preset(difficulty)

	Global.reset_run()
	if target_waves > 0:
		spawn_forts()
	set_process(true)

	if wave_mode:
		# Starting level N skips the first N waves.
		wave = starting_level
		Global.wave = wave
		wave_state = WaveState.BREAK
		break_left = 3.0
		return

	difficulty_time = float(starting_level) * maxf(difficulty_ramp_seconds, 1.0)

	# Spawn the first enemy immediately.
	spawn_random_node()

	spawn_countdown = get_current_spawn_interval()


# Settings picked in the main menu override the Inspector values.
func apply_menu_settings() -> void:
	difficulty = Global.difficulty as Difficulty
	starting_level = Global.starting_level
	infantry_enabled = Global.infantry_enabled
	car_enabled = Global.car_enabled
	tank_enabled = Global.tank_enabled
	aa_enabled = Global.aa_enabled

	# Without infantry, let vehicles appear from the start instead of
	# leaving the map empty until they unlock.
	if not infantry_enabled:
		car_min_level = 0
		tank_min_level = 0
		aa_min_level = 0


# A campaign mission sets the starting level and enemy mix from its rig.
# Assaults end after the rig's waves are cleared; defends are endless.
func apply_mission() -> void:
	var rig: Dictionary = Campaign.RIGS[Global.mission["rig"]]
	var weights: Dictionary = Campaign.profile(Global.mission["rig"])["weights"]
	wave_mode = true
	starting_level = rig["level"]
	infantry_weight = weights["infantry"]
	car_weight = weights["car"]
	tank_weight = weights["tank"]
	aa_weight = weights["aa"]
	infantry_enabled = infantry_weight > 0.0
	car_enabled = car_weight > 0.0
	tank_enabled = tank_weight > 0.0
	aa_enabled = aa_weight > 0.0
	# The garrison is all there from the first wave.
	car_min_level = 0
	tank_min_level = 0
	aa_min_level = 0
	target_waves = rig["waves"] if Global.is_assault() else 0
	if rig["biome"] == "terminal":
		# The gulf is on the right-hand edge.
		blocked_edges = [3]


# Waves still to clear before an assault is won.
func waves_left() -> int:
	return maxi(target_waves - (wave - starting_level), 0)


func is_final_wave(number: int) -> bool:
	return target_waves > 0 and number - starting_level == target_waves


func apply_preset(preset: Difficulty) -> void:
	var values: Dictionary = PRESETS[preset]
	enemy_health_multiplier = values["health"]
	enemy_speed_multiplier = values["speed"]
	enemy_damage_multiplier = values["damage"]
	spawn_rate_multiplier = values["spawn_rate"]
	progression_multiplier = values["progression"]


func _process(delta: float) -> void:
	if wave_mode:
		process_waves(delta)
		return

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


# --- Waves ---------------------------------------------------------------

func process_waves(delta: float) -> void:
	prune_spawned()

	if waves_done:
		return

	if wave_state == WaveState.BREAK:
		break_left -= delta
		if break_left <= 0.0:
			begin_wave(wave + 1)
		return

	wave_spawn_timer -= delta

	if wave_spawn_timer <= 0.0 and not wave_queue.is_empty():
		for i in get_wave_burst_size():
			if wave_queue.is_empty() or alive_count() >= wave_max_alive:
				break
			var entry = wave_queue.pop_front()
			if entry is String and entry == "boss":
				spawn_boss()
			else:
				spawn_enemy(entry)
		wave_spawn_timer = get_wave_spawn_interval()

	if wave_queue.is_empty() and alive_count() == 0:
		clear_wave()


func begin_wave(number: int) -> void:
	wave = number
	Global.wave = number
	wave_state = WaveState.ACTIVE
	wave_spawn_timer = 0.5
	wave_queue.clear()

	var count := int(round(first_wave_enemies + (number - 1) * enemies_per_wave * maxf(progression_multiplier, 0.0)))
	for i in count:
		var scene := pick_enemy_scene()
		if scene != null:
			wave_queue.append(scene)

	# Assaults end with the garrison's boss; endless runs get one every few waves.
	var is_boss := boss_every > 0 and number % boss_every == 0 and tank_scene != null
	if target_waves > 0:
		is_boss = is_final_wave(number) and tank_scene != null
	if is_boss:
		# The boss rolls in after the first few escorts.
		wave_queue.insert(mini(2, wave_queue.size()), "boss")

	wave_had_enemies = not wave_queue.is_empty()
	wave_started.emit(number, is_boss)


func clear_wave() -> void:
	var bonus := wave_clear_bonus * wave if wave_had_enemies else 0
	Global.add_score(bonus)
	wave_state = WaveState.BREAK
	break_left = breather_time
	wave_cleared.emit(wave, bonus)

	if is_final_wave(wave):
		waves_done = true
		check_assault_won()


# --- Assault forts -------------------------------------------------------

# Bunkers and flak guns in a ring around the enemy rig.
func spawn_forts() -> void:
	var counts: Array = Campaign.RIGS[Global.mission["rig"]]["forts"]
	var kinds: Array = []
	for i in counts[0]:
		kinds.append(Bunker)
	for i in counts[1]:
		kinds.append(FlakGun)
	kinds.shuffle()

	var start := randf() * TAU
	for i in kinds.size():
		var angle := start + TAU * i / kinds.size() + randf_range(-0.25, 0.25)
		var radius := randf_range(15.0, 28.0)
		var fort: Node3D = kinds[i].new()
		apply_modifiers(fort)
		add_child(fort)
		fort.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		fort.rotation.y = -angle + PI / 2.0
		fort.tree_exiting.connect(on_fort_exiting.bind(fort))


func forts_left() -> int:
	var count := 0
	for fort in get_tree().get_nodes_in_group("forts"):
		if not fort.is_queued_for_deletion() and fort.health > 0.0:
			count += 1
	return count


func on_fort_exiting(fort: Node3D) -> void:
	# Only count forts that were destroyed, not ones freed with the scene.
	if fort.health > 0.0 or Global.is_game_over or not is_inside_tree():
		return
	fort_destroyed.emit(forts_left())
	check_assault_won()


# The rig is captured once the last wave is cleared and every fort is down.
func check_assault_won() -> void:
	if assault_won or not waves_done or forts_left() > 0:
		return
	assault_won = true
	# A moment to enjoy the last explosion before the victory screen.
	await get_tree().create_timer(2.0).timeout
	Global.mission_won()


func get_wave_spawn_interval() -> float:
	var interval := wave_spawn_interval * pow(0.93, wave - 1) / maxf(spawn_rate_multiplier, 0.1)
	return maxf(interval, maxf(min_spawn_interval, 0.1))


func get_wave_burst_size() -> int:
	return clampi(1 + (wave - 1) / 3, 1, maxi(max_burst_size, 1))


func prune_spawned() -> void:
	for i in range(spawned_nodes.size() - 1, -1, -1):
		if not is_instance_valid(spawned_nodes[i]):
			spawned_nodes.remove_at(i)


func alive_count() -> int:
	var count := 0
	for enemy in spawned_nodes:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			count += 1
	return count


# Enemies still to come in this wave, including those on the map.
func enemies_left() -> int:
	return wave_queue.size() + alive_count()


# A super-sized tank: much tougher, hits harder, worth more points.
func spawn_boss() -> void:
	var boss = spawn_enemy(tank_scene)
	if boss == null:
		return

	boss.add_to_group("boss")
	boss.scale = Vector3.ONE * 1.5
	boss.max_health *= boss_health_multiplier
	boss.health = boss.max_health
	boss.update_health_bar()
	if "shell_damage" in boss:
		boss.shell_damage *= 1.5
	if "fire_interval" in boss:
		boss.fire_interval *= 0.7
	boss.display_name = "BOSS"
	if "score_value" in boss:
		boss.score_value *= 6


func get_difficulty_level() -> int:
	if wave_mode:
		# Each wave counts as a level for enemy unlocks.
		return maxi(wave - 1, 0)

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
		[aa_enabled, aa_scene, aa_weight, aa_min_level],
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
	if "missile_damage" in enemy:
		enemy.missile_damage *= enemy_damage_multiplier
	if "shell_damage" in enemy:
		enemy.shell_damage *= enemy_damage_multiplier


func spawn_random_node() -> void:
	if max_nodes <= 0:
		return

	var scene := pick_enemy_scene()

	if scene == null:
		return

	# Remove references to enemies that have already been freed.
	prune_spawned()

	# Enforce the current alive limit.
	# Skip spawning until some enemies have been killed.
	if spawned_nodes.size() >= get_current_alive_limit():
		return

	spawn_enemy(scene)


# Spawn one enemy of the given scene on a random edge of the spawn square.
func spawn_enemy(scene: PackedScene) -> Node3D:
	if scene == null:
		return null

	# Choose a random position along one of the square's edges.
	var half_size: float = square_size / 2.0
	var coordinate: float = randf_range(-half_size, half_size)
	var edge: int = randi_range(0, 3)
	while blocked_edges.has(edge) and blocked_edges.size() < 4:
		edge = randi_range(0, 3)

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
		return null

	var new_node := instance as Node3D

	apply_modifiers(new_node)
	add_child(new_node)
	new_node.position = spawn_position

	spawned_nodes.append(new_node)
	return new_node
