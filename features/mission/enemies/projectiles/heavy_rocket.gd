extends "res://features/mission/enemies/projectiles/aa_missile.gd"

# Heavy rocket: one big, dark rocket that can't be sent back. It lines up
# on the helicopter from afar, then commits to a straight run for the last
# commit_distance: anything still on that line gets hit, so a sidestep
# beats it. Then it flies on, slows, swings round and lines up again,
# max_passes times, before it runs dry and airbursts. Easy to dodge once;
# the test is keeping track of it while doing everything else.

# Speed on the straight. With the target well off its nose it bleeds down
# to loop_speed, so it visibly swings round between passes.
var cruise_speed: float = 40.0
var loop_speed: float = 22.0
# How quickly it gains or loses speed, in m/s².
var speed_change: float = 30.0
# Turn rate (radians per second) at cruise and at loop speed.
var cruise_turn_rate: float = 1.5
var loop_turn_rate: float = 1.8
# Inside this distance it stops steering and flies straight.
var commit_distance: float = 22.0
# After each pass it flies straight on this long before turning, so it
# comes back at you head-on instead of circling you.
var extend_time: float = 1.0
# Height it won't dive below while lining up.
var min_altitude: float = 6.0
# Dodges before it gives up.
var max_passes: int = 4

var passes: int = 0
var extend_left: float = 0.0
# On its committed straight run.
var committed: bool = false
# Approaches abandoned in a row for being badly lined up.
var break_offs: int = 0


func _init() -> void:
	# Too heavy to turn back: it has to be outflown, every pass.
	deflectable = false
	size = 1.8
	damage = 50.0
	fuze_radius = 5.0
	hit_radius = 2.0
	# A slower, heavier pop out of the tube.
	eject_speed = 7.0
	eject_time = 1.2
	# The nose leads by its cruise speed while it drifts unlit.
	boost_speed = cruise_speed
	# The motor lasts as long as the rocket; it ends by giving up.
	motor_time = 25.0
	lifetime = 25.0
	body_color = Color(0.22, 0.24, 0.2)
	trail_color = Color(0.32, 0.3, 0.28, 0.65)
	source_name = "HEAVY ROCKET"


# Lit: cruise on the straight, slow right down to come round.
func update_speed(delta: float) -> void:
	if not ignited:
		super(delta)
		return
	var speed := velocity.length()
	var goal := cruise_speed
	if is_instance_valid(target) and extend_left <= 0.0 and not committed:
		var off := velocity.angle_to(target.global_position - global_position)
		goal = lerpf(cruise_speed, loop_speed, clampf((off - deg_to_rad(40.0)) / deg_to_rad(60.0), 0.0, 1.0))
	# The motor kicks it up to speed hard as it lights.
	var rate := ignition_accel if burn_age() < 0.5 else speed_change
	velocity = velocity.normalized() * move_toward(speed, goal, rate * delta)


func steer(delta: float) -> void:
	if extend_left > 0.0:
		extend_left -= delta
		return

	var to_target := target.global_position - global_position
	var distance := to_target.length()

	# The straight run: no steering until it has gone past.
	if committed:
		if velocity.dot(to_target) < 0.0 and distance > fuze_radius:
			pass_by()
		return
	# Close in it never turns tight, so a sidestep always works: lined up,
	# it commits to the run; badly lined up, it breaks off and goes round
	# (twice at most, then it commits anyway).
	if distance <= commit_distance:
		if velocity.angle_to(to_target) < deg_to_rad(25.0) or break_offs >= 2:
			committed = true
			break_offs = 0
		else:
			break_offs += 1
			extend_left = extend_time
		return

	# Lining up: pure pursuit, tighter the slower it goes.
	var current := velocity.normalized()
	var desired := to_target.normalized()
	# Low down, pull up rather than plough into the ground.
	if global_position.y < min_altitude:
		desired.y = maxf(desired.y, 0.4)
		desired = desired.normalized()
	var angle := current.angle_to(desired)
	var slowed := clampf((cruise_speed - velocity.length()) / (cruise_speed - loop_speed), 0.0, 1.0)
	var step := lerpf(cruise_turn_rate, loop_turn_rate, slowed) * delta
	var direction := desired if angle <= step else current.slerp(desired, step / angle).normalized()
	velocity = direction * velocity.length()


# It turns away and back on purpose, so the base rocket's "distance is
# growing, it has lost them" check doesn't apply; steer() spots passes.
func lose_target() -> void:
	pass


# Sent back: a fresh set of passes, at a faster cruise.
func reflect(at: Node3D) -> void:
	super(at)
	cruise_speed *= rally_speedup
	passes = 0
	committed = false
	extend_left = 0.0
	break_offs = 0


# Gone past on a straight run: a dodge. Fly on, then come round again;
# after the last one it airbursts.
func pass_by() -> void:
	committed = false
	extend_left = extend_time
	passes += 1
	if passes >= max_passes:
		lost = true

	var heli := helicopter()
	var mission := MissionContext.of(self)
	if heli == null or mission == null:
		return
	Sfx.play_2d("missile_flyby", 0.0, 0.65)
	mission.shake(0.15)
	var text := "DODGED %d/%d" % [passes, max_passes]
	mission.hud.spawn_popup(text, heli.global_position, Color(0.55, 0.85, 1.0), passes >= max_passes)
