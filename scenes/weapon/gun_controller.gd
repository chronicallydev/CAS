extends Node3D

enum Weapon { CANNON, MINIGUN, JAVELIN }
const WEAPON_NAMES := ["CANNON", "MINIGUN", "JAVELIN"]

const JavelinMissile := preload("res://scenes/weapon/javelin_missile.gd")
const JavelinExplosion := preload("res://assets/vfx/javelin_explosion.gd")

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


@export_group("Minigun")
@export_range(1.0, 6000.0, 1.0) var minigun_rpm: float = 2400.0
@export_range(0.0, 10.0, 0.05) var minigun_impact_delay: float = 0.35
@export_range(0.0, 50.0, 0.1) var minigun_spread: float = 1.5
@export_range(0.1, 100.0, 0.1) var minigun_radius: float = 2.5
@export_range(0.05, 2.0, 0.05) var minigun_explosion_scale: float = 0.35
@export var minigun_shake_strength: float = 1.5


@export_group("Javelin")
@export_range(0.1, 30.0, 0.1) var javelin_reload: float = 2.0
@export_range(1.0, 100.0, 0.5) var javelin_speed: float = 15.0
# Speed the missile accelerates to in its final dive.
@export_range(1.0, 300.0, 1.0) var javelin_dive_speed: float = 60.0
@export_range(0.1, 100.0, 0.1) var javelin_radius: float = 8.0
# Enemies this close to the clicked point get locked and tracked.
@export_range(0.0, 50.0, 0.5) var javelin_lock_radius: float = 10.0
# How far above the launch point the missile climbs before diving.
@export_range(0.0, 100.0, 1.0) var javelin_climb: float = 15.0
# How far below the camera the missile is launched from.
@export_range(0.0, 50.0, 0.5) var javelin_launch_drop: float = 3.0


@export_group("Targeting")
@export_flags_3d_physics var collision_mask: int = 1
@export_range(10.0, 10000.0, 10.0) var ray_length: float = 5000.0

var current_weapon: Weapon = Weapon.CANNON
var is_firing: bool = false
var fire_timer: float = 0.0
var locked_target: Vector3 = Vector3.ZERO
var kills : float = 0
var javelin_cooldown: float = 0.0
var weapon_label: Label

@onready var default_cursor_size = cursor.scale


func _ready() -> void:
	# Weapon name shown under the kill counter.
	weapon_label = Label.new()
	weapon_label.add_theme_font_size_override("font_size", 28)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_label.position = kill_count.position + Vector2(0, kill_count.size.y)
	weapon_label.size = Vector2(kill_count.size.x, 40)
	kill_count.get_parent().add_child.call_deferred(weapon_label)
	update_weapon_label()


func _process(delta: float) -> void:

	kill_count.text = str(kills)
	javelin_cooldown = maxf(javelin_cooldown - delta, 0.0)
	update_weapon_label()

	if is_firing:
		cursor.scale = default_cursor_size * 0.9
	else:
		cursor.scale = default_cursor_size

	# Tint the reticle red while the Javelin is reloading.
	if current_weapon == Weapon.JAVELIN and javelin_cooldown > 0.0:
		cursor.modulate = Color(1.0, 0.4, 0.4)
	else:
		cursor.modulate = Color.WHITE

	var mouse_pos := cursor.get_global_mouse_position()
	var cursor_size := cursor.size * cursor.scale
	var shake_offset := Vector2.ZERO

	if is_firing:
		var strength := get_current_shake_strength()
		shake_offset = Vector2(
			randf_range(-strength, strength),
			randf_range(-strength, strength)
		)

	cursor.global_position = mouse_pos - cursor_size * 0.5 + shake_offset

	if not is_firing:
		return

	match current_weapon:
		Weapon.CANNON:
			var interval: float = 60.0 / maxf(rpm, 1.0)
			fire_timer -= delta

			while fire_timer <= 0.0:
				fire_round(locked_target)
				fire_timer += interval

		Weapon.MINIGUN:
			var interval: float = 60.0 / maxf(minigun_rpm, 1.0)
			fire_timer -= delta

			while fire_timer <= 0.0:
				fire_minigun_round()
				fire_timer += interval




func _input(event: InputEvent) -> void:
	# Physical key, so Q works on any keyboard layout.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q:
			switch_weapon()
			return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_firing or camera == null:
					return

				match current_weapon:
					Weapon.CANNON:
						var hit: Variant = get_mouse_world_position()

						# Only fire when the mouse ray hits a collider.
						if hit != null:
							locked_target = hit
							is_firing = true
							fire_timer = 0.0

					Weapon.MINIGUN:
						# Minigun follows the cursor, no target lock.
						is_firing = true
						fire_timer = 0.0

					Weapon.JAVELIN:
						launch_javelin()
			else:
				is_firing = false


func switch_weapon() -> void:
	current_weapon = ((current_weapon + 1) % Weapon.size()) as Weapon
	is_firing = false
	fire_timer = 0.0
	update_weapon_label()


func update_weapon_label() -> void:
	if weapon_label == null:
		return

	var text: String = WEAPON_NAMES[current_weapon]

	if current_weapon == Weapon.JAVELIN and javelin_cooldown > 0.0:
		text += "  (%.1f)" % javelin_cooldown

	weapon_label.text = "[Q] " + text


func get_current_shake_strength() -> float:
	match current_weapon:
		Weapon.MINIGUN:
			return minigun_shake_strength
		Weapon.JAVELIN:
			return 0.0
	return shake_strength


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


func play_shot_sound(pitch_min: float, pitch_max: float) -> void:
	if shoot_sound != null:
		# Slightly randomize pitch and loudness for each shot.
		shoot_sound.pitch_scale = randf_range(pitch_min, pitch_max)
		shoot_sound.volume_db = randf_range(-2.0, 0.0)
		shoot_sound.play()


func random_spread(spread: float) -> Vector3:
	var angle := randf() * TAU
	var radius := sqrt(randf()) * spread

	return Vector3(
		cos(angle) * radius,
		0.0,
		sin(angle) * radius
	)


# Each shot schedules an explosion at the locked target.
func fire_round(target: Vector3) -> void:
	play_shot_sound(0.8, 1.0)
	schedule_explosion(target + random_spread(impact_spread), impact_delay, explosion_radius, 1.0)


# Minigun rounds land wherever the cursor currently points.
func fire_minigun_round() -> void:
	var hit: Variant = get_mouse_world_position()

	if hit == null:
		return

	play_shot_sound(1.4, 1.7)
	schedule_explosion(hit + random_spread(minigun_spread), minigun_impact_delay, minigun_radius, minigun_explosion_scale)


func launch_javelin() -> void:
	if javelin_cooldown > 0.0:
		return

	var hit: Variant = get_mouse_world_position()

	if hit == null:
		return

	var missile := JavelinMissile.new()
	missile.speed = javelin_speed
	missile.climb_height = javelin_climb
	missile.dive_speed = javelin_dive_speed
	missile.impacted.connect(javelin_impact)

	get_tree().current_scene.add_child(missile)
	missile.launch(
		camera.global_position + Vector3.DOWN * javelin_launch_drop,
		hit,
		find_nearest_enemy(hit, javelin_lock_radius)
	)

	javelin_cooldown = javelin_reload
	play_shot_sound(0.5, 0.6)


func javelin_impact(impact_position: Vector3) -> void:
	var explosion := JavelinExplosion.new()
	explosion.size = javelin_radius / 8.0
	# Position before adding so the particle bursts start in the right place.
	explosion.position = impact_position
	get_tree().current_scene.add_child(explosion)

	damage_enemies(impact_position, javelin_radius)


func find_nearest_enemy(point: Vector3, max_distance: float) -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := max_distance

	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D

		if enemy == null or enemy.is_queued_for_deletion():
			continue

		var distance := enemy.global_position.distance_to(point)

		if distance <= nearest_distance:
			nearest = enemy
			nearest_distance = distance

	return nearest


func schedule_explosion(position: Vector3, delay: float, radius: float, vfx_scale: float) -> void:
	await get_tree().create_timer(delay).timeout

	if not is_inside_tree():
		return

	explode_at(position, radius, vfx_scale)


func explode_at(position: Vector3, radius: float, vfx_scale: float) -> void:
	if explosion_scene != null:
		var explosion := explosion_scene.instantiate() as Node3D

		if explosion != null:
			get_tree().current_scene.add_child(explosion)
			explosion.global_position = position
			explosion.scale = Vector3.ONE * vfx_scale

	damage_enemies(position, radius)


func damage_enemies(position: Vector3, radius: float) -> void:
	# Find and delete enemies near the explosion.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue

		if not enemy is Node3D:
			continue

		var distance = enemy.global_position.distance_to(position)

		if distance <= radius:
			enemy.queue_free()
			kills += 0.5
