class_name Helicopter
extends Node3D

# Player helicopter: WASD / arrow keys fly it over the map at a fixed
# altitude, and it turns to face the mouse cursor.
#
# The mission context sets its stats from the hangar loadout (see
# Loadout.apply_to_helicopter) and then calls initialize() with the
# airframe and the weapons mounted on its hardpoints, so nothing here reads
# saved data directly.

# Every hit: how much and who dealt it (e.g. "STINGER"), for stats.
signal damage_taken(amount: float, source: String)

@export var camera: Camera3D
@export var speed: float = 24.0
# How quickly the helicopter reaches the requested speed.
@export var acceleration: float = 5.0
@export var altitude: float = 16.0
# Radius of the area of operations around the rig. Past it a warning
# shows and the helicopter is pushed back; it can't go more than
# `bounds_overshoot` further. Campaign missions set their own radius.
@export var bounds: float = 90.0
@export var bounds_overshoot: float = 20.0
# How far out an assault starts, flying in from friendly territory.
@export var ingress_distance: float = 90.0
@export var turn_speed: float = 6.0
@export var max_tilt_degrees: float = 16.0
# Height of the ground plane used for mouse aiming.
@export var ground_y: float = -0.4

@export_group("Health")
@export var max_health: float = 100.0
@export var explosion_scene: PackedScene
# Seconds between being shot down and the round restarting.
@export var restart_delay: float = 2.0
# Test range cheats: hits still count but do no harm, and flares and the
# dash recharge instantly.
var invulnerable: bool = false
var infinite_flares: bool = false

@export_group("Flares")
# Flares are unlimited but recharge: F or Space drops a spread, then they
# take this many seconds to be ready again. The loadout sets it from the
# airframe and its "Flare rate" upgrade.
@export var flare_cooldown: float = 8.0
# After a drop, nothing can lock on for this long.
@export var flare_protection: float = 1.8

@export_group("Low flight")
# Hold Ctrl to drop to this altitude. Low, the helicopter rams anything it
# flies over, its weapons are more accurate, and it hides from radar (SAM
# trucks, SAM sites and ripple launchers can't lock), but small arms, flak,
# Stingers and Shilkas hit it harder.
@export var low_altitude: float = 4.5
# How fast the helicopter drops and climbs (0..1 blend per second).
@export var dive_rate: float = 2.2
@export var ram_radius: float = 3.5
# Damage to everything rammed (infantry die outright)...
@export var ram_damage: float = 8.0
# ...and to the helicopter's hull per vehicle or fort hit.
@export var ram_self_damage: float = 3.0
@export var ram_interval: float = 0.3
@export var low_damage_multiplier: float = 1.5

@export_group("Dash")
# Shift: a quick burst in the steering direction, then a cooldown. The
# loadout sets the cooldown from the airframe.
@export var dash_distance: float = 12.0
@export var dash_time: float = 0.18
@export var dash_cooldown: float = 3.0

# Damage sources that hit harder while flying low: everything but radar
# SAMs (which can't lock on low anyway) and the helicopter's own rams.
const LOW_SAFE_SOURCES := ["", "RAM", "SAM TRUCK", "SAM SITE", "RIPPLE"]

const Flare := preload("res://features/mission/player/flare.gd")

var velocity: Vector3 = Vector3.ZERO
var time: float = 0.0
var health: float = 0.0
var dead: bool = false
# Kept above zero by AA launchers while they are locking on.
var lock_warning_timer: float = 0.0
# Past the edge of the area of operations.
var out_of_bounds: bool = false
# 0 -> 1 while lifting off the rig's pad at the start of a defence.
var takeoff: float = 1.0
var flare_cooldown_left: float = 0.0
var flare_protection_left: float = 0.0
# 0 = cruising altitude, 1 = flying low.
var low_blend: float = 0.0
var ram_timer: float = 0.0
var dash_cooldown_left: float = 0.0
var dash_time_left: float = 0.0
var dash_velocity: Vector3 = Vector3.ZERO

var body: Node3D
var main_rotor: Node3D
var tail_rotor: Node3D
var muzzle: Marker3D
# Weapon id -> muzzle markers of its mounted copies (for the gun controller).
var weapon_muzzles: Dictionary = {}
var bomb_bay: Marker3D

var health_bar: ProgressBar
var warning_label: Label
var flare_label: Label
var hit_flash: ColorRect

var rotor_sound: AudioStreamPlayer
var lock_sound: AudioStreamPlayer
var inbound_sound: AudioStreamPlayer

var mission: MissionContext


# Called by the mission context once the loadout's stats have been set.
# `weapons` holds a WeaponData (or null) per hardpoint of the airframe.
func initialize(mission_context: MissionContext, airframe: HelicopterData, weapons: Array) -> void:
	mission = mission_context
	health = max_health
	build_model(airframe, weapons)
	build_hud()
	build_sounds()
	position.y = altitude
	place_for_mission()


# `source` names who fired, for the test range's damage stats.
func take_damage(amount: float, source: String = "") -> void:
	if dead:
		return

	if is_low() and not LOW_SAFE_SOURCES.has(source):
		amount *= low_damage_multiplier
	damage_taken.emit(amount, source)
	if not invulnerable:
		health = maxf(health - amount, 0.0)
	health_bar.value = health
	# Small-arms hits only tint the screen a little; missiles flash it red.
	hit_flash.color.a = maxf(hit_flash.color.a, clampf(0.06 + amount / 55.0, 0.06, 0.45))
	Sfx.play_2d("heli_hit")
	# Rifle rounds rattle the cabin; missiles throw it about.
	mission.shake(clampf(0.12 + amount / 40.0, 0.12, 0.55))

	if health <= 0.0:
		shot_down()


# Called every frame by an AA launcher that is locking on.
func warn_lock() -> void:
	lock_warning_timer = 0.2


# False for a moment after dropping flares: lock-on weapons (SAMs, Stingers,
# radar flak) must break their lock and start over.
func can_be_locked() -> bool:
	return not dead and flare_protection_left <= 0.0


# Flying low (Ctrl held and the drop mostly done).
func is_low() -> bool:
	return low_blend > 0.75


func _unhandled_input(event: InputEvent) -> void:
	# Physical keys, so this works on any keyboard layout.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F or event.physical_keycode == KEY_SPACE:
			deploy_flares()
		elif event.physical_keycode == KEY_SHIFT:
			dash()


# Drops a spread of decoys. Missiles already homing on the helicopter
# switch to one of them, and new locks are blocked for flare_protection.
func deploy_flares() -> void:
	if dead or flare_cooldown_left > 0.0:
		return
	flare_cooldown_left = 0.0 if infinite_flares else flare_cooldown
	flare_protection_left = flare_protection

	var decoys: Array = []
	for i in 4:
		var flare := Flare.new()
		MissionContext.spawn_parent(self).add_child(flare)
		var throw := Vector3(randf_range(-7.0, 7.0), randf_range(0.5, 3.0), randf_range(-7.0, 7.0))
		flare.launch(global_position + Vector3.DOWN * 1.2, velocity * 0.4 + throw)
		decoys.append(flare)

	for missile in get_tree().get_nodes_in_group("aa_missiles"):
		if missile.get("target") == self:
			missile.target = decoys.pick_random()
	Sfx.play_3d("flare", global_position)


func shot_down() -> void:
	dead = true

	if explosion_scene != null:
		var explosion := explosion_scene.instantiate() as Node3D
		MissionContext.spawn_parent(self).add_child(explosion)
		explosion.global_position = global_position
		explosion.scale = Vector3.ONE * 1.5

	body.visible = false
	mission.shake(1.0)
	rotor_sound.stop()
	lock_sound.stop()
	inbound_sound.stop()
	set_physics_process(false)

	await get_tree().create_timer(restart_delay).timeout
	mission.game_over("Your helicopter was shot down")


# Assaults start far out on the friendly side and fly in; defences lift
# off from the rig's own pad.
# Free play keeps the position set in the scene.
func place_for_mission() -> void:
	var state := mission.state
	if not state.is_campaign():
		return
	if state.is_assault:
		var side: Vector2 = mission.services.campaign.approach_side(state.rig.id)
		position = Vector3(side.x, 0.0, side.y) * ingress_distance + Vector3(0, altitude, 0)
		rotation.y = atan2(side.x, side.y)
		bounds = ingress_distance + 35.0
	else:
		position = Vector3(0, 2.5, 9.0)
		takeoff = 0.0
		bounds = 120.0


# The nose: where hit marks are aimed from when no weapon muzzle applies.
func get_muzzle_position() -> Vector3:
	return muzzle.global_position if muzzle != null else global_position


func get_bomb_bay_position() -> Vector3:
	return bomb_bay.global_position if bomb_bay != null else global_position + Vector3.DOWN * 1.5


func get_input_direction() -> Vector3:
	var direction := Vector3.ZERO

	# Physical keys, so this works on any keyboard layout.
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		direction.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		direction.z += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0

	return direction.normalized()


# Point on the ground under the mouse cursor (no physics needed).
func get_mouse_ground_point() -> Variant:
	if camera == null:
		return null

	var mouse_pos := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse_pos)
	var direction := camera.project_ray_normal(mouse_pos)

	return Plane(Vector3.UP, ground_y).intersects_ray(origin, direction)


func _physics_process(delta: float) -> void:
	time += delta

	# Smoothly accelerate toward the input direction.
	var desired := get_input_direction() * speed
	velocity = velocity.lerp(desired, 1.0 - exp(-acceleration * delta))

	position += velocity * delta
	# A dash adds a short burst on top of normal flight.
	if dash_time_left > 0.0:
		dash_time_left -= delta
		position += dash_velocity * delta
	keep_in_bounds(delta)

	# Lift off the pad, then hold altitude (or drop low while Ctrl is held)
	# with a gentle bob.
	takeoff = minf(takeoff + delta / 2.5, 1.0)
	var want_low := Input.is_physical_key_pressed(KEY_CTRL) and takeoff >= 1.0
	low_blend = move_toward(low_blend, 1.0 if want_low else 0.0, dive_rate * delta)
	var cruise := lerpf(altitude, low_altitude, smoothstep(0.0, 1.0, low_blend))
	position.y = lerpf(2.5, cruise, smoothstep(0.0, 1.0, takeoff)) + sin(time * 1.7) * 0.25

	if is_low():
		ram_timer -= delta
		if ram_timer <= 0.0:
			ram_timer = ram_interval
			ram()

	# Turn the nose toward the cursor.
	var aim: Variant = get_mouse_ground_point()

	if aim != null:
		var to_aim: Vector3 = aim - global_position
		if Vector2(to_aim.x, to_aim.z).length() > 1.0:
			var desired_yaw := atan2(-to_aim.x, -to_aim.z)
			rotation.y = lerp_angle(rotation.y, desired_yaw, 1.0 - exp(-turn_speed * delta))

	# Tilt the body into the direction of travel.
	var local_velocity := global_transform.basis.inverse() * velocity
	var tilt := deg_to_rad(max_tilt_degrees)
	body.rotation.x = lerpf(body.rotation.x, tilt * local_velocity.z / speed, 1.0 - exp(-5.0 * delta))
	body.rotation.z = lerpf(body.rotation.z, -tilt * local_velocity.x / speed, 1.0 - exp(-5.0 * delta))


# Flying low smashes whatever is underneath: infantry die, vehicles and
# forts take ram_damage, and each vehicle or fort costs some hull. Kills
# score and drop pickups like any other (it goes through the guns).
func ram() -> void:
	var ground := Vector3(global_position.x, 0.0, global_position.z)
	var hit_any := false
	var heavy := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		var offset := enemy.global_position - ground
		if Vector2(offset.x, offset.z).length() > ram_radius:
			continue
		hit_any = true
		if enemy.get("max_health") != null and enemy.max_health > 2.0:
			heavy += 1
	if not hit_any:
		return
	mission.guns.damage_enemies(ground, ram_radius, ram_damage)
	Sfx.play_3d("body_thud", ground, 4.0, 0.8)
	if heavy > 0:
		Sfx.play_3d("heli_hit", ground)
		take_damage(ram_self_damage * heavy, "RAM")
	mission.shake(0.25 + 0.1 * heavy)


# A quick burst in the steering direction (or straight ahead), then a
# cooldown.
func dash() -> void:
	if dead or dash_cooldown_left > 0.0:
		return
	var direction := get_input_direction()
	if direction == Vector3.ZERO:
		direction = -global_transform.basis.z
		direction.y = 0.0
		direction = direction.normalized()
	dash_velocity = direction * dash_distance / maxf(dash_time, 0.01)
	dash_time_left = dash_time
	dash_cooldown_left = 0.0 if infinite_flares else dash_cooldown
	velocity += direction * speed * 0.4
	Sfx.play_3d("missile_launch", global_position, -6.0, 1.7)


# Soft edge of the area of operations: push back past it, harder the
# further out, and never more than bounds_overshoot beyond.
func keep_in_bounds(delta: float) -> void:
	var flat := Vector2(position.x, position.z)
	var over := flat.length() - bounds
	out_of_bounds = over > 0.0
	if not out_of_bounds:
		return
	var inward := -flat.normalized()
	velocity += Vector3(inward.x, 0.0, inward.y) * minf(over * 1.5, speed) * 3.0 * delta
	if over > bounds_overshoot:
		flat = flat.normalized() * (bounds + bounds_overshoot)
		position.x = flat.x
		position.z = flat.y


func _process(delta: float) -> void:
	update_hud(delta)

	if dead:
		return

	if main_rotor != null:
		main_rotor.rotate_y(delta * 28.0)
	if tail_rotor != null:
		tail_rotor.rotate_x(delta * 40.0)


func update_hud(delta: float) -> void:
	hit_flash.color.a = maxf(hit_flash.color.a - delta * 1.5, 0.0)
	lock_warning_timer = maxf(lock_warning_timer - delta, 0.0)
	flare_cooldown_left = maxf(flare_cooldown_left - delta, 0.0)
	flare_protection_left = maxf(flare_protection_left - delta, 0.0)
	dash_cooldown_left = maxf(dash_cooldown_left - delta, 0.0)
	var flares := "FLARES [F]" if flare_cooldown_left <= 0.0 else "FLARES %.1fs" % flare_cooldown_left
	var dash_text := "DASH [SHIFT]" if dash_cooldown_left <= 0.0 else "DASH %.1fs" % dash_cooldown_left
	var altitude_text := "LOW: RAMMING, RADAR-HIDDEN" if is_low() else "LOW [CTRL]"
	flare_label.text = "%s     %s     %s" % [flares, dash_text, altitude_text]
	flare_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.35) if is_low() else Color(1.0, 0.85, 0.5))

	var incoming := false
	for missile in get_tree().get_nodes_in_group("aa_missiles"):
		if missile.get("target") == self:
			incoming = true
			break

	if dead:
		warning_label.visible = false
	elif incoming:
		warning_label.text = "MISSILE INBOUND"
		warning_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
		warning_label.visible = fmod(time, 0.25) < 0.15
	elif lock_warning_timer > 0.0:
		warning_label.text = "MISSILE LOCK"
		warning_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
		warning_label.visible = fmod(time, 0.6) < 0.4
	elif out_of_bounds:
		warning_label.text = "LEAVING AREA OF OPERATIONS"
		warning_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		warning_label.visible = fmod(time, 0.8) < 0.55
	else:
		warning_label.visible = false

	# Warning tones: fast beeps for an incoming missile, slower for a lock.
	set_loop_playing(inbound_sound, incoming and not dead)
	set_loop_playing(lock_sound, lock_warning_timer > 0.0 and not incoming and not dead)


func set_loop_playing(player: AudioStreamPlayer, on: bool) -> void:
	if on and not player.playing:
		player.play()
	elif not on and player.playing:
		player.stop()


func make_loop_player(sound: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = Sfx.get_stream(sound)
	player.volume_db = Sfx.mix_db(sound)
	add_child(player)
	return player


func build_sounds() -> void:
	rotor_sound = make_loop_player("rotor_loop")
	lock_sound = make_loop_player("lock_tone")
	inbound_sound = make_loop_player("inbound_tone")
	rotor_sound.play()


func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	hit_flash = ColorRect.new()
	hit_flash.color = Color(1.0, 0.1, 0.05, 0.0)
	hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(hit_flash)

	# Hull bar at the bottom centre.
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -260
	box.offset_right = 260
	box.offset_top = -96
	box.offset_bottom = -24
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)

	var caption := Label.new()
	caption.text = "HULL"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", UiStyle.px(16))
	box.add_child(caption)

	health_bar = ProgressBar.new()
	health_bar.max_value = max_health
	health_bar.value = health
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(320, 14)
	health_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 0.7)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.85, 0.45)
	health_bar.add_theme_stylebox_override("background", bg)
	health_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(health_bar)

	# Flares left, under the hull bar.
	flare_label = Label.new()
	flare_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flare_label.add_theme_font_size_override("font_size", UiStyle.px(16))
	flare_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	flare_label.add_theme_constant_override("outline_size", 4)
	box.add_child(flare_label)

	# Lock / missile warning above the hull bar.
	warning_label = Label.new()
	warning_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	warning_label.offset_left = -200
	warning_label.offset_right = 200
	warning_label.offset_top = -142
	warning_label.offset_bottom = -102
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.add_theme_font_size_override("font_size", UiStyle.px(30))
	warning_label.visible = false
	layer.add_child(warning_label)


func build_model(airframe: HelicopterData, weapons: Array) -> void:
	var parts: Dictionary = HeliModel.build(self, airframe, weapons)
	body = parts["body"]
	main_rotor = parts["main_rotor"]
	tail_rotor = parts["tail_rotor"]
	muzzle = parts["muzzle"]
	weapon_muzzles = parts["muzzles"]
	bomb_bay = parts["bomb_bay"]
