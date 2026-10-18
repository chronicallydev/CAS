extends "res://scenes/Enemies/enemy_base.gd"

# Infantry: walks straight at the base.

@export var speed: float = 5.0


func _physics_process(delta: float) -> void:
	global_position += flat_direction_to_center() * speed * delta
