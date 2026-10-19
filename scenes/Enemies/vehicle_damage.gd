extends Node

# Visible battle damage for a vehicle (added by enemy_base for enemies
# that leave a wreck):
# - bullet holes (light weapons) and scorched dents (heavy weapons) as
#   decals on the side facing the shooter or on the roof,
# - a burst of sparks at every hit; armour that stops the minigun gives a
#   ricochet with sparks only,
# - light smoke below half health, fire and black smoke below a quarter.
# Holes are oversized on purpose: at pixel-art scale a real one would be
# smaller than a pixel.

const MAX_HOLES := 12
# Fastest rate holes are added (sparks still show for every hit).
const HOLE_INTERVAL_MS := 90
const Debris := preload("res://scenes/Enemies/debris.gd")

static var hole_texture: Texture2D
static var scorch_texture: Texture2D
static var spark_mesh: Mesh

var vehicle: Node3D
var holes: Array = []
var last_hole_ms: int = -100000
var bounds: AABB
var bounds_ready: bool = false
var smoke: CPUParticles3D
var fire: CPUParticles3D
# The vehicle's own paint, for chips knocked off by heavy hits.
var paints: Array = []


func _ready() -> void:
	vehicle = get_parent() as Node3D
	if hole_texture == null:
		hole_texture = make_mark_texture(false)
		scorch_texture = make_mark_texture(true)
		spark_mesh = make_spark_mesh()


# Called by the weapons for every hit that didn't destroy the vehicle.
func register_hit(from: Vector3, light_weapon: bool, armored: bool) -> void:
	if vehicle == null or vehicle.is_queued_for_deletion():
		return

	var hit := pick_hit_point(from)
	var point: Vector3 = hit[0]
	var normal: Vector3 = hit[1]
	var world_normal := (vehicle.global_transform.basis * normal).normalized()
	spawn_sparks(vehicle.global_transform * point, world_normal, armored)

	# Heavy hits knock chips of bodywork off.
	if not light_weapon:
		spawn_chips(vehicle.global_transform * point, world_normal)

	# Armour shrugs the round off: ricochet sparks, no hole.
	if armored:
		return

	var now := Time.get_ticks_msec()
	if now - last_hole_ms < HOLE_INTERVAL_MS:
		return
	last_hole_ms = now
	add_mark(point, normal, not light_weapon)


func update_damage_state(fraction: float) -> void:
	if fraction < 0.5 and smoke == null:
		smoke = make_emitter(Color(0.55, 0.55, 0.55, 0.55), 20, 1.8, 1.0, 3.0)
	if fraction < 0.25 and fire == null:
		fire = make_emitter(Color(1.0, 0.55, 0.15, 0.95), 18, 0.6, 0.9, 2.0)
		# Smoke turns black once it's burning.
		if smoke != null:
			(smoke.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = Color(0.12, 0.11, 0.1, 0.65)


# --- Hit placement ------------------------------------------------------

# Bounding box of the vehicle's meshes in its own space.
func get_bounds() -> AABB:
	if bounds_ready:
		return bounds

	var inverse := vehicle.global_transform.affine_inverse()
	var first := true
	for mesh in vehicle.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = inverse * mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	bounds_ready = true
	return bounds


# A point on the vehicle's box (local space) and the face normal: usually
# the roof (we look from above), otherwise the side facing the shooter.
func get_face(from_local: Vector3, box: AABB) -> Vector3:
	var to_shooter := from_local - box.get_center()
	if randf() < 0.55 or Vector2(to_shooter.x, to_shooter.z).length() < 0.01:
		return Vector3.UP
	if absf(to_shooter.x) > absf(to_shooter.z):
		return Vector3(signf(to_shooter.x), 0, 0)
	return Vector3(0, 0, signf(to_shooter.z))


func pick_hit_point(from: Vector3) -> Array:
	var box := get_bounds()
	var normal := get_face(vehicle.global_transform.affine_inverse() * from, box)

	var point := box.position + box.size * Vector3(randf_range(0.15, 0.85), randf_range(0.35, 0.85), randf_range(0.15, 0.85))
	if normal.y > 0.0:
		point.y = box.end.y
	elif normal.x != 0.0:
		point.x = box.end.x if normal.x > 0.0 else box.position.x
	else:
		point.z = box.end.z if normal.z > 0.0 else box.position.z
	return [point, normal]


# --- Holes --------------------------------------------------------------

func add_mark(point: Vector3, normal: Vector3, heavy: bool) -> void:
	var decal := Decal.new()
	decal.texture_albedo = scorch_texture if heavy else hole_texture
	var size := randf_range(1.2, 1.6) if heavy else randf_range(0.7, 0.9)
	# Deep enough to reach down from the top of the box to the roof panels.
	var depth := 1.4 if normal.y > 0.0 else 0.8
	decal.size = Vector3(size, depth, size)
	decal.upper_fade = 0.05
	decal.lower_fade = 0.05

	# Decals project along their -Y axis, so point Y out of the surface.
	var side := Vector3.UP.cross(normal)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var basis := Basis(side, normal, side.cross(normal)).rotated(normal, randf() * TAU)
	decal.transform = Transform3D(basis, point)
	vehicle.add_child(decal)

	holes.append(decal)
	if holes.size() > MAX_HOLES:
		var oldest: Node = holes.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


static func make_mark_texture(heavy: bool) -> ImageTexture:
	var n := 32
	var image := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 if heavy else 7
	var center := Vector2(n, n) * 0.5 - Vector2(0.5, 0.5)

	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(center) / (n * 0.5)
			var color := Color(0, 0, 0, 0)
			if heavy:
				# Scorched dent: black core fading out through soot, ragged edge.
				var edge := 0.85 + rng.randf_range(-0.15, 0.1)
				if d < 0.25:
					color = Color(0.03, 0.03, 0.03, 1.0)
				elif d < edge:
					color = Color(0.1, 0.08, 0.06, 0.95 * (1.0 - (d - 0.25) / (edge - 0.25)) + 0.05)
			else:
				# Bullet hole: dark centre, bright torn-metal rim, soot ring.
				if d < 0.35:
					color = Color(0.02, 0.02, 0.02, 1.0)
				elif d < 0.6:
					color = Color(0.7, 0.68, 0.62, 0.95)
				elif d < 0.85 + rng.randf_range(-0.1, 0.05):
					color = Color(0.12, 0.1, 0.08, 0.55)
			image.set_pixel(x, y, color)

	return ImageTexture.create_from_image(image)


# --- Sparks -------------------------------------------------------------

static func make_spark_mesh() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.14, 0.14, 0.14)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	return mesh


func spawn_sparks(at: Vector3, normal: Vector3, ricochet: bool) -> void:
	var scene := vehicle.get_tree().current_scene
	if scene == null:
		return

	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.explosiveness = 0.95
	sparks.amount = 14 if ricochet else 9
	sparks.lifetime = 0.35
	sparks.local_coords = false
	sparks.mesh = spark_mesh
	sparks.direction = normal
	sparks.spread = 55.0
	sparks.initial_velocity_min = 7.0
	sparks.initial_velocity_max = 16.0 if ricochet else 12.0
	sparks.gravity = Vector3(0, -22, 0)
	sparks.scale_amount_min = 0.7
	sparks.scale_amount_max = 1.3
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 0.75))
	ramp.set_color(1, Color(1.0, 0.45, 0.1))
	sparks.color_ramp = ramp
	scene.add_child(sparks)
	sparks.global_position = at
	sparks.emitting = true
	scene.get_tree().create_timer(0.6).timeout.connect(sparks.queue_free)


# --- Smoke and fire -----------------------------------------------------

func make_emitter(color: Color, amount: int, life: float, size: float, rise: float) -> CPUParticles3D:
	var box := get_bounds()
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = life
	particles.local_coords = false
	particles.position = Vector3(box.get_center().x, box.end.y, box.get_center().z)
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.5
	particles.direction = Vector3.UP
	particles.spread = 12.0
	particles.initial_velocity_min = rise * 0.6
	particles.initial_velocity_max = rise
	particles.gravity = Vector3(0, 0.6, 0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1, 0.8))
	particles.scale_amount_curve = curve

	var mesh := SphereMesh.new()
	mesh.radius = size * 0.5
	mesh.height = size
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	mesh.material = material
	particles.mesh = mesh

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = ramp

	vehicle.add_child(particles)
	return particles


# --- Chips --------------------------------------------------------------

func spawn_chips(at: Vector3, normal: Vector3) -> void:
	if paints.is_empty():
		for mesh in vehicle.find_children("*", "MeshInstance3D", true, false):
			var material: Material = mesh.material_override
			if material == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
				material = mesh.mesh.surface_get_material(0)
			if material != null and not paints.has(material):
				paints.append(material)
	if paints.is_empty():
		return

	var scene := vehicle.get_tree().current_scene
	for i in randi_range(2, 4):
		Debris.spawn_chip(scene, at, normal, paints.pick_random())


# The scorch texture, for ground marks too (creates it if no vehicle has yet).
static func scorch_texture_for_ground() -> Texture2D:
	if scorch_texture == null:
		hole_texture = make_mark_texture(false)
		scorch_texture = make_mark_texture(true)
		spark_mesh = make_spark_mesh()
	return scorch_texture
