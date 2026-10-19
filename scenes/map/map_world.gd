extends Node3D

# 3D campaign map: desert terrain split into regions, a derrick at every
# rig, drifting clouds over land you can't reach yet and a fixed tilted
# camera. Built from primitives in code. The map screen (map.gd) puts its
# UI and the rig badges (map_markers.gd) on top.

const P := preload("res://scenes/environment/prop_builder.gd")
const Campaign := preload("res://scenes/map/campaign.gd")
const Terrain := preload("res://scenes/map/map_terrain.gd")
const REGION_SHADER := preload("res://scenes/map/map_regions.gdshader")

const OWNED := Color(0.3, 0.95, 0.4)
const ENEMY := Color(1.0, 0.22, 0.16)

# Where the camera looks; shifted right of the map centre so the map sits
# left of the info panel.
@export var look_at_point := Vector3(37.0, 0.0, 3.0)
@export var camera_distance: float = 170.0
@export var camera_pitch: float = 58.0

var terrain: Terrain
var ground_material: ShaderMaterial
var camera: Camera3D
var hovered: int = -1
var selected: int = -1
# Per rig: {"top": Vector3, "gush": Node3D, "flare": Node3D, "phase": float}
var rigs: Array = []
var clouds: Array = [] # [node, base position, drift speed]
var time: float = 0.0


func _ready() -> void:
	terrain = Terrain.new()
	build_environment()
	build_camera()
	build_ground()
	build_water()
	for i in Campaign.RIG_ORDER.size():
		build_rig(i)
	build_clouds()
	refresh_states()


func _process(delta: float) -> void:
	time += delta

	for rig in rigs:
		var t: float = time * 2.2 + rig["phase"]
		if rig["gush"] != null:
			rig["gush"].scale = Vector3.ONE * (0.85 + 0.2 * sin(t))
		if rig["flare"] != null:
			rig["flare"].scale = Vector3(1, 0.8 + 0.4 * absf(sin(t * 3.1)), 1)

	for cloud in clouds:
		var node: Node3D = cloud[0]
		var base: Vector3 = cloud[1]
		# Sway back and forth rather than crossing the map.
		var x: float = base.x + sin(time * 0.06 * cloud[2] + base.z) * 7.0 * cloud[2]
		node.position = Vector3(x, base.y + sin(time * 0.4 + base.z) * 0.4, base.z)


# --- Picking ----------------------------------------------------------------

# Where a screen point meets the ground (stepping along the terrain heights).
func ground_point(screen: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if direction.y > -0.01:
		return null
	var height := 1.0
	var point := Vector3.ZERO
	for i in 4:
		var t := (height - origin.y) / direction.y
		point = origin + direction * t
		height = maxf(terrain.height_at(point.x, point.z), 0.0)
	return point


# Region index under a screen point, or -1.
func region_at_screen(screen: Vector2) -> int:
	var point = ground_point(screen)
	if point == null:
		return -1
	return terrain.region_at(point.x, point.z)


func set_hovered(index: int) -> void:
	hovered = index
	ground_material.set_shader_parameter("hovered", index)


func set_selected(index: int) -> void:
	selected = index
	ground_material.set_shader_parameter("selected", index)


# Recolour regions after captures (1 owned, 2 attackable, 3 out of reach).
func refresh_states() -> void:
	var states := PackedInt32Array()
	states.resize(8)
	for i in Campaign.RIG_ORDER.size():
		var id: String = Campaign.RIG_ORDER[i]
		states[i] = 1 if Campaign.is_owned(id) else (2 if Campaign.can_attack(id) else 3)
	ground_material.set_shader_parameter("region_state", states)


func rig_top(index: int) -> Vector3:
	return rigs[index]["top"]


# --- World -----------------------------------------------------------------

func build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.55, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.78, 0.68)
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_hdr_threshold = 1.2
	# Haze toward the distance hides where the terrain ends.
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.62, 0.52)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	add_child(sun)


func build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 36.0
	camera.far = 600.0
	var pitch := deg_to_rad(camera_pitch)
	camera.position = look_at_point + Vector3(0.0, sin(pitch), cos(pitch)) * camera_distance
	add_child(camera)
	camera.look_at(look_at_point)
	camera.current = true


func build_ground() -> void:
	ground_material = ShaderMaterial.new()
	ground_material.shader = REGION_SHADER
	ground_material.set_shader_parameter("region_ids", terrain.region_id_texture())
	ground_material.set_shader_parameter("region_border", terrain.region_border_texture())
	var size := Terrain.REGION_MAX - Terrain.REGION_MIN
	ground_material.set_shader_parameter("region_rect", Vector4(Terrain.REGION_MIN.x, Terrain.REGION_MIN.y, size.x, size.y))
	ground_material.set_shader_parameter("border_range", Terrain.BORDER_RANGE)
	ground_material.set_shader_parameter("owned_color", Color(OWNED.r, OWNED.g, OWNED.b))
	ground_material.set_shader_parameter("enemy_color", Color(ENEMY.r, ENEMY.g, ENEMY.b))

	var ground := MeshInstance3D.new()
	ground.mesh = terrain.build_mesh()
	ground.material_override = ground_material
	add_child(ground)


func build_water() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(400, 400)
	var water := P.material(Color(0.17, 0.42, 0.5, 0.88), 0.25)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	P.add_mesh(self, mesh, Vector3(0, 0.0, 0), water)

	# A lighter band of shallows along the shore.
	var shallow_mesh := PlaneMesh.new()
	shallow_mesh.size = Vector2(400, 400)
	var shallow := P.material(Color(0.35, 0.62, 0.62, 0.35), 0.4)
	shallow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	P.add_mesh(self, shallow_mesh, Vector3(0, -0.35, 0), shallow)


# A lattice derrick on a concrete pad, like the map icon: tapered legs with
# cross-bracing, a stepped crown and an oil gush (owned) or a burning flare
# (enemy). A couple of storage tanks sit beside it.
func build_rig(index: int) -> void:
	var id: String = Campaign.RIG_ORDER[index]
	var point: Vector2 = terrain.rig_points[index]
	var base := Vector3(point.x, terrain.height_at(point.x, point.y), point.y)
	var owned := Campaign.is_owned(id)
	var team := OWNED if owned else ENEMY

	var root := Node3D.new()
	root.position = base
	root.rotation_degrees.y = 20.0 + index * 37.0
	add_child(root)

	var steel := P.material(Color(0.1, 0.12, 0.1) if owned else Color(0.16, 0.09, 0.08), 0.7)
	var concrete := P.material(Color(0.6, 0.57, 0.52), 0.95)
	var accent := P.material(team.darkened(0.25), 0.8)

	P.box(root, Vector3(4.6, 0.4, 4.6), Vector3(0, 0.2, 0), concrete)
	P.box(root, Vector3(4.9, 0.12, 4.9), Vector3(0, 0.06, 0), accent)

	var height := 7.0
	var bottom := 1.4
	var top := 0.45
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var leg := func(corner: Vector2, y: float) -> Vector3:
		var half := lerpf(bottom, top, y / height)
		return Vector3(corner.x * half, 0.4 + y, corner.y * half)

	for corner in corners:
		P.beam(root, leg.call(corner, 0.0), leg.call(corner, height), 0.22, steel)

	# Horizontal rings and X braces on every face.
	var levels := [0.0, 1.9, 3.6, 5.1, height]
	for k in levels.size():
		for f in 4:
			var a: Vector2 = corners[f]
			var b: Vector2 = corners[(f + 1) % 4]
			P.beam(root, leg.call(a, levels[k]), leg.call(b, levels[k]), 0.14, steel)
			if k < levels.size() - 1:
				P.beam(root, leg.call(a, levels[k]), leg.call(b, levels[k + 1]), 0.1, steel)
				P.beam(root, leg.call(b, levels[k]), leg.call(a, levels[k + 1]), 0.1, steel)

	# Stepped crown.
	var crown_y := 0.4 + height
	P.box(root, Vector3(1.6, 0.35, 1.6), Vector3(0, crown_y + 0.17, 0), steel)
	P.box(root, Vector3(1.1, 0.45, 1.1), Vector3(0, crown_y + 0.57, 0), steel)
	P.box(root, Vector3(0.6, 0.5, 0.6), Vector3(0, crown_y + 1.05, 0), steel)
	P.sphere(root, 0.22, Vector3(0, crown_y + 1.45, 0), P.glow_material(team, 4.0))

	var gush: Node3D = null
	var flare: Node3D = null
	var tip := Vector3(0, crown_y + 1.4, 0)
	if owned:
		# Three teardrops of oil spraying from the top.
		gush = Node3D.new()
		gush.position = tip
		root.add_child(gush)
		var oil := P.material(Color(0.05, 0.05, 0.05), 0.15)
		for angle in [-38.0, 0.0, 38.0]:
			var drop := Node3D.new()
			drop.rotation_degrees.z = angle
			gush.add_child(drop)
			P.sphere(drop, 0.42, Vector3(0, 1.15, 0), oil, Vector3(0.75, 1.6, 0.75))
	else:
		flare = Node3D.new()
		flare.position = tip + Vector3(0, 0.3, 0)
		root.add_child(flare)
		P.sphere(flare, 0.45, Vector3(0, 0.45, 0), P.glow_material(Color(1.0, 0.55, 0.15), 6.0), Vector3(0.8, 1.6, 0.8))
		P.sphere(flare, 0.25, Vector3(0, 0.75, 0), P.glow_material(Color(1.0, 0.85, 0.4), 8.0), Vector3(0.8, 1.6, 0.8))

	# Storage tanks and a shed on the pad's edge.
	var tank := P.material(Color(0.86, 0.84, 0.78), 0.6)
	P.cylinder(root, 0.9, 1.5, Vector3(3.6, 0.75, 1.2), tank)
	P.cylinder(root, 0.7, 1.2, Vector3(3.4, 0.6, -1.0), tank)
	P.box(root, Vector3(1.4, 1.0, 1.0), Vector3(-3.4, 0.5, 1.6), accent)

	rigs.append({"top": base + Vector3(0, crown_y + 2.6, 0), "gush": gush, "flare": flare, "phase": index * 1.7})


# Cloud puffs: a ring that drifts around the map edges, and banks that sit
# over regions still out of reach.
func build_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var white := P.material(Color(0.97, 0.95, 0.92, 0.45), 1.0)
	white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	white.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	var half := Terrain.MAP_SIZE * 0.5
	for i in 34:
		var side := rng.randi_range(0, 3)
		var p := Vector2.ZERO
		match side:
			0: p = Vector2(rng.randf_range(-half.x - 20, half.x + 20), -half.y - rng.randf_range(2, 16))
			1: p = Vector2(rng.randf_range(-half.x - 20, half.x + 20), half.y + rng.randf_range(10, 22))
			2: p = Vector2(-half.x - rng.randf_range(4, 18), rng.randf_range(-half.y, half.y))
			3: p = Vector2(half.x + rng.randf_range(4, 18), rng.randf_range(-half.y, half.y))
		add_cloud(rng, Vector3(p.x, rng.randf_range(12, 17), p.y), rng.randf_range(4.0, 7.0), white, rng.randf_range(0.6, 1.4))

	var centres := terrain.region_centres()
	for i in Campaign.RIG_ORDER.size():
		var id: String = Campaign.RIG_ORDER[i]
		if Campaign.is_owned(id) or Campaign.can_attack(id):
			continue
		var centre: Vector2 = centres[i]
		for k in 5:
			var p: Vector2 = centre + Vector2(rng.randf_range(-11, 11), rng.randf_range(-8, 8))
			add_cloud(rng, Vector3(p.x, rng.randf_range(11, 15), p.y), rng.randf_range(3.5, 5.5), white, 0.0)


func add_cloud(rng: RandomNumberGenerator, position: Vector3, size: float, mat: Material, drift: float) -> void:
	var puff := Node3D.new()
	puff.position = position
	add_child(puff)
	for k in rng.randi_range(3, 5):
		var offset := Vector3(rng.randf_range(-1.2, 1.2) * size, rng.randf_range(-0.2, 0.4) * size, rng.randf_range(-0.6, 0.6) * size)
		var radius := size * rng.randf_range(0.55, 0.9)
		var ball := P.sphere(puff, radius, offset, mat, Vector3(1.0, 0.45, 0.8))
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clouds.append([puff, position, drift])
