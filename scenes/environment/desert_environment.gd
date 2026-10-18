@tool
extends Node3D

# Desert oil field around the base: dirt roads, dunes, rocks, shrubs, a
# storage tank farm, animated pumpjacks, pipelines and a site camp.
# Everything is placed from a seed, so the layout is the same every run.
# Props have no collision, so they never block aiming.

const P := preload("res://scenes/environment/prop_builder.gd")

@export var seed_value: int = 1337:
	set(value):
		seed_value = value
		rebuild()
# Height of the ground surface.
@export var ground_y: float = -0.408:
	set(value):
		ground_y = value
		rebuild()
@export var outer_radius: float = 260.0
@export var rock_count: int = 260
@export var shrub_count: int = 320
@export var dune_count: int = 34
@export var pumpjack_count: int = 7
# Angle of the storage tank farm around the base, in degrees.
@export var tank_farm_angle: float = 40.0

var rng := RandomNumberGenerator.new()
var pumpjacks: Array = [] # [beam pivot, crank pivot, phase]
var time: float = 0.0

var sand: StandardMaterial3D
var dirt: StandardMaterial3D
var concrete: StandardMaterial3D
var steel: StandardMaterial3D
var tank_white: StandardMaterial3D
var pipe_mat: StandardMaterial3D
var yellow: StandardMaterial3D


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	if not is_inside_tree():
		return

	for child in get_children():
		child.queue_free()

	pumpjacks.clear()
	build()


func build() -> void:
	rng.seed = seed_value

	sand = P.material(Color(0.8, 0.63, 0.42), 1.0)
	dirt = P.material(Color(0.62, 0.48, 0.33), 1.0)
	concrete = P.material(Color(0.66, 0.64, 0.6), 0.95)
	steel = P.material(Color(0.36, 0.38, 0.4), 0.5, 0.6)
	tank_white = P.material(Color(0.88, 0.88, 0.85), 0.6, 0.2)
	pipe_mat = P.material(Color(0.55, 0.55, 0.52), 0.4, 0.7)
	yellow = P.material(Color(0.95, 0.72, 0.12), 0.6, 0.2)

	var farm_pos := polar(deg_to_rad(tank_farm_angle), 85.0)

	build_roads(farm_pos)
	build_dunes()
	build_rocks()
	build_shrubs()
	build_tank_farm(farm_pos)
	# Pipeline from the rig to the tank farm, running beside the farm road.
	var side := Vector3(-farm_pos.z, 0.0, farm_pos.x).normalized() * 6.0
	build_pipeline(polar(deg_to_rad(tank_farm_angle), 7.0) + side, polar(deg_to_rad(tank_farm_angle), 72.0) + side)
	build_pumpjacks()
	build_camp()


# Point on the ground at an angle (radians) and distance from the centre.
func polar(angle: float, radius: float) -> Vector3:
	return Vector3(cos(angle) * radius, ground_y, sin(angle) * radius)


func random_ground_point(min_radius: float, max_radius: float) -> Vector3:
	var angle := rng.randf() * TAU
	# sqrt keeps the density even over the ring.
	var t := sqrt(rng.randf_range(pow(min_radius / max_radius, 2.0), 1.0))
	return polar(angle, t * max_radius)


func build_roads(farm_pos: Vector3) -> void:
	# Main access road and a track to the tank farm.
	var road_ends := [polar(deg_to_rad(200.0), outer_radius), farm_pos]
	for end in road_ends:
		var start: Vector3 = end.normalized() * 5.0
		start.y = ground_y
		var road := P.beam(self, start + Vector3(0, 0.02, 0), end + Vector3(0, 0.02, 0), 1.0, dirt)
		# Flatten the beam into a wide, thin strip.
		var basis := road.transform.basis
		road.transform.basis = Basis(basis.x.normalized() * 7.0, basis.y.normalized() * 0.04, basis.z)
		road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func build_dunes() -> void:
	var dune_mat := P.material(Color(0.78, 0.61, 0.4), 1.0)

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


func build_tank_farm(center: Vector3) -> void:
	var farm := Node3D.new()
	farm.position = center
	farm.rotation.y = -deg_to_rad(tank_farm_angle) + PI / 2.0
	add_child(farm)

	var band := P.material(Color(0.75, 0.3, 0.15), 0.6, 0.2)

	# Pad and containment berm.
	P.box(farm, Vector3(34, 0.2, 24), Vector3(0, 0.1, 0), concrete)
	for side in [-1, 1]:
		P.box(farm, Vector3(34, 1.0, 0.8), Vector3(0, 0.5, side * 12.0), dirt)
		P.box(farm, Vector3(0.8, 1.0, 24), Vector3(side * 17.0, 0.5, 0), dirt)

	# Storage tanks.
	for x in [-8.5, 8.5]:
		for z in [-5.0, 5.0]:
			P.cylinder(farm, 4.2, 6.5, Vector3(x, 3.45, z), tank_white, Vector3.ZERO, 28)
			P.cylinder(farm, 4.25, 0.5, Vector3(x, 5.2, z), band, Vector3.ZERO, 28)
			P.cylinder(farm, 3.8, 0.3, Vector3(x, 6.85, z), tank_white, Vector3.ZERO, 28)
			# Spiral-ish stair up the side.
			P.beam(farm, Vector3(x + 4.3, 0.2, z - 2.0), Vector3(x + 4.3, 6.7, z + 2.0), 0.4, steel)

	# Manifold pipes between the tanks.
	for z in [-5.0, 5.0]:
		P.pipe(farm, Vector3(-8.5, 1.0, z), Vector3(8.5, 1.0, z), 0.3, pipe_mat)
	P.pipe(farm, Vector3(0, 1.0, -5.0), Vector3(0, 1.0, 5.0), 0.3, pipe_mat)


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
	var farm_angle := deg_to_rad(tank_farm_angle)
	var placed := 0
	var attempts := 0

	while placed < pumpjack_count and attempts < 200:
		attempts += 1
		var angle := rng.randf() * TAU
		# Keep clear of the tank farm and the main road.
		if absf(angle_difference(angle, farm_angle)) < 0.35:
			continue
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
