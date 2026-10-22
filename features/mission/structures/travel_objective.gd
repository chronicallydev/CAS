class_name TravelObjective
extends Node3D

# A small objective on a travel stretch (see DESIGN.md), built from tanks,
# infantry and buildings, with the stretch's SAMs nearby. The run director
# holds the view on it until it's cleared:
#   compound  - a walled yard with a few buildings, dug-in tanks and
#               riflemen; the buildings and tanks must go
#   convoy    - tanks and trucks crossing the screen once it comes into
#               view; any that drive off the side get away (escaped) and
#               turn up again in the stretch's city
#   depot     - fuel tanks that set each other off, with a few guards
#   tank_line - dug-in tanks behind berms, riflemen in a trench behind
#   patrol    - a few riflemen and a car wandering about, coming at you
#               with their usual moves (the early stretches)
#   armored_patrol - the same with a tank along
# Units go into the mission world like any other enemy; buildings and
# scenery are children of this node.

signal cleared
signal escaped(scene_path: String)

const P := preload("res://shared/props/prop_builder.gd")
const TankScene := preload("res://features/mission/enemies/tank.tscn")
const CarScene := preload("res://features/mission/enemies/car.tscn")
const InfantryScene := preload("res://features/mission/enemies/infantry.tscn")

const KINDS := ["compound", "convoy", "depot", "tank_line", "patrol", "armored_patrol"]
const NAMES := {"compound": "COMPOUND", "convoy": "CONVOY", "depot": "FUEL DEPOT", "tank_line": "TANK LINE",
		"patrol": "PATROL", "armored_patrol": "PATROL"}

@export_enum("compound", "convoy", "depot", "tank_line", "patrol", "armored_patrol") var kind: String = "compound"
@export var convoy_speed: float = 6.0
# The convoy sets off once the view centre is this close to it, and a
# vehicle this far out to the side has got away.
@export var convoy_start: float = 30.0
@export var escape_x: float = 58.0
# Ground depth it takes up, for holding the view.
@export var depth: float = 24.0
@export var ground_y: float = -0.408

var mission: MissionContext
# What has to be destroyed.
var parts: Array = []
# Convoy vehicles and which way they drive (+1 or -1 along x).
var movers: Array = []
var convoy_direction: float = 1.0
var moving: bool = false
var done: bool = false


func _ready() -> void:
	mission = MissionContext.of(self)
	match kind:
		"convoy": build_convoy()
		"depot": build_depot()
		"tank_line": build_tank_line()
		"patrol": build_patrol(false)
		"armored_patrol": build_patrol(true)
		_: build_compound()


func display_name() -> String:
	return NAMES.get(kind, "TARGET")


## Furthest-back z the view must keep on screen while this stands: its
## own back edge, or a part that has wandered further back.
func rear_z() -> float:
	var rear := global_position.z + depth * 0.5
	for part in parts:
		if alive(part):
			rear = maxf(rear, part.global_position.z + 4.0)
	return rear


func _physics_process(delta: float) -> void:
	if done:
		return
	if kind == "convoy":
		drive(delta)
	parts = parts.filter(alive)
	if parts.is_empty():
		done = true
		cleared.emit()


func alive(part: Variant) -> bool:
	if not is_instance_valid(part):
		return false
	if part is Building:
		return part.stage != Building.Stage.COLLAPSED
	return part.is_in_group("enemies")


func drive(delta: float) -> void:
	if not moving:
		if mission == null or mission.camera_rig.get_focus().z - global_position.z > convoy_start:
			return
		moving = true
	for vehicle in movers.duplicate():
		if not alive(vehicle):
			movers.erase(vehicle)
			continue
		vehicle.global_position.x += convoy_direction * convoy_speed * delta
		if absf(vehicle.global_position.x) > escape_x:
			movers.erase(vehicle)
			parts.erase(vehicle)
			escaped.emit(vehicle.scene_file_path)
			vehicle.queue_free()


# --- Builds --------------------------------------------------------------------

func build_compound() -> void:
	depth = 26.0
	var wall := Building.material(Color(0.62, 0.6, 0.56))
	# A low yard wall with a gap facing the player.
	for side in [-1.0, 1.0]:
		P.box(self, Vector3(0.8, 1.4, 22.0), Vector3(side * 16.0, ground_y + 0.7, 0), wall)
		P.box(self, Vector3(12.0, 1.4, 0.8), Vector3(side * 10.0, ground_y + 0.7, 11.0), wall)
	P.box(self, Vector3(32.0, 1.4, 0.8), Vector3(0, ground_y + 0.7, -11.0), wall)
	var kinds := ["warehouse", "house", "block"]
	kinds.shuffle()
	var spots := [Vector3(-8.0, 0, -4.0), Vector3(7.0, 0, -5.0), Vector3(0.0, 0, 3.0)]
	for i in randi_range(2, 3):
		var footprint := Vector2(9.0, 7.0) if kinds[i] != "house" else Vector2(7.0, 7.0)
		parts.append(add_building(Building.make(kinds[i], footprint), spots[i]))
	parts.append(unit(TankScene, Vector3(-12.0, 0, 7.0)))
	parts.append(unit(TankScene, Vector3(12.0, 0, 7.0)))
	for i in 4:
		unit(InfantryScene, Vector3(randf_range(-12.0, 12.0), 0, randf_range(5.0, 9.0)))


func build_convoy() -> void:
	depth = 14.0
	convoy_direction = 1.0 if randf() < 0.5 else -1.0
	var dirt := Building.material(Color(0.5, 0.42, 0.33))
	P.box(self, Vector3(140.0, 0.05, 7.0), Vector3(-global_position.x, ground_y + 0.02, 0), dirt).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var column := [TankScene, CarScene, CarScene, TankScene] if randf() < 0.5 else [CarScene, TankScene, CarScene, CarScene, TankScene]
	# Lined up behind the lead vehicle, which starts on screen near the
	# edge it drives away from.
	for i in column.size():
		var x := -convoy_direction * (30.0 + i * 9.0) - global_position.x
		var vehicle := unit(column[i], Vector3(x, 0, 0))
		vehicle.rotation.y = -convoy_direction * PI * 0.5
		movers.append(vehicle)
		parts.append(vehicle)


func build_depot() -> void:
	depth = 26.0
	var concrete := Building.material(Color(0.66, 0.64, 0.6))
	P.box(self, Vector3(34.0, 0.2, 24.0), Vector3(0, ground_y + 0.1, 0), concrete)
	for column in range(-1, 2):
		for row in range(2):
			if randf() < 0.2:
				continue
			var at := Vector3(column * 11.0, 0, -5.5 + row * 11.0)
			parts.append(add_building(Building.make("fuel_tank", Vector2(8.0, 8.0)), at))
	if parts.is_empty():
		parts.append(add_building(Building.make("fuel_tank", Vector2(8.0, 8.0)), Vector3.ZERO))
	var pipe := Building.material(Color(0.4, 0.4, 0.42))
	for row in range(2):
		P.pipe(self, Vector3(-13.0, ground_y + 0.8, -5.5 + row * 11.0), Vector3(13.0, ground_y + 0.8, -5.5 + row * 11.0), 0.3, pipe)
	for i in 3:
		unit(InfantryScene, Vector3(randf_range(-15.0, 15.0), 0, 13.0))


func build_tank_line() -> void:
	depth = 18.0
	var berm := Building.material(Color(0.42, 0.36, 0.3))
	var count := randi_range(3, 4)
	for i in count:
		var x := (i - (count - 1) * 0.5) * 12.0
		P.box(self, Vector3(7.0, 1.3, 1.6), Vector3(x, ground_y + 0.65, 3.8), berm)
		parts.append(unit(TankScene, Vector3(x, 0, 0)))
	# The trench: a dark strip with riflemen along it.
	P.box(self, Vector3(count * 12.0, 0.05, 2.4), Vector3(0, ground_y + 0.02, -6.0), Building.material(Color(0.2, 0.18, 0.17))).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in count + 2:
		unit(InfantryScene, Vector3(randf_range(-0.5, 0.5) * count * 12.0, 0, -6.0))


func build_patrol(armored: bool) -> void:
	depth = 20.0
	var squad: Array = [InfantryScene, InfantryScene, InfantryScene, CarScene]
	if armored:
		squad = [InfantryScene, InfantryScene, CarScene, TankScene]
	for scene: PackedScene in squad:
		var node := unit(scene, Vector3(randf_range(-16.0, 16.0), 0, randf_range(-8.0, 8.0)))
		# On the move, not dug in.
		node.set("dug_in", false)
		parts.append(node)


func add_building(building: Building, at: Vector3) -> Building:
	building.ground_y = ground_y
	building.position = at
	add_child(building)
	return building


# A unit in the mission world at `at` (local), dug in, facing the player.
func unit(scene: PackedScene, at: Vector3) -> Node3D:
	var node := scene.instantiate() as Node3D
	node.set("dug_in", true)
	MissionContext.spawn_parent(self).add_child(node)
	node.global_position = to_global(at) + Vector3(0, 0.4, 0)
	node.rotation.y = PI
	return node
