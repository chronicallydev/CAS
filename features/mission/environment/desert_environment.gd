@tool
class_name DesertEnvironment
extends Node3D

# The battlefield around the rig, in one of several biomes so each rig on
# the campaign map fights somewhere different:
#   desert   - dunes, pumpjacks and a site camp (the home rig)
#   wadi     - a dry riverbed with boulders and date palms
#   saltflat - blinding white salt crust, cracked, nearly bare
#   ridge    - mountains along the north and rocky outcrops
#   refinery - distillation columns and burning flare stacks
#   terminal - the gulf coast: sea, a jetty and a moored tanker
#   oilfield - pumpjacks everywhere, burning wells and oil spills
# The mission context sets the biome from the rig (RigData.biome). Everything is
# placed from a seed, so a biome looks the same every run. Props have no
# collision, so they never block aiming. No storage tanks here: they'd
# pass for a fuel depot (travel_objective.gd) that can't be shot.

const P := preload("res://shared/props/prop_builder.gd")

# Ground colour for each biome (tints the ground mesh beside this node).
const GROUND := {
	"desert": Color(0.72, 0.6, 0.46),
	"wadi": Color(0.74, 0.62, 0.47),
	"saltflat": Color(0.9, 0.87, 0.8),
	"ridge": Color(0.56, 0.5, 0.44),
	"refinery": Color(0.64, 0.55, 0.43),
	"terminal": Color(0.8, 0.7, 0.52),
	"oilfield": Color(0.64, 0.52, 0.39),
}

@export_enum("desert", "wadi", "saltflat", "ridge", "refinery", "terminal", "oilfield") var biome: String = "desert":
	set(value):
		biome = value
		queue_rebuild()
@export var seed_value: int = 1337:
	set(value):
		seed_value = value
		queue_rebuild()
# Height of the ground surface.
@export var ground_y: float = -0.408:
	set(value):
		ground_y = value
		queue_rebuild()
@export var outer_radius: float = 260.0
@export var rock_count: int = 260
@export var shrub_count: int = 320
@export var dune_count: int = 34
@export var pumpjack_count: int = 7

var rng := RandomNumberGenerator.new()
var pumpjacks: Array = [] # [beam pivot, crank pivot, phase]
var flames: Array = [] # [node, phase] - flickering fires
var smoke: Array = [] # [node, base position, phase] - rising smoke puffs
var time: float = 0.0
# Props are kept west of this x (the terminal's sea is to the east).
var land_max_x: float = INF
# Areas kept clear of props (see clear_area), in local x, z.
var clear_zones: Array[Rect2] = []

var sand: StandardMaterial3D
var dirt: StandardMaterial3D
var concrete: StandardMaterial3D
var steel: StandardMaterial3D
var pipe_mat: StandardMaterial3D
var yellow: StandardMaterial3D


var _rebuild_queued: bool = false


func _ready() -> void:
	queue_rebuild()


# Rebuilds once at the end of the frame, however many settings changed
# (the mission context sets the biome right after this node is ready).
func queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return

	for child in get_children():
		child.queue_free()

	pumpjacks.clear()
	flames.clear()
	smoke.clear()
	land_max_x = INF
	build()
	for zone in clear_zones:
		clear_zone(zone)


## Keeps props out of `area` (x, z on the ground, in world space), e.g.
## where a city stands. Props already there are removed.
func clear_area(area: Rect2) -> void:
	var local := Rect2(area.position - Vector2(global_position.x, global_position.z), area.size)
	clear_zones.append(local)
	clear_zone(local)


func clear_zone(zone: Rect2) -> void:
	# Big props reach well past their centre.
	var reach := zone.grow(18.0)
	var doomed: Array[Node] = []
	for child in get_children():
		if child is Node3D and reach.has_point(Vector2(child.position.x, child.position.z)):
			doomed.append(child)
	if doomed.is_empty():
		return
	var gone := func(node: Node) -> bool:
		return doomed.any(func(d: Node) -> bool: return d == node or d.is_ancestor_of(node))
	pumpjacks = pumpjacks.filter(func(entry: Array) -> bool: return not gone.call(entry[0]))
	flames = flames.filter(func(entry: Array) -> bool: return not gone.call(entry[0]))
	smoke = smoke.filter(func(entry: Array) -> bool: return not gone.call(entry[0]))
	for node in doomed:
		node.queue_free()


func build() -> void:
	rng.seed = seed_value

	sand = P.material(Color(0.72, 0.6, 0.46), 1.0)
	dirt = P.material(Color(0.62, 0.48, 0.33), 1.0)
	concrete = P.material(Color(0.66, 0.64, 0.6), 0.95)
	steel = P.material(Color(0.36, 0.38, 0.4), 0.5, 0.6)
	pipe_mat = P.material(Color(0.55, 0.55, 0.52), 0.4, 0.7)
	yellow = P.material(Color(0.95, 0.72, 0.12), 0.6, 0.2)

	tint_ground(GROUND.get(biome, GROUND["desert"]))

	match biome:
		"wadi": build_wadi()
		"saltflat": build_saltflat()
		"ridge": build_ridge()
		"refinery": build_refinery()
		"terminal": build_terminal()
		"oilfield": build_oilfield()
		_: build_desert()


# Recolour the ground mesh that sits next to this node in the scene.
func tint_ground(color: Color) -> void:
	var ground := get_parent().get_node_or_null("CSGMesh3D") as CSGMesh3D if get_parent() != null else null
	if ground == null or ground.material == null:
		return
	var mat: StandardMaterial3D = ground.material.duplicate()
	mat.albedo_color = color
	ground.material = mat


# --- Biomes ----------------------------------------------------------------

func build_desert() -> void:
	build_roads()
	build_dunes()
	build_rocks()
	build_shrubs()
	build_pumpjacks()
	build_camp()


func build_wadi() -> void:
	# The dry riverbed winds past the rig to the south.
	var bed := [Vector3(-260, 0, -70), Vector3(-120, 0, -10), Vector3(-45, 0, 22), Vector3(0, 0, 26),
		Vector3(45, 0, 16), Vector3(110, 0, 40), Vector3(260, 0, 110)]
	var gravel := P.material(Color(0.62, 0.56, 0.46), 1.0)
	var damp := P.material(Color(0.5, 0.44, 0.35), 1.0)
	for i in bed.size() - 1:
		var a: Vector3 = bed[i] + Vector3(0, ground_y, 0)
		var b: Vector3 = bed[i + 1] + Vector3(0, ground_y, 0)
		flat_strip(a, b, 14.0, 0.03, gravel)
		flat_strip(a, b, 5.0, 0.05, damp)
		# Boulders washed down along the banks.
		for k in 10:
			var t := rng.randf()
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var across := (b - a).cross(Vector3.UP).normalized() * side * rng.randf_range(4.0, 8.0)
			var s := rng.randf_range(0.6, 2.0)
			P.sphere(self, 1.0, a.lerp(b, t) + across + Vector3(0, s * 0.2, 0), P.material(Color(0.42, 0.38, 0.33), 1.0), Vector3(s * 1.3, s * 0.7, s))
		# Date palms growing where the water was.
		for k in 3:
			var t := rng.randf()
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var across := (b - a).cross(Vector3.UP).normalized() * side * rng.randf_range(8.0, 13.0)
			build_palm(a.lerp(b, t) + across)

	dune_count = 16
	shrub_count = 520
	rock_count = 320
	pumpjack_count = 4
	build_dunes()
	build_rocks()
	build_shrubs()
	build_pumpjacks()


func build_saltflat() -> void:
	# Cracks in the salt crust: short, thin, slightly darker lines.
	var crack := P.material(Color(0.74, 0.7, 0.62), 1.0)
	for i in 320:
		var pos := random_ground_point(6.0, 150.0)
		var angle := rng.randf() * TAU
		var length := rng.randf_range(3.0, 9.0)
		var dir := Vector3(cos(angle), 0, sin(angle)) * length * 0.5
		flat_strip(pos - dir, pos + dir, rng.randf_range(0.12, 0.25), 0.02, crack)

	# Low salt mounds, bleached white.
	var salt := P.material(Color(0.96, 0.95, 0.9), 1.0)
	for i in 26:
		var pos := random_ground_point(20.0, 160.0)
		var size := Vector3(rng.randf_range(3.0, 7.0), rng.randf_range(0.6, 1.4), rng.randf_range(2.5, 6.0))
		P.sphere(self, 1.0, pos - Vector3(0, size.y * 0.3, 0), salt, size)

	# Dunes only far out on the edge of the flat.
	var dune_mat := P.material(Color(0.8, 0.7, 0.55), 1.0)
	for i in 22:
		var pos := random_ground_point(150.0, outer_radius)
		var size := Vector3(rng.randf_range(18.0, 40.0), rng.randf_range(2.5, 7.0), rng.randf_range(10.0, 22.0))
		P.sphere(self, 1.0, pos - Vector3(0, size.y * 0.35, 0), dune_mat, size).rotation.y = rng.randf() * TAU

	rock_count = 30
	pumpjack_count = 3
	build_rocks()
	build_pumpjacks()


func build_ridge() -> void:
	# Mountains along the north, out past where the helicopter can fly.
	var rock_tones := [Color(0.46, 0.38, 0.31), Color(0.4, 0.33, 0.28), Color(0.53, 0.44, 0.35)]
	for i in 30:
		var angle := deg_to_rad(rng.randf_range(195.0, 345.0))
		var pos := polar(angle, rng.randf_range(72.0, 150.0))
		var tone: Color = rock_tones[rng.randi() % rock_tones.size()]
		build_peak(pos, rng.randf_range(14.0, 28.0), rng.randf_range(16.0, 38.0), P.material(tone, 1.0))

	# Rocky outcrops nearer in: clusters of big faceted boulders.
	var facets := SphereMesh.new()
	facets.radial_segments = 6
	facets.rings = 3
	for i in 22:
		var pos := random_ground_point(30.0, 70.0)
		var mat := P.material(rock_tones[rng.randi() % rock_tones.size()], 1.0)
		for k in rng.randi_range(3, 5):
			var size := Vector3(rng.randf_range(3.0, 7.0), rng.randf_range(2.0, 5.5), rng.randf_range(3.0, 6.0))
			var offset := Vector3(rng.randf_range(-4, 4), size.y * 0.15, rng.randf_range(-4, 4))
			var boulder := P.add_mesh(self, facets, pos + offset, mat)
			boulder.scale = size
			boulder.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))

	rock_count = 620
	shrub_count = 140
	pumpjack_count = 2
	build_rocks()
	build_shrubs()
	build_pumpjacks()


func build_refinery() -> void:
	# Distillation columns with ring platforms, linked by pipe racks.
	var column_mat := P.material(Color(0.78, 0.78, 0.74), 0.5, 0.3)
	var unit := polar(deg_to_rad(100.0), 36.0)
	for i in 5:
		var pos := unit + Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-6, 6))
		var radius := rng.randf_range(1.2, 2.0)
		var height := rng.randf_range(8.0, 12.0)
		P.cylinder(self, radius, height, pos + Vector3(0, height * 0.5, 0), column_mat)
		for k in 3:
			P.cylinder(self, radius + 0.6, 0.15, pos + Vector3(0, height * (0.3 + k * 0.25), 0), steel)
		P.pipe(self, pos + Vector3(0, height * 0.8, 0), unit + Vector3(0, 3.0, 0), 0.25, pipe_mat)
	P.box(self, Vector3(24, 0.2, 18), unit + Vector3(0, 0.1, 0), concrete)
	build_pipeline(polar(deg_to_rad(100.0), 8.0), unit)

	# Flare stacks burning off gas, out at the edge.
	for angle in [75.0, 210.0, 330.0]:
		var pos := polar(deg_to_rad(angle), rng.randf_range(72.0, 86.0))
		P.cylinder(self, 0.7, 26.0, pos + Vector3(0, 13.0, 0), steel)
		build_fire(pos + Vector3(0, 26.5, 0), 1.6)

	dune_count = 8
	rock_count = 140
	shrub_count = 60
	build_dunes()
	build_rocks()
	build_shrubs()


func build_terminal() -> void:
	# The gulf to the east: sea, a wet beach and the shoreline.
	var coast := 36.0
	land_max_x = coast - 4.0
	var sea := P.material(Color(0.16, 0.4, 0.48, 0.92), 0.2)
	sea.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	P.add_mesh(self, plane, Vector3(coast + 350.0, ground_y + 0.08, 0), sea)
	var shallows := P.material(Color(0.36, 0.6, 0.58, 0.6), 0.3)
	shallows.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	P.box(self, Vector3(8, 0.04, 700), Vector3(coast + 4.0, ground_y + 0.1, 0), shallows)
	P.box(self, Vector3(6, 0.04, 700), Vector3(coast - 2.0, ground_y + 0.03, 0), P.material(Color(0.62, 0.52, 0.38), 1.0))

	# Jetty on piles out to the tanker berth.
	var deck := P.material(Color(0.42, 0.36, 0.3), 0.9)
	var jetty_z := 6.0
	P.box(self, Vector3(60, 0.5, 5), Vector3(coast + 28.0, ground_y + 1.4, jetty_z), deck)
	for x in range(int(coast), int(coast + 58), 6):
		for z in [-2.0, 2.0]:
			P.cylinder(self, 0.3, 3.0, Vector3(x, ground_y, jetty_z + z), steel)
	build_pipeline(Vector3(coast - 30.0, ground_y, jetty_z + 1.5), Vector3(coast + 56.0, ground_y + 1.6, jetty_z + 1.5))

	# A tanker moored alongside.
	var ship := Node3D.new()
	ship.position = Vector3(coast + 36.0, ground_y, jetty_z + 13.0)
	add_child(ship)
	var hull_red := P.material(Color(0.5, 0.14, 0.1), 0.8)
	var hull_dark := P.material(Color(0.14, 0.15, 0.17), 0.7)
	var white := P.material(Color(0.9, 0.9, 0.87), 0.7)
	P.box(ship, Vector3(64, 3.0, 12), Vector3(0, 0.6, 0), hull_red)
	P.box(ship, Vector3(64, 3.0, 12), Vector3(0, 3.6, 0), hull_dark)
	P.box(ship, Vector3(10, 1.0, 9), Vector3(30, 3.6, 0), hull_dark)
	P.box(ship, Vector3(56, 0.3, 11), Vector3(-2, 5.2, 0), P.material(Color(0.5, 0.2, 0.15), 0.8))
	P.box(ship, Vector3(8, 6, 10), Vector3(-26, 8, 0), white)
	P.box(ship, Vector3(8.2, 1, 10.2), Vector3(-26, 10, 0), P.material(Color(0.15, 0.22, 0.3), 0.2, 0.4))
	P.cylinder(ship, 1.0, 4.0, Vector3(-30, 13, 0), hull_red)
	for x in range(-18, 26, 6):
		P.pipe(ship, Vector3(x, 5.6, -4), Vector3(x, 5.6, 4), 0.25, pipe_mat)

	dune_count = 14
	rock_count = 160
	shrub_count = 120
	build_dunes()
	build_rocks()
	build_shrubs()


func build_oilfield() -> void:
	# Black oil spills soaking into the sand.
	var oil := P.material(Color(0.07, 0.06, 0.05), 0.2)
	for i in 30:
		var pos := random_ground_point(15.0, 150.0)
		var size := Vector3(rng.randf_range(3.0, 9.0), 0.06, rng.randf_range(2.0, 7.0))
		P.sphere(self, 1.0, pos, oil, size).rotation.y = rng.randf() * TAU

	# Burning wellheads with smoke climbing off them.
	for i in 6:
		var pos := random_ground_point(32.0, 95.0)
		P.box(self, Vector3(2.0, 1.0, 2.0), pos + Vector3(0, 0.5, 0), P.material(Color(0.12, 0.1, 0.09), 0.9))
		build_fire(pos + Vector3(0, 1.4, 0), 2.4)

	# Small lattice derricks among the pumpjacks.
	for i in 6:
		build_small_derrick(random_ground_point(35.0, 120.0))

	pumpjack_count = 18
	dune_count = 10
	rock_count = 200
	shrub_count = 80
	build_pumpjacks()
	build_dunes()
	build_rocks()
	build_shrubs()


# --- Biome props -----------------------------------------------------------

# A flat strip on the ground from a to b (riverbeds, cracks).
func flat_strip(a: Vector3, b: Vector3, width: float, lift: float, mat: Material) -> void:
	var strip := P.beam(self, a + Vector3(0, lift, 0), b + Vector3(0, lift, 0), 1.0, mat)
	if strip == null:
		return
	var basis := strip.transform.basis
	strip.transform.basis = Basis(basis.x.normalized() * width, basis.y.normalized() * 0.04, basis.z)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func build_palm(pos: Vector3) -> void:
	var trunk := P.material(Color(0.42, 0.33, 0.22), 1.0)
	var frond := P.material(Color(0.32, 0.45, 0.2), 0.9)
	var lean := Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
	var height := rng.randf_range(6.0, 9.0)
	var top := pos + Vector3(0, height, 0) + lean
	P.pipe(self, pos, pos.lerp(top, 0.5) + lean * 0.3, 0.32, trunk)
	P.pipe(self, pos.lerp(top, 0.5) + lean * 0.3, top, 0.26, trunk)
	for k in 8:
		var angle := TAU * k / 8.0 + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(angle), 0, sin(angle))
		P.beam(self, top, top + out * 2.4 + Vector3(0, 0.4, 0), 0.35, frond)
		P.beam(self, top + out * 2.4 + Vector3(0, 0.4, 0), top + out * 4.0 + Vector3(0, -1.2, 0), 0.3, frond)


# A mountain: a cone of rock with a couple of shoulders.
func build_peak(pos: Vector3, radius: float, height: float, mat: Material) -> void:
	for k in 3:
		var mesh := CylinderMesh.new()
		var r := radius * (1.0 - k * 0.25)
		var h := height * (1.0 - k * 0.3)
		mesh.top_radius = r * 0.08
		mesh.bottom_radius = r
		mesh.height = h
		mesh.radial_segments = 7
		mesh.rings = 1
		var offset := Vector3(rng.randf_range(-0.4, 0.4) * radius, h * 0.5 - 1.0, rng.randf_range(-0.4, 0.4) * radius)
		var peak := P.add_mesh(self, mesh, pos + offset, mat)
		peak.rotation.y = rng.randf() * TAU


# A fire with smoke puffs that rise from it, animated in _process.
func build_fire(pos: Vector3, size: float) -> void:
	var flame := Node3D.new()
	flame.position = pos
	add_child(flame)
	P.sphere(flame, size * 0.5, Vector3(0, size * 0.5, 0), P.glow_material(Color(1.0, 0.45, 0.1), 5.0), Vector3(1.0, 1.8, 1.0))
	P.sphere(flame, size * 0.3, Vector3(0, size * 0.8, 0), P.glow_material(Color(1.0, 0.8, 0.35), 7.0), Vector3(1.0, 1.8, 1.0))
	flames.append([flame, rng.randf() * TAU])

	var soot := P.material(Color(0.1, 0.09, 0.09, 0.55), 1.0)
	soot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for k in 5:
		var puff := P.sphere(self, size * 0.7, pos, soot)
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smoke.append([puff, pos + Vector3(0, size, 0), float(k) / 5.0])


func build_small_derrick(pos: Vector3) -> void:
	var dark := P.material(Color(0.2, 0.2, 0.21), 0.6, 0.4)
	P.box(self, Vector3(4, 0.3, 4), pos + Vector3(0, 0.15, 0), concrete)
	var top := pos + Vector3(0, 11, 0)
	for c in [Vector3(-1.4, 0, -1.4), Vector3(1.4, 0, -1.4), Vector3(1.4, 0, 1.4), Vector3(-1.4, 0, 1.4)]:
		P.beam(self, pos + c + Vector3(0, 0.3, 0), top + c * 0.25, 0.18, dark)
	for k in 4:
		var y := 2.0 + k * 2.2
		var w := lerpf(1.4, 0.35, y / 11.0)
		P.box(self, Vector3(w * 2.0, 0.12, w * 2.0), pos + Vector3(0, y, 0), dark)
	P.box(self, Vector3(1.0, 0.6, 1.0), top + Vector3(0, 0.3, 0), dark)


# Point on the ground at an angle (radians) and distance from the centre.
func polar(angle: float, radius: float) -> Vector3:
	return Vector3(cos(angle) * radius, ground_y, sin(angle) * radius)


func random_ground_point(min_radius: float, max_radius: float) -> Vector3:
	var point := Vector3.ZERO
	# Retry a few times to keep props out of the sea.
	for attempt in 20:
		var angle := rng.randf() * TAU
		# sqrt keeps the density even over the ring.
		var t := sqrt(rng.randf_range(pow(min_radius / max_radius, 2.0), 1.0))
		point = polar(angle, t * max_radius)
		if point.x < land_max_x:
			break
	return point


func build_roads() -> void:
	# The main access road.
	for end in [polar(deg_to_rad(200.0), outer_radius)]:
		var start: Vector3 = end.normalized() * 5.0
		start.y = ground_y
		var road := P.beam(self, start + Vector3(0, 0.02, 0), end + Vector3(0, 0.02, 0), 1.0, dirt)
		# Flatten the beam into a wide, thin strip.
		var basis := road.transform.basis
		road.transform.basis = Basis(basis.x.normalized() * 7.0, basis.y.normalized() * 0.04, basis.z)
		road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func build_dunes() -> void:
	var dune_mat := P.material(Color(0.7, 0.58, 0.44), 1.0)

	for i in dune_count:
		var pos := random_ground_point(80.0, outer_radius)
		var size := Vector3(rng.randf_range(18.0, 40.0), rng.randf_range(2.5, 7.0), rng.randf_range(10.0, 22.0))
		var dune := P.sphere(self, 1.0, pos - Vector3(0, size.y * 0.35, 0), dune_mat, size)
		dune.rotation.y = rng.randf() * TAU


func build_rocks() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := P.material(Color(1, 1, 1), 1.0)
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = rock_count

	for i in rock_count:
		var pos := random_ground_point(9.0, outer_radius)
		var s := rng.randf_range(0.4, 2.4)
		var scale := Vector3(s * rng.randf_range(0.8, 1.4), s * rng.randf_range(0.4, 0.8), s * rng.randf_range(0.8, 1.4))
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled_local(scale)
		pos.y += scale.y * 0.2
		multimesh.set_instance_transform(i, Transform3D(basis, pos))
		var shade := rng.randf_range(0.22, 0.36)
		multimesh.set_instance_color(i, Color(shade * 1.1, shade * 0.95, shade * 0.8))

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	add_child(instance)


func build_shrubs() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 7
	mesh.rings = 4
	var mat := P.material(Color(1, 1, 1), 1.0)
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = shrub_count

	for i in shrub_count:
		var pos := random_ground_point(9.0, outer_radius)
		var s := rng.randf_range(0.5, 1.5)
		var basis := Basis.IDENTITY.scaled(Vector3(s, s * 0.6, s))
		pos.y += s * 0.15
		multimesh.set_instance_transform(i, Transform3D(basis, pos))
		var green := rng.randf_range(0.0, 1.0)
		multimesh.set_instance_color(i, Color(0.45, 0.42, 0.25).lerp(Color(0.38, 0.45, 0.22), green))

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	add_child(instance)


func build_pipeline(from: Vector3, to: Vector3) -> void:
	var height := 1.0
	var length := from.distance_to(to)
	var supports := int(length / 6.0)

	P.pipe(self, from + Vector3(0, height, 0), to + Vector3(0, height, 0), 0.32, pipe_mat)

	for i in supports + 1:
		var p := from.lerp(to, float(i) / maxf(supports, 1))
		P.box(self, Vector3(0.25, height, 0.25), p + Vector3(0, height * 0.5, 0), steel)
		P.box(self, Vector3(1.0, 0.15, 0.3), p + Vector3(0, height - 0.32, 0), steel)


func build_pumpjacks() -> void:
	var placed := 0
	var attempts := 0

	while placed < pumpjack_count and attempts < 200:
		attempts += 1
		var angle := rng.randf() * TAU
		# Keep clear of the main road.
		if absf(angle_difference(angle, deg_to_rad(200.0))) < 0.15:
			continue

		var pos := polar(angle, rng.randf_range(58.0, 120.0))
		build_pumpjack(pos, rng.randf() * TAU)

		# Flowline back toward the rig, lying on the ground.
		var inner := polar(angle, 9.0)
		P.pipe(self, pos + Vector3(0, 0.15, 0), inner + Vector3(0, 0.15, 0), 0.12, pipe_mat)
		placed += 1


func build_pumpjack(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)

	var dark := P.material(Color(0.25, 0.27, 0.3), 0.5, 0.6)
	var blue := P.material(Color(0.2, 0.35, 0.55), 0.6, 0.3)

	# Concrete base and skid.
	P.box(root, Vector3(9.0, 0.3, 2.6), Vector3(0, 0.15, 0), concrete)
	P.box(root, Vector3(8.0, 0.35, 1.2), Vector3(-0.5, 0.45, 0), dark)

	# Samson post (A-frame).
	for z in [-0.9, 0.9]:
		P.beam(root, Vector3(-1.0, 0.5, z), Vector3(0, 4.0, 0), 0.25, blue)
		P.beam(root, Vector3(1.0, 0.5, z), Vector3(0, 4.0, 0), 0.25, blue)

	# Walking beam with horsehead, pivoting on the post.
	var beam := Node3D.new()
	beam.position = Vector3(0, 4.1, 0)
	root.add_child(beam)
	P.box(beam, Vector3(7.0, 0.45, 0.4), Vector3(0.3, 0, 0), blue)
	P.box(beam, Vector3(0.6, 1.8, 0.6), Vector3(3.9, -0.5, 0), yellow)

	# Polished rod and wellhead.
	P.cylinder(root, 0.06, 3.0, Vector3(4.15, 1.6, 0), steel)
	P.box(root, Vector3(0.8, 0.8, 0.8), Vector3(4.15, 0.4, 0), dark)

	# Gearbox and rotating crank with counterweights.
	P.box(root, Vector3(1.4, 1.2, 1.2), Vector3(-2.8, 1.2, 0), dark)
	var crank := Node3D.new()
	crank.position = Vector3(-2.8, 1.4, 0)
	root.add_child(crank)
	for z in [-0.75, 0.75]:
		P.box(crank, Vector3(2.4, 0.3, 0.15), Vector3(0, 0, z), dark)
		P.box(crank, Vector3(1.0, 1.0, 0.3), Vector3(-1.2, 0, z), yellow)

	# Pitman arm from crank to the beam's tail.
	P.beam(root, Vector3(-2.8, 1.4, 0), Vector3(-3.0, 4.0, 0), 0.15, steel)

	pumpjacks.append([beam, crank, rng.randf() * TAU])


func build_camp() -> void:
	# Site trailers and containers just outside the base.
	var camp := Node3D.new()
	camp.position = polar(deg_to_rad(250.0), 13.0)
	camp.rotation.y = deg_to_rad(-250.0) + PI / 2.0
	add_child(camp)

	var trailer := P.material(Color(0.9, 0.9, 0.88), 0.7)
	var window := P.material(Color(0.15, 0.22, 0.3), 0.15, 0.5)
	var container_colors := [Color(0.65, 0.2, 0.15), Color(0.2, 0.4, 0.6), Color(0.8, 0.5, 0.15)]

	for i in 3:
		var x := -5.0 + i * 5.0
		P.box(camp, Vector3(3.0, 2.6, 8.0), Vector3(x, 1.5, 0), trailer)
		P.box(camp, Vector3(3.05, 0.6, 5.0), Vector3(x, 2.0, 0), window)
		P.box(camp, Vector3(1.2, 0.2, 1.2), Vector3(x + 1.5, 0.2, 3.0), steel)

	for i in 3:
		var color: Color = container_colors[i]
		P.box(camp, Vector3(2.4, 2.6, 6.0), Vector3(-6.0 + i * 3.0, 1.3, 9.0), P.material(color, 0.7, 0.3))

	# Oil drums.
	var drum := P.material(Color(0.25, 0.35, 0.55), 0.6, 0.4)
	for i in 6:
		P.cylinder(camp, 0.35, 0.9, Vector3(6.5 + (i % 3) * 0.8, 0.45, 5.0 + (i / 3) * 0.8), drum)


func _process(delta: float) -> void:
	time += delta

	for jack in pumpjacks:
		var beam: Node3D = jack[0]
		var crank: Node3D = jack[1]
		var phase: float = jack[2]
		if not is_instance_valid(beam):
			continue
		var angle := time * 1.6 + phase
		crank.rotation.z = angle
		beam.rotation.z = sin(angle) * 0.22

	for fire in flames:
		var node: Node3D = fire[0]
		var phase: float = fire[1]
		node.scale = Vector3(1.0 + 0.12 * sin(time * 9.0 + phase), 0.85 + 0.3 * absf(sin(time * 6.3 + phase)), 1.0 + 0.12 * cos(time * 7.7 + phase))

	# Smoke puffs climb, swell and fade, then start again at the fire.
	for puff in smoke:
		var node: MeshInstance3D = puff[0]
		var base: Vector3 = puff[1]
		var t := fmod(time * 0.12 + puff[2], 1.0)
		node.position = base + Vector3(t * 6.0, t * 22.0, t * 2.0)
		node.scale = Vector3.ONE * (1.0 + t * 3.0)
		node.transparency = t
