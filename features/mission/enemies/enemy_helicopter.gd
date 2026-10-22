extends EnemyBase

# Enemy helicopter: the main enemy (see DESIGN.md). It flies at the
# player's altitude and dogfights: circles at a preferred range with its
# nose on the helicopter, swaps direction now and then, locks on (warning
# the player) and fires a salvo of homing missiles, spaced so a good chain
# dodge can take them all. It mirrors the player's chain dodge: a deflected
# missile coming for it may be sent straight back (reflect_chance), so a
# missile can rally between them, or else it dashes clear (dash_chance)
# while it has charges. Shot down, it spins out trailing smoke, hits the
# ground and blows up.
#
# The look and the numbers are all exports, so each type is just a scene
# (enemy_scout.tscn, enemy_gunship.tscn).

const Missile := preload("res://features/mission/enemies/projectiles/aa_missile.gd")
const HeavyRocket := preload("res://features/mission/enemies/projectiles/heavy_rocket.gd")

@export_group("Look")
@export var color: Color = Color(0.4, 0.38, 0.3)
@export var fuselage: Vector3 = Vector3(1.3, 1.15, 2.5)
@export var tail_length: float = 6.6
@export var rotor_radius: float = 4.75
@export var blades: int = 4
@export var wing_span: float = 3.8
@export var tandem: bool = true
@export var wheels: bool = false
@export var model_scale: float = 1.0

@export_group("Flight")
@export var altitude: float = 16.0
@export var speed: float = 22.0
# m/s² it can change velocity by (its agility).
@export var acceleration: float = 18.0
# It circles the helicopter between these distances.
@export var range_min: float = 26.0
@export var range_max: float = 40.0
# Seconds between swapping the direction it circles in.
@export var orbit_swap_min: float = 2.5
@export var orbit_swap_max: float = 6.0
# Nose turn rate (radians per second) and lean into the motion.
@export var turn_rate: float = 4.0
@export var max_tilt_degrees: float = 30.0
# Other enemy helicopters closer than this push it away.
@export var separation: float = 14.0

@export_group("Missiles")
@export var engage_range: float = 70.0
@export var lock_time: float = 1.4
@export var reload_time: float = 5.0
@export var salvo_size: int = 3
# Seconds between missiles in a salvo.
@export var salvo_spacing: float = 0.3
# Heavy rockets (flare-proof, make repeated passes) instead of SAMs.
@export var heavy_rockets: bool = false
@export var missile_damage: float = 34.0
@export var missile_explosion: PackedScene

@export_group("Dash")
@export var dash_charges: int = 1
@export var dash_cooldown: float = 4.0
@export var dash_distance: float = 12.0
@export var dash_time: float = 0.2
# Chance it dashes away from a threat it sees coming.
@export_range(0.0, 1.0) var dash_chance: float = 0.6
# Threats closer than this, in seconds to impact, make it react.
@export var threat_window: float = 0.5
# Chance it sends a deflected missile straight back at the player, times
# reflect_falloff for every rally that missile has already had.
@export_range(0.0, 1.0) var reflect_chance: float = 0.5
@export_range(0.0, 1.0) var reflect_falloff: float = 0.6
# Under sustained fire it jinks: once it has taken this much damage
# (fading at half this per second), it swaps its circling direction and
# dashes, if it has a charge, so the player has to find it again.
@export var jink_damage: float = 5.0

@export_group("Hits")
# Each hit knocks the airframe this far (metres) away from the shot and
# twitches its roll; it springs back at hit_recover per second.
@export var hit_jolt: float = 0.35
@export var hit_twitch_degrees: float = 5.0
@export var hit_recover: float = 12.0

@export_group("Crash")
@export var crash_explosion_scale: float = 2.4
@export var crash_spin: float = 9.0

var velocity: Vector3 = Vector3.ZERO
var orbit_direction: float = 1.0
var orbit_timer: float = 0.0
var preferred_range: float = 0.0
var reload_timer: float = 0.0
var firing: bool = false
var dash_charges_left: int = 0
var dash_recharge_left: float = 0.0
var dash_time_left: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
# Threats already weighed for a dash, so each gets one roll.
var judged_threats: Dictionary = {}
# Recent damage, for jinking under fire (see jink_damage).
var under_fire: float = 0.0
# The body's knock-back from hits (see hit_jolt).
var jolt: Vector3 = Vector3.ZERO
var crashing: bool = false
var crash_velocity: Vector3 = Vector3.ZERO
var smoke: CPUParticles3D

var body: Node3D
var main_rotor: Node3D
var tail_rotor: Node3D
var muzzle: Marker3D
var time: float = 0.0


func _ready() -> void:
	build_model()
	super()
	add_to_group("air_enemies")
	# Sparks, chips and holes for every hit, smoke below half health and
	# fire below a quarter (see vehicle_damage.gd), placed on the fuselage
	# only: the model's full box is mostly rotor disc.
	damage_fx = VehicleDamage.new()
	add_child(damage_fx)
	var hull := fuselage * model_scale
	damage_fx.bounds = AABB(-hull, hull * 2.0)
	damage_fx.bounds_ready = true
	position.y = altitude
	orbit_direction = 1.0 if randf() < 0.5 else -1.0
	orbit_timer = randf_range(orbit_swap_min, orbit_swap_max)
	preferred_range = randf_range(range_min, range_max)
	reload_timer = randf_range(1.5, 3.0)
	dash_charges_left = dash_charges


func build_model() -> void:
	var data := HelicopterData.new()
	data.color = color
	data.fuselage = fuselage
	data.tail_length = tail_length
	data.rotor_radius = rotor_radius
	data.blades = blades
	data.wing_span = wing_span
	data.tandem = tandem
	data.wheels = wheels
	data.model_scale = model_scale
	var parts := HeliModel.build(self, data)
	body = parts["body"]
	main_rotor = parts["main_rotor"]
	tail_rotor = parts["tail_rotor"]
	muzzle = parts["muzzle"]


func _process(delta: float) -> void:
	# Rotors spin (slower as it goes down).
	var spin := 0.35 if crashing else 1.0
	main_rotor.rotate_y(28.0 * spin * delta)
	tail_rotor.rotate_x(40.0 * spin * delta)


func _physics_process(delta: float) -> void:
	time += delta
	if crashing:
		update_crash(delta)
		return

	var heli := helicopter()
	update_dash_charges(delta)
	under_fire = move_toward(under_fire, 0.0, jink_damage * 0.5 * delta)
	if dash_time_left > 0.0:
		update_dash(delta)
	else:
		fly(heli, delta)
		react_to_threats()
	position.y = altitude + sin(time * 1.9) * 0.3

	if heli != null:
		face_target(heli.global_position, delta)
		update_missiles(heli, delta)
	lean(delta)


# --- Flight ------------------------------------------------------------------

# Circle the helicopter at the preferred range, closing in or backing off
# to stay in the band, and keep clear of other enemy helicopters.
func fly(heli: Helicopter, delta: float) -> void:
	var desired := Vector3.ZERO
	if heli != null:
		orbit_timer -= delta
		if orbit_timer <= 0.0:
			orbit_direction = -orbit_direction
			orbit_timer = randf_range(orbit_swap_min, orbit_swap_max)
			preferred_range = randf_range(range_min, range_max)

		var offset := heli.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		var toward := offset / maxf(distance, 0.01)
		var around := toward.cross(Vector3.UP) * orbit_direction
		# -1 too close .. 1 too far, gently.
		var range_error := clampf((distance - preferred_range) / 10.0, -1.0, 1.0)
		desired = (around + toward * range_error * 1.5).normalized() * speed

	for other in get_tree().get_nodes_in_group("air_enemies"):
		if other == self or other.get("crashing"):
			continue
		var away: Vector3 = global_position - other.global_position
		away.y = 0.0
		var gap := away.length()
		if gap < separation and gap > 0.01:
			desired += away / gap * speed * (1.0 - gap / separation)

	velocity = velocity.move_toward(desired.limit_length(speed * 1.2), acceleration * delta)
	position += velocity * delta


func face_target(at: Vector3, delta: float) -> void:
	var to_target := at - global_position
	if Vector2(to_target.x, to_target.z).length() < 1.0:
		return
	var yaw := atan2(-to_target.x, -to_target.z)
	rotation.y = rotate_toward(rotation.y, yaw, turn_rate * delta)


# Lean the body into its motion, like the player's.
func lean(delta: float) -> void:
	var local := global_transform.basis.inverse() * (velocity / maxf(speed, 0.01))
	var tilt := deg_to_rad(max_tilt_degrees)
	var follow := 1.0 - exp(-8.0 * delta)
	body.rotation.x = lerpf(body.rotation.x, local.z * tilt, follow)
	body.rotation.z = lerpf(body.rotation.z, -local.x * tilt, follow)
	jolt = jolt.lerp(Vector3.ZERO, 1.0 - exp(-hit_recover * delta))
	body.position = global_transform.basis.inverse() * jolt


# --- Dash ----------------------------------------------------------------------

func update_dash_charges(delta: float) -> void:
	if dash_charges_left >= dash_charges:
		return
	dash_recharge_left -= delta
	if dash_recharge_left <= 0.0:
		dash_charges_left += 1
		dash_recharge_left = dash_cooldown


# Deflected missiles and the player's rockets: when one is about to land,
# roll once whether to jink out of the way.
# A deflected missile about to hit it gets one roll: send it back at the
# player (reflect_chance, less likely each rally), else dash clear if it
# has a charge (dash_chance), which shakes the missile off.
func react_to_threats() -> void:
	for missile in get_tree().get_nodes_in_group("aa_missiles"):
		# One roll per missile per rally.
		var key := "%d:%d" % [missile.get_instance_id(), missile.rallies]
		if not missile.deflected or judged_threats.has(key):
			continue
		if missile.deflect_target != self:
			continue
		var offset: Vector3 = global_position - missile.global_position
		var closing: float = missile.velocity.dot(offset.normalized())
		if closing <= 0.0 or offset.length() / closing > threat_window:
			continue
		judged_threats[key] = true
		# Sideways to the threat's path.
		var side: Vector3 = missile.velocity.cross(Vector3.UP).normalized()
		if randf() < 0.5:
			side = -side
		var heli := helicopter()
		if heli != null and randf() < reflect_chance * pow(reflect_falloff, missile.rallies):
			# Its own perfect dodge: a free dash, and the missile goes back.
			dash(side, false)
			missile.reflect(heli)
			if mission != null:
				mission.hud.dodge_fx.enemy_reflect(global_position, missile.rallies)
			return
		if dash_charges_left > 0 and randf() < dash_chance:
			dash(side)
			# Out of its seeker: it flies on past.
			missile.deflect_homing = false
			return


# `costs` false for the free dash of a reflect.
func dash(direction: Vector3, costs: bool = true) -> void:
	if costs:
		if dash_charges_left == dash_charges:
			dash_recharge_left = dash_cooldown
		dash_charges_left -= 1
	direction.y = 0.0
	dash_direction = direction.normalized()
	dash_time_left = dash_time
	velocity = dash_direction * speed
	Sfx.play_3d("dash_whoosh", global_position, 0.0, 0.85, 0.12)


func update_dash(delta: float) -> void:
	var before := 1.0 - dash_time_left / dash_time
	dash_time_left = maxf(dash_time_left - delta, 0.0)
	var after := 1.0 - dash_time_left / dash_time
	# Ease out, like the player's dash.
	var eased_before := 1.0 - (1.0 - before) * (1.0 - before)
	var eased_after := 1.0 - (1.0 - after) * (1.0 - after)
	position += dash_direction * dash_distance * (eased_after - eased_before)


# --- Missiles ------------------------------------------------------------------

func update_missiles(heli: Helicopter, delta: float) -> void:
	if firing:
		return
	if reload_timer > 0.0:
		reload_timer -= delta
		return
	if distance_to_heli(heli) > engage_range:
		lock_timer = 0.0
		return
	if update_lock(heli, delta, lock_time, heavy_rockets):
		fire_salvo(heli)


func fire_salvo(heli: Helicopter) -> void:
	firing = true
	for i in salvo_size:
		if i > 0:
			await get_tree().create_timer(salvo_spacing, false).timeout
		if crashing or not is_inside_tree() or heli == null or not is_instance_valid(heli) or heli.dead:
			break
		launch_missile(heli, i)
	firing = false
	reload_timer = reload_time


func launch_missile(heli: Helicopter, index: int) -> void:
	var missile: Node3D = HeavyRocket.new() if heavy_rockets else Missile.new()
	missile.target = heli
	missile.explosion_scene = missile_explosion
	missile.damage = missile_damage
	missile.source_name = display_name
	# Fired in the air: a short drop off the rail, then the motor.
	missile.eject_time = 0.35
	missile.eject_gravity = 3.0
	MissionContext.spawn_parent(self).add_child(missile)
	# Alternate rails, kicked out to the side, so a salvo fans out.
	var side := global_transform.basis.x * (1.0 if index % 2 == 0 else -1.0)
	var forward := -global_transform.basis.z
	var from := muzzle.global_position + side * 1.5
	missile.launch(from, (forward + side * 0.6).normalized())


# --- Damage and the crash ----------------------------------------------------

func take_damage(amount: float, light_weapon: bool = false) -> bool:
	var health_before := health
	var killed := super(amount, light_weapon)
	if not killed and not crashing:
		under_fire += health_before - health
		if under_fire >= jink_damage:
			under_fire = 0.0
			jink()
	return killed


# Every hit that doesn't kill: the damage effects, plus a knock away from
# the shot and a twitch of the roll, so rounds visibly land.
func register_hit(from: Vector3, light_weapon: bool) -> void:
	super(from, light_weapon)
	var away := global_position - from
	away.y = 0.0
	jolt = (jolt + away.normalized() * hit_jolt).limit_length(hit_jolt * 3.5)
	body.rotation.z += deg_to_rad(randf_range(-hit_twitch_degrees, hit_twitch_degrees))


# Breaks off under fire: circles the other way and, with a charge, dashes
# across the player's line of fire.
func jink() -> void:
	orbit_direction = -orbit_direction
	orbit_timer = randf_range(orbit_swap_min, orbit_swap_max)
	var heli := helicopter()
	if heli == null or dash_charges_left <= 0 or dash_time_left > 0.0:
		return
	var toward := heli.global_position - global_position
	dash(toward.cross(Vector3.UP).normalized() * orbit_direction)


func die() -> void:
	# Out of the fight at once; the wreck falls on its own.
	crashing = true
	remove_from_group("enemies")
	remove_from_group("air_enemies")
	lock_timer = 0.0
	if health_bar != null:
		health_bar.visible = false
	crash_velocity = velocity * 0.6
	smoke = make_crash_smoke()
	add_child(smoke)
	if mission != null:
		mission.shake(0.3, global_position)
	Sfx.play_3d("explosion_small", global_position)


# Spins and falls, smoking, until it hits the ground and blows up.
func update_crash(delta: float) -> void:
	crash_velocity.y -= 14.0 * delta
	position += crash_velocity * delta
	rotate_y(crash_spin * delta)
	body.rotation.z = move_toward(body.rotation.z, 0.7, delta)
	body.rotation.x = move_toward(body.rotation.x, 0.4, delta)
	if global_position.y > 0.5:
		return

	if missile_explosion != null:
		var explosion := missile_explosion.instantiate() as Node3D
		MissionContext.spawn_parent(self).add_child(explosion)
		explosion.global_position = global_position
		explosion.scale = Vector3.ONE * crash_explosion_scale
	if mission != null:
		mission.shake(0.6, global_position)
		mission.hit_stop(0.06)
	smoke.emitting = false
	smoke.reparent(MissionContext.spawn_parent(self))
	get_tree().create_timer(smoke.lifetime).timeout.connect(smoke.queue_free)
	super.die()


func make_crash_smoke() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = 60
	particles.lifetime = 1.6
	particles.local_coords = false
	particles.gravity = Vector3(0, 2.0, 0)
	particles.direction = Vector3.UP
	particles.spread = 40.0
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 3.0
	particles.scale_amount_min = 1.2
	particles.scale_amount_max = 2.2
	# Black smoke with a white rim: it's an enemy going down.
	particles.mesh = OneBit.puff(Color.BLACK, Color.WHITE, 0.3)
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(0.3, 1.0))
	grow.add_point(Vector2(1.0, 0.2))
	particles.scale_amount_curve = grow
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.emitting = true
	return particles
