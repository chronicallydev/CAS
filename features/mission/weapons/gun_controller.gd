class_name GunController
extends Node3D

# The helicopter's weapons: aiming with the reticle, firing, and dealing
# damage. Kills add to the mission score and are reported through
# kill_registered (the HUD shows pop-ups and multi-kills from it).
#
# The mission context calls equip() with up to two weapon types and the
# muzzles of their mounted copies: the first type fires with the left mouse
# button, the second with the right, and both can fire at once. Each
# mounted copy adds firepower:
#   minigun - fire rate times the number of guns, alternating barrels
#   rockets - every pod fires its own salvo

# A weapon killed an enemy: points scored, where, and its display name.
signal kill_registered(points: int, world_position: Vector3, label: String)
# Damage actually done to an enemy (after armour), for the test range's DPS.
signal damage_dealt(amount: float)

enum Weapon { MINIGUN, ROCKETS }
const WEAPON_NAMES := ["MINIGUN", "ROCKETS"]
# WeaponData ids, in Weapon order.
const WEAPON_IDS := ["minigun", "rockets"]
# Mouse button per equipped slot.
const SLOT_BUTTONS := [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
const SLOT_NAMES := ["LMB", "RMB"]
# Killing an enemy with at least this much health (tanks) freezes the game
# for a moment.
const HEAVY_KILL_HEALTH := 10.0

const JavelinExplosion := preload("res://features/mission/vfx/javelin_explosion.gd")
const Tracer := preload("res://features/mission/enemies/projectiles/tank_shell.gd")
const Rocket := preload("res://features/mission/weapons/rocket.gd")

@export_group("References")
@export var camera: Camera3D
# Optional vehicle the weapons are mounted on (see Helicopter): rounds fly
# from its muzzles as visible tracers.
@export var shooter: Node3D
@export var explosion_scene: PackedScene
@export var cursor : TextureRect
@onready var shoot_sound: AudioStreamPlayer3D = $ShootSound
@onready var kill_count: Label = %KillCount


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


@export_group("Rockets")
# One click fires a salvo of unguided rockets from every mounted pod.
# rockets_salvo is per pod.
@export_range(1, 30, 1) var rockets_salvo: int = 4
@export_range(0.01, 1.0, 0.01) var rockets_interval: float = 0.08
@export_range(0.1, 30.0, 0.1) var rockets_reload: float = 3.0
@export_range(5.0, 300.0, 1.0) var rockets_speed: float = 60.0
@export_range(0.0, 20.0, 0.1) var rockets_spread: float = 9.0
@export_range(0.1, 100.0, 0.1) var rockets_damage: float = 6.0
@export_range(0.1, 50.0, 0.1) var rockets_radius: float = 8.0


@export_group("Targeting")
@export_flags_3d_physics var collision_mask: int = 1
@export_range(10.0, 10000.0, 10.0) var ray_length: float = 5000.0

# Equipped weapons: slot 0 fires with LMB, slot 1 with RMB.
var equipped: Array[Weapon] = []
# Weapon -> muzzle markers of its mounted copies (empty = fire from the
# helicopter's nose).
var muzzles: Dictionary = {}
# Weapon -> next muzzle to fire from (copies take turns).
var next_muzzle: Dictionary = {}
# Weapon -> trigger held (guns fire while it is).
var trigger: Dictionary = {}
# Weapon -> time to the next round, for the guns.
var fire_timers: Dictionary = {}

var kills : int = 0
# Reticle flash when rounds land on an enemy.
var hit_flash: float = 0.0
var hit_was_kill: bool = false
# Minigun state: heat 0..1, overheat lockout and barrel spin.
var minigun_heat: float = 0.0
var minigun_overheated: bool = false
var minigun_spin: float = 0.0
var heat_bar: ColorRect
var heat_fill: ColorRect
# Rockets: shots left in the current salvo, time to the next, reload.
var rockets_queued: int = 0
var rocket_shot_timer: float = 0.0
var rocket_reload_timer: float = 0.0
var weapon_label: Label
var mission: MissionContext
# Test range cheat: no reloads, no minigun heat.
var infinite_ammo: bool = false

@onready var default_cursor_size = cursor.scale


func _ready() -> void:
	mission = MissionContext.of(self)
	# The reticle follows the mouse; it must never swallow clicks.
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Equipped weapons, bottom right.
	weapon_label = Label.new()
	weapon_label.add_theme_font_size_override("font_size", UiStyle.px(24))
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	weapon_label.add_theme_constant_override("outline_size", 6)
	# Bottom-right corner, clear of the hull bar.
	weapon_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_label.offset_left = -460
	weapon_label.offset_top = -64
	weapon_label.offset_right = -24
	weapon_label.offset_bottom = -20
	kill_count.get_parent().add_child.call_deferred(weapon_label)
	# Kills are shown in the HUD readout now.
	kill_count.visible = false
	build_heat_bar()
	update_weapon_label()


# Fits the weapons. `weapon_ids` are WeaponData ids in slot order (at most
# two); `weapon_muzzles` maps each id to the muzzles of its mounted copies.
func equip(weapon_ids: Array[String], weapon_muzzles: Dictionary) -> void:
	equipped.clear()
	for id in weapon_ids:
		var weapon := WEAPON_IDS.find(id)
		if weapon < 0 or equipped.size() >= SLOT_BUTTONS.size():
			continue
		equipped.append(weapon as Weapon)
		muzzles[weapon] = weapon_muzzles.get(id, [])
		next_muzzle[weapon] = 0
		trigger[weapon] = false
		fire_timers[weapon] = 0.0
	update_weapon_label()


func is_equipped(weapon: Weapon) -> bool:
	return equipped.has(weapon)


# Mounted copies of a weapon (0 if not equipped).
func copies(weapon: Weapon) -> int:
	if not is_equipped(weapon):
		return 0
	return maxi(muzzles.get(weapon, []).size(), 1)


# Where the next round of `weapon` leaves from; copies take turns.
func take_muzzle(weapon: Weapon) -> Vector3:
	var list: Array = muzzles.get(weapon, [])
	if list.is_empty():
		return get_shot_origin()
	var index: int = next_muzzle.get(weapon, 0) % list.size()
	next_muzzle[weapon] = index + 1
	return (list[index] as Node3D).global_position


func is_firing() -> bool:
	return trigger.get(Weapon.MINIGUN, false)


func _process(delta: float) -> void:
	kill_count.text = str(kills)
	if infinite_ammo:
		rocket_reload_timer = 0.0
		minigun_heat = 0.0
		minigun_overheated = false
	# A button released over UI never reaches _unhandled_input; let go here.
	for slot in equipped.size():
		if trigger.get(equipped[slot], false) and not Input.is_mouse_button_pressed(SLOT_BUTTONS[slot]):
			trigger[equipped[slot]] = false
	update_rockets(delta)
	update_minigun(delta)
	update_weapon_label()
	update_cursor(delta)

	if shooter != null and shooter.get("dead"):
		return

	# A held minigun keeps firing at its (copy-multiplied) rate.
	if trigger.get(Weapon.MINIGUN, false):
		# Nothing until the barrels are up to speed, and nothing while jammed.
		if minigun_overheated or minigun_spin < minigun_spin_up:
			fire_timers[Weapon.MINIGUN] = 0.0
		else:
			fire_gun(Weapon.MINIGUN, minigun_rpm, delta)


func fire_gun(weapon: Weapon, gun_rpm: float, delta: float) -> void:
	var interval: float = 60.0 / maxf(gun_rpm * copies(weapon), 1.0)
	fire_timers[weapon] -= delta
	while fire_timers[weapon] <= 0.0:
		fire_minigun_round()
		fire_timers[weapon] += interval


func update_cursor(delta: float) -> void:
	var firing := is_firing()
	cursor.scale = default_cursor_size * (0.9 if firing else 1.0)

	# The minigun reticle opens up with the bloom.
	if is_equipped(Weapon.MINIGUN):
		cursor.scale *= 1.0 + minigun_heat * 0.45

	# Tint the reticle red while the LMB weapon reloads or the minigun jams.
	var primary_reloading := not equipped.is_empty() and get_reload_left(equipped[0]) > 0.0
	if primary_reloading:
		cursor.modulate = Color(1.0, 0.4, 0.4)
	elif trigger.get(Weapon.MINIGUN, false) and minigun_overheated:
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

	if firing:
		var strength := minigun_shake_strength
		shake_offset = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))

	cursor.global_position = mouse_pos - cursor_size * 0.5 + shake_offset


# Unhandled, so clicks on UI (e.g. the test range panel) don't fire.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var slot := SLOT_BUTTONS.find(event.button_index)
	if slot < 0 or slot >= equipped.size():
		return
	var weapon := equipped[slot]

	if not event.pressed:
		trigger[weapon] = false
		return
	if camera == null or (shooter != null and shooter.get("dead")):
		return

	match weapon:
		Weapon.MINIGUN:
			# The gun follows the cursor while the button is held.
			if not trigger[weapon]:
				trigger[weapon] = true
				fire_timers[weapon] = 0.0
		Weapon.ROCKETS:
			start_rocket_salvo()


func update_weapon_label() -> void:
	if weapon_label == null:
		return

	var parts: Array[String] = []
	for slot in equipped.size():
		var weapon := equipped[slot]
		var text: String = WEAPON_NAMES[weapon]
		if copies(weapon) > 1:
			text += " x%d" % copies(weapon)
		var reload := get_reload_left(weapon)
		if reload > 0.0:
			text += " (%.1f)" % reload
		elif weapon == Weapon.MINIGUN and minigun_overheated:
			text += " OVERHEAT"
		parts.append("%s %s" % [SLOT_NAMES[slot], text])
	weapon_label.text = "     ".join(parts) if not parts.is_empty() else "NO WEAPONS"


# Seconds until `weapon` can fire again (0 when ready).
func get_reload_left(weapon: Weapon) -> float:
	if weapon == Weapon.ROCKETS:
		return rocket_reload_timer if rockets_queued == 0 else 0.0
	return 0.0


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


func play_shot_sound(mix: String, pitch_min: float, pitch_max: float, from: Vector3) -> void:
	if shoot_sound != null:
		# Slightly randomize pitch and loudness for each shot.
		shoot_sound.pitch_scale = randf_range(pitch_min, pitch_max)
		shoot_sound.volume_db = Sfx.mix_db(mix) + randf_range(-1.5, 0.0)
		# Play from the gun, so it follows the helicopter.
		shoot_sound.global_position = from
		shoot_sound.play()


func random_spread(spread: float) -> Vector3:
	var angle := randf() * TAU
	var radius := sqrt(randf()) * spread

	return Vector3(
		cos(angle) * radius,
		0.0,
		sin(angle) * radius
	)


# Minigun rounds land wherever the cursor currently points.
func fire_minigun_round() -> void:
	var hit: Variant = get_mouse_world_position()

	if hit == null:
		return

	# Rounds scatter around the reticle, wider the hotter the barrels get.
	var spread := minigun_spread + minigun_bloom * minigun_heat
	var from := take_muzzle(Weapon.MINIGUN)

	play_shot_sound("gun_minigun", 1.4, 1.7, from)
	schedule_explosion(from, hit + random_spread(spread), minigun_impact_delay, minigun_radius, minigun_damage, minigun_explosion_scale, true)


# Spin-up, heat build-up while firing, cooling, and the overheat lockout.
# All mounted miniguns share one heat gauge.
func update_minigun(delta: float) -> void:
	var trigger_down: bool = trigger.get(Weapon.MINIGUN, false) and not minigun_overheated

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


# Slim heat gauge under the reticle while a minigun is fitted.
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

	heat_bar.visible = is_equipped(Weapon.MINIGUN) and minigun_heat > 0.01
	heat_bar.position = get_viewport().get_mouse_position() + Vector2(-HEAT_BAR_SIZE.x * 0.5, 62)
	heat_fill.size.x = HEAT_BAR_SIZE.x * minigun_heat

	if minigun_overheated:
		var blink := fmod(Time.get_ticks_msec() / 1000.0, 0.3) < 0.15
		heat_fill.color = Color(1.0, 0.2, 0.15) if blink else Color(1.0, 0.6, 0.5)
	else:
		heat_fill.color = Color(0.95, 0.85, 0.3).lerp(Color(1.0, 0.3, 0.15), minigun_heat)


# --- Rocket pods ---------------------------------------------------------

# Every mounted pod fires a full salvo; the pods take turns, so the whole
# volley takes as long as one pod's salvo.
func start_rocket_salvo() -> void:
	if rockets_queued > 0 or rocket_reload_timer > 0.0:
		return
	rockets_queued = rockets_salvo * copies(Weapon.ROCKETS)
	rocket_shot_timer = 0.0


func update_rockets(delta: float) -> void:
	if rockets_queued == 0:
		rocket_reload_timer = maxf(rocket_reload_timer - delta, 0.0)
		return

	rocket_shot_timer -= delta
	while rocket_shot_timer <= 0.0 and rockets_queued > 0:
		fire_rocket()
		rockets_queued -= 1
		rocket_shot_timer += rockets_interval / copies(Weapon.ROCKETS)

	if rockets_queued == 0:
		rocket_reload_timer = rockets_reload


# One rocket from the next pod, aimed at wherever the cursor is now.
func fire_rocket() -> void:
	var hit: Variant = get_mouse_world_position()
	if hit == null:
		return

	var from := take_muzzle(Weapon.ROCKETS)
	var target: Vector3 = hit + random_spread(rockets_spread)
	var rocket := Rocket.new()
	MissionContext.spawn_parent(self).add_child(rocket)
	rocket.launch(from, target, rockets_speed, rocket_impact)
	Sfx.play_3d("rocket_fire", from, 0.0, 1.6)


# Each rocket hit is a big layered blast with its own boom and kick.
func rocket_impact(at: Vector3) -> void:
	var explosion := JavelinExplosion.new()
	explosion.size = rockets_radius / 11.0
	explosion.lifetime = 3.5
	explosion.volume_db = 0.0
	explosion.shake = 0.3
	explosion.position = at
	MissionContext.spawn_parent(self).add_child(explosion)
	damage_enemies(at, rockets_radius, rockets_damage)


# A round fired from `from` that lands at `position` after `delay` seconds.
func schedule_explosion(from: Vector3, position: Vector3, delay: float, radius: float, hit_damage: float, vfx_scale: float, light_weapon: bool = false) -> void:
	spawn_tracer(from, position, delay, vfx_scale)

	await get_tree().create_timer(delay).timeout

	if not is_inside_tree():
		return

	explode_at(position, radius, hit_damage, vfx_scale, light_weapon)


# Visible round flying from the muzzle to where it will land.
func spawn_tracer(from: Vector3, target: Vector3, flight_time: float, vfx_scale: float) -> void:
	if shooter == null or flight_time <= 0.0:
		return

	var tracer := Tracer.new()
	tracer.radius = 0.12 + 0.13 * clampf(vfx_scale, 0.0, 1.0)
	tracer.color = Color(1.0, 0.85, 0.45)
	MissionContext.spawn_parent(self).add_child(tracer)
	tracer.setup(from, target, flight_time, 0.0, Callable())


func explode_at(position: Vector3, radius: float, hit_damage: float, vfx_scale: float, light_weapon: bool = false) -> void:
	if explosion_scene != null:
		var explosion := explosion_scene.instantiate() as Node3D

		if explosion != null:
			MissionContext.spawn_parent(self).add_child(explosion)
			explosion.global_position = position
			explosion.scale = Vector3.ONE * vfx_scale

	damage_enemies(position, radius, hit_damage, light_weapon)


func damage_enemies(position: Vector3, radius: float, hit_damage: float, light_weapon: bool = false) -> void:
	# How hard the blast throws bodies around (0 for light weapons):
	# rockets ~1.2.
	var force := 0.0 if light_weapon else hit_damage * radius / 40.0
	# Light rounds come from the gun; blasts push away from their centre.
	var from := get_shot_origin() if light_weapon else position
	var killed := 0
	var heavy_killed := false

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

		if enemy.has_method("set_last_hit"):
			enemy.set_last_hit(from, force, light_weapon)

		if enemy.has_method("take_damage"):
			var health_before: float = enemy.get("health") if enemy.get("health") != null else 0.0
			var killed_now: bool = enemy.take_damage(hit_damage, light_weapon)
			if enemy.get("health") != null:
				damage_dealt.emit(health_before - maxf(enemy.health, 0.0))
			if killed_now:
				register_kill(enemy, enemy.score_value if "score_value" in enemy else 10)
				killed += 1
				if enemy.get("max_health") != null and enemy.max_health >= HEAVY_KILL_HEALTH:
					heavy_killed = true
			else:
				register_hit()
				if enemy.has_method("register_hit"):
					enemy.register_hit(get_shot_origin(), light_weapon)
		else:
			enemy.queue_free()
			register_kill(enemy, 10)
			killed += 1

	# A tiny freeze on big multi-kills, or on killing something big, makes
	# them land harder.
	if killed >= 3:
		mission.hit_stop(0.05 + minf(killed, 8) * 0.01)
	elif heavy_killed:
		mission.hit_stop(0.045)


# Where shots come from, for placing hit marks on the side that was hit.
func get_shot_origin() -> Vector3:
	if shooter != null and shooter.has_method("get_muzzle_position"):
		return shooter.get_muzzle_position()
	return camera.global_position if camera != null else global_position


func register_hit() -> void:
	if not (hit_flash > 0.0 and hit_was_kill):
		hit_flash = 0.1
		hit_was_kill = false
	Sfx.play_2d("hit_tick")


func register_kill(enemy: Node3D, points: int) -> void:
	kills += 1
	mission.add_score(points)
	hit_flash = 0.22
	hit_was_kill = true
	Sfx.play_2d("kill_tick")

	# Score pop-up and multi-kill tracking live in the HUD, which the
	# mission context connects to this signal.
	var label: String = enemy.get("display_name") if enemy.get("display_name") != null else ""
	kill_registered.emit(points, enemy.global_position, label)
