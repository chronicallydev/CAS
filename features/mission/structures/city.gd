class_name City
extends Node3D

# A small city for a lock arena (see DESIGN.md): a grid of dark roads with
# blocks of houses, apartment blocks and warehouses, all destructible
# (building.gd). A few lots hold marked targets (HQ, radar, ammo dump);
# the arena holds until they're destroyed. Laid out at random, centred
# on this node, filling `extent` (x, z) metres.

signal targets_changed(left: int, total: int)

const P := preload("res://shared/props/prop_builder.gd")
const TARGET_KINDS := ["hq", "radar", "ammo_dump"]

@export var extent: Vector2 = Vector2(92.0, 60.0)
@export var target_count: int = 3
@export var road_width: float = 6.0
# Blocks along x and z.
@export var columns: int = 4
@export var rows: int = 3
@export var ground_y: float = -0.408

var targets: Array[Building] = []
var buildings: Array[Building] = []


func _ready() -> void:
	add_to_group("cities")
	build_roads()
	build_blocks()


func targets_left() -> int:
	return targets.filter(func(b: Building) -> bool: return b.stage != Building.Stage.COLLAPSED).size()


## A random crossroads inside the city, in world space.
func road_spot() -> Vector3:
	var block := block_size()
	var column := randi_range(0, columns - 2)
	var row := randi_range(0, rows - 2)
	var x := -extent.x * 0.5 + (column + 1) * (block.x + road_width) - road_width * 0.5
	var z := -extent.y * 0.5 + (row + 1) * (block.y + road_width) - road_width * 0.5
	return to_global(Vector3(x, 0.0, z))


func block_size() -> Vector2:
	return Vector2((extent.x - road_width * (columns - 1)) / columns, (extent.y - road_width * (rows - 1)) / rows)


func block_centre(column: int, row: int) -> Vector3:
	var block := block_size()
	return Vector3(-extent.x * 0.5 + block.x * 0.5 + column * (block.x + road_width), 0.0,
		-extent.y * 0.5 + block.y * 0.5 + row * (block.y + road_width))


# Dark asphalt between the blocks (and round the edge), so the grid reads
# in 1-bit against pale walls and sand.
func build_roads() -> void:
	var asphalt := Building.material(Color(0.26, 0.25, 0.25))
	var block := block_size()
	var y := ground_y + 0.03
	for column in range(-1, columns):
		var x := -extent.x * 0.5 + (column + 1) * (block.x + road_width) - road_width * 0.5
		P.box(self, Vector3(road_width, 0.06, extent.y + road_width * 2.0), Vector3(x, y, 0), asphalt).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for row in range(-1, rows):
		var z := -extent.y * 0.5 + (row + 1) * (block.y + road_width) - road_width * 0.5
		P.box(self, Vector3(extent.x + road_width * 2.0, 0.06, road_width), Vector3(0, y + 0.005, z), asphalt).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func build_blocks() -> void:
	# Targets go in blocks spread across the grid.
	var lots: Array = []
	for column in columns:
		for row in rows:
			lots.append(Vector2i(column, row))
	lots.shuffle()
	var target_lots := lots.slice(0, mini(target_count, lots.size()))
	var kinds := TARGET_KINDS.duplicate()
	kinds.shuffle()

	var block := block_size()
	for lot: Vector2i in lots:
		var centre := block_centre(lot.x, lot.y)
		var index := target_lots.find(lot)
		if index >= 0:
			var kind: String = kinds[index % kinds.size()]
			var footprint := Vector2(minf(block.x - 4.0, 14.0), minf(block.y - 4.0, 12.0))
			var building := add_building(Building.make(kind, footprint, true), centre, 0.0)
			targets.append(building)
			building.destroyed.connect(func(_b: Building) -> void:
				targets_changed.emit(targets_left(), targets.size()))
			continue
		fill_block(centre, block)


# Splits a block into two or three lots along its long side and puts a
# building on each (or leaves a yard).
func fill_block(centre: Vector3, block: Vector2) -> void:
	var along_x := block.x >= block.y
	var long_side := block.x if along_x else block.y
	var count := randi_range(2, 3)
	var lot_long := long_side / count
	for k in count:
		var offset := -long_side * 0.5 + lot_long * (k + 0.5)
		var lot := Vector2(lot_long, block.y) if along_x else Vector2(block.x, lot_long)
		var at := centre + (Vector3(offset, 0, 0) if along_x else Vector3(0, 0, offset))
		var roll := randf()
		if roll < 0.22:
			continue
		var kind := "house" if roll < 0.62 else ("block" if roll < 0.87 else "warehouse")
		var footprint := Vector2(lot.x - randf_range(1.5, 3.0), lot.y - randf_range(1.5, 3.0))
		if kind == "house":
			footprint = footprint.min(Vector2(9.0, 9.0))
		add_building(Building.make(kind, footprint), at, 0.0)


func add_building(building: Building, at: Vector3, yaw: float) -> Building:
	building.ground_y = ground_y
	building.position = at
	building.rotation.y = yaw
	add_child(building)
	buildings.append(building)
	return building
