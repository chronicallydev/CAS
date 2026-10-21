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

# Switched from the test range's LOOK section.
static var chunky: bool = true

const FPS := 12.0
# Outline thickness in world units: about one low-res pixel at the default
# zoom, so even a small bullet impact keeps a visible rim.
const OUTLINE := 0.45

static var blob_mesh: SphereMesh
static var white: StandardMaterial3D
static var black: StandardMaterial3D
# Black, drawn inside out: an "inverted hull" behind the blob shows only as
# a rim around it.
static var hull: StandardMaterial3D
# The debris streaks in solid black: the scene's glowing orange ones come
# out white and vanish into the sand.
static var streak_mesh: Mesh

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
		if streak_mesh == null:
			streak_mesh = debris.draw_pass_1.duplicate()
			streak_mesh.surface_set_material(0, OneBit.solid(Color.BLACK))
		debris.draw_pass_1 = streak_mesh
		build_blobs.call_deferred()
	else:
		fire.emitting = true
		smoke.emitting = true
	debris.emitting = true
	play_sound.call_deferred()

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
	white = unshaded(Color.WHITE)
	black = unshaded(Color.BLACK)
	hull = unshaded(Color.BLACK)
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
		add_blob(Vector3.ZERO, 0, 2, 9.0, white, 0.0)
		for i in 3:
			var at := Vector3(randf_range(-2.5, 2.5), randf_range(0.0, 1.0), randf_range(-2.5, 2.5))
			add_blob(at, randi_range(1, 2), randi_range(3, 4), randf_range(4.0, 5.0), black, 0.6)
		step_blobs()
		return
	# The flash: one big white ball for the first two frames.
	# Sizes are diameters at scale 1, to match the old particle fireball.
	add_blob(Vector3.ZERO, 0, 2, 4.0, white, 0.0)
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
	# Only white needs an outline; black already stands out.
	var rim: MeshInstance3D = null
	if material == white:
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
