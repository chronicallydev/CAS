class_name ExplosionScene
extends Node3D

# The shared explosion. Two looks:
#   chunky (retro) - hard-edged blobs stepped at 12 fps, made for the 1-bit
#                    look: a white flash, then solid white fire balls with
#                    black outlines, then solid black smoke puffs that rise
#                    and pop out instead of fading. Bullet impacts (scale
#                    under 0.5) are just the flash and black dust kicks.
#                    The debris sparks stay.
#   soft           - the original particle fireball and smoke.
# Mid-tones would dither into the sand, so every blob is pure black or
# white; the outlines keep the white fire from vanishing into bright ground.
# With a colour palette the fire is yellow with red rims and the smoke dark
# grey (OneBit.ROLES).

# Switched from the test range's LOOK section.
static var chunky: bool = true

const FPS := 12.0
# Outline thickness in world units: about one low-res pixel at the default
# zoom, so even a small bullet impact keeps a visible rim.
const OUTLINE := 0.45
# Explosions at least this big, this close to the ground (Helicopter.ground_y),
# leave a scorch mark there; the oldest go once there are SCORCH_LIMIT, and
# each fades after SCORCH_TIME seconds.
const GROUND_Y := -0.4
const SCORCH_MIN_SCALE := 0.8
const SCORCH_MAX_HEIGHT := 4.0
const SCORCH_LIMIT := 40
const SCORCH_TIME := 25.0

static var blob_mesh: SphereMesh
# Whether the materials were made for a monochrome palette, so a palette
# switch remakes them.
static var made_mono: bool = true
# The first-frame flash (pure white), then fire and smoke: white and black
# in 1-bit (see OneBit.ROLES).
static var flash: StandardMaterial3D
static var white: StandardMaterial3D
static var black: StandardMaterial3D
# The fire's rim colour, drawn inside out: an "inverted hull" behind the
# blob shows only as a rim around it.
static var hull: StandardMaterial3D
# The debris streaks in solid smoke colour: the scene's glowing orange
# ones come out white and vanish into the sand.
static var streak_mesh: Mesh
static var scorches: Array[Node3D] = []

@onready var debris: GPUParticles3D = %Debris
@onready var fire: GPUParticles3D = %Fire
@onready var smoke: GPUParticles3D = %Smoke

# Each: {node, rim, start, life, size, rise, base}, times in frames.
var blobs: Array[Dictionary] = []
var age: float = 0.0
var frame: int = -1


func _ready() -> void:
	# Scale is set by whoever spawned us, right after adding us to the tree.
	if chunky:
		if streak_mesh == null or made_mono != OneBit.mono():
			make_materials()
			streak_mesh = debris.draw_pass_1.duplicate()
			streak_mesh.surface_set_material(0, OneBit.solid(OneBit.fill("smoke")))
		debris.draw_pass_1 = streak_mesh
		build_blobs.call_deferred()
	else:
		fire.emitting = true
		smoke.emitting = true
	debris.emitting = true
	play_sound.call_deferred()
	leave_scorch.call_deferred()

	# Free the effect once the particles are done.
	await get_tree().create_timer(3.0).timeout
	queue_free()


func _process(delta: float) -> void:
	if blobs.is_empty():
		return
	age += delta
	var now := floori(age * FPS)
	if now != frame:
		frame = now
		step_blobs()


static func make_materials() -> void:
	blob_mesh = SphereMesh.new()
	blob_mesh.radial_segments = 8
	blob_mesh.rings = 4
	made_mono = OneBit.mono()
	flash = unshaded(Color.WHITE)
	white = unshaded(OneBit.fill("fire"))
	black = unshaded(OneBit.fill("smoke"))
	hull = unshaded(OneBit.rim_color("fire"))
	hull.cull_mode = BaseMaterial3D.CULL_FRONT


static func unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


func build_blobs() -> void:
	if blob_mesh == null:
		make_materials()
	# Bullet impacts: a flash, then black dust kicked up off the sand. Sized
	# up against their small scale so they read wider than the tracers.
	if scale.x < 0.5:
		add_blob(Vector3.ZERO, 0, 2, 9.0, flash, 0.0)
		for i in 3:
			var at := Vector3(randf_range(-2.5, 2.5), randf_range(0.0, 1.0), randf_range(-2.5, 2.5))
			add_blob(at, randi_range(1, 2), randi_range(3, 4), randf_range(4.0, 5.0), black, 0.6)
		step_blobs()
		return
	# The flash: one big white ball for the first frame, then fire.
	# Sizes are diameters at scale 1, to match the old particle fireball.
	add_blob(Vector3.ZERO, 0, 1, 5.5, flash, 0.0)
	add_blob(Vector3.ZERO, 1, 2, 4.0, white, 0.0)
	for i in 6:
		var at := Vector3(randf_range(-1.4, 1.4), randf_range(0.0, 1.0), randf_range(-1.4, 1.4))
		add_blob(at, randi_range(0, 2), randi_range(4, 6), randf_range(1.8, 2.6), white, 0.1)
	for i in 4:
		var at := Vector3(randf_range(-1.2, 1.2), randf_range(0.8, 1.6), randf_range(-1.2, 1.2))
		add_blob(at, randi_range(3, 5), randi_range(6, 9), randf_range(1.5, 2.2), black, 0.35)
	step_blobs()


func add_blob(at: Vector3, start: int, life: int, size: float, material: Material, rise: float) -> void:
	var node := make_mesh(material)
	node.position = at
	node.visible = false
	add_child(node)
	# Only the light blobs need an outline; dark ones already stand out.
	var rim: MeshInstance3D = null
	if material == white or material == flash:
		rim = make_mesh(hull)
		node.add_child(rim)
	blobs.append({"node": node, "rim": rim, "start": start, "life": life, "size": size, "rise": rise, "base": at})


func make_mesh(material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = blob_mesh
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


# One 12 fps frame: each blob swells, rises and burns down in whole steps,
# and vanishes at the end of its life.
func step_blobs() -> void:
	for blob in blobs:
		var node: MeshInstance3D = blob.node
		var t: int = maxi(frame, 0) - blob.start
		node.visible = t >= 0 and t < blob.life
		if not node.visible:
			continue
		var progress: float = float(t) / blob.life
		# Swells fast, then shrinks as it burns out.
		var swell: float = 0.6 + 0.4 * minf(t / 2.0, 1.0) - 0.5 * maxf(progress - 0.5, 0.0)
		node.scale = Vector3.ONE * blob.size * swell
		node.position = blob.base + Vector3.UP * blob.rise * t
		if blob.rim != null:
			# The same world thickness whatever the blob's size.
			var diameter: float = blob.size * swell * scale.x
			blob.rim.scale = Vector3.ONE * (diameter + OUTLINE * 2.0) / diameter


# A flat burn on the sand: a few brown ovals round a dark middle, flat and
# unlit so they never pass for something standing there. Colour palettes
# only: in 1-bit a dark patch would read as an enemy.
func leave_scorch() -> void:
	if OneBit.mono() or scale.x < SCORCH_MIN_SCALE or global_position.y > GROUND_Y + SCORCH_MAX_HEIGHT:
		return
	var mark := Node3D.new()
	MissionContext.spawn_parent(self).add_child(mark)
	mark.global_position = Vector3(global_position.x, GROUND_Y + 0.03, global_position.z)
	mark.rotation.y = randf() * TAU
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.01
	disc.radial_segments = 10
	var size := scale.x
	for i in 3:
		var part := MeshInstance3D.new()
		part.mesh = disc
		part.material_override = OneBit.solid(OneBit.colour("brown"))
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.position = Vector3(randf_range(-0.8, 0.8), 0.0, randf_range(-0.8, 0.8)) * size
		part.scale = Vector3(randf_range(1.4, 2.0), 1.0, randf_range(1.0, 1.6)) * size
		mark.add_child(part)
	var middle := MeshInstance3D.new()
	middle.mesh = disc
	middle.material_override = OneBit.solid(OneBit.colour("dark_grey"))
	middle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	middle.position.y = 0.01
	middle.scale = Vector3(0.9, 1.0, 0.7) * size
	mark.add_child(middle)

	# Untyped: a freed mark fails a typed parameter.
	scorches = scorches.filter(func(old: Variant) -> bool: return is_instance_valid(old))
	scorches.append(mark)
	if scorches.size() > SCORCH_LIMIT:
		scorches.pop_front().queue_free()
	# Fades by shrinking away (solid colours can't fade).
	var fade := mark.create_tween()
	fade.tween_interval(SCORCH_TIME)
	fade.tween_property(mark, "scale", Vector3(0.01, 1.0, 0.01), 2.0)
	fade.tween_callback(mark.queue_free)


# Small effects (hit sparks, muzzle flashes) stay silent; their source
# plays its own sound.
func play_sound() -> void:
	var size := scale.x

	if size < 0.3:
		return
	# Rockets (0.8) and missiles stay in the lighter tier so salvos don't
	# stack six full booms and shakes; cannon shells and bigger get the full one.
	if size < 0.9:
		Sfx.play_3d("explosion_small", global_position)
	else:
		Sfx.play_3d("explosion", global_position)
		var mission := MissionContext.of(self)
		if mission != null:
			mission.shake(0.22, global_position)
