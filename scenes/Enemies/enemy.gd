extends Node3D

@export var speed: float = 5.0

func _ready() -> void:
	add_to_group("enemies")

func _physics_process(delta: float) -> void:
	var direction: Vector3 = Vector3(
		-global_position.x,
		0.0,
		-global_position.z
	)

	if direction.length() > 0.01:
		direction = direction.normalized()
		global_position += direction * speed * delta
	
