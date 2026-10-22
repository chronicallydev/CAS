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

# Upgrades (see RunUpgrades and the end of this file).
# Seeker Rounds: how far from the aim an enemy pulls rounds onto it.
const SEEK_RADIUS := 5.0
# Rubber Bullets: ricochets look this far for a new target, this often,
# for this share of a round's damage.
const RICOCHET_RANGE := 12.0
const RICOCHET_CHANCE := 0.5
const RICOCHET_SHARE := 0.6
# Flak Screen: missiles this close to a round's path are shot down.
const FLAK_RADIUS := 3.0
# Shredder: each round on the same target adds this, up to SHRED_MAX
# (3x damage); a gap longer than SHRED_GAP_MS starts it over.
const SHRED_STEP := 0.1
const SHRED_MAX := 2.0
const SHRED_GAP_MS := 400
# Incendiary: chance a round sets its target alight.
const IGNITE_CHANCE := 0.08
# Painted (a combo): how long a seeker hit marks an enemy.
const PAINT_MS := 4000
# Shredder: the multiplier shown under the reticle while it's ramping.
var shred_label: Label
var last_shred: float = 1.0
var last_shred_ms: int = -100000

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
# Spread radius around the reticle.
@export_range(0.0, 50.0, 0.1) var minigun_spread: float = 2.0
@export_range(0.1, 100.0, 0.1) var minigun_radius: float = 1.5
@export_range(0.1, 100.0, 0.1) var minigun_damage: float = 1.0
@export_range(0.05, 2.0, 0.05) var minigun_explosion_scale: float = 0.35
@export var minigun_shake_strength: float = 1.5
# Share of ground rounds that glance off as a ricochet streak. On an enemy
# helicopter the chance is its armour (light_armor).
@export_range(0.0, 1.0, 0.05) var ricochet_chance: float = 0.3
# Barrels spin up for this long before the first round.
@export_range(0.0, 3.0, 0.05) var minigun_spin_up: float = 0.4


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
# Enemy helicopters fly at the player's altitude, so the ground under the
# cursor is well off from where they are on screen. With the cursor this
# close to one on screen (in pixels), shots go to the helicopter itself.
@export var air_aim_radius: float = 150.0

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
# Minigun barrel spin.
var minigun_spin: float = 0.0
# Rockets: shots left in the current salvo, time to the next, reload.
var rockets_queued: int = 0
var rocket_shot_timer: float = 0.0
var rocket_reload_timer: float = 0.0
var weapon_label: Label
var mission: MissionContext
# The enemy helicopter the reticle is locked on (see locked_air_target).
var locked_target: Node3D
# Test range cheat: no reloads.
var infinite_ammo: bool = false

# Pixels of the reticle image per canvas pixel (see Reticle).
const RETICLE_SCALE := 3.0
var default_cursor_size := Vector2.ONE * RETICLE_SCALE
var reticle_normal: ImageTexture
var reticle_locked: ImageTexture
# Air-aim reach of a round: it hits a helicopter whose hull is within this
# many metres of where it lands, and air rounds scatter by this multiple
# of the ground spread. Scatter is even over a disc, so about
# (air_hit_radius / scatter)^2 of the rounds connect: ~15% by default,
# so the gun alone takes ~6s on a scout and ~18s on a gunship; deflected
# missiles are what win a dogfight.
@export_group("Air targets")
@export var air_hit_radius: float = 2.0
@export_range(0.0, 5.0, 0.05) var air_spread_scale: float = 2.6


func _ready() -> void:
	mission = MissionContext.of(self)
	# The reticle follows the mouse; it must never swallow clicks.
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle_normal = Reticle.make(false)
	reticle_locked = Reticle.make(true)
	cursor.texture = reticle_normal
	cursor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cursor.size = Vector2(Reticle.SIZE, Reticle.SIZE)
	cursor.scale = default_cursor_size

	# Equipped weapons, bottom right.
	weapon_label = Label.new()
	weapon_label.add_theme_font_size_override("font_size", UiStyle.px(24))
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.add_theme_color_override("font_outline_color", Color.BLACK)
	weapon_label.add_theme_constant_override("outline_size", 12)
	weapon_label.add_theme_stylebox_override("normal", UiStyle.plate(6.0))
	weapon_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# Bottom-right corner, clear of the hull bar.
	weapon_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	# Sized to its text (its plate hugs it), growing up and left from there.
	weapon_label.offset_left = -24
	weapon_label.offset_top = -24
	weapon_label.offset_right = -24
	weapon_label.offset_bottom = -24
	weapon_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	kill_count.get_parent().add_child.call_deferred(weapon_label)
	# Kills are shown in the HUD readout now.
	kill_count.visible = false
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
		# Nothing until the barrels are up to speed.
		if minigun_spin < minigun_spin_up:
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
	update_shred_label()

	# Tint the reticle red while the LMB weapon reloads.
	var primary_reloading := not equipped.is_empty() and get_reload_left(equipped[0]) > 0.0
	if primary_reloading:
		cursor.modulate = Color(1.0, 0.4, 0.4)
	else:
		cursor.modulate = Color.WHITE

	# Flash and pop the reticle on hits (amber) and kills (red).
	if hit_flash > 0.0:
		hit_flash -= delta
		cursor.modulate = Color(1.0, 0.3, 0.25) if hit_was_kill else Color(1.0, 0.85, 0.35)
		cursor.scale *= 1.2 if hit_was_kill else 1.08

	var mouse_pos := cursor.get_global_mouse_position()
	# Snaps onto an enemy helicopter it's aiming at (see air_target), and
	# switches to the locked reticle. The cursor's layer is scaled, so the
	# screen point is mapped into it the way the mouse is.
	var air := locked_air_target()
	cursor.texture = reticle_locked if air != null else reticle_normal
	if air != null:
		mouse_pos = cursor.get_canvas_transform().affine_inverse() * camera.unproject_position(air.global_position)
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
		var text := tr(WEAPON_NAMES[weapon])
		if copies(weapon) > 1:
			text += " x%d" % copies(weapon)
		var reload := get_reload_left(weapon)
		if reload > 0.0:
			text += " (%.1f)" % reload
		parts.append("%s %s" % [tr(SLOT_NAMES[slot]), text])
	weapon_label.text = "     ".join(parts) if not parts.is_empty() else "NO WEAPONS"


# Seconds until `weapon` can fire again (0 when ready).
func get_reload_left(weapon: Weapon) -> float:
	if weapon == Weapon.ROCKETS:
		return rocket_reload_timer if rockets_queued == 0 else 0.0
	return 0.0


# Cast a ray from the camera through the mouse position.
func get_mouse_world_position() -> Variant:
	var mouse_pos := get_viewport().get_mouse_position()

	var air := locked_air_target()
	if air != null:
		return air.global_position

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


# The enemy helicopter being aimed at, or null. While a trigger is held
# the lock sticks to the same helicopter wherever the cursor goes, until
# it's shot down; if it jinks the reticle follows it, and the rounds
# already in the air (aimed where it was heading) miss.
func locked_air_target() -> Node3D:
	var holding: bool = trigger.values().has(true)
	if holding and locked_target != null and is_instance_valid(locked_target) and locked_target.is_in_group("air_enemies"):
		return locked_target
	locked_target = air_target(get_viewport().get_mouse_position())
	return locked_target


# The enemy helicopter closest to `mouse_pos` on screen, within
# air_aim_radius, or null.
func air_target(mouse_pos: Vector2) -> Node3D:
	var best: Node3D = null
	var best_distance := air_aim_radius
	for node in get_tree().get_nodes_in_group("air_enemies"):
		var enemy := node as Node3D
		if enemy == null or camera.is_position_behind(enemy.global_position):
			continue
		var distance := camera.unproject_position(enemy.global_position).distance_to(mouse_pos)
		if distance < best_distance:
			best = enemy
			best_distance = distance
	return best


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
	# Rounds scatter around the reticle.
	var spread := minigun_spread * gun_spread_scale()
	var air := locked_air_target()
	if air != null:
		var from_air := take_muzzle(Weapon.MINIGUN)
		play_shot_sound("gun_minigun", 1.4, 1.7, from_air)
		# Double The Gun only doubles the scatter's area up here, so the
		# extra rounds make up for the misses rather than all going wide.
		fire_air_round(from_air, air, minigun_spread * sqrt(gun_spread_scale()) * air_spread_scale)
		return

	var hit: Variant = get_mouse_world_position()

	if hit == null:
		return

	var from := take_muzzle(Weapon.MINIGUN)
	var landing: Vector3 = hit + random_spread(spread)
	# Seeker Rounds (an upgrade): curve onto an enemy near the aim.
	if upgraded("seeker_rounds"):
		var seek := seek_target(hit)
		if seek != null:
			landing = seek.global_position + random_spread(0.8)
			landing.y = hit.y
			# Painted (a combo): deflections go for what seekers hit.
			if mission.combo("seeker_rounds", "redirect"):
				seek.set_meta("painted_ms", Time.get_ticks_msec() + PAINT_MS)

	play_shot_sound("gun_minigun", 1.4, 1.7, from)
	schedule_explosion(from, landing, minigun_impact_delay, minigun_radius, minigun_damage, minigun_explosion_scale, true)


# A round at an enemy helicopter: aimed where it will be when the round
# arrives (its velocity times the flight time), scattered by `spread`.
# It hits if the hull is within air_hit_radius of that point on arrival,
# so a helicopter that dashes or jinks hard can slip the burst.
func fire_air_round(from: Vector3, target: Node3D, spread: float) -> void:
	var lead := target.global_position
	var target_velocity: Variant = target.get("velocity")
	if target_velocity is Vector3:
		lead += target_velocity * minigun_impact_delay
	var aim := lead + random_spread(spread)
	spawn_tracer(from, aim, minigun_impact_delay, minigun_explosion_scale)

	await get_tree().create_timer(minigun_impact_delay).timeout
	if not is_inside_tree():
		return
	# Mid-jink (dashing) it's out of the burst whatever the distance.
	var jinking: bool = is_instance_valid(target) and target.get("dash_time_left") > 0.0
	if is_instance_valid(target) and target.is_in_group("air_enemies") and not jinking and target.global_position.distance_to(aim) <= air_hit_radius:
		# On the hull: a burst there and the damage on this target alone.
		# Armour turns some rounds aside with a ping.
		spawn_impact(target.global_position, minigun_explosion_scale)
		var armor: float = target.get("light_armor") if target.get("light_armor") != null else 0.0
		if randf() < armor:
			var outward := (from - target.global_position).normalized()
			spawn_ricochet(target.global_position, target.global_position - from, (outward + Vector3.UP * 0.5).normalized())
		if damage_enemy(target, minigun_damage, true):
			report_kills(1, target.get("max_health") >= HEAVY_KILL_HEALTH)
		after_round(from, target.global_position)
	else:
		# A miss: a smaller puff where it passed.
		spawn_impact(aim, minigun_explosion_scale * 0.6)
		after_round(from, aim)


# Barrels spin up while the trigger is held and wind down when let go.
func update_minigun(delta: float) -> void:
	var trigger_down: bool = trigger.get(Weapon.MINIGUN, false)

	if trigger_down:
		if minigun_spin <= 0.0:
			Sfx.play_2d("spin_up")
		minigun_spin = minf(minigun_spin + delta, minigun_spin_up)
	else:
		minigun_spin = maxf(minigun_spin - delta * 2.0, 0.0)


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
	if light_weapon and randf() < ricochet_chance:
		spawn_ricochet(position, position - from, Vector3.UP)
	if light_weapon:
		after_round(from, position)


# A round glancing off at `at`: a short bright streak bouncing away
# (`incoming` mirrored off the surface `normal`, kept shallow and
# scattered) and a ping.
func spawn_ricochet(at: Vector3, incoming: Vector3, normal: Vector3) -> void:
	var bounce := incoming.normalized().bounce(normal)
	bounce += normal * randf_range(0.1, 0.5) + random_spread(0.6)
	var to := at + bounce.normalized() * randf_range(6.0, 12.0)
	var streak := Tracer.new()
	streak.radius = 0.16
	streak.length = 2.2
	streak.outline = 0.28
	streak.color = OneBit.fill("player_fire")
	streak.outline_color = OneBit.rim_color("player_fire")
	MissionContext.spawn_parent(self).add_child(streak)
	streak.setup(at, to, randf_range(0.1, 0.18), 0.0, Callable())
	Sfx.play_3d("ricochet", at, 0.0, randf_range(0.85, 1.25), 0.0)


# Visible round flying from the muzzle to where it will land.
func spawn_tracer(from: Vector3, target: Vector3, flight_time: float, vfx_scale: float) -> void:
	if shooter == null or flight_time <= 0.0:
		return

	# A light streak with a dark rim (see OneBit.ROLES), each at least a
	# low-res pixel wide (about 0.5 m at the default zoom), so it reads on
	# any ground.
	var tracer := Tracer.new()
	tracer.radius = 0.22 + 0.13 * clampf(vfx_scale, 0.0, 1.0)
	tracer.length = 3.5
	tracer.outline = 0.4
	tracer.color = OneBit.fill("player_fire")
	tracer.outline_color = OneBit.rim_color("player_fire")
	MissionContext.spawn_parent(self).add_child(tracer)
	tracer.setup(from, target, flight_time, 0.0, Callable())


func explode_at(position: Vector3, radius: float, hit_damage: float, vfx_scale: float, light_weapon: bool = false) -> void:
	spawn_impact(position, vfx_scale)
	damage_enemies(position, radius, hit_damage, light_weapon)


func spawn_impact(position: Vector3, vfx_scale: float) -> void:
	if explosion_scene == null:
		return
	var explosion := explosion_scene.instantiate() as Node3D
	if explosion != null:
		MissionContext.spawn_parent(self).add_child(explosion)
		explosion.global_position = position
		explosion.scale = Vector3.ONE * vfx_scale


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

		if damage_enemy(enemy, hit_damage, light_weapon, force, from):
			killed += 1
			if enemy.get("max_health") != null and enemy.max_health >= HEAVY_KILL_HEALTH:
				heavy_killed = true

	# Buildings (building.gd) are hit anywhere on their footprint.
	for node in get_tree().get_nodes_in_group("structures"):
		var building := node as Building
		if building == null or building.ground_distance(position) > radius:
			continue
		if damage_enemy(building, hit_damage, light_weapon, force, from):
			heavy_killed = true

	report_kills(killed, heavy_killed)


# Hits one enemy, counting the damage and the hit or kill. `force` and
# `from` are for its death effects. True if it died.
func damage_enemy(enemy: Node3D, hit_damage: float, light_weapon: bool, force: float = 0.0, from: Variant = null) -> bool:
	if enemy.has_method("set_last_hit"):
		enemy.set_last_hit(from if from is Vector3 else get_shot_origin(), force, light_weapon)

	if not enemy.has_method("take_damage"):
		enemy.queue_free()
		register_kill(enemy, 10)
		return true

	# Shredder (an upgrade): rounds held on one target ramp up.
	if light_weapon and upgraded("shredder"):
		hit_damage *= shred(enemy)
	var health_before: float = enemy.get("health") if enemy.get("health") != null else 0.0
	var killed_now: bool = enemy.take_damage(hit_damage, light_weapon)
	# Incendiary (an upgrade): vehicles and buildings catch fire.
	if light_weapon and not killed_now and upgraded("incendiary") and burnable(enemy) and randf() < IGNITE_CHANCE:
		Burn.ignite(enemy, mission)
	if enemy.get("health") != null:
		damage_dealt.emit(health_before - maxf(enemy.health, 0.0))
	if killed_now:
		register_kill(enemy, enemy.score_value if "score_value" in enemy else 10)
	else:
		register_hit()
		if enemy.has_method("register_hit"):
			enemy.register_hit(get_shot_origin(), light_weapon)
	return killed_now


# A tiny freeze on big multi-kills, or on killing something big, makes
# them land harder.
func report_kills(killed: int, heavy_killed: bool) -> void:
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
	# Salvage (an upgrade): wrecks leave scrap.
	if upgraded("salvage"):
		if enemy.get("leaves_wreck") or enemy.has_method("make_crash_smoke"):
			Scrap.drop(enemy.global_position, mission, 0.5)
		elif enemy is Building:
			Scrap.drop(enemy.global_position, mission, 0.25)
	mission.add_score(points)
	hit_flash = 0.22
	hit_was_kill = true
	Sfx.play_2d("kill_tick")

	# Score pop-up and multi-kill tracking live in the HUD, which the
	# mission context connects to this signal.
	var label: String = enemy.get("display_name") if enemy.get("display_name") != null else ""
	kill_registered.emit(points, enemy.global_position, label)


# --- Upgrades (see RunUpgrades) ---------------------------------------------

func upgraded(id: String) -> bool:
	return mission != null and mission.upgraded(id)


# The enemy nearest `point` within SEEK_RADIUS for Seeker Rounds: a ground
# unit, or a building that's a marked target. Null if none.
func seek_target(point: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := SEEK_RADIUS
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or enemy.is_in_group("air_enemies"):
			continue
		var distance := Vector2(enemy.global_position.x - point.x, enemy.global_position.z - point.z).length()
		if distance < best_distance:
			best = enemy
			best_distance = distance
	if best != null:
		return best
	for node in get_tree().get_nodes_in_group("structures"):
		var building := node as Building
		if building != null and building.target and not building.dormant and building.ground_distance(point) < SEEK_RADIUS:
			return building
	return null


# What happens after any minigun round lands at `at`, fired from `from`.
func after_round(from: Vector3, at: Vector3) -> void:
	if upgraded("flak_screen"):
		shoot_down_missiles(from, at)
	if upgraded("rubber_bullets") and randf() < RICOCHET_CHANCE:
		ricochet(at)


# Flak Screen: enemy missiles near the round's path burst harmlessly.
# Shrapnel (a combo with Split) bursts them into two deflections.
func shoot_down_missiles(from: Vector3, to: Vector3) -> void:
	var path := to - from
	for missile in get_tree().get_nodes_in_group("aa_missiles"):
		if missile.deflected or missile.harmless:
			continue
		var along := clampf((missile.global_position - from).dot(path) / maxf(path.length_squared(), 0.001), 0.0, 1.0)
		if missile.global_position.distance_to(from + path * along) > FLAK_RADIUS:
			continue
		if mission.combo("flak_screen", "split"):
			var away: Vector3 = missile.velocity.normalized()
			for side in [-1.0, 1.0]:
				missile.split_off(away.rotated(Vector3.UP, side * 0.5))
		missile.fizzle()
		mission.hud.spawn_popup("SHOT DOWN", missile.global_position, Color.WHITE)


# Rubber Bullets: the round bounces into the nearest enemy around `at`
# (not one it's sitting on). Hot Ricochets (a combo with Incendiary) sets
# what it hits alight.
func ricochet(at: Vector3) -> void:
	var best: Node3D = null
	var best_distance := RICOCHET_RANGE
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var distance := enemy.global_position.distance_to(at)
		if distance > minigun_radius and distance < best_distance:
			best = enemy
			best_distance = distance
	if best == null:
		return
	var target := best
	var streak := Tracer.new()
	streak.radius = 0.18
	streak.length = 2.0
	streak.outline = 0.3
	streak.color = OneBit.fill("player_fire")
	streak.outline_color = OneBit.rim_color("player_fire")
	MissionContext.spawn_parent(self).add_child(streak)
	streak.setup(at, target.global_position, 0.12, 0.0, func(_where: Vector3) -> void:
		if not is_instance_valid(target) or not target.is_in_group("enemies"):
			return
		damage_enemy(target, minigun_damage * RICOCHET_SHARE, true)
		if mission.combo("rubber_bullets", "incendiary") and is_instance_valid(target) and burnable(target):
			Burn.ignite(target, mission))
	Sfx.play_3d("ricochet", at, 0.0, randf_range(0.9, 1.3), 0.0)


func burnable(node: Node3D) -> bool:
	return node is Building or node.get("leaves_wreck") == true


# Shredder: the damage multiplier for one more round on `enemy`, ramping
# while the rounds keep coming.
func shred(enemy: Node3D) -> float:
	var now := Time.get_ticks_msec()
	var stack := 0.0
	if enemy.has_meta("shred"):
		var state: Array = enemy.get_meta("shred")
		if now - int(state[1]) <= SHRED_GAP_MS:
			stack = minf(float(state[0]) + SHRED_STEP, SHRED_MAX)
	enemy.set_meta("shred", [stack, now])
	last_shred = 1.0 + stack
	last_shred_ms = now
	return 1.0 + stack


## Finisher (Shredder + Ram): the shred built up on `enemy`, spent.
func cash_in_shred(enemy: Node3D) -> float:
	if not enemy.has_meta("shred"):
		return 0.0
	var state: Array = enemy.get_meta("shred")
	enemy.remove_meta("shred")
	return float(state[0]) if Time.get_ticks_msec() - int(state[1]) <= SHRED_GAP_MS * 3 else 0.0


# Double The Gun: every doubling halves accuracy (doubles the spread).
func gun_spread_scale() -> float:
	if mission == null:
		return 1.0
	return pow(2.0, int(mission.upgrades.get("double_gun", 0)))


# Shredder's multiplier ("x2.4") under the reticle while rounds keep it
# climbing, so you can see the focus paying off.
func update_shred_label() -> void:
	if shred_label == null:
		if not upgraded("shredder"):
			return
		shred_label = Label.new()
		shred_label.add_theme_font_size_override("font_size", UiStyle.px(16))
		shred_label.add_theme_color_override("font_outline_color", Color.BLACK)
		shred_label.add_theme_constant_override("outline_size", 12)
		shred_label.add_theme_stylebox_override("normal", UiStyle.plate(4.0))
		shred_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cursor.get_parent().add_child(shred_label)
	var climbing := Time.get_ticks_msec() - last_shred_ms < SHRED_GAP_MS and last_shred >= 1.3
	shred_label.visible = climbing
	if climbing:
		shred_label.text = "x%.1f" % last_shred
		shred_label.reset_size()
		shred_label.position = get_viewport().get_mouse_position() + Vector2(-shred_label.size.x * 0.5, 70.0)
