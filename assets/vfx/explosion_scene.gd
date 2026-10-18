extends Node3D
@onready var debris: GPUParticles3D = %Debris
@onready var fire: GPUParticles3D = %Fire
@onready var smoke: GPUParticles3D = %Smoke



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	fire.emitting = true
	smoke.emitting = true
	debris.emitting = true
