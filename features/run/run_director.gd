class_name RunDirector
extends Node

# Runs the stretches of a run (see DESIGN.md) on a mission. Forward is -z
# (up the screen). Each stretch is:
#   travel - fly forward: the view only ever scrolls forward and the bottom
#            of the screen is a wall, so you have to keep moving. SAM trucks
#            appear ahead as you reach them.
#   arena  - reaching the end locks the view: enemy helicopters intercept in
#            waves, generated from a budget that grows each stretch (two
#            waves in the last one, the stand-in for a boss).
#   clear  - arena_cleared fires; the run context shows an upgrade pick,
#            then calls next_stretch(). After the last, run_complete.
# Terrain streams in ahead: a DesertEnvironment per stretch, each its own
# biome, freed once well behind.

signal stretch_started(index: int)
signal arena_started(index: int)
signal arena_cleared(index: int)
signal run_complete

const SamScene := preload("res://features/mission/enemies/aa_launcher.tscn")
const HeavySamScene := preload("res://features/mission/enemies/heavy_launcher.tscn")
const ScoutScene := preload("res://features/mission/enemies/enemy_scout.tscn")
const GunshipScene := preload("res://features/mission/enemies/enemy_gunship.tscn")

# Biomes along the run (the ridge is left out: its mountains would sit on
# the route).
const BIOMES := ["desert", "wadi", "oilfield", "saltflat", "refinery", "desert"]

enum State { TRAVEL, ARENA, CLEARED, DONE }

@export var stretch_count: int = 6
# Metres per stretch along -z, of which the first travel_length is travel.
@export var stretch_length: float = 320.0
@export var travel_length: float = 230.0
@export var corridor_half_width: float = 50.0
# Ground distance from the view's centre to the bottom edge of the screen,
# and the arena's half depth.
@export var view_back: float = 36.0
@export var arena_half_depth: float = 34.0
# SAM trucks spawn when the view centre comes this close to their spot.
@export var spawn_ahead: float = 100.0
# Enemies this far behind the view centre are dropped.
@export var despawn_behind: float = 75.0

var mission: MissionContext
var stretch: int = 0
var state: State = State.TRAVEL
var arena_z: float = 0.0
# SAM trucks still to appear this stretch: [scene, position].
var pending: Array = []
# Arena waves still to come (arrays of scenes), and the current wave's
# units still alive.
var waves: Array = []
var wave_units: Array = []
var environments: Dictionary = {}


func setup(mission_context: MissionContext) -> void:
	mission = mission_context
	mission.helicopter.use_corridor = true
	start_stretch(0)


func is_last_stretch() -> bool:
	return stretch >= stretch_count - 1


func stretch_start_z(index: int) -> float:
	return -index * stretch_length


func start_stretch(index: int) -> void:
	stretch = index
	state = State.TRAVEL
	var start := stretch_start_z(index)
	arena_z = start - travel_length - arena_half_depth
	plan_travel(start)
	waves = plan_waves()
	stream_terrain()
	stretch_started.emit(index)


# --- Each frame ----------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if mission == null or mission.helicopter == null:
		return
	var heli := mission.helicopter
	var rig := mission.camera_rig
	var focus_z := rig.get_focus().z

	match state:
		State.TRAVEL:
			# The view never scrolls back, and the bottom of the screen is a
			# wall; ahead, the corridor runs to the far side of the arena.
			rig.max_focus_z = minf(rig.max_focus_z, focus_z)
			rig.min_focus_z = -INF
			heli.corridor = corridor(arena_z - arena_half_depth, minf(rig.max_focus_z, focus_z) + view_back)
			spawn_pending(focus_z)
			if heli.global_position.z < arena_z + arena_half_depth - 8.0:
				start_arena()
		State.ARENA:
			update_arena()

	despawn_behind_view(focus_z)


func corridor(far_z: float, near_z: float) -> Rect2:
	return Rect2(-corridor_half_width, far_z, corridor_half_width * 2.0, near_z - far_z)


# --- Travel --------------------------------------------------------------------

# SAM trucks along the travel stretch: more each stretch, heavy ones from
# the third on.
func plan_travel(start: float) -> void:
	pending.clear()
	var light := mini(2 + stretch, 5)
	var heavy := 0 if stretch < 2 else mini(1 + stretch / 3, 2)
	for i in light + heavy:
		var scene: PackedScene = HeavySamScene if i < heavy else SamScene
		var z := randf_range(start - 70.0, start - travel_length + 10.0)
		var x := randf_range(-corridor_half_width + 8.0, corridor_half_width - 8.0)
		pending.append([scene, Vector3(x, 0.0, z)])


func spawn_pending(focus_z: float) -> void:
	for entry in pending.duplicate():
		var at: Vector3 = entry[1]
		if at.z > focus_z - spawn_ahead:
			pending.erase(entry)
			spawn(entry[0], at)


# --- Arena -----------------------------------------------------------------------

# Budget per wave: a scout costs 1, a gunship 2 (likelier later on). The
# last stretch has two waves.
func plan_waves() -> Array:
	var budgets := [1.0 + stretch * 0.8]
	if is_last_stretch():
		budgets = [4.0, 5.0]
	var planned: Array = []
	for budget: float in budgets:
		var wave: Array = []
		var left := budget
		while left >= 1.0:
			if left >= 2.0 and randf() < 0.35 + stretch * 0.08:
				wave.append(GunshipScene)
				left -= 2.0
			else:
				wave.append(ScoutScene)
				left -= 1.0
		planned.append(wave)
	return planned


func start_arena() -> void:
	state = State.ARENA
	var rig := mission.camera_rig
	rig.min_focus_z = arena_z
	rig.max_focus_z = arena_z
	mission.helicopter.corridor = corridor(arena_z - arena_half_depth, arena_z + arena_half_depth)
	# Trucks never reached still turn up, so nothing is skipped.
	for entry in pending:
		spawn(entry[0], entry[1])
	pending.clear()
	next_wave()
	arena_started.emit(stretch)


# Helicopters come in from beyond the top of the screen and the sides.
func next_wave() -> void:
	var wave: Array = waves.pop_front()
	wave_units.clear()
	for i in wave.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * randf_range(20.0, 60.0), 0.0, arena_z - arena_half_depth - randf_range(25.0, 45.0))
		wave_units.append(spawn(wave[i], at))


func update_arena() -> void:
	wave_units = wave_units.filter(func(unit: Node) -> bool:
		return is_instance_valid(unit) and unit.is_in_group("enemies"))
	if not wave_units.is_empty():
		return
	if not waves.is_empty():
		next_wave()
		return
	state = State.CLEARED
	if is_last_stretch():
		state = State.DONE
		run_complete.emit()
	else:
		arena_cleared.emit(stretch)


## After the upgrade pick: unlock the view and start the next stretch.
func next_stretch() -> void:
	var rig := mission.camera_rig
	rig.min_focus_z = -INF
	rig.max_focus_z = rig.get_focus().z
	start_stretch(stretch + 1)


# --- Units and terrain ---------------------------------------------------------

func spawn(scene: PackedScene, at: Vector3) -> Node3D:
	var unit := scene.instantiate() as Node3D
	mission.world.add_child(unit)
	unit.position = Vector3(at.x, 5.69, at.z)
	# Facing the helicopter's side of the map.
	unit.rotation.y = atan2(-(mission.helicopter.global_position.x - at.x), -(mission.helicopter.global_position.z - at.z))
	return unit


# Anything left well behind the view drops out of the fight quietly.
func despawn_behind_view(focus_z: float) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if wave_units.has(enemy):
			continue
		if enemy.global_position.z > focus_z + despawn_behind:
			enemy.queue_free()


# The mission's own environment covers the start; each later stretch gets
# its own, built a stretch ahead.
func stream_terrain() -> void:
	for index in range(1, mini(stretch + 3, stretch_count)):
		if environments.has(index):
			continue
		var environment := DesertEnvironment.new()
		environment.outer_radius = 200.0
		environment.rock_count = 150
		environment.shrub_count = 180
		environment.dune_count = 20
		environment.biome = BIOMES[index % BIOMES.size()]
		environment.seed_value = randi()
		mission.world.add_child(environment)
		environment.position.z = stretch_start_z(index) - stretch_length * 0.5
		environments[index] = environment
	for index in environments.keys():
		if index < stretch - 1:
			environments[index].queue_free()
			environments.erase(index)
