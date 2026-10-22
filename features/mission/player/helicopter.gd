class_name Helicopter
extends Node3D

# Player helicopter: WASD / arrow keys fly it over the map at a fixed
# altitude, and it turns to face the mouse cursor.
#
# The mission context sets its stats from the airframe (HelicopterData) and
# then calls initialize() with the airframe and the weapons mounted on its
# hardpoints.

# Every hit: how much and who dealt it (e.g. "STINGER"), for stats.
signal damage_taken(amount: float, source: String)

@export var camera: Camera3D
@export var speed: float = 24.0
# How quickly the helicopter spools up to full speed (see throttle_response).
@export var acceleration: float = 5.0
@export var altitude: float = 16.0
# Radius of the area of operations around the map centre. Past it a
# warning shows and the helicopter is pushed back; it can't go more than
# `bounds_overshoot` further.
@export var bounds: float = 90.0
@export var bounds_overshoot: float = 20.0
# Agility: how fast the nose follows the cursor and the flight path bends
# toward the steering direction.
@export var turn_speed: float = 6.0
@export var max_tilt_degrees: float = 40.0
# Height of the ground plane used for mouse aiming.
@export var ground_y: float = -0.4

@export_group("Handling")
# The helicopter has momentum: it spools up to full speed at a steady rate,
# bends its flight path toward the steering direction while keeping its
# speed, and glides to a stop when the keys are let go. These turn the
# airframe's acceleration and turn_speed (set from the HelicopterData) into
# those rates.
#
# Seconds from a hover to full speed = throttle_response / acceleration
# (Cobra ~0.15 s).
@export var throttle_response: float = 1.5
# Stopping takes this multiple of the spool-up time (Cobra ~0.28 s).
@export var brake_ratio: float = 1.9
# Degrees per second the flight path turns, per point of turn_speed
# (Cobra ~1300).
@export var path_turn_scale: float = 146.0
# Steering further than this off the current heading brakes and reverses
# in a straight line instead of swinging round in an arc.
@export var reverse_angle: float = 120.0
# How fast the nose follows the cursor, per point of turn_speed.
@export var turn_scale: float = 3.0
# Lean from the steering force on top of the lean from speed, and the most
# it can lean, in multiples of max_tilt_degrees.
@export var thrust_lean: float = 2.0
@export var max_lean: float = 1.7

@export_group("Health")
@export var max_health: float = 100.0
@export var explosion_scene: PackedScene
# Seconds between being shot down and the round restarting.
@export var restart_delay: float = 2.0
# Test range cheats: hits still count but do no harm, and flares and dash
# charges recharge instantly.
var invulnerable: bool = false
var infinite_flares: bool = false

@export_group("Flares")
# Flares are unlimited but recharge: F drops a spread, then they
# # take this many seconds to be ready again. The mission sets it from the
# airframe.
@export var flare_cooldown: float = 8.0
# After a drop, nothing can lock on for this long.
@export var flare_protection: float = 1.8

@export_group("Dash")
# Space or Shift, at any altitude: a quick burst in the steering direction (or straight ahead). It
# takes over the movement, fastest at the start and easing out, and
# nothing can hurt the helicopter while it lasts.
@export var dash_distance: float = 14.0
@export var dash_time: float = 0.18
# Dashes stored up; each one recharges in dash_cooldown seconds, one at a
# time. The loadout sets the cooldown from the airframe.
@export var dash_charges: int = 2
@export var dash_cooldown: float = 3.0
# Speed coming out of a dash, as a fraction of `speed`. It is kept for
# dash_carry seconds (even with no keys held), then bleeds back to full
# speed at overspeed_bleed times the spool-up rate.
@export var dash_exit_speed: float = 1.15
@export var dash_carry: float = 0.15
@export var overspeed_bleed: float = 0.35
# A dash throws the body over toward the dash, this many degrees past its
# normal lean, and eases back level at dash_tilt_recover per second after.
@export var dash_bank_degrees: float = 15.0
@export var dash_tilt_recover: float = 3.5
# The rotor spools up for the burst: extra spin, rotor pitch and blur at the
# peak (as a fraction of normal), fading at dash_rotor_recover per second.
@export var dash_rotor_boost: float = 0.6
@export var dash_rotor_recover: float = 1.8
# Extra seconds of invulnerability after a dash ends.
@export var dash_grace: float = 0.06
# A dash pressed this many seconds too early (still dashing, or out of
# charges) fires as soon as it can.
@export var input_buffer: float = 0.15

const Flare := preload("res://features/mission/player/flare.gd")

var velocity: Vector3 = Vector3.ZERO
var time: float = 0.0
var health: float = 0.0
var dead: bool = false
# Kept above zero by AA launchers while they are locking on.
var lock_warning_timer: float = 0.0
# Past the edge of the area of operations.
var out_of_bounds: bool = false
# Set by a run (RunDirector): a rectangle (x, z) to stay in instead of the
# round area of operations. See keep_in_corridor.
var use_corridor: bool = false
var corridor: Rect2 = Rect2()
var corridor_margin: float = 6.0
var flare_cooldown_left: float = 0.0
var flare_protection_left: float = 0.0
var dash_charges_left: int = 0
# Time until the next charge is back (counts only while one is missing).
var dash_recharge_left: float = 0.0
var dash_time_left: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
# Invulnerable while above zero (the dash plus dash_grace).
var dodge_left: float = 0.0
var dodged_this_dash: bool = false
# Time left on a dash pressed too early (see input_buffer).
var dash_buffer_left: float = 0.0
# Steering force as a fraction of `speed`, for leaning the body.
var thrust: Vector3 = Vector3.ZERO
var dash_carry_left: float = 0.0
# 1 while dashing, easing to 0 after: the extra bank into the dash...
var dash_tilt: float = 0.0
# ...and the rotor's spool-up.
var rotor_boost: float = 0.0
# Smoothed 0..1.2 speed, for the rotor's spin and pitch.
var rotor_effort: float = 0.0

var body: Node3D
var main_rotor: Node3D
var tail_rotor: Node3D
var muzzle: Marker3D
var rotor_blur: StandardMaterial3D
var rotor_blur_alpha: float = 0.12
var blade_count: int = 4
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
var chain_dodge: ChainDodge


# Called by the mission context once the loadout's stats have been set.
# `weapons` holds a WeaponData (or null) per hardpoint of the airframe.
func initialize(mission_context: MissionContext, airframe: HelicopterData, weapons: Array) -> void:
	mission = mission_context
	health = max_health
	dash_charges_left = dash_charges
	chain_dodge = ChainDodge.new()
	add_child(chain_dodge)
	chain_dodge.setup(self, mission)
	build_model(airframe, weapons)
	build_hud()
	build_sounds()
	position.y = altitude


# `source` names who fired, for the test range's damage stats.
func take_damage(amount: float, source: String = "") -> void:
	if dead:
		return
	# Dashing through fire: nothing lands, and the first dodge says so.
	if dodge_left > 0.0:
		if not dodged_this_dash:
			dodged_this_dash = true
			mission.hud.spawn_popup("DODGE", global_position, Color(0.55, 0.85, 1.0))
		return

	damage_taken.emit(amount, source)
	chain_dodge.break_chain()
	if not invulnerable:
		health = maxf(health - amount, 0.0)
	health_bar.value = health
	# Small-arms hits only tint the screen a little; missiles flash it red.
	# In 1-bit a tint would come out grey, so heavy hits invert the screen
	# for a frame or two instead.
	if PixelArt.is_monochrome():
		if amount >= 8.0:
			PixelArt.invert_flash(0.06 if amount < 25.0 else 0.12)
	else:
		hit_flash.color.a = maxf(hit_flash.color.a, clampf(0.06 + amount / 55.0, 0.06, 0.45))
	# Black: the 1-bit helicopter is already white.
	HitFlash.trigger(body, Color.BLACK)
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


func _unhandled_input(event: InputEvent) -> void:
	# Physical keys, so this works on any keyboard layout.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F:
				deploy_flares()
			KEY_SPACE, KEY_SHIFT:
				dash_buffer_left = input_buffer
				try_dash()


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
		if missile.get("target") == self and not missile.get("ignores_flares"):
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


# The nose: where hit marks are aimed from when no weapon muzzle applies.
func get_muzzle_position() -> Vector3:
	return muzzle.global_position if muzzle != null else global_position


func get_bomb_bay_position() -> Vector3:
	return bomb_bay.global_position if bomb_bay != null else global_position + Vector3.DOWN * 1.5


# Spool-up in m/s², from a hover to full speed in throttle_response /
# acceleration seconds.
func get_acceleration_rate() -> float:
	return speed * acceleration / maxf(throttle_response, 0.01)


# Braking in m/s², to a stop in brake_ratio of the spool-up time.
func get_brake_rate() -> float:
	return get_acceleration_rate() / maxf(brake_ratio, 0.01)


# One frame of normal flight. Steering mostly bends the flight path at a
# fixed turn rate and holds the speed; a hard reversal brakes straight
# through instead, and no input glides to a stop.
func steer(delta: float) -> void:
	var input := get_input_direction()
	var desired := input * speed
	var rate := get_acceleration_rate()
	var brake := get_brake_rate()
	var current := velocity.length()
	# Coming out of a dash: keep the extra speed for a moment.
	var carrying := dash_carry_left > 0.0
	dash_carry_left = maxf(dash_carry_left - delta, 0.0)

	if input == Vector3.ZERO:
		if not carrying:
			velocity = velocity.move_toward(Vector3.ZERO, brake * delta)
	elif current < 0.5:
		# From a hover: just spool up along the input.
		velocity = velocity.move_toward(desired, rate * delta)
	else:
		var heading := velocity / current
		var angle := heading.signed_angle_to(input, Vector3.UP)
		if absf(angle) > deg_to_rad(reverse_angle):
			velocity = velocity.move_toward(desired, brake * delta)
		else:
			var max_turn := deg_to_rad(turn_speed * path_turn_scale) * delta
			heading = heading.rotated(Vector3.UP, clampf(angle, -max_turn, max_turn))
			if current < speed:
				current = move_toward(current, speed, rate * delta)
			elif not carrying:
				current = move_toward(current, speed, rate * overspeed_bleed * delta)
			velocity = heading * current

	thrust = ((desired - velocity) / speed).limit_length(1.0)
	position += velocity * delta


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
	if dash_buffer_left > 0.0:
		dash_buffer_left -= delta
		try_dash()
	dodge_left = maxf(dodge_left - delta, 0.0)

	if dash_time_left > 0.0:
		update_dash(delta)
	else:
		steer(delta)
	keep_in_bounds(delta)

	# Hold altitude with a gentle bob.
	position.y = altitude + sin(time * 1.7) * 0.25

	# Turn the nose toward the cursor.
	var aim: Variant = get_mouse_ground_point()

	if aim != null:
		var to_aim: Vector3 = aim - global_position
		if Vector2(to_aim.x, to_aim.z).length() > 1.0:
			var desired_yaw := atan2(-to_aim.x, -to_aim.z)
			rotation.y = lerp_angle(rotation.y, desired_yaw, 1.0 - exp(-turn_speed * turn_scale * delta))

	# Tilt the body into the direction of travel, and further into the
	# steering force: nose down speeding up, flared back braking, banked
	# into turns, thrown hard into a dash.
	var lean := velocity / speed + thrust * thrust_lean
	var to_local := global_transform.basis.inverse()
	var local_lean := (to_local * lean).limit_length(max_lean) * deg_to_rad(max_tilt_degrees)
	# A dash throws it further over, snapping in fast and easing back out.
	if dash_time_left <= 0.0:
		dash_tilt = move_toward(dash_tilt, 0.0, dash_tilt_recover * delta)
	var bank := smoothstep(0.0, 1.0, dash_tilt)
	local_lean += to_local * dash_direction * deg_to_rad(dash_bank_degrees) * bank
	var follow := 1.0 - exp(-lerpf(8.0, 30.0, bank) * delta)
	body.rotation.x = lerpf(body.rotation.x, local_lean.z, follow)
	body.rotation.z = lerpf(body.rotation.z, -local_lean.x, follow)


# A dash pressed while it can't go (still dashing, out of charges) is kept
# for input_buffer seconds, so an early press isn't lost.
func try_dash() -> void:
	if dash():
		dash_buffer_left = 0.0


# A quick burst in the steering direction (or straight ahead), using up a
# charge. False if it can't go yet (the press may be buffered).
func dash() -> bool:
	# In a chain dodge's slow motion a new dash cuts the current one short.
	var cancel := chain_dodge.is_slowed()
	var velocity_before := velocity
	if dead or dash_charges_left <= 0 or (dash_time_left > 0.0 and not cancel):
		return false
	var direction := get_input_direction()
	if direction == Vector3.ZERO:
		direction = -global_transform.basis.z
		direction.y = 0.0
		direction = direction.normalized()
	dash_direction = direction
	dash_time_left = dash_time
	dodge_left = dash_time + dash_grace
	dodged_this_dash = false
	if not infinite_flares:
		if dash_charges_left == dash_charges:
			dash_recharge_left = dash_cooldown
		dash_charges_left -= 1
	# Coming out of it at a bit over full speed, carried for dash_carry
	# seconds (see steer). The body is thrown over into it and the rotor
	# spools up (see the tilt in _physics_process and the rotor in _process).
	velocity = direction * speed * dash_exit_speed
	dash_carry_left = dash_carry
	thrust = direction
	dash_tilt = 1.0
	rotor_boost = 1.0

	mission.kick(direction, 1.2)
	# The last charge sounds a little higher, so you hear you're out.
	var pitch := 1.15 if dash_charges_left == 0 else 1.0
	Sfx.play_3d("dash_whoosh", global_position, 0.0, pitch, 0.12)
	chain_dodge.on_dash(velocity_before)
	return true


# Moves along the dash on an ease-out curve: most of the distance in the
# first few frames, so it feels instant, then a soft finish.
func update_dash(delta: float) -> void:
	var duration := maxf(dash_time, 0.01)
	var before := dash_ease(1.0 - dash_time_left / duration)
	dash_time_left = maxf(dash_time_left - delta, 0.0)
	var after := dash_ease(1.0 - dash_time_left / duration)
	position += dash_direction * dash_distance * (after - before)


static func dash_ease(t: float) -> float:
	var left := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - left * left


# Soft edge of the area of operations: push back past it, harder the
# further out, and never more than bounds_overshoot beyond.
func keep_in_bounds(delta: float) -> void:
	if use_corridor:
		keep_in_corridor(delta)
		return
	var flat := Vector2(position.x, position.z)
	var over := flat.length() - bounds
	out_of_bounds = over > 0.0
	if not out_of_bounds:
		return
	var inward := -flat.normalized()
	# Scaled with the spool-up rate so the steering can't simply out-pull
	# it: holding outward settles about 8 m past the edge for any airframe.
	var push := get_acceleration_rate() * minf(over / 8.0, 1.6)
	velocity += Vector3(inward.x, 0.0, inward.y) * push * delta
	if over > bounds_overshoot:
		flat = flat.normalized() * (bounds + bounds_overshoot)
		position.x = flat.x
		position.z = flat.y


# A run's corridor: inside `corridor` (x, z on the ground) it's pushed
# back from the last corridor_margin metres of each edge and can't cross
# them. The edges are the screen's, so there's no warning.
func keep_in_corridor(delta: float) -> void:
	var low := corridor.position
	var high := corridor.end
	var push := get_acceleration_rate() * 1.2
	var over_low := Vector2(low.x + corridor_margin - position.x, low.y + corridor_margin - position.z)
	var over_high := Vector2(position.x - (high.x - corridor_margin), position.z - (high.y - corridor_margin))
	if over_low.x > 0.0:
		velocity.x += push * minf(over_low.x / corridor_margin, 1.0) * delta
	if over_high.x > 0.0:
		velocity.x -= push * minf(over_high.x / corridor_margin, 1.0) * delta
	if over_low.y > 0.0:
		velocity.z += push * minf(over_low.y / corridor_margin, 1.0) * delta
	if over_high.y > 0.0:
		velocity.z -= push * minf(over_high.y / corridor_margin, 1.0) * delta
	position.x = clampf(position.x, low.x, high.x)
	position.z = clampf(position.z, low.y, high.y)
	out_of_bounds = false


func _process(delta: float) -> void:
	update_hud(delta)

	if dead:
		return

	# The rotor works harder, and sounds it, the faster the helicopter goes,
	# and spools right up for a dash.
	var effort := clampf(velocity.length() / speed, 0.0, 1.2)
	rotor_effort = lerpf(rotor_effort, effort, 1.0 - exp(-6.0 * delta))
	if dash_time_left <= 0.0:
		rotor_boost = move_toward(rotor_boost, 0.0, dash_rotor_recover * delta)
	var boost := rotor_boost * dash_rotor_boost
	rotor_sound.pitch_scale = lerpf(0.95, 1.12, rotor_effort) + 0.25 * boost
	var spin := 1.0 + 0.3 * rotor_effort + boost
	# Turning more than half a blade gap per frame makes the blades seem to
	# crawl or spin backwards, so cap the step; past that, the thickening
	# blur disc shows the extra speed.
	if main_rotor != null:
		main_rotor.rotate_y(minf(delta * 28.0 * spin, PI / blade_count * 0.85))
	if tail_rotor != null:
		tail_rotor.rotate_x(minf(delta * 40.0 * spin, PI / 4.0 * 0.85))
	if rotor_blur != null:
		rotor_blur.albedo_color.a = rotor_blur_alpha * (1.0 + 0.5 * rotor_effort + 2.5 * boost)


func update_hud(delta: float) -> void:
	hit_flash.color.a = maxf(hit_flash.color.a - delta * 1.5, 0.0)
	lock_warning_timer = maxf(lock_warning_timer - delta, 0.0)
	flare_cooldown_left = maxf(flare_cooldown_left - delta, 0.0)
	flare_protection_left = maxf(flare_protection_left - delta, 0.0)
	# Dash charges come back one at a time.
	if dash_charges_left < dash_charges:
		dash_recharge_left -= delta
		if dash_recharge_left <= 0.0:
			dash_charges_left += 1
			dash_recharge_left = dash_cooldown
	var flares := "FLARES [F]" if flare_cooldown_left <= 0.0 else "FLARES %.1fs" % flare_cooldown_left
	var dash_text := "DASH %d/%d [SPACE]" % [dash_charges_left, dash_charges]
	if dash_charges_left < dash_charges:
		dash_text = "DASH %d/%d %.1fs" % [dash_charges_left, dash_charges, dash_recharge_left]
	flare_label.text = "%s     %s" % [flares, dash_text]

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
	flare_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
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
	rotor_blur = parts["rotor_blur"]
	rotor_blur_alpha = rotor_blur.albedo_color.a
	blade_count = maxi(airframe.blades, 1)
	# Near-white with black outlines in 1-bit, against near-black enemies.
	OneBit.paper(body)
	OneBit.rim(body)
