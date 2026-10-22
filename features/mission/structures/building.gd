class_name Building
extends Node3D

# A building that can be shot down, in stages (see DESIGN.md):
#   intact   - hits chip bits off the side facing the gun
#   damaged  - below 2/3 health: roof clutter is blown off, it smokes
#   burning  - below 1/3: fire and a black smoke column
#   collapse - it sinks into a cloud of dust, throwing chunks, and leaves
#              smoking rubble. Soldiers inside run out; an explosive one
#              (ammo dump, fuel tank) blows up and hits everything around
#              it, so buildings can set each other off.
# It isn't an enemy: weapons find it in the "structures" group and measure
# blasts against its footprint (ground_distance), so rounds anywhere on
# the roof count. A box collider lets the reticle land on the roof.
# Marked targets (target = true) are drawn in ink with a marker overhead.
# Everything is built in code from `kind` and `size`.

signal destroyed(building: Building)

const P := preload("res://shared/props/prop_builder.gd")
const Debris := preload("res://features/mission/effects/debris.gd")
const JavelinExplosion := preload("res://features/mission/vfx/javelin_explosion.gd")
const InfantryScene := preload("res://features/mission/enemies/infantry.tscn")

const KINDS := ["house", "block", "warehouse", "hq", "radar", "ammo_dump", "fuel_tank"]
# Stage thresholds, as fractions of max_health.
const DAMAGED := 0.66
const BURNING := 0.33
# Fastest rate chips fly off.
const CHIP_INTERVAL_MS := 60

@export_enum("house", "block", "warehouse", "hq", "radar", "ammo_dump", "fuel_tank") var kind: String = "house"
# Footprint (x, z) and height, in metres.
@export var size: Vector3 = Vector3(8.0, 5.0, 8.0)
@export var target: bool = false
@export var max_health: float = 40.0
# Fraction of minigun damage the walls soak up.
@export_range(0.0, 1.0, 0.01) var light_armor: float = 0.5
@export var score_value: int = 25
@export var display_name: String = "BUILDING"
# Soldiers that run out when it comes down.
@export var occupants: int = 0
@export var explosive: bool = false
@export var blast_radius: float = 16.0
@export var blast_damage: float = 30.0
# Height of the ground surface.
@export var ground_y: float = -0.408

enum Stage { INTACT, DAMAGED, BURNING, COLLAPSED }

static var materials: Dictionary = {}

var health: float = 0.0
var stage: Stage = Stage.INTACT
var mission: MissionContext
# The standing building (sinks on collapse) and its roof clutter, thrown
# off as it takes damage.
var body: Node3D
var loose: Array[Node3D] = []
var collider: StaticBody3D
var marker: Node3D
var smoke: CPUParticles3D
var fire: CPUParticles3D
var wall: Material
var last_chip_ms: int = -100000
var last_hit_from: Vector3 = Vector3.ZERO
var time: float = 0.0
var spinner: Node3D


func _ready() -> void:
	mission = MissionContext.of(self)
	add_to_group("structures")
	health = max_health
	position.y = ground_y
	time = randf() * TAU
	body = Node3D.new()
	add_child(body)
	build_body()
	if target:
		OneBit.ink(body)
		build_marker()
	add_collider()


# --- Model ---------------------------------------------------------------------

static func material(color: Color) -> StandardMaterial3D:
	if not materials.has(color):
		materials[color] = P.material(color, 0.95)
	return materials[color]


func build_body() -> void:
	# Targets get their own copies, so inking them leaves the city's
	# shared materials alone.
	var light := Color(0.84, 0.8, 0.72) if randf() < 0.6 else Color(0.74, 0.7, 0.64)
	wall = P.material(light, 0.95) if target else material(light)
	var roof: Material = P.material(Color(0.5, 0.48, 0.45), 0.95) if target else material(Color(0.5, 0.48, 0.45))
	var band: Material = P.material(Color(0.18, 0.18, 0.2), 0.95) if target else material(Color(0.18, 0.18, 0.2))
	var h := size.y
	match kind:
		"house":
			P.box(body, Vector3(size.x, h, size.z), Vector3(0, h * 0.5, 0), wall)
			P.box(body, Vector3(size.x + 0.4, 0.4, size.z + 0.4), Vector3(0, h + 0.2, 0), roof)
			add_band(band, h * 0.55, 0.7)
			loose_cylinder(0.9, 1.4, Vector3(size.x * 0.22, h + 1.1, -size.z * 0.2), band)
			loose_box(Vector3(1.4, 0.8, 1.0), Vector3(-size.x * 0.25, h + 0.8, size.z * 0.2), roof)
		"block":
			P.box(body, Vector3(size.x, h, size.z), Vector3(0, h * 0.5, 0), wall)
			P.box(body, Vector3(size.x + 0.3, 0.5, size.z + 0.3), Vector3(0, h + 0.25, 0), roof)
			var floor_y := 2.0
			while floor_y < h - 0.8:
				add_band(band, floor_y, 0.8)
				floor_y += 3.0
			loose_box(Vector3(2.4, 1.6, 2.4), Vector3(size.x * 0.25, h + 1.3, 0), wall)
			loose_box(Vector3(1.2, 0.7, 1.2), Vector3(-size.x * 0.3, h + 0.85, size.z * 0.25), roof)
			loose_box(Vector3(0.15, 3.5, 0.15), Vector3(-size.x * 0.3, h + 2.2, -size.z * 0.3), band)
		"warehouse":
			P.box(body, Vector3(size.x, h, size.z), Vector3(0, h * 0.5, 0), wall)
			# A pitched roof: two slabs meeting along the ridge.
			var pitch := 18.0
			for side in [-1.0, 1.0]:
				P.box(body, Vector3(size.x + 0.4, 0.35, size.z * 0.54), Vector3(0, h + 0.7, side * size.z * 0.25), roof, Vector3(side * pitch, 0, 0))
			P.box(body, Vector3(size.x * 0.3, h * 0.6, 0.2), Vector3(0, h * 0.3, size.z * 0.5 + 0.1), band)
			for k in 3:
				loose_cylinder(0.4, 1.0, Vector3((k - 1) * size.x * 0.3, h + 1.8, 0), band)
		"hq":
			P.box(body, Vector3(size.x, h * 0.6, size.z), Vector3(0, h * 0.3, 0), wall)
			P.box(body, Vector3(size.x * 0.6, h * 0.4, size.z * 0.6), Vector3(0, h * 0.8, 0), wall)
			P.box(body, Vector3(size.x * 0.64, 0.4, size.z * 0.64), Vector3(0, h + 0.2, 0), roof)
			add_band(band, h * 0.3, 0.8)
			loose_box(Vector3(0.25, 6.0, 0.25), Vector3(size.x * 0.15, h + 3.0, 0), band)
			loose_box(Vector3(2.4, 0.2, 0.2), Vector3(size.x * 0.15, h + 5.0, 0), band)
			loose_cylinder(1.1, 0.3, Vector3(-size.x * 0.15, h + 0.6, size.z * 0.1), band)
		"radar":
			P.box(body, Vector3(size.x, h * 0.5, size.z), Vector3(0, h * 0.25, 0), wall)
			P.cylinder(body, 0.6, h * 0.5, Vector3(0, h * 0.75, 0), band)
			# The dish turns (see _process) until it's shot off.
			spinner = Node3D.new()
			spinner.position = Vector3(0, h + 0.3, 0)
			body.add_child(spinner)
			P.cylinder(spinner, size.x * 0.42, 0.35, Vector3(0, 1.4, 0), wall, Vector3(70, 0, 0), 20)
			P.box(spinner, Vector3(0.3, 2.2, 0.3), Vector3(0, 0.8, -0.6), band, Vector3(30, 0, 0))
			loose.append(spinner)
		"ammo_dump":
			# Earth-banked bunkers and crate stacks: no walls to chip.
			for k in 3:
				var at := Vector3((k - 1) * size.x * 0.32, 0.0, (k % 2) * size.z * 0.2 - size.z * 0.1)
				P.sphere(body, 1.0, at, roof, Vector3(size.x * 0.17, h * 0.8, size.z * 0.3))
				P.box(body, Vector3(1.4, 1.2, 0.2), at + Vector3(0, 0.6, size.z * 0.3), band)
			for k in 4:
				loose_box(Vector3(1.1, 0.8, 1.1), Vector3(randf_range(-0.4, 0.4) * size.x, 0.4 + (k % 2) * 0.8, size.z * 0.42), wall)
		"fuel_tank":
			P.cylinder(body, size.x * 0.5, h, Vector3(0, h * 0.5, 0), wall, Vector3.ZERO, 24)
			P.cylinder(body, size.x * 0.505, 0.6, Vector3(0, h * 0.65, 0), band, Vector3.ZERO, 24)
			P.cylinder(body, size.x * 0.45, 0.3, Vector3(0, h + 0.15, 0), roof, Vector3.ZERO, 24)
			loose_box(Vector3(0.3, h, 0.3), Vector3(size.x * 0.52, h * 0.5, 0), band)


# A dark band of windows around the walls at height y.
func add_band(mat: Material, y: float, height: float) -> void:
	P.box(body, Vector3(size.x + 0.12, height, size.z * 0.7), Vector3(0, y, 0), mat)
	P.box(body, Vector3(size.x * 0.7, height, size.z + 0.12), Vector3(0, y, 0), mat)


func loose_box(box_size: Vector3, at: Vector3, mat: Material) -> void:
	loose.append(P.box(body, box_size, at, mat))


func loose_cylinder(radius: float, height: float, at: Vector3, mat: Material) -> void:
	loose.append(P.cylinder(body, radius, height, at, mat))


# A downward arrow over a marked target: white with a black rim, so it
# reads on any ground in 1-bit.
func build_marker() -> void:
	marker = Node3D.new()
	marker.position = Vector3(0, size.y + 6.0, 0)
	add_child(marker)
	var arrow := CylinderMesh.new()
	arrow.top_radius = 1.6
	arrow.bottom_radius = 0.0
	arrow.height = 2.6
	arrow.radial_segments = 4
	arrow.rings = 1
	P.add_mesh(marker, arrow, Vector3.ZERO, OneBit.solid(Color.WHITE))
	OneBit.rim(marker, Color.BLACK, 0.45)


func add_collider() -> void:
	collider = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, size.y * 0.5, 0)
	collider.add_child(shape)
	add_child(collider)


func _process(delta: float) -> void:
	time += delta
	if marker != null:
		marker.position.y = size.y + 6.0 + sin(time * 3.0) * 0.6
		marker.rotation.y += delta * 1.5
	if spinner != null and is_instance_valid(spinner) and spinner.get_parent() == body:
		spinner.rotation.y += delta * 1.2


# --- Damage --------------------------------------------------------------------

# Ground distance from `at` to the footprint (0 inside it).
func ground_distance(at: Vector3) -> float:
	var local := to_local(at)
	var dx := maxf(absf(local.x) - size.x * 0.5, 0.0)
	var dz := maxf(absf(local.z) - size.z * 0.5, 0.0)
	return Vector2(dx, dz).length()


func set_last_hit(from: Vector3, _force: float, _light_weapon: bool) -> void:
	last_hit_from = from


func take_damage(amount: float, light_weapon: bool = false) -> bool:
	if stage == Stage.COLLAPSED:
		return false
	if light_weapon:
		amount *= 1.0 - light_armor
	health -= amount
	var fraction := health / maxf(max_health, 0.001)
	if stage < Stage.DAMAGED and fraction < DAMAGED:
		enter_damaged()
	if stage < Stage.BURNING and fraction < BURNING:
		enter_burning()
	if health <= 0.0:
		collapse()
		return true
	return false


# A chip off the side facing the shot (or the roof, from high up).
func register_hit(from: Vector3, _light_weapon: bool) -> void:
	var now := Time.get_ticks_msec()
	if now - last_chip_ms < CHIP_INTERVAL_MS:
		return
	last_chip_ms = now
	var local := to_local(from)
	var normal := Vector3.ZERO
	var point := Vector3(randf_range(-0.5, 0.5) * size.x, randf_range(0.3, 1.0) * size.y, randf_range(-0.5, 0.5) * size.z)
	if absf(local.x) / size.x > absf(local.z) / size.z:
		normal = Vector3(signf(local.x), 0, 0)
		point.x = normal.x * size.x * 0.5
	else:
		normal = Vector3(0, 0, signf(local.z))
		point.z = normal.z * size.z * 0.5
	if randf() < 0.4:
		normal = Vector3.UP
		point.y = size.y
	var scene := MissionContext.spawn_parent(self)
	Debris.spawn_chip(scene, to_global(point), global_transform.basis * normal, wall)
	if randf() < 0.2:
		Debris.spawn_dust(scene, to_global(point), 0.8)


func enter_damaged() -> void:
	stage = Stage.DAMAGED
	throw_loose(ceili(loose.size() * 0.5))
	smoke = make_emitter(Color.BLACK, Color.WHITE, 14, 2.2, 0.9, 3.0)
	Sfx.play_3d("base_hit", global_position, -4.0)


func enter_burning() -> void:
	stage = Stage.BURNING
	throw_loose(loose.size())
	if smoke != null:
		smoke.amount = 30
	fire = make_emitter(Color.WHITE, Color.BLACK, 18, 0.7, 1.1, 2.0)
	Sfx.play_3d("explosion_small", global_position + Vector3(0, size.y, 0))


func throw_loose(count: int) -> void:
	for i in count:
		if loose.is_empty():
			return
		var piece: Node3D = loose.pop_back()
		if not is_instance_valid(piece):
			continue
		var away := piece.global_position - global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
		Debris.throw_node(piece, away * randf_range(3.0, 7.0) + Vector3.UP * randf_range(8.0, 13.0), randf_range(5.0, 10.0), 5.0, true, true)


# Smoke or fire puffs rising off the roof, spread over the footprint.
func make_emitter(fill: Color, rim: Color, amount: int, life: float, puff_size: float, rise: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = life
	particles.local_coords = false
	particles.position = Vector3(0, size.y, 0)
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(size.x * 0.35, 0.3, size.z * 0.35)
	particles.direction = Vector3.UP
	particles.spread = 15.0
	particles.gravity = Vector3(0, rise, 0)
	particles.initial_velocity_min = 0.5
	particles.initial_velocity_max = 1.5
	particles.scale_amount_min = puff_size * 0.8
	particles.scale_amount_max = puff_size * 1.6
	particles.scale_amount_curve = Debris.shrink_curve()
	particles.mesh = OneBit.puff(fill, rim, 0.6)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.emitting = true
	add_child(particles)
	return particles


# --- Collapse ------------------------------------------------------------------

func collapse() -> void:
	stage = Stage.COLLAPSED
	health = 0.0
	remove_from_group("structures")
	collider.queue_free()
	if marker != null:
		marker.queue_free()
		marker = null
	throw_loose(loose.size())
	var scene := MissionContext.spawn_parent(self)
	var centre := global_position + Vector3(0, size.y * 0.4, 0)

	if mission != null:
		mission.shake(0.35 + minf(size.y, 12.0) * 0.03, centre)
	Sfx.play_3d("base_hit", centre)
	Sfx.play_3d("explosion_small", centre, 0.0, 0.7)

	# Dust rolling out from the base.
	for k in 6:
		var at := Vector3(randf_range(-0.6, 0.6) * size.x, 0.6, randf_range(-0.6, 0.6) * size.z)
		Debris.spawn_dust(scene, to_global(at), randf_range(2.2, 3.2))
	throw_chunks(scene)

	# Sinks down into its own dust, leaning a little.
	var tween := create_tween().set_parallel()
	tween.tween_property(body, "position:y", -size.y * 0.95, 1.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(body, "rotation", Vector3(randf_range(-0.12, 0.12), 0, randf_range(-0.12, 0.12)), 1.3)
	tween.chain().tween_callback(func() -> void:
		body.queue_free()
		build_rubble())

	if smoke == null:
		smoke = make_emitter(Color.BLACK, Color.WHITE, 30, 2.2, 0.9, 3.0)
	smoke.position.y = 1.0
	if fire != null:
		fire.position.y = 0.8
	# The smoke thins out and stops after a while.
	get_tree().create_timer(9.0, false).timeout.connect(func() -> void:
		for emitter in [smoke, fire]:
			if emitter != null and is_instance_valid(emitter):
				emitter.emitting = false)

	if explosive:
		explode()
	release_occupants()
	destroyed.emit(self)


# Chunks of wall thrown out as it comes down.
func throw_chunks(scene: Node) -> void:
	var count := clampi(int(size.x * size.z / 20.0), 3, 8)
	for k in count:
		if not Debris.can_spawn():
			return
		var chunk := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(randf_range(0.8, 1.8), randf_range(0.5, 1.2), randf_range(0.8, 1.8))
		chunk.mesh = mesh
		chunk.material_override = wall
		scene.add_child(chunk)
		var at := Vector3(randf_range(-0.5, 0.5) * size.x, randf_range(0.5, 1.0) * size.y, randf_range(-0.5, 0.5) * size.z)
		chunk.global_position = to_global(at)
		var away := Vector3(at.x, 0, at.z).normalized() if Vector2(at.x, at.z).length() > 0.1 else Vector3.FORWARD
		Debris.throw_node(chunk, global_transform.basis * away * randf_range(3.0, 8.0) + Vector3.UP * randf_range(6.0, 12.0), randf_range(4.0, 9.0), randf_range(3.0, 5.0), false, true)


# A low heap of charred blocks and a few wall stubs where it stood.
func build_rubble() -> void:
	var rubble := Node3D.new()
	add_child(rubble)
	var burnt := Debris.get_burnt_material()
	var heaps := clampi(int(size.x * size.z / 12.0), 4, 12)
	for k in heaps:
		var piece := Vector3(randf_range(1.2, 3.0), randf_range(0.4, 1.4), randf_range(1.2, 3.0))
		var at := Vector3(randf_range(-0.42, 0.42) * size.x, piece.y * 0.4, randf_range(-0.42, 0.42) * size.z)
		P.box(rubble, piece, at, burnt if randf() < 0.6 else wall, Vector3(randf_range(-15, 15), randf() * 90.0, randf_range(-15, 15)))
	if kind in ["house", "block", "hq", "warehouse"]:
		# Stubs of wall left standing along the edges.
		for k in 3:
			var height := randf_range(1.0, minf(3.0, size.y * 0.5))
			var side := 1.0 if randf() < 0.5 else -1.0
			if randf() < 0.5:
				P.box(rubble, Vector3(0.5, height, randf_range(1.5, 3.5)), Vector3(side * size.x * 0.48, height * 0.5, randf_range(-0.35, 0.35) * size.z), wall)
			else:
				P.box(rubble, Vector3(randf_range(1.5, 3.5), height, 0.5), Vector3(randf_range(-0.35, 0.35) * size.x, height * 0.5, side * size.z * 0.48), wall)


func explode() -> void:
	var blast := JavelinExplosion.new()
	blast.size = blast_radius / 11.0
	blast.lifetime = 4.0
	blast.volume_db = 2.0
	blast.shake = 0.5
	MissionContext.spawn_parent(self).add_child(blast)
	blast.global_position = global_position + Vector3(0, 1.0, 0)
	if mission != null:
		mission.hit_stop(0.06)
	# A beat later the blast reaches its neighbours, so chains ripple out.
	get_tree().create_timer(0.18, false).timeout.connect(func() -> void:
		if mission != null and mission.guns != null:
			mission.guns.damage_enemies(global_position, blast_radius, blast_damage))


# Soldiers inside run out from the walls.
func release_occupants() -> void:
	var scene := MissionContext.spawn_parent(self)
	for k in occupants:
		var soldier := InfantryScene.instantiate() as Node3D
		scene.add_child(soldier)
		var angle := randf() * TAU
		var out := Vector3(cos(angle), 0, sin(angle))
		var edge := Vector3(out.x * size.x * 0.6, 0.0, out.z * size.z * 0.6)
		soldier.global_position = to_global(edge)
		soldier.rotation.y = atan2(-out.x, -out.z) + global_rotation.y


# --- Presets -------------------------------------------------------------------

## A building of `kind`, sized and tuned for it. Targets are named and
## worth more.
static func make(kind_name: String, footprint: Vector2, as_target: bool = false) -> Building:
	var building := Building.new()
	building.kind = kind_name
	building.target = as_target
	match kind_name:
		"house":
			building.size = Vector3(footprint.x, randf_range(3.5, 5.0), footprint.y)
			building.max_health = 14.0
			building.occupants = randi_range(0, 1)
		"block":
			building.size = Vector3(footprint.x, randf_range(6.0, 8.5), footprint.y)
			building.max_health = 28.0
			building.occupants = randi_range(1, 3)
			building.score_value = 50
		"warehouse":
			building.size = Vector3(footprint.x, randf_range(4.5, 6.0), footprint.y)
			building.max_health = 22.0
			building.score_value = 35
		"hq":
			building.size = Vector3(footprint.x, 9.0, footprint.y)
			building.max_health = 60.0
			building.occupants = 3
			building.display_name = "HQ"
		"radar":
			building.size = Vector3(footprint.x, 5.0, footprint.y)
			building.max_health = 40.0
			building.occupants = 1
			building.display_name = "RADAR"
		"ammo_dump":
			building.size = Vector3(footprint.x, 2.6, footprint.y)
			building.max_health = 36.0
			building.light_armor = 0.4
			building.explosive = true
			building.blast_radius = 20.0
			building.display_name = "AMMO DUMP"
		"fuel_tank":
			building.size = Vector3(footprint.x, randf_range(5.0, 7.0), footprint.x)
			building.max_health = 24.0
			building.light_armor = 0.3
			building.explosive = true
			# Enough to set off the next tank over: depots go up in chains.
			building.blast_damage = 50.0
			building.display_name = "FUEL TANK"
	if as_target:
		building.score_value = 200
	return building
