extends EnemyBase

# Shilka (ZSU-23-4): a tracked, radar-guided flak tank. It drives in like a
# SAM truck, stops at range and spins up its radar. Each time the radar
# locks, it marks an amber strip (danger_zone.gd) along where the
# helicopter will be if it keeps doing what it's doing, a straight line or
# a steady circle, then fills it with flak for a moment, hurting every
# tick you're inside. Hovering gets a box right on top of you. Turning out
# of the strip during the warning saves you. Heavy armour shrugs off the
# minigun. Answer: rockets or cannon, change course when the strip
# appears, or a flare (which stops the radar locking on).
# Built from primitives in code.

const P := preload("res://shared/props/prop_builder.gd")
const Tracer := preload("res://features/mission/enemies/projectiles/tank_shell.gd")
const DangerZone := preload("res://features/mission/hazards/danger_zone.gd")
const HEALTH_BAR := preload("res://shared/health_bar/health_bar_3d.tscn")

@export var speed: float = 7.0
@export var ride_height: float = -0.4
# It stops somewhere in this distance range from the helicopter, and
# follows once it's well out of reach.
@export var firing_range_min: float = 30.0
@export var firing_range_max: float = 44.0

@export_group("Guns")
# Max horizontal distance to the helicopter for the radar to lock.
@export var engage_range: float = 70.0
@export var lock_time: float = 1.0
@export var burst_cooldown: float = 2.2
# How quickly the radar's estimate of the helicopter's velocity and turn
# rate catches up (per second). Lower = laggier.
@export var tracking: float = 5.0

@export_group("Flak zone")
# Seconds the strip shows before the flak arrives, and how long it stays
# live, hurting the helicopter every tick_interval it's inside.
@export var zone_warning: float = 0.8
@export var zone_active: float = 0.8
@export var tick_interval: float = 0.2
@export var tick_damage: float = 4.0
# Strip width, and its length: what the helicopter covers while it's
# live, plus some margin, within these bounds.
@export var zone_width: float = 10.0
@export var zone_length_min: float = 14.0
@export var zone_length_max: float = 48.0
@export var zone_color: Color = Color(1.0, 0.55, 0.1)

@export_group("Tracers")
# Shells in the visible stream into the zone (the zone does the damage).
@export var shot_interval: float = 0.05
@export var shell_flight_time: float = 0.45

var firing_range: float = 0.0
var in_position: bool = false
var turret: Node3D
var guns: Node3D
var radar: Node3D
var muzzles: Array = []
var muzzle_flash: OmniLight3D
var next_barrel: int = 0
var shot_timer: float = 0.0
var cooldown: float = 0.0
# The strip it's firing into, while it's warning or live.
var zone: Node3D
# The radar's smoothed estimate of the helicopter's motion: its velocity
# and how fast its heading is turning (radians per second, around Y).
var tracked_velocity: Vector3 = Vector3.ZERO
var tracked_speed: float = 0.0
var tracked_turn: float = 0.0
# The helicopter's velocity last frame, for measuring its turn rate.
var last_velocity: Vector3 = Vector3.ZERO


func _init() -> void:
	max_health = 14.0
	light_armor = 0.95
	score_value = 70
	display_name = "SHILKA"
	leaves_wreck = true
	detach_parts = PackedStringArray(["Turret"])
	contact_damage = 20.0


func _ready() -> void:
	build_model()
	super()
	firing_range = randf_range(firing_range_min, firing_range_max)
	cooldown = randf_range(1.0, 2.5)


func _physics_process(delta: float) -> void:
	global_position.y = ride_height
	# The radar never stops turning.
	radar.rotate_y(delta * 3.0)
	muzzle_flash.light_energy = maxf(muzzle_flash.light_energy - delta * 40.0, 0.0)

	# Drive in, then hold position (follow the helicopter if it gets away).
	if in_position and objective_distance() > engage_range * 0.8:
		in_position = false
	if not in_position:
		var direction := flat_direction_to_center()
		global_position += direction * speed * delta
		face_direction(direction)
		if objective() == null or objective_distance() <= firing_range:
			in_position = true

	var heli := helicopter()
	if heli == null:
		lock_timer = 0.0
		return

	track(heli, delta)

	# Aim at the strip while firing into it, else at the helicopter.
	var firing := is_instance_valid(zone)
	aim_guns(zone.strike_point() if firing else heli.global_position, delta)

	if firing:
		# The stream starts so the first shells arrive as the strip goes
		# live, and keeps pouring in until it's done.
		if zone.done:
			zone = null
			cooldown = burst_cooldown * randf_range(0.85, 1.2)
		elif zone.active_left > 0.0 or zone.time_left <= shell_flight_time:
			shot_timer -= delta
			while shot_timer <= 0.0:
				shot_timer += shot_interval
				fire_at(zone.random_point())
		return

	if not in_position or distance_to_heli(heli) > engage_range:
		lock_timer = 0.0
		return

	cooldown -= delta
	if cooldown > 0.0:
		lock_timer = 0.0
		return

	# Lock on (flares break it), then mark the strip.
	if update_lock(heli, delta, lock_time):
		mark_zone(heli)


func aim_guns(at: Vector3, delta: float) -> void:
	var to_target := at - guns.global_position
	var yaw := atan2(-to_target.x, -to_target.z) - global_rotation.y
	var pitch := atan2(to_target.y, Vector2(to_target.x, to_target.z).length())
	turret.rotation.y = lerp_angle(turret.rotation.y, yaw, clampf(6.0 * delta, 0.0, 1.0))
	guns.rotation.x = lerpf(guns.rotation.x, pitch, clampf(6.0 * delta, 0.0, 1.0))


# Lays the strip along the helicopter's predicted path while it's live:
# centred on where it will be halfway through, as long as the stretch it
# covers, turned along its heading there. Hovering, a box over it.
func mark_zone(heli: Helicopter) -> void:
	var middle := zone_warning + zone_active * 0.5
	var centre := predict(heli, middle)
	var heading := predict(heli, middle + 0.05) - predict(heli, middle - 0.05)
	heading.y = 0.0
	if heading.length() < 0.1:
		# Hovering: line the box up with the guns.
		heading = heli.global_position - global_position
		heading.y = 0.0

	zone = DangerZone.new()
	zone.size = zone_width
	zone.length = clampf(tracked_speed * zone_active + 10.0, zone_length_min, zone_length_max)
	zone.warning_time = zone_warning
	zone.active_time = zone_active
	zone.tick_interval = tick_interval
	zone.damage = tick_damage
	zone.source_name = "SHILKA"
	zone.color = zone_color
	MissionContext.spawn_parent(self).add_child(zone)
	zone.global_position = Vector3(centre.x, ride_height, centre.z)
	zone.rotation.y = atan2(-heading.x, -heading.z)
	shot_timer = 0.0


# Follows the helicopter's velocity and turn rate, with the radar's lag.
func track(heli: Helicopter, delta: float) -> void:
	var measured: Vector3 = heli.velocity
	var weight := 1.0 - exp(-tracking * delta)
	var flat_old := Vector2(last_velocity.x, last_velocity.z)
	var flat_new := Vector2(measured.x, measured.z)
	last_velocity = measured
	var turn := 0.0
	if flat_old.length() > 3.0 and flat_new.length() > 3.0 and delta > 0.0:
		# Heading change this frame (sign flipped: +Y turns are clockwise in x/z).
		turn = -flat_old.angle_to(flat_new) / delta
	tracked_turn = lerpf(tracked_turn, clampf(turn, -6.0, 6.0), weight)
	tracked_velocity = tracked_velocity.lerp(measured, weight)
	tracked_speed = lerpf(tracked_speed, measured.length(), weight)


# Where the helicopter will be in `time` seconds if it keeps its tracked
# speed and turn rate: along an arc, so a steady circle is led properly.
func predict(heli: Helicopter, time: float) -> Vector3:
	var at := heli.global_position
	# In a steady turn the smoothed heading trails the real one by about
	# turn / tracking: rotate it forward to make up for that, and use the
	# smoothed speed (blending headings shortens the vector).
	var velocity := Vector3.ZERO
	if tracked_velocity.length() > 0.5:
		velocity = tracked_velocity.rotated(Vector3.UP, tracked_turn / tracking).normalized() * tracked_speed
	var steps := 8
	var step := time / steps
	for i in steps:
		velocity = velocity.rotated(Vector3.UP, tracked_turn * step)
		at += velocity * step
	return at


func fire_at(target: Vector3) -> void:
	var muzzle: Node3D = muzzles[next_barrel]
	next_barrel = (next_barrel + 1) % muzzles.size()
	var from := muzzle.global_position
	var tracer := Tracer.new()
	# Fat, long bolts so the stream reads at the camera's distance.
	tracer.radius = 0.22
	tracer.length = 2.6
	tracer.color = Color(1.0, 0.6, 0.25)
	MissionContext.spawn_parent(self).add_child(tracer)
	tracer.setup(from, target, shell_flight_time, 0.0, shell_burst)
	muzzle_flash.global_position = from
	muzzle_flash.light_energy = 3.0
	if next_barrel % 2 == 0:
		Sfx.play_3d("car_gun", from, 1.0, 1.25)


# A shell bursts: a puff of flak smoke (the zone does the damage).
func shell_burst(at: Vector3) -> void:
	if not is_inside_tree():
		return
	var puff := P.sphere(MissionContext.spawn_parent(self), 0.6, at, flak_smoke())
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tween := puff.create_tween()
	tween.tween_property(puff, "scale", Vector3.ONE * 2.2, 0.45).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(puff.material_override, "albedo_color:a", 0.0, 0.45)
	tween.tween_callback(puff.queue_free)


func flak_smoke() -> StandardMaterial3D:
	var mat := P.material(Color(0.3, 0.28, 0.26, 0.75), 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func build_model() -> void:
	var paint := P.material(Color(0.36, 0.38, 0.27), 0.8)
	var dark := P.material(Color(0.14, 0.14, 0.15), 0.6, 0.4)
	var tread := P.material(Color(0.08, 0.08, 0.08), 1.0)

	# Low hull on two tracks with road wheels.
	P.box(self, Vector3(3.0, 0.9, 5.4), Vector3(0, 0.75, 0), paint)
	P.box(self, Vector3(2.6, 0.3, 1.2), Vector3(0, 1.2, -2.3), paint, Vector3(-20, 0, 0))
	for x in [-1.55, 1.55]:
		P.box(self, Vector3(0.6, 0.8, 5.8), Vector3(x, 0.45, 0), tread)
		for k in 6:
			P.cylinder(self, 0.32, 0.62, Vector3(x, 0.35, -2.2 + k * 0.88), dark, Vector3(0, 0, 90), 10)

	# Turret: wide box, four barrels on a pitching mount, radar dish behind.
	turret = Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.2, 0.3)
	add_child(turret)
	P.box(turret, Vector3(2.4, 0.9, 2.6), Vector3(0, 0.45, 0), paint)

	guns = Node3D.new()
	guns.position = Vector3(0, 0.7, -1.2)
	turret.add_child(guns)
	for x in [-0.55, 0.55]:
		for y in [0.0, 0.32]:
			P.cylinder(guns, 0.06, 2.2, Vector3(x, y, -1.1), dark, Vector3(90, 0, 0), 6)
			var muzzle := Node3D.new()
			muzzle.position = Vector3(x, y, -2.2)
			guns.add_child(muzzle)
			muzzles.append(muzzle)

	muzzle_flash = OmniLight3D.new()
	muzzle_flash.light_color = Color(1.0, 0.7, 0.35)
	muzzle_flash.omni_range = 7.0
	muzzle_flash.light_energy = 0.0
	add_child(muzzle_flash)

	# Radar on a short mast at the back of the turret.
	P.cylinder(turret, 0.1, 0.8, Vector3(0, 1.3, 1.0), dark)
	radar = Node3D.new()
	radar.position = Vector3(0, 1.75, 1.0)
	turret.add_child(radar)
	P.box(radar, Vector3(1.6, 0.6, 0.12), Vector3(0, 0, 0), dark, Vector3(-15, 0, 0))

	var bar := HEALTH_BAR.instantiate()
	bar.name = "HealthBar3D"
	bar.position = Vector3(0, 4.6, 0)
	add_child(bar)
