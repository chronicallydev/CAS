extends Node3D
@onready var debris: GPUParticles3D = %Debris
@onready var fire: GPUParticles3D = %Fire
@onready var smoke: GPUParticles3D = %Smoke



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	fire.emitting = true
	smoke.emitting = true
	debris.emitting = true

	# Scale is set by whoever spawned us, right after adding us to the tree.
	play_sound.call_deferred()

	# Free the effect once the particles are done.
	await get_tree().create_timer(3.0).timeout
	queue_free()


# Small effects (hit sparks, muzzle flashes) stay silent; their source
# plays its own sound.
func play_sound() -> void:
	var size := scale.x

	if size < 0.3:
		return
	if size < 0.65:
		Sfx.play_3d("explosion_small", global_position)
	else:
		Sfx.play_3d("explosion", global_position)
		Global.shake(0.22, global_position)
