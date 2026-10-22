class_name RunDirector
extends Node

# Runs the stretches of a run (see DESIGN.md) on a mission. Forward is -z
# (up the screen). Each stretch is:
#   travel - fly forward: the view only ever scrolls forward and the bottom
#            of the screen is a wall, so you have to keep moving. SAM trucks
#            appear ahead as you reach them, and the view won't scroll a
#            live one off the bottom: they have to be destroyed, not
#            flown past.
#   arena  - reaching the end locks the view, over a city (city.gd) from
#            the second stretch on. Enemy helicopters defend it in waves,
#            and while targets still stand scouts keep flying in a few at a
#            time, so it never turns into shooting an empty town. It clears
#            once the targets are down and nothing is left in the air
#            (waves not yet sent are skipped: fast is rewarded). An
#            open-ground arena plays all its waves.
#   clear  - arena_cleared fires; the run context shows an upgrade pick,
#            then calls next_stretch(). After the last, run_complete.
# Terrain streams in ahead: a DesertEnvironment per stretch, each its own
# biome, freed once well behind.

signal stretch_started(index: int)
signal arena_started(index: int)
# The view first held up this stretch, by a live SAM truck or objective;
# `what` names it ("SAMS", "CONVOY", ...).
signal held_by(what: String)
# A convoy vehicle got away (it turns up again in the city).
signal convoy_escaped
# A held view let go: the way ahead is open again.
signal path_cleared
# How many things are left holding you up, once few enough to mark them
# (see leftover_mark); 0 when they aren't being counted.
signal leftovers_changed(count: int)
signal arena_cleared(index: int)
# A marked target in the city went down (or the city was built).
signal targets_changed(left: int, total: int)
signal run_complete

const SamScene := preload("res://features/mission/enemies/aa_launcher.tscn")
const HeavySamScene := preload("res://features/mission/enemies/heavy_launcher.tscn")
const ScoutScene := preload("res://features/mission/enemies/enemy_scout.tscn")
const GunshipScene := preload("res://features/mission/enemies/enemy_gunship.tscn")

# Biomes along the run (the ridge is left out: its mountains would sit on
# the route).
const BIOMES := ["desert", "wadi", "oilfield", "saltflat", "refinery", "desert"]

# The run's ramp: each stretch brings in one new thing. Per stretch:
#   objectives - travel objectives, in the order they come
#   sams, heavy - SAM trucks along the way (one more sits by each
#                 objective)
#   city       - [columns, rows, targets], or [] for open ground
#   waves      - helicopter wave budgets: a scout costs 1, a gunship 2
#   scouts     - how many helicopters may be up at once before more scouts
#                trickle in, while targets still stand
const PLAN := [
	{"objectives": ["tank_line"], "sams": 1, "heavy": 0, "city": [], "waves": [1.0], "scouts": 0},
	{"objectives": ["compound"], "sams": 1, "heavy": 0, "city": [2, 2, 1], "waves": [1.0], "scouts": 1},
	{"objectives": ["convoy"], "sams": 2, "heavy": 1, "city": [3, 2, 2], "waves": [2.0], "scouts": 1},
	{"objectives": ["depot", "tank_line"], "sams": 2, "heavy": 1, "city": [3, 3, 2], "waves": [2.0], "scouts": 2},
	{"objectives": ["convoy", "compound"], "sams": 2, "heavy": 1, "city": [4, 3, 3], "waves": [2.0, 2.0], "scouts": 2},
	{"objectives": ["depot", "convoy"], "sams": 3, "heavy": 1, "city": [4, 3, 4], "waves": [3.0, 3.0], "scouts": 3},
]

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
# A live SAM truck holds the view from scrolling on once it's this far
# behind the view centre, so it stays on screen above the bottom edge.
@export var sam_hold: float = 26.0
# Seconds between one wave going down and the next coming in.
@export var wave_gap: float = 2.5
# Seconds between trickling scouts (see PLAN).
@export var scout_interval: float = 4.0
# Once this few enemies are left holding you up (a held view, or the
# helicopters after a city's targets fall), each gets a marker.
@export var leftover_mark: int = 3

var mission: MissionContext
var stretch: int = 0
var state: State = State.TRAVEL
var arena_z: float = 0.0
# SAM trucks still to appear this stretch: [scene, position].
var pending: Array = []
# SAM trucks spawned this stretch, while alive.
var sams: Array = []
var held: bool = false
# The view is stopped at a hold (see path_cleared).
var blocked: bool = false
# Travel objectives still to appear: [kind, position]; and the ones in
# play, until cleared.
var pending_objectives: Array = []
var objectives: Array = []
# What holds the view right now (see gate()).
var holder: String = ""
# Scenes of convoy vehicles that got away, waiting for the next city.
var escaped: Array[String] = []
# Arena waves still to come (arrays of scenes), and the current wave's
# units still alive.
var waves: Array = []
var wave_units: Array = []
# Counts down wave_gap before the next wave.
var wave_timer: float = 0.0
# Counts down scout_interval before the next trickling scout.
var scout_timer: float = 0.0
# Leftovers last counted (see leftovers_changed).
var leftover_count: int = 0
var environments: Dictionary = {}
# Each stretch's city (built with the stretch), and the ground they take
# up, kept clear of terrain props.
var cities: Dictionary = {}
var clear_areas: Array[Rect2] = []
# Every travel objective built, to free with its stretch: [index, node].
var objective_nodes: Array = []


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
	held = false
	blocked = false
	var start := stretch_start_z(index)
	arena_z = start - travel_length - arena_half_depth
	plan_travel(start)
	waves = plan_waves()
	stream_terrain()
	build_city(index)
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
			rig.min_focus_z = minf(gate(), rig.max_focus_z)
			# The helicopter can't fly on past the top of a held view.
			var far_z := maxf(arena_z - arena_half_depth, rig.min_focus_z - arena_half_depth)
			heli.corridor = corridor(far_z, minf(rig.max_focus_z, focus_z) + view_back)
			if not held and heli.global_position.z < far_z + heli.corridor_margin and holder != "":
				held = true
				held_by.emit(holder)
			# The view caught up with a hold; once that lets go, say so.
			if holder != "" and focus_z <= rig.min_focus_z + 2.0:
				blocked = true
			elif blocked and holder == "":
				# Free to fly on; the next hold gets its own callout.
				blocked = false
				held = false
				path_cleared.emit()
			spawn_pending(focus_z)
			if sams.is_empty() and objectives.is_empty() and pending_objectives.is_empty() and heli.global_position.z < arena_z + arena_half_depth - 8.0:
				start_arena()
		State.ARENA:
			update_arena()

	mark_leftovers()
	despawn_behind_view(focus_z)


# What's holding you up right now: at a held view, the live SAM trucks and
# objective parts; in an arena once a city's targets are down (or over
# open ground), the helicopters still up. A city's standing targets have
# their own markers, so nothing else counts while they do.
func leftovers() -> Array:
	var left: Array = []
	match state:
		State.TRAVEL:
			if not blocked:
				return left
			left.append_array(sams)
			for objective: TravelObjective in objectives:
				left.append_array(objective.parts.filter(objective.alive))
		State.ARENA:
			var city: City = cities.get(stretch)
			if city != null and city.targets_left() > 0:
				return left
			left.append_array(get_tree().get_nodes_in_group("air_enemies"))
	return left


# Marks the leftovers once there are leftover_mark or fewer, and reports
# how many.
func mark_leftovers() -> void:
	var left := leftovers()
	var count := left.size() if left.size() <= leftover_mark else 0
	if count > 0:
		for node: Node3D in left:
			var above: float = node.size.y + 6.0 if node is Building else 6.0
			TargetMarker.follow(node, above)
	if count != leftover_count:
		leftover_count = count
		leftovers_changed.emit(count)


func corridor(far_z: float, near_z: float) -> Rect2:
	return Rect2(-corridor_half_width, far_z, corridor_half_width * 2.0, near_z - far_z)


# --- Travel --------------------------------------------------------------------

func plan() -> Dictionary:
	return PLAN[mini(stretch, PLAN.size() - 1)]


# The stretch's travel objectives (see PLAN) spread along it, each with a
# SAM truck beside it, and its SAM trucks scattered along the way.
func plan_travel(start: float) -> void:
	pending.clear()
	pending_objectives.clear()
	var kinds: Array = plan().objectives
	var count := kinds.size()
	for i in count:
		var z := start - travel_length * (i + 1.0) / (count + 1.0) - randf_range(-15.0, 15.0)
		var x := randf_range(-14.0, 14.0)
		pending_objectives.append([kinds[i], Vector3(x, 0.0, z)])
		var side := 1.0 if x < 0.0 else -1.0
		pending.append([SamScene, Vector3(x + side * randf_range(22.0, 30.0), 0.0, z - randf_range(8.0, 16.0))])
	var light: int = plan().sams
	var heavy: int = plan().heavy
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
			sams.append(spawn(entry[0], at))
	for entry in pending_objectives.duplicate():
		var at: Vector3 = entry[1]
		if at.z > focus_z - spawn_ahead:
			pending_objectives.erase(entry)
			spawn_objective(entry[0], at)


func spawn_objective(kind: String, at: Vector3) -> void:
	var objective := TravelObjective.new()
	objective.kind = kind
	# Placed before it builds: a convoy lines up from its own position.
	objective.position = Vector3(at.x, 0.0, at.z)
	mission.world.add_child(objective)
	objectives.append(objective)
	objective_nodes.append([stretch, objective])
	objective.cleared.connect(func() -> void: objectives.erase(objective))
	objective.escaped.connect(func(scene_path: String) -> void:
		escaped.append(scene_path)
		convoy_escaped.emit())
	var area := Rect2(at.x - 22.0, at.z - objective.depth * 0.5 - 4.0, 44.0, objective.depth + 8.0)
	if kind == "convoy":
		area = Rect2(-corridor_half_width, at.z - 6.0, corridor_half_width * 2.0, 12.0)
	clear_areas.append(area)
	for environment in terrain():
		environment.clear_area(area)


# How far forward the view may go: the rearmost live SAM truck stays
# sam_hold behind its centre, and so does the back of each objective still
# standing (-INF with none). Sets holder to what's holding it.
func gate() -> float:
	sams = sams.filter(func(unit: Variant) -> bool:
		return is_instance_valid(unit) and unit.is_in_group("enemies"))
	var limit := -INF
	holder = ""
	for sam: Node3D in sams:
		if sam.global_position.z - sam_hold > limit:
			limit = sam.global_position.z - sam_hold
			holder = "SAMS"
	for objective: TravelObjective in objectives:
		if objective.rear_z() - sam_hold > limit:
			limit = objective.rear_z() - sam_hold
			holder = objective.display_name()
	return limit


# --- Arena -----------------------------------------------------------------------

# The stretch's waves (see PLAN).
func plan_waves() -> Array:
	var planned: Array = []
	for budget: float in plan().waves:
		planned.append(make_wave(budget))
	return planned


# Helicopters for a budget: a scout costs 1, a gunship 2 (likelier later
# on).
func make_wave(budget: float) -> Array:
	var wave: Array = []
	var left := budget
	while left >= 1.0:
		if left >= 2.0 and randf() < 0.35 + stretch * 0.08:
			wave.append(GunshipScene)
			left -= 2.0
		else:
			wave.append(ScoutScene)
			left -= 1.0
	return wave


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
	# Convoy vehicles that got away hold the city's crossroads.
	var city: City = cities.get(stretch)
	if city != null:
		for scene_path in escaped:
			var vehicle := (load(scene_path) as PackedScene).instantiate() as Node3D
			vehicle.set("dug_in", true)
			mission.world.add_child(vehicle)
			vehicle.global_position = city.road_spot()
		escaped.clear()
	next_wave()
	scout_timer = scout_interval
	arena_started.emit(stretch)


# Helicopters come in from beyond the top of the screen and the sides.
func next_wave() -> void:
	var wave: Array = waves.pop_front()
	wave_units.clear()
	for i in wave.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := Vector3(side * randf_range(20.0, 60.0), 0.0, arena_z - arena_half_depth - randf_range(25.0, 45.0))
		wave_units.append(spawn(wave[i], at))


# While a city's targets stand, a scout flies in every scout_interval
# whenever fewer than the stretch's limit are up (see PLAN).
func trickle_scouts() -> void:
	scout_timer -= get_physics_process_delta_time()
	if scout_timer > 0.0:
		return
	if get_tree().get_nodes_in_group("air_enemies").size() >= plan().scouts:
		return
	scout_timer = scout_interval
	var side := -1.0 if randf() < 0.5 else 1.0
	spawn(ScoutScene, Vector3(side * randf_range(20.0, 60.0), 0.0, arena_z - arena_half_depth - randf_range(25.0, 45.0)))


func update_arena() -> void:
	wave_units = wave_units.filter(func(unit: Variant) -> bool:
		return is_instance_valid(unit) and unit.is_in_group("enemies"))
	var city: City = cities.get(stretch)
	var defending := city != null and city.targets_left() > 0
	if defending:
		trickle_scouts()
	if not wave_units.is_empty():
		wave_timer = wave_gap
		return
	# The next planned wave, a beat after the last: over open ground every
	# one comes, over a city only while it still has targets.
	if not waves.is_empty() and (defending or city == null):
		wave_timer -= get_physics_process_delta_time()
		if wave_timer <= 0.0:
			next_wave()
		return
	if defending or not get_tree().get_nodes_in_group("air_enemies").is_empty():
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


# The stretch's city (see PLAN), sized by its blocks: from a village up
# to a town filling the arena. Open ground has none.
func build_city(index: int) -> void:
	var layout: Array = plan().city
	if layout.is_empty():
		targets_changed.emit(0, 0)
		return
	var city := City.new()
	city.columns = layout[0]
	city.rows = layout[1]
	city.target_count = layout[2]
	city.extent = Vector2(city.columns * 18.5 + (city.columns - 1) * city.road_width, city.rows * 16.0 + (city.rows - 1) * city.road_width)
	mission.world.add_child(city)
	city.position = Vector3(0.0, 0.0, arena_z)
	cities[index] = city
	city.targets_changed.connect(func(left: int, total: int) -> void:
		if index == stretch:
			targets_changed.emit(left, total))
	targets_changed.emit(city.target_count, city.target_count)

	var area := Rect2(-city.extent.x * 0.5, arena_z - city.extent.y * 0.5, city.extent.x, city.extent.y)
	clear_areas.append(area)
	for environment in terrain():
		environment.clear_area(area)


# Every DesertEnvironment in play: the mission's own and the streamed ones.
func terrain() -> Array:
	return mission.world.find_children("*", "DesertEnvironment", true, false)


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
		for area in clear_areas:
			environment.clear_area(area)
		environments[index] = environment
	for index in environments.keys():
		if index < stretch - 1:
			environments[index].queue_free()
			environments.erase(index)
	for index in cities.keys():
		if index < stretch - 1:
			cities[index].queue_free()
			cities.erase(index)
	for entry in objective_nodes.duplicate():
		if entry[0] < stretch - 1:
			entry[1].queue_free()
			objective_nodes.erase(entry)
