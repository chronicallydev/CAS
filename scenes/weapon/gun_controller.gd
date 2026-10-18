extends Node3D

@export_group("References")
@export var camera: Camera3D
@export var explosion_scene: PackedScene
@export var cursor : TextureRect
@onready var shoot_sound: AudioStreamPlayer3D = $ShootSound
@onready var kill_count: Label = %KillCount



@export_group("Weapon")
@export_range(1.0, 3000.0, 1.0) var rpm: float = 600.0
@export_range(0.0, 10.0, 0.1) var impact_delay: float = 1.8
@export_range(0.0, 50.0, 0.1) var impact_spread: float = 2.5

@export_group("Damage")
@export_range(0.1, 100.0, 0.1) var explosion_radius: float = 5.0


@export var shake_strength: float = 5.0


@export_group("Targeting")
@export_flags_3d_physics var collision_mask: int = 1
@export_range(10.0, 10000.0, 10.0) var ray_length: float = 5000.0

var is_firing: bool = false
var fire_timer: float = 0.0
var locked_target: Vector3 = Vector3.ZERO
var kills : float = 0

@onready var default_cursor_size = cursor.scale

func _process(delta: float) -> void:
	
	kill_count.text = str(kills)
	
	if is_firing:
		cursor.scale = default_cursor_size * 0.9
	else:
		cursor.scale = default_cursor_size

	var mouse_pos := cursor.get_global_mouse_position()
	var cursor_size := cursor.size * cursor.scale
	var shake_offset := Vector2.ZERO

	if is_firing:
		shake_offset = Vector2(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength)
		)

	cursor.global_position = mouse_pos - cursor_size * 0.5 + shake_offset

	if not is_firing:
		return

	var interval: float = 60.0 / maxf(rpm, 1.0)
	fire_timer -= delta

	while fire_timer <= 0.0:
		fire_round(locked_target)
		fire_timer += interval

	
	

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not is_firing and camera != null:
					var hit: Variant = get_mouse_world_position()

					# Only fire when the mouse ray hits a collider.
					if hit != null:
						locked_target = hit
						is_firing = true
						fire_timer = 0.0
			else:
				is_firing = false


# Cast a ray from the camera through the mouse position.
func get_mouse_world_position() -> Variant:
	var mouse_pos := get_viewport().get_mouse_position()

	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_direction := camera.project_ray_normal(mouse_pos)

	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * ray_length,
		collision_mask
	)

	query.collide_with_areas = true

	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if result.is_empty():
		return null

	return result["position"]


# Each shot schedules an explosion at the locked target.
func fire_round(target: Vector3) -> void:
	if shoot_sound != null:
		# Slightly randomize pitch and loudness for each shot.
		shoot_sound.pitch_scale = randf_range(0.8, 1)
		shoot_sound.volume_db = randf_range(-2.0, 0.0)
		shoot_sound.play()

	var angle := randf() * TAU
	var radius := sqrt(randf()) * impact_spread

	var spread := Vector3(
		cos(angle) * radius,
		0.0,
		sin(angle) * radius
	)

	schedule_explosion(target + spread)


func schedule_explosion(position: Vector3) -> void:
	await get_tree().create_timer(impact_delay).timeout

	if not is_inside_tree() or explosion_scene == null:
		return

	var explosion := explosion_scene.instantiate() as Node3D

	if explosion == null:
		return

	get_tree().current_scene.add_child(explosion)
	explosion.global_position = position

	# Find and delete enemies near the explosion.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue

		if not enemy is Node3D:
			continue

		var distance = enemy.global_position.distance_to(position)

		if distance <= explosion_radius:
			enemy.queue_free()
			kills += 0.5
