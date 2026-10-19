extends RefCounted

# Everything that happens when a soldier dies:
# - the body collapses (light weapons) or is thrown by the blast,
# - helmet and rifle drop; blasts tear limbs off (bleeding as they fly) and
#   big ones char the body,
# - dust where it lands, a scorch mark under blast kills, and (if enabled)
#   a large blood pool where the body rests, each one shaped differently,
# - a squad scream when several die at once,
# - nearby soldiers panic and dive away from blasts.

const Debris := preload("res://scenes/Enemies/debris.gd")
const Corpse := preload("res://scenes/Enemies/corpse.gd")
const VehicleDamage := preload("res://scenes/Enemies/vehicle_damage.gd")

# Blasts at least this strong tear limbs off and char the body (Javelin, FAB).
const BIG_BLAST := 2.5
# Cannon and rocket hits can tear a limb off too.
const LIMB_BLAST := 0.8
const MAX_GROUND_MARKS := 40
const MAX_BLOOD_MARKS := 80
const BLOOD_VARIANTS := 8
const PANIC_RADIUS := 12.0

static var ground_marks: Array = []
static var blood_marks: Array = []
static var blood_textures: Array = []
static var recent_deaths: Array = []
static var last_scream_ms: int = -100000
static var blood_mesh: Mesh


static func kill(soldier: Node3D, from: Vector3, force: float, light_weapon: bool) -> void:
	var scene := soldier.get_tree().current_scene
	if scene == null:
		return

	var position := soldier.global_position
	var away := position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var big := force >= BIG_BLAST
	var ground: float = soldier.ground_y

	drop_gear(soldier, away, force)
	# Big blasts always tear limbs off; cannon and rocket hits sometimes do.
	if big or (force >= LIMB_BLAST and randf() < 0.5):
		tear_limbs(soldier, away, force, big)

	var corpse := Corpse.spawn(soldier.model, away, force, ground)
	if corpse != null:
		if big:
			corpse.char_meshes()
		if Global.blood:
			# A big pool where the body comes to rest.
			corpse.landed.connect(func(at: Vector3, heading: Vector3) -> void:
				add_blood(scene, at, heading, randf_range(4.2, 5.2)))

	var ground_point := Vector3(position.x, ground, position.z)
	if not light_weapon:
		add_ground_mark(scene, ground_point, VehicleDamage.scorch_texture_for_ground(), randf_range(2.0, 3.0))
	if Global.blood:
		spray_blood(scene, position + Vector3.UP * 1.6, away)
		# Spatter where they were hit (the body may be thrown away from it).
		add_blood(scene, ground_point, away, randf_range(1.6, 2.2))

	squad_scream(position)
	if not light_weapon:
		panic_nearby(soldier, from)


# Helmet pops off and the rifle clatters down.
static func drop_gear(soldier: Node3D, away: Vector3, force: float) -> void:
	var push := clampf(2.0 + force, 2.0, 10.0)
	for gear in [soldier.helmet, soldier.rifle]:
		if gear == null or not is_instance_valid(gear):
			continue
		var velocity: Vector3 = away * push * randf_range(0.6, 1.2) + Vector3.UP * randf_range(4.0, 7.0) \
			+ Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		var piece := Debris.throw_node(gear, velocity, randf_range(8.0, 14.0), 4.0, force >= BIG_BLAST, true)
		if piece != null:
			piece.land_sound = "gear_clank"


# Throw limbs off on their own: 2-4 from big blasts, 1 from smaller ones.
# They keep their colour so they're easy to spot, and bleed as they fly.
static func tear_limbs(soldier: Node3D, away: Vector3, force: float, big: bool) -> void:
	var limbs := [soldier.arm_left, soldier.arm_right, soldier.leg_left, soldier.leg_right]
	limbs.shuffle()
	var scene := soldier.get_tree().current_scene
	for i in (randi_range(2, 4) if big else 1):
		if not Debris.can_spawn():
			return
		var limb: Node3D = limbs[i]
		var velocity: Vector3 = away * clampf(4.0 + force, 5.0, 14.0) * randf_range(0.7, 1.3) \
			+ Vector3.UP * randf_range(12.0, 18.0) + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		var piece := Debris.throw_node(limb, velocity, randf_range(7.0, 12.0), 6.0, false, true)
		if piece == null or not Global.blood:
			continue
		piece.add_blood_trail(get_blood_drop_mesh())
		var trail_dir := Vector3(velocity.x, 0, velocity.z)
		piece.touched_ground.connect(func(at: Vector3) -> void:
			add_blood(scene, at, trail_dir, randf_range(1.4, 2.0)))


# Scorch mark on the ground, with a cap (oldest goes first).
static func add_ground_mark(scene: Node, at: Vector3, texture: Texture2D, size: float) -> void:
	var decal := make_ground_decal(scene, at, texture, Vector3(size, 0.8, size), randf() * TAU)
	ground_marks.append(decal)
	ground_marks = trim(ground_marks, MAX_GROUND_MARKS)


# Blood on the ground, stretched and turned along `heading` (the way the
# body or limb was moving). Every decal gets a random texture variant, size
# and proportions, so no two look alike. These stay until the cap is hit.
static func add_blood(scene: Node, at: Vector3, heading: Vector3, size: float) -> void:
	var yaw := atan2(heading.x, heading.z) if heading.length() > 0.1 else randf() * TAU
	var extent := Vector3(size * randf_range(0.75, 1.0), 1.0, size * randf_range(1.0, 1.3))
	var decal := make_ground_decal(scene, at, get_blood_texture(), extent, yaw + randf_range(-0.3, 0.3))
	blood_marks.append(decal)
	blood_marks = trim(blood_marks, MAX_BLOOD_MARKS)


static func make_ground_decal(scene: Node, at: Vector3, texture: Texture2D, extent: Vector3, yaw: float) -> Decal:
	var decal := Decal.new()
	decal.texture_albedo = texture
	# Shallow, so it marks the ground (and bodies lying on it), not much else.
	decal.size = extent
	decal.upper_fade = 0.05
	decal.lower_fade = 0.05
	decal.rotation.y = yaw
	scene.add_child(decal)
	decal.global_position = at
	return decal


# Remove the oldest decals over the cap (and ones freed with an old scene).
static func trim(marks: Array, cap: int) -> Array:
	marks = marks.filter(func(mark): return is_instance_valid(mark))
	while marks.size() > cap:
		var oldest: Node = marks.pop_front()
		oldest.queue_free()
	return marks


# One of several procedural blood textures. Each is built the first time
# it's picked, so the cost is spread out.
static func get_blood_texture() -> Texture2D:
	var index := randi() % BLOOD_VARIANTS
	if blood_textures.size() < BLOOD_VARIANTS:
		blood_textures.resize(BLOOD_VARIANTS)
	if blood_textures[index] == null:
		blood_textures[index] = make_blood_texture(index)
	return blood_textures[index]


# A pool made of overlapping blobs, a smear trailing along +V (the decal's
# heading), and scattered droplets. Shade varies per variant.
static func make_blood_texture(variant: int) -> ImageTexture:
	var n := 48
	var image := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant * 7919

	var blobs := []
	var center := Vector2(n * 0.5 + rng.randf_range(-3, 3), n * 0.42 + rng.randf_range(-3, 3))
	for i in rng.randi_range(7, 11):
		var offset := Vector2(rng.randf_range(-8, 8), rng.randf_range(-7, 7))
		blobs.append([center + offset, rng.randf_range(6.0, 11.0)])
	# Smear trailing the way the body was moving.
	var smear := center
	for i in rng.randi_range(3, 6):
		smear += Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(3.0, 5.0))
		blobs.append([smear, rng.randf_range(1.5, 4.0) * (1.0 - i * 0.12)])
	# Droplets.
	for i in rng.randi_range(10, 22):
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(10.0, 22.0)
		blobs.append([center + Vector2(cos(angle), sin(angle)) * dist, rng.randf_range(0.6, 1.8)])

	var base := Color(rng.randf_range(0.3, 0.42), rng.randf_range(0.02, 0.05), rng.randf_range(0.02, 0.05), 0.9)
	for y in n:
		for x in n:
			var p := Vector2(x, y)
			for blob in blobs:
				var d: float = p.distance_to(blob[0])
				if d < blob[1]:
					# Darker towards the middle of each blob, for a little depth.
					image.set_pixel(x, y, base.darkened(0.25 * (1.0 - d / blob[1])))
					break
	return ImageTexture.create_from_image(image)


static func get_blood_drop_mesh() -> Mesh:
	if blood_mesh == null:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.14, 0.14, 0.14)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.45, 0.04, 0.04)
		mesh.material = material
		blood_mesh = mesh
	return blood_mesh


# A few dark-red pixels flying out (stylised, not gory).
static func spray_blood(scene: Node, at: Vector3, away: Vector3) -> void:
	var drops := CPUParticles3D.new()
	drops.one_shot = true
	drops.explosiveness = 0.95
	drops.amount = 14
	drops.lifetime = 0.5
	drops.local_coords = false
	drops.mesh = get_blood_drop_mesh()
	drops.direction = (away + Vector3.UP).normalized()
	drops.spread = 40.0
	drops.initial_velocity_min = 3.0
	drops.initial_velocity_max = 6.0
	drops.gravity = Vector3(0, -25, 0)
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(drops)
	drops.global_position = at
	drops.emitting = true
	scene.get_tree().create_timer(0.8).timeout.connect(drops.queue_free)


# When three or more soldiers die within a moment, play a distant shout.
static func squad_scream(at: Vector3) -> void:
	var now := Time.get_ticks_msec()
	recent_deaths.append(now)
	recent_deaths = recent_deaths.filter(func(time): return now - time < 300)
	if recent_deaths.size() >= 3 and now - last_scream_ms > 1500:
		last_scream_ms = now
		Sfx.play_3d("scream", at, 0.0, randf_range(0.9, 1.1))


static func panic_nearby(soldier: Node3D, from: Vector3) -> void:
	for node in soldier.get_tree().get_nodes_in_group("enemies"):
		if node == soldier or not node.has_method("react_to_blast") or node.is_queued_for_deletion():
			continue
		if node.global_position.distance_to(soldier.global_position) <= PANIC_RADIUS:
			node.react_to_blast(from)
