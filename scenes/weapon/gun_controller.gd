extends Node3D

enum Weapon { CANNON, MINIGUN, JAVELIN }
const WEAPON_NAMES := ["CANNON", "MINIGUN", "JAVELIN"]

const JavelinMissile := preload("res://scenes/weapon/javelin_missile.gd")
const JavelinExplosion := preload("res://assets/vfx/javelin_explosion.gd")
const Tracer := preload("res://scenes/Enemies/tank_shell.gd")

@export_group("References")
@export var camera: Camera3D
# Optional vehicle the weapons fire from (needs get_muzzle_position()).
# When set, rounds fly from it as visible tracers.
@export var shooter: Node3D
@export var explosion_scene: PackedScene
@export var cursor : TextureRect
@onready var shoot_sound: AudioStreamPlayer3D = $ShootSound
@onready var kill_count: Label = %KillCount



@export_group("Weapon")
@export_range(1.0, 3000.0, 1.0) var rpm: float = 600.0
@export_range(0.0, 10.0, 0.1) var impact_delay: float = 1.8
@export_range(0.0, 50.0, 0.1) var impact_spread: float = 2.5
# Shell speed when firing from a vehicle (see shooter); sets the flight time.
@export_range(5.0, 500.0, 1.0) var cannon_shell_speed: float = 55.0

@export_group("Damage")
@export_range(0.1, 100.0, 0.1) var explosion_radius: float = 5.0
@export_range(0.1, 100.0, 0.1) var damage: float = 5.0


@export var shake_strength: float = 5.0


@export_group("Minigun")
@export_range(1.0, 6000.0, 1.0) var minigun_rpm: float = 1800.0
@export_range(0.0, 10.0, 0.05) var minigun_impact_delay: float = 0.35
# Spread radius around the reticle when cold; grows by minigun_bloom as
# the barrels heat up.
@export_range(0.0, 50.0, 0.1) var minigun_spread: float = 2.0
@export_range(0.0, 50.0, 0.1) var minigun_bloom: float = 3.0
@export_range(0.1, 100.0, 0.1) var minigun_radius: float = 1.5
@export_range(0.1, 100.0, 0.1) var minigun_damage: float = 1.0
@export_range(0.05, 2.0, 0.05) var minigun_explosion_scale: float = 0.35
@export var minigun_shake_strength: float = 1.5
# Barrels spin up for this long before the first round.
@export_range(0.0, 3.0, 0.05) var minigun_spin_up: float = 0.4
# Seconds of continuous fire until it overheats.
@export_range(0.5, 30.0, 0.1) var minigun_heat_time: float = 3.0
# Heat lost per second while not firing (1.0 = fully cool in a second).
@export_range(0.05, 5.0, 0.05) var minigun_cool_rate: float = 0.5
# How long an overheat locks the gun out.
@export_range(0.1, 10.0, 0.1) var minigun_jam_time: float = 2.0


@export_group("Javelin")
@export_range(0.1, 30.0, 0.1) var javelin_reload: float = 2.0
@export_range(1.0, 100.0, 0.5) var javelin_speed: float = 15.0
# Speed the missile accelerates to in its final dive.
@export_range(1.0, 300.0, 1.0) var javelin_dive_speed: float = 60.0
@export_range(0.1, 100.0, 0.1) var javelin_radius: float = 8.0
@export_range(0.1, 100.0, 0.1) var javelin_damage: float = 15.0
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
var kills : int = 0
var javelin_cooldown: float = 0.0
# Reticle flash when rounds land on an enemy.
var hit_flash: float = 0.0
var hit_was_kill: bool = false
# Minigun state: heat 0..1, overheat lockout and barrel spin.
var minigun_heat: float = 0.0
var minigun_overheated: bool = false
var minigun_spin: float = 0.0
var heat_bar: ColorRect
var heat_fill: ColorRect
var weapon_label: Label

@onready var default_cursor_size = cursor.scale


func _ready() -> void:
	# Weapon name, bottom right.
	weapon_label = Label.new()
	weapon_label.add_theme_font_size_override("font_size", 28)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	weapon_label.add_theme_constant_override("outline_size", 6)
	# Bottom-right corner, clear of the wave banners and the base health bar.
	weapon_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_label.offset_left = -360
	weapon_label.offset_top = -64
	weapon_label.offset_right = -24
	weapon_label.offset_bottom = -20
	kill_count.get_parent().add_child.call_deferred(weapon_label)
	# Kills are shown in the HUD readout now.
	kill_count.visible = false
	build_heat_bar()
	update_weapon_label()


func _process(delta: float) -> void:

	kill_count.text = str(kills)
	javelin_cooldown = maxf(javelin_cooldown - delta, 0.0)
	update_minigun(delta)
	update_weapon_label()

	if is_firing:
		cursor.scale = default_cursor_size * 0.9
	else:
		cursor.scale = default_cursor_size

	# The minigun reticle opens up with the bloom.
	if current_weapon == Weapon.MINIGUN:
		cursor.scale *= 1.0 + minigun_heat * 0.45

	# Tint the reticle red while the Javelin is reloading or the minigun is jammed.
	if current_weapon == Weapon.JAVELIN and javelin_cooldown > 0.0:
		cursor.modulate = Color(1.0, 0.4, 0.4)
	elif current_weapon == Weapon.MINIGUN and minigun_overheated:
		cursor.modulate = Color(1.0, 0.45, 0.25)
	else:
		cursor.modulate = Color.WHITE

	# Flash and pop the reticle on hits (amber) and kills (red).
	if hit_flash > 0.0:
		hit_flash -= delta
		cursor.modulate = Color(1.0, 0.3, 0.25) if hit_was_kill else Color(1.0, 0.85, 0.35)
		cursor.scale *= 1.2 if hit_was_kill else 1.08

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
				fire_round()
				fire_timer += interval

		Weapon.MINIGUN:
			# Nothing until the barrels are up to speed, and nothing while jammed.
			if minigun_overheated or minigun_spin < minigun_spin_up:
				fire_timer = 0.0
				return

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
				if is_firing or camera == null or (shooter != null and shooter.get("dead")):
					return

				match current_weapon:
					Weapon.CANNON, Weapon.MINIGUN:
						# Both guns follow the cursor while the button is held.
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
	elif current_weapon == Weapon.MINIGUN and minigun_overheated:
		text += "  OVERHEAT"

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


func play_shot_sound(mix: String, pitch_min: float, pitch_max: float) -> void:
	if shoot_sound != null:
		# Slightly randomize pitch and loudness for each shot.
		shoot_sound.pitch_scale = randf_range(pitch_min, pitch_max)
		shoot_sound.volume_db = Sfx.mix_db(mix) + randf_range(-1.5, 0.0)
		# Play from the gun, so it follows the helicopter.
		if shooter != null and shooter.has_method("get_muzzle_position"):
			shoot_sound.global_position = shooter.get_muzzle_position()
		shoot_sound.play()


func random_spread(spread: float) -> Vector3:
	var angle := randf() * TAU
	var radius := sqrt(randf()) * spread

	return Vector3(
		cos(angle) * radius,
		0.0,
		sin(angle) * radius
	)


# Heavy cannon round aimed at the cursor. Fired from a vehicle, the shell
# takes time to fly there, so moving targets need to be led.
func fire_round() -> void:
	var hit: Variant = get_mouse_world_position()

	if hit == null:
		return

	var target: Vector3 = hit + random_spread(impact_spread)
	var delay := impact_delay

	if shooter != null and shooter.has_method("get_muzzle_position"):
		delay = shooter.get_muzzle_position().distance_to(target) / maxf(cannon_shell_speed, 1.0)

	play_shot_sound("gun_cannon", 0.8, 1.0)
	schedule_explosion(target, delay, explosion_radius, damage, 1.0)


# Minigun rounds land wherever the cursor currently points.
func fire_minigun_round() -> void:
	var hit: Variant = get_mouse_world_position()

	if hit == null:
		return

	# Rounds scatter around the reticle, wider the hotter the barrels get.
	var spread := minigun_spread + minigun_bloom * minigun_heat

	play_shot_sound("gun_minigun", 1.4, 1.7)
	schedule_explosion(hit + random_spread(spread), minigun_impact_delay, minigun_radius, minigun_damage, minigun_explosion_scale, true)


# Spin-up, heat build-up while firing, cooling, and the overheat lockout.
func update_minigun(delta: float) -> void:
	var trigger_down := is_firing and current_weapon == Weapon.MINIGUN and not minigun_overheated

	if trigger_down:
		if minigun_spin <= 0.0:
			Sfx.play_2d("spin_up")
		minigun_spin = minf(minigun_spin + delta, minigun_spin_up)
	else:
		minigun_spin = maxf(minigun_spin - delta * 2.0, 0.0)

	if trigger_down and minigun_spin >= minigun_spin_up:
		minigun_heat += delta / maxf(minigun_heat_time, 0.1)
		if minigun_heat >= 1.0:
			minigun_heat = 1.0
			minigun_overheated = true
			minigun_spin = 0.0
			Sfx.play_2d("overheat")
	elif minigun_overheated:
		# Locked out until it has fully cooled.
		minigun_heat -= delta / maxf(minigun_jam_time, 0.1)
		if minigun_heat <= 0.0:
			minigun_heat = 0.0
			minigun_overheated = false
	else:
		minigun_heat = maxf(minigun_heat - delta * minigun_cool_rate, 0.0)

	update_heat_bar()


# Slim heat gauge under the reticle while the minigun is selected.
const HEAT_BAR_SIZE := Vector2(80, 5)

func build_heat_bar() -> void:
	heat_bar = ColorRect.new()
	heat_bar.color = Color(0.05, 0.05, 0.05, 0.6)
	heat_bar.size = HEAT_BAR_SIZE
	heat_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_fill = ColorRect.new()
	heat_fill.size = Vector2(0, HEAT_BAR_SIZE.y)
	heat_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_bar.add_child(heat_fill)
	kill_count.get_parent().add_child.call_deferred(heat_bar)


func update_heat_bar() -> void:
	if heat_bar == null:
		return

	heat_bar.visible = current_weapon == Weapon.MINIGUN and minigun_heat > 0.01
	heat_bar.position = get_viewport().get_mouse_position() + Vector2(-HEAT_BAR_SIZE.x * 0.5, 62)
	heat_fill.size.x = HEAT_BAR_SIZE.x * minigun_heat

	if minigun_overheated:
		var blink := fmod(Time.get_ticks_msec() / 1000.0, 0.3) < 0.15
		heat_fill.color = Color(1.0, 0.2, 0.15) if blink else Color(1.0, 0.6, 0.5)
	else:
		heat_fill.color = Color(0.95, 0.85, 0.3).lerp(Color(1.0, 0.3, 0.15), minigun_heat)


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
	var launch_from := camera.global_position + Vector3.DOWN * javelin_launch_drop
	if shooter != null and shooter.has_method("get_muzzle_position"):
		launch_from = shooter.get_muzzle_position()

	missile.launch(
		launch_from,
		hit,
		find_nearest_enemy(hit, javelin_lock_radius)
	)

	javelin_cooldown = javelin_reload
	Sfx.play_3d("javelin_launch", launch_from, 0.0, 1.25)


func javelin_impact(impact_position: Vector3) -> void:
	var explosion := JavelinExplosion.new()
	explosion.size = javelin_radius / 8.0
	# Position before adding so the particle bursts start in the right place.
	explosion.position = impact_position
	get_tree().current_scene.add_child(explosion)

	damage_enemies(impact_position, javelin_radius, javelin_damage)


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


func schedule_explosion(position: Vector3, delay: float, radius: float, hit_damage: float, vfx_scale: float, light_weapon: bool = false) -> void:
	spawn_tracer(position, delay, vfx_scale)

	await get_tree().create_timer(delay).timeout

	if not is_inside_tree():
		return

	explode_at(position, radius, hit_damage, vfx_scale, light_weapon)


# Visible round flying from the shooter to where it will land.
func spawn_tracer(target: Vector3, flight_time: float, vfx_scale: float) -> void:
	if shooter == null or not shooter.has_method("get_muzzle_position") or flight_time <= 0.0:
		return

	var tracer := Tracer.new()
	tracer.radius = 0.12 + 0.13 * clampf(vfx_scale, 0.0, 1.0)
	tracer.color = Color(1.0, 0.85, 0.45)
	get_tree().current_scene.add_child(tracer)
	tracer.setup(shooter.get_muzzle_position(), target, flight_time, 0.0, Callable())


func explode_at(position: Vector3, radius: float, hit_damage: float, vfx_scale: float, light_weapon: bool = false) -> void:
	if explosion_scene != null:
		var explosion := explosion_scene.instantiate() as Node3D

		if explosion != null:
			get_tree().current_scene.add_child(explosion)
			explosion.global_position = position
			explosion.scale = Vector3.ONE * vfx_scale

	damage_enemies(position, radius, hit_damage, light_weapon)


func damage_enemies(position: Vector3, radius: float, hit_damage: float, light_weapon: bool = false) -> void:
	# Damage enemies near the explosion. Distance is measured on the ground
	# plane so tall or floating enemies are hit the same as vehicles.
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D

		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue

		var offset := enemy.global_position - position
		var distance := Vector2(offset.x, offset.z).length()

		if distance > radius:
			continue

		if enemy.has_method("take_damage"):
			if enemy.take_damage(hit_damage, light_weapon):
				register_kill(enemy, enemy.score_value if "score_value" in enemy else 10)
			else:
				register_hit()
		else:
			enemy.queue_free()
			register_kill(enemy, 10)


func register_hit() -> void:
	if not (hit_flash > 0.0 and hit_was_kill):
		hit_flash = 0.1
		hit_was_kill = false
	Sfx.play_2d("hit_tick")


func register_kill(enemy: Node3D, points: int) -> void:
	kills += 1
	Global.add_score(points)
	hit_flash = 0.22
	hit_was_kill = true
	Sfx.play_2d("kill_tick")

	# Score pop-up and multi-kill tracking live in the HUD.
	var hud := get_tree().get_first_node_in_group("game_hud")
	if hud != null:
		var label: String = enemy.get("display_name") if enemy.get("display_name") != null else ""
		hud.register_kill(points, enemy.global_position, label)
