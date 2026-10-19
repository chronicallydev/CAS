class_name EnemyGenerator
extends Node3D

# Spawns the enemies. In wave mode (the default) waves arrive with breaks
# in between, each from one of the enemy sides; with wave mode off there is
# an endless, ramping stream instead.
#
# The mission context calls start() with the difficulty and settings. A
# campaign mission also sets the enemy mix, starting level and enemy sides
# from its rig, and an assault adds forts around the enemy rig and ends
# once its waves are cleared and its forts destroyed.

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
# Sets the multipliers below. Leave empty to use the Custom Modifiers
# values. The menu's choice replaces this when the game is played normally.
@export var difficulty: DifficultyPreset

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
# Only used when no difficulty preset is set.
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

const Bunker := preload("res://features/mission/enemies/forts/bunker.gd")
const FlakGun := preload("res://features/mission/enemies/forts/flak_gun.gd")

# Assault missions: waves to clear to win. 0 = endless.
var target_waves: int = 0
# Assaults: the last wave has been cleared (forts may still stand).
var waves_done: bool = false
var assault_won: bool = false
# Directions (x = east, y = south) enemies come from, out of enemy
# territory. Each wave picks one as its main heading.
var enemy_sides: Array = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
var wave_side: Vector2 = Vector2(0, -1)
# Assaults: waves hold off until the helicopter flies within contact_range.
var awaiting_contact: bool = false
var contact_range: float = 70.0
# Spawns stay west of this x (the terminal's sea is to the east).
var sea_x: float = INF

signal wave_started(wave: int, is_boss: bool)
signal wave_cleared(wave: int, bonus: int)
# A fort around an assaulted rig was destroyed; `left` are still standing.
signal fort_destroyed(left: int)
# The helicopter reached the assaulted rig; the fight starts.
signal contact_made

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

var mission: MissionContext


func _ready() -> void:
	# Nothing spawns until the mission context calls start().
	set_process(false)


# Starts spawning. `preset` and `settings` come from the main menu; pass
# null to keep the Inspector values (when mission.tscn is run on its own).
func start(mission_context: MissionContext, preset: DifficultyPreset, settings: GameSettings) -> void:
	mission = mission_context

	if node_scene == null:
		push_warning("Assign a node scene in the Inspector.")
		return

	if square_size <= 0.0:
		push_warning("Square size must be greater than zero.")
		return

	if max_nodes <= 0:
		push_warning("Maximum number of nodes must be greater than zero.")
		return

	if settings != null:
		apply_menu_settings(settings)
	if preset != null:
		difficulty = preset

	if mission.state.is_campaign():
		apply_mission(mission.state.rig)

	if difficulty != null:
		apply_preset(difficulty)

	if target_waves > 0:
		spawn_forts()
	set_process(true)

	if wave_mode:
		# Starting level N skips the first N waves.
		wave = starting_level
		mission.state.wave = wave
		wave_state = WaveState.BREAK
		wave_side = pick_wave_side()
		# Assaults wait for the helicopter to arrive; a defence gives a
		# moment to lift off before the first column turns up.
		awaiting_contact = target_waves > 0
		break_left = 8.0 if mission.state.is_campaign() else 3.0
		return

	difficulty_time = float(starting_level) * maxf(difficulty_ramp_seconds, 1.0)

	# Spawn the first enemy immediately.
	spawn_random_node()

	spawn_countdown = get_current_spawn_interval()


# Free-play options from the main menu override the Inspector values.
func apply_menu_settings(settings: GameSettings) -> void:
	starting_level = settings.starting_level
	infantry_enabled = settings.infantry_enabled
	car_enabled = settings.car_enabled
	tank_enabled = settings.tank_enabled
	aa_enabled = settings.aa_enabled

	# Without infantry, let vehicles appear from the start instead of
	# leaving the map empty until they unlock.
	if not infantry_enabled:
		car_min_level = 0
		tank_min_level = 0
		aa_min_level = 0


# A campaign mission sets the starting level and enemy mix from its rig.
# Assaults end after the rig's waves are cleared; defends are endless.
func apply_mission(rig: RigData) -> void:
	var garrison := rig.garrison
	wave_mode = true
	starting_level = rig.threat_level
	infantry_weight = garrison.infantry_weight
	car_weight = garrison.car_weight
	tank_weight = garrison.tank_weight
	aa_weight = garrison.aa_weight
	infantry_enabled = infantry_weight > 0.0
	car_enabled = car_weight > 0.0
	tank_enabled = tank_weight > 0.0
	aa_enabled = aa_weight > 0.0
	# The garrison is all there from the first wave.
	car_min_level = 0
	tank_min_level = 0
	aa_min_level = 0
	target_waves = rig.waves if mission.is_assault() else 0
	enemy_sides = mission.services.campaign.enemy_sides(rig.id)
	if rig.biome == "terminal":
		# The gulf lies to the east.
		sea_x = 30.0


# Waves still to clear before an assault is won.
func waves_left() -> int:
	return maxi(target_waves - (wave - starting_level), 0)


func is_final_wave(number: int) -> bool:
	return target_waves > 0 and number - starting_level == target_waves


func apply_preset(preset: DifficultyPreset) -> void:
	enemy_health_multiplier = preset.health
	enemy_speed_multiplier = preset.speed
	enemy_damage_multiplier = preset.damage
	spawn_rate_multiplier = preset.spawn_rate
	progression_multiplier = preset.progression


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

	if awaiting_contact:
		var heli := mission.helicopter
		if heli != null and Vector2(heli.global_position.x, heli.global_position.z).length() <= contact_range:
			awaiting_contact = false
			break_left = 2.5
			contact_made.emit()
		return

	if wave_state == WaveState.BREAK:
		break_left -= delta
		if break_left <= 0.0:
			begin_wave(wave + 1)
		return

	wave_spawn_timer -= delta

	if wave_spawn_timer <= 0.0 and not wave_queue.is_empty():
		var spawned := spawn_group()
		wave_spawn_timer = get_wave_spawn_interval() * maxi(spawned, 1)

	if wave_queue.is_empty() and alive_count() == 0:
		clear_wave()


func begin_wave(number: int) -> void:
	wave = number
	mission.state.wave = number
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
	mission.add_score(bonus)
	wave_state = WaveState.BREAK
	break_left = breather_time
	# The next wave comes from a fresh direction, announced during the break.
	wave_side = pick_wave_side()
	wave_cleared.emit(wave, bonus)

	if is_final_wave(wave):
		waves_done = true
		check_assault_won()


# --- Assault forts -------------------------------------------------------

# Bunkers and flak guns in a ring around the enemy rig.
func spawn_forts() -> void:
	var rig := mission.state.rig
	var counts: Array = [rig.bunkers, rig.flak_guns]
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
	if fort.health > 0.0 or mission.state.is_over or not is_inside_tree():
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
	mission.mission_won()


func get_wave_spawn_interval() -> float:
	var interval := wave_spawn_interval * pow(0.93, wave - 1) / maxf(spawn_rate_multiplier, 0.1)
	return maxf(interval, maxf(min_spawn_interval, 0.1))


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
func spawn_boss(at: Variant = null) -> void:
	var boss = spawn_enemy(tank_scene, at)
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


# --- Where enemies come from ---------------------------------------------

# A wave's main heading: one of the enemy sides, swung a little.
func pick_wave_side() -> Vector2:
	var side: Vector2 = enemy_sides[randi() % enemy_sides.size()]
	return side.rotated(randf_range(-0.35, 0.35))


# A group of enemies arriving together from just off-screen. Most groups
# come along the wave's heading; some flank from another enemy side.
# Returns how many were spawned.
func spawn_group() -> int:
	var number := wave - starting_level if target_waves > 0 else wave
	var size := clampi(2 + number / 2, 3, 7)
	var side := wave_side.rotated(randf_range(-0.4, 0.4))
	if randf() < 0.3:
		side = pick_wave_side()
	var origin := offscreen_point(side)

	var spawned := 0
	for i in size:
		if wave_queue.is_empty() or alive_count() >= wave_max_alive:
			break
		var entry = wave_queue.pop_front()
		# Spread out a little, mostly across the line of advance.
		var across := Vector3(-side.y, 0.0, side.x) * randf_range(-7.0, 7.0)
		var back := Vector3(side.x, 0.0, side.y) * randf_range(0.0, 6.0)
		var at := origin + across + back
		if entry is String and entry == "boss":
			spawn_boss(at)
		else:
			spawn_enemy(entry, at)
		spawned += 1
	return spawned


# A point along `side` from the centre of the view, just past its edge so
# nothing appears on screen.
func offscreen_point(side: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var camera_rig := mission.camera_rig
	var focus: Vector3 = camera_rig.get_focus() if camera_rig != null else Vector3.ZERO
	focus.y = 0.0
	var direction := Vector3(side.x, 0.0, side.y).normalized()

	var point := focus + direction * 60.0
	var distance := 60.0
	while distance < 220.0:
		point = focus + direction * distance
		point.x = minf(point.x, sea_x)
		if camera == null or not on_screen(camera, point):
			break
		distance += 8.0
	# A few metres more so a whole group clears the edge.
	point += direction * 10.0
	point.x = minf(point.x, sea_x)
	point.y = vertical_offset
	return point


func on_screen(camera: Camera3D, point: Vector3) -> bool:
	if camera.is_position_behind(point):
		return false
	var rect := get_viewport().get_visible_rect().grow(60.0)
	return rect.has_point(camera.unproject_position(point))


# Spawn one enemy of the given scene at `at`, or (without one) off-screen
# on a random enemy side.
func spawn_enemy(scene: PackedScene, at: Variant = null) -> Node3D:
	if scene == null:
		return null

	var spawn_position: Vector3 = at if at is Vector3 else offscreen_point(pick_wave_side())

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
	# Face the way they're heading from the start.
	new_node.rotation.y = atan2(spawn_position.x, spawn_position.z)

	spawned_nodes.append(new_node)
	return new_node
