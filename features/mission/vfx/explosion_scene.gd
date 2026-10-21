class_name ExplosionScene
extends Node3D

# The shared explosion. Two looks:
#   chunky (retro) - hard-edged blobs stepped at 12 fps: a white flash, then
#                    fire that cools from yellow through orange and red,
#                    then smoke puffs that rise and pop out instead of
#                    fading. The debris sparks stay.
#   soft           - the original particle fireball and smoke.

# Switched from the test range's LOOK section.
static var chunky: bool = true

const FPS := 12.0
const FIRE_RAMP: Array[Color] = [
	Color(1.0, 1.0, 0.85), Color(1.0, 0.9, 0.35), Color(1.0, 0.6, 0.15),
	Color(0.9, 0.3, 0.1), Color(0.55, 0.16, 0.08)]
const SMOKE_RAMP: Array[Color] = [
	Color(0.42, 0.4, 0.38), Color(0.3, 0.28, 0.27), Color(0.2, 0.19, 0.18)]

static var blob_mesh: SphereMesh

@onready var debris: GPUParticles3D = %Debris
@onready var fire: GPUParticles3D = %Fire
@onready var smoke: GPUParticles3D = %Smoke

# Each: {node, material, start, life, size, ramp, rise}, times in frames.
var blobs: Array[Dictionary] = []
var age: float = 0.0
var frame: int = -1


func _ready() -> void:
	debris.emitting = true
	# Scale is set by whoever spawned us, right after adding us to the tree.
	if chunky:
		build_blobs.call_deferred()
	else:
		fire.emitting = true
		smoke.emitting = true
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


func build_blobs() -> void:
	if blob_mesh == null:
		blob_mesh = SphereMesh.new()
		blob_mesh.radial_segments = 8
		blob_mesh.rings = 4
	# Bullet impacts and sparks get a short pop; blasts the full show.
	var small := scale.x < 0.5
	# The flash: one big white ball for the first two frames.
	# Sizes are diameters at scale 1, to match the old particle fireball.
	add_blob(Vector3.ZERO, 0, 2, 4.0, [Color.WHITE], 0.0)
	for i in (2 if small else 6):
		var at := Vector3(randf_range(-1.4, 1.4), randf_range(0.0, 1.0), randf_range(-1.4, 1.4))
		add_blob(at, randi_range(0, 2), randi_range(3, 4) if small else randi_range(4, 6), randf_range(1.8, 2.6), FIRE_RAMP, 0.1)
	for i in (0 if small else 4):
		var at := Vector3(randf_range(-1.2, 1.2), randf_range(0.8, 1.6), randf_range(-1.2, 1.2))
		add_blob(at, randi_range(3, 5), randi_range(6, 9), randf_range(1.5, 2.2), SMOKE_RAMP, 0.35)
	step_blobs()


func add_blob(at: Vector3, start: int, life: int, size: float, ramp: Array[Color], rise: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var node := MeshInstance3D.new()
	node.mesh = blob_mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = at
	node.visible = false
	add_child(node)
	blobs.append({"node": node, "material": material, "start": start, "life": life,
		"size": size, "ramp": ramp, "rise": rise, "base": at})


# One 12 fps frame: each blob swells, cools a colour step and rises,
# all in whole steps, and vanishes at the end of its life.
func step_blobs() -> void:
	for blob in blobs:
		var node: MeshInstance3D = blob.node
		var t: int = maxi(frame, 0) - blob.start
		node.visible = t >= 0 and t < blob.life
		if not node.visible:
			continue
		var progress: float = float(t) / blob.life
		var ramp: Array[Color] = blob.ramp
		blob.material.albedo_color = ramp[mini(floori(progress * ramp.size()), ramp.size() - 1)]
		# Swells fast, then shrinks a little as it burns out.
		var swell: float = 0.6 + 0.4 * minf(t / 2.0, 1.0) - 0.25 * maxf(progress - 0.6, 0.0)
		node.scale = Vector3.ONE * blob.size * swell
		node.position = blob.base + Vector3.UP * blob.rise * t


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
