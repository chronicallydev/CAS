extends Node3D

# Homing anti-air rocket. A gas charge pops it lazily out of the tube;
# a second later the motor lights and it boosts much faster than a
# helicopter can fly, then settles to a sustain speed that still closes
# from behind, so running away doesn't work. It steers by proportional
# navigation (aiming where the target is going) with a limit on how hard
# it can turn: flying straight gets you hit, a hard break at the last
# moment makes it overshoot. When the motor burns out it slows and turns
# worse, and soon self-destructs.
#
# A proximity fuze sets it off at its closest pass; the blast hurts the
# helicopter by distance, so a near miss still stings.

var target: Node3D
# Ejected from the tube at this speed; it arcs up and sags for
# eject_time while its nose swings round (at eject_turn_rate, radians per
# second) toward the intercept, then the motor lights along the nose.
var eject_speed: float = 9.0
var eject_time: float = 1.0
var eject_gravity: float = 5.0
var eject_turn_rate: float = 2.5
# Once lit it surges at this many m/s² up to boost_speed, holds it until
# boost_time after ignition, then eases to sustain_speed.
var ignition_accel: float = 120.0
var boost_speed: float = 62.0
var sustain_speed: float = 44.0
# Long enough to win back the ground a fleeing helicopter gains while
# the rocket drifts unlit.
var boost_time: float = 1.6
# Hardest turn, in radians per second. Turn radius is speed / this, so
# the fast boost phase turns wider (Cobra at full speed turns far
# tighter, which is how a late break beats it).
var turn_rate: float = 1.8
# Proportional navigation gain: 3 to 5 leads the target well.
var nav_gain: float = 4.0
# Seconds of motor burn from ignition. After it the rocket coasts,
# slowing and turning worse, until lifetime (counted from launch).
var motor_time: float = 5.0
var lifetime: float = 8.0
# The fuze arms at this distance and fires at the closest pass; inside
# hit_radius it fires at once.
var fuze_radius: float = 4.5
var hit_radius: float = 1.5
# Damage at hit_radius; at the edge of the fuze it falls to this fraction.
var damage: float = 34.0
var edge_damage: float = 0.35
var explosion_scene: PackedScene
var ground_y: float = -0.4
# Model size: Stinger missiles are small, SAM-site missiles big.
var size: float = 1.0
# Who fired it, for damage stats (e.g. "STINGER").
var source_name: String = "MISSILE"
# Flares don't pull it off (see Helicopter.deploy_flares).
var ignores_flares: bool = false
# A darker body and smoke tell rockets apart at a glance.
var body_color: Color = Color(0.92, 0.92, 0.9)
var trail_color: Color = Color(0.92, 0.92, 0.9, 0.5)

# Passing the target this close counts as a near miss for feedback;
# closer than close_call_radius the game slows for a moment.
var near_miss_radius: float = 10.0
var close_call_radius: float = 6.0
# After it overshoots, it flies on unguided this long and airbursts.
var lost_burst_delay: float = 0.6

# Deflected by a perfect dodge (see ChainDodge): it turns on the enemies,
# homing at deflect_turn_rate on the nearest one (favouring those ahead),
# and blows up on contact, hurting every enemy within deflect_radius.
var deflect_speed: float = 46.0
var deflect_turn_rate: float = 2.6
var deflect_time: float = 3.0
var deflect_damage: float = 120.0
var deflect_radius: float = 7.0
var deflect_contact: float = 3.5

var velocity: Vector3
# Where it points. Before ignition this turns on its own while the
# rocket drifts; once lit it follows the flight path.
var nose: Vector3 = Vector3.FORWARD
var age: float = 0.0
# Smoothed estimate of the target's velocity, for leading it.
var target_velocity: Vector3 = Vector3.ZERO
var last_target_position: Vector3
var tracked: Node3D
var closest: float = INF
var previous_distance: float = INF
# Overshot (or outrun): no more guidance.
var lost: bool = false
var lost_age: float = 0.0
var ignited: bool = false
var burned_out: bool = false
var deflected: bool = false
var deflect_homing: bool = true
var deflect_left: float = 0.0
var deflect_target: Node3D
# Times an enemy helicopter has sent it back at the player (see reflect).
var rallies: int = 0
# Each rally sends it back this much faster.
var rally_speedup: float = 1.12

var model: Node3D
var flame: MeshInstance3D
var motor_light: OmniLight3D
var trail: CPUParticles3D
var motor_sound: AudioStreamPlayer3D
var wobble_phase: float = 0.0


func _ready() -> void:
	add_to_group("aa_missiles")
	build_visuals()
	# Drawn 1.6x life size so it reads in 1-bit (it was about a pixel wide).
	model.scale *= size * 1.6
	# Dark until the motor lights.
	flame.visible = false
	motor_light.visible = false
	trail.emitting = false
	wobble_phase = randf() * TAU

	motor_sound = AudioStreamPlayer3D.new()
	motor_sound.stream = Sfx.get_stream("missile_motor")
	motor_sound.volume_db = Sfx.mix_db("missile_motor")
	motor_sound.unit_size = 45.0
	motor_sound.max_db = 6.0
	add_child(motor_sound)


# Call after adding to the tree.
func launch(from: Vector3, direction: Vector3) -> void:
	global_position = from
	nose = direction.normalized()
	velocity = nose * eject_speed
	face(nose)
	# A soft pop and a puff of gas; the real noise comes at ignition.
	spawn_blast(from, direction.normalized(), 3.0, 18, 1.0)
	Sfx.play_3d("missile_eject", from)


# Seconds since the motor lit (negative before).
func burn_age() -> float:
	return age - eject_time


func _physics_process(delta: float) -> void:
	age += delta
	if deflected:
		fly_deflected(delta)
		return
	if not ignited and age >= eject_time:
		ignite()

	var has_target: bool = not lost and is_instance_valid(target) and not target.get("dead")
	if has_target:
		track_target(delta)

	update_speed(delta)
	if has_target:
		if ignited:
			steer(delta)
		else:
			point_nose(delta)
	if ignited:
		nose = velocity.normalized()

	global_position += velocity * delta
	face(nose)
	update_motor(delta)

	if lost:
		lost_age += delta
		if lost_age >= lost_burst_delay:
			detonate()
		return

	if has_target:
		var distance := global_position.distance_to(target.global_position)
		# Fuze: at once when very close, else at the closest pass.
		if distance <= hit_radius or (distance <= fuze_radius and distance > previous_distance):
			detonate()
			return
		# Overshot, or outrun after burnout: it has lost them. The margin
		# keeps a dash straight away from it from counting. The target
		# pulls away while it drifts unlit, so only count from ignition.
		if ignited:
			closest = minf(closest, distance)
			if distance > closest + 8.0:
				lose_target()
		previous_distance = distance

	if age >= lifetime or global_position.y <= ground_y:
		detonate()


func track_target(delta: float) -> void:
	var position_now := target.global_position
	# New target (launch, or a flare swap): start the estimate over.
	if target != tracked:
		tracked = target
		last_target_position = position_now
		var start = target.get("velocity")
		target_velocity = start if start is Vector3 else Vector3.ZERO
		closest = INF
		previous_distance = INF
	var measured := (position_now - last_target_position) / maxf(delta, 0.001)
	last_target_position = position_now
	# Smooth out frame jitter; a flare swap jumps once and settles.
	target_velocity = target_velocity.lerp(measured, 1.0 - exp(-12.0 * delta))


# Drift unlit, surge to boost, ease to sustain, then bleed speed once
# the motor is out.
func update_speed(delta: float) -> void:
	if not ignited:
		velocity *= exp(-0.3 * delta)
		velocity.y -= eject_gravity * delta
		return

	var speed := velocity.length()
	var burn := burn_age()
	var goal := boost_speed
	var rate := 0.0
	if burn < boost_time:
		velocity = velocity.normalized() * move_toward(speed, boost_speed, ignition_accel * delta)
		return
	elif burn < motor_time:
		goal = sustain_speed
		rate = 2.5
	else:
		goal = sustain_speed * 0.45
		rate = 0.6
	if rate > 0.0:
		speed = lerpf(speed, goal, 1.0 - exp(-rate * delta))
	velocity = velocity.normalized() * speed


# Unlit: swing the nose toward where the target will be once the motor
# has brought it up to speed.
func point_nose(delta: float) -> void:
	var to_target := target.global_position - global_position
	var aim := to_target + target_velocity * (to_target.length() / boost_speed)
	var desired := aim.normalized()
	var angle := nose.angle_to(desired)
	var step := eject_turn_rate * delta
	nose = desired if angle <= step else nose.slerp(desired, step / angle).normalized()


# Proportional navigation: turn at nav_gain times the rate the line of
# sight swings, so it heads for the intercept point.
func steer(delta: float) -> void:
	var to_target := target.global_position - global_position
	var range_sq := maxf(to_target.length_squared(), 0.01)
	var relative := target_velocity - velocity
	var los_rate := to_target.cross(relative) / range_sq
	var accel := los_rate.cross(velocity) * nav_gain

	# Fins bite less as it slows after burnout.
	var speed := velocity.length()
	var authority := 1.0
	if burn_age() >= motor_time:
		authority = clampf(speed / sustain_speed, 0.2, 1.0)
		authority *= authority
	accel = accel.limit_length(turn_rate * speed * authority)

	velocity = (velocity + accel * delta).normalized() * speed


func lose_target() -> void:
	lost = true
	var heli := helicopter()
	# Only the helicopter's own dodges get feedback, not flares doing their job.
	if heli == null or target != heli or closest > near_miss_radius:
		return
	var mission := MissionContext.of(self)
	if mission == null:
		return
	Sfx.play_2d("missile_flyby", 0.0, 0.8)
	mission.shake(0.18)
	mission.hud.spawn_popup("EVADED", heli.global_position, Color(0.55, 0.85, 1.0))
	if closest <= close_call_radius:
		mission.hit_stop(0.28, 0.3)


## Perfect-dodged: stop chasing the helicopter and turn on the enemies.
func deflect(homing: bool) -> void:
	deflected = true
	deflect_homing = homing
	deflect_left = deflect_time
	target = null
	velocity = velocity.normalized() * maxf(velocity.length(), deflect_speed)


## Sent back at `at` (the player) by an enemy helicopter's own perfect
## dodge: guided again, its motor re-lit as if just fired, a little faster
## each rally, and black again (the enemy's). The player can deflect it
## once more, so a missile can go back and forth.
func reflect(at: Node3D) -> void:
	deflected = false
	deflect_target = null
	rallies += 1
	target = at
	lost = false
	tracked = null
	ignited = true
	burned_out = false
	# Back in the boost phase with a full motor.
	age = eject_time
	boost_speed *= rally_speedup
	sustain_speed *= rally_speedup
	var toward := (at.global_position - global_position).normalized()
	velocity = toward * maxf(velocity.length(), sustain_speed)
	nose = toward
	face(nose)
	flame.visible = true
	motor_light.visible = true
	trail.emitting = true
	motor_sound.volume_db = Sfx.mix_db("missile_motor")
	if not motor_sound.playing:
		motor_sound.play()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", false, false):
		if mesh != flame:
			mesh.material_override = null


func fly_deflected(delta: float) -> void:
	deflect_left -= delta
	if deflect_homing:
		if not is_valid_enemy(deflect_target):
			deflect_target = pick_enemy()
		if deflect_target != null:
			# Lead a moving target (enemy helicopters) by where it will be.
			var aim := deflect_target.global_position
			var target_velocity: Variant = deflect_target.get("velocity")
			if target_velocity is Vector3:
				aim += target_velocity * aim.distance_to(global_position) / maxf(velocity.length(), 1.0)
			var desired := (aim - global_position).normalized()
			var current := velocity.normalized()
			var angle := current.angle_to(desired)
			# Turns tighter the longer it's been deflected, so it comes round
			# after overshooting the player and doesn't orbit a dodging target.
			var tighten := 1.0 + 1.5 * clampf((deflect_time - deflect_left) / 0.8, 0.0, 1.0)
			var step := deflect_turn_rate * tighten * delta
			var direction := desired if angle <= step else current.slerp(desired, step / angle).normalized()
			velocity = direction * velocity.length()
	velocity = velocity.normalized() * move_toward(velocity.length(), deflect_speed, 40.0 * delta)
	nose = velocity.normalized()
	global_position += velocity * delta
	face(nose)
	update_motor(delta)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_valid_enemy(enemy) and global_position.distance_to(enemy.global_position) <= deflect_contact:
			detonate()
			return
	if deflect_left <= 0.0 or global_position.y <= ground_y:
		detonate()


func is_valid_enemy(enemy: Node) -> bool:
	return enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.get("health") > 0.0


# Nearest enemy, with those behind the missile counted as further away.
func pick_enemy() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var forward := velocity.normalized()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_valid_enemy(enemy):
			continue
		var offset: Vector3 = enemy.global_position - global_position
		var score := offset.length() * (2.0 - forward.dot(offset.normalized()))
		if score < best_score:
			best = enemy
			best_score = score
	return best


# Every enemy in the blast takes the deflected missile's damage.
func blast_enemies() -> int:
	var kills := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_valid_enemy(enemy):
			continue
		if global_position.distance_to(enemy.global_position) <= deflect_radius:
			if enemy.take_damage(deflect_damage):
				kills += 1
	return kills


func update_motor(delta: float) -> void:
	# Wobble the model so the smoke corkscrews a little.
	wobble_phase += delta * 9.0
	var burn := burn_age()
	var wobble := 0.06 if burn < boost_time else 0.12
	model.position = Vector3(sin(wobble_phase), cos(wobble_phase * 1.3), 0.0) * wobble * size

	if not ignited:
		return
	if not burned_out and burn >= motor_time:
		burned_out = true
		trail.emitting = false
		flame.visible = false
		motor_light.visible = false
		create_tween().tween_property(motor_sound, "volume_db", -40.0, 0.3)
		return
	if burned_out:
		return

	var boosting := burn < boost_time
	var flicker := randf_range(0.85, 1.15)
	# The flame flares huge as it lights, then settles to the boost size.
	var surge := 1.0 + 1.5 * clampf(1.0 - burn / 0.3, 0.0, 1.0)
	flame.scale = Vector3.ONE * (1.7 if boosting else 1.0) * surge * flicker
	motor_light.light_energy = (4.0 if boosting else 2.0) * surge * flicker

	# Louder and higher as it closes on the helicopter.
	var heli := helicopter()
	var near := 0.0
	if heli != null:
		near = clampf(1.0 - global_position.distance_to(heli.global_position) / 40.0, 0.0, 1.0)
	motor_sound.volume_db = Sfx.mix_db("missile_motor") + near * 9.0
	motor_sound.pitch_scale = (1.15 if boosting else 1.0) + near * 0.35


# The motor lights: flash, a burst of smoke behind, the roar, and the
# trail starts.
func ignite() -> void:
	ignited = true
	# Thrust drives it along the nose from here.
	velocity = nose * velocity.length()
	flame.visible = true
	motor_light.visible = true
	trail.emitting = true
	motor_sound.play()

	spawn_blast(global_position - nose * size, nose, 9.0, 30, 1.6)
	Sfx.play_3d("sam_launch", global_position)
	var mission := MissionContext.of(self)
	if mission != null:
		mission.shake(0.22, global_position)


func helicopter() -> Node3D:
	var mission := MissionContext.of(self)
	if mission == null or mission.helicopter == null or mission.helicopter.dead:
		return null
	return mission.helicopter


func face(direction: Vector3) -> void:
	var up := Vector3.UP
	if absf(direction.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	look_at(global_position + direction, up)


func detonate() -> void:
	var on_ground := global_position.y <= ground_y + 0.5
	# A deflected missile is the player's: it spares the helicopter.
	var hurt := false if deflected else blast_helicopter()
	if deflected:
		var kills := blast_enemies()
		var mission := MissionContext.of(self)
		if kills > 0 and mission != null:
			mission.hud.dodge_fx.deflect_kill(global_position, kills)

	if explosion_scene != null and get_parent() != null:
		var explosion := explosion_scene.instantiate() as Node3D
		get_parent().add_child(explosion)
		explosion.global_position = global_position
		# Airbursts get the full boom; a hit gets a bigger one.
		explosion.scale = Vector3.ONE * (1.3 if hurt else (0.8 if on_ground else 1.0))
		# A deflected missile is the payoff: the biggest boom.
		if deflected:
			explosion.scale = Vector3.ONE * 1.8

	if hurt:
		var mission := MissionContext.of(self)
		if mission != null:
			mission.hit_stop(0.07)

	# Leave the smoke trail behind to fade out.
	if trail != null and get_parent() != null:
		trail.emitting = false
		trail.reparent(get_parent())
		get_tree().create_timer(trail.lifetime).timeout.connect(trail.queue_free)

	queue_free()


# The blast hurts the helicopter by distance, whatever the rocket was
# chasing (a flare dropped too close still lets it through). True if hit.
func blast_helicopter() -> bool:
	var heli := helicopter()
	if heli == null:
		return false
	var distance := global_position.distance_to(heli.global_position)
	if distance > fuze_radius:
		return false
	var falloff := clampf((distance - hit_radius) / maxf(fuze_radius - hit_radius, 0.01), 0.0, 1.0)
	heli.take_damage(damage * lerpf(1.0, edge_damage, falloff), source_name)
	return true


# A flash and a burst of smoke blown back against `direction` (the
# eject pop at the tube, the motor lighting in the air).
func spawn_blast(at: Vector3, direction: Vector3, flash_energy: float, puffs: int, puff_scale: float) -> void:
	var parent := get_parent()
	if parent == null:
		return

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.75, 0.4)
	flash.omni_range = 14.0
	flash.light_energy = flash_energy
	parent.add_child(flash)
	flash.global_position = at
	var fade := flash.create_tween()
	fade.tween_property(flash, "light_energy", 0.0, 0.35)
	fade.tween_callback(flash.queue_free)

	var smoke := make_smoke(puffs, 2.2, Color(0.85, 0.82, 0.78, 0.6))
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	smoke.direction = -direction
	smoke.spread = 35.0
	smoke.initial_velocity_min = 3.0
	smoke.initial_velocity_max = 9.0
	smoke.damping_min = 4.0
	smoke.damping_max = 6.0
	smoke.scale_amount_min = 1.0 * puff_scale
	smoke.scale_amount_max = 2.0 * puff_scale
	parent.add_child(smoke)
	smoke.global_position = at
	smoke.emitting = true
	get_tree().create_timer(smoke.lifetime + 0.2).timeout.connect(smoke.queue_free)


func make_smoke(amount: int, life: float, color: Color) -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.amount = amount
	smoke.lifetime = life
	smoke.local_coords = false
	smoke.gravity = Vector3(0, 0.5, 0)
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# 1-bit: solid puffs, white with a black rim for light smoke and black
	# with a white rim for dark, instead of see-through ones that would only
	# dither into the sand.
	var light := color.get_luminance() > 0.5
	smoke.mesh = OneBit.puff(Color.WHITE if light else Color.BLACK, Color.BLACK if light else Color.WHITE, 0.25)

	# Puffs swell off the nozzle, then shrink away and pop out.
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(0.2, 1.0))
	grow.add_point(Vector2(1.0, 0.3))
	smoke.scale_amount_curve = grow
	return smoke


func build_visuals() -> void:
	# Everything that wobbles (the smoke too) hangs off the model.
	model = Node3D.new()
	add_child(model)

	# 1-bit: a solid black body (enemy fire is ink), drawn bigger than life
	# so it's more than a pixel wide; `body_color` only tints the colour
	# palettes.
	var white := OneBit.solid(body_color.darkened(0.85))

	# Body (forward is -Z).
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.18
	body_mesh.bottom_radius = 0.18
	body_mesh.height = 1.6
	body_mesh.material = white
	body.mesh = body_mesh
	body.rotation_degrees.x = 90.0
	model.add_child(body)

	# Nose cone.
	var nose := MeshInstance3D.new()
	var nose_mesh := CylinderMesh.new()
	nose_mesh.top_radius = 0.0
	nose_mesh.bottom_radius = 0.18
	nose_mesh.height = 0.4
	nose_mesh.material = white
	nose.mesh = nose_mesh
	nose.rotation_degrees.x = -90.0
	nose.position = Vector3(0, 0, -1.0)
	model.add_child(nose)

	# Motor glow: big in the boost, goes out at burnout.
	flame = MeshInstance3D.new()
	flame.mesh = OneBit.puff(Color.WHITE, Color.BLACK, 0.35)
	flame.position = Vector3(0, 0, 1.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(flame)

	motor_light = OmniLight3D.new()
	motor_light.light_color = Color(1.0, 0.7, 0.35)
	motor_light.omni_range = 8.0
	motor_light.position = Vector3(0, 0, 1.2)
	model.add_child(motor_light)

	# Thick smoke trail in world space.
	trail = make_smoke(170, 2.6, trail_color)
	trail.position = Vector3(0, 0, 1.1)
	trail.direction = Vector3(0, 0, 1)
	trail.spread = 6.0
	trail.initial_velocity_min = 0.3
	trail.initial_velocity_max = 1.0
	trail.scale_amount_min = 1.2
	trail.scale_amount_max = 2.0
	model.add_child(trail)
