extends EnemyBase

# Shilka (ZSU-23-4): a tracked, radar-guided flak tank. It drives in like a
# SAM truck, stops at range and spins up its radar. Once the radar has a
# lock it hoses a long, leading stream from four barrels: hovering is death,
# and only sharp turns throw the stream off. Heavy armour shrugs off the
# minigun. Answer: Javelin, rockets, the FAB or a well-timed flare (which
# breaks the radar lock mid-burst). Built from primitives in code.

const P := preload("res://shared/props/prop_builder.gd")
const Tracer := preload("res://features/mission/enemies/projectiles/tank_shell.gd")
const HEALTH_BAR := preload("res://shared/health_bar/health_bar_3d.tscn")

@export var speed: float = 7.0
@export var ride_height: float = -0.4
# The Shilka stops somewhere in this distance range from its objective.
@export var firing_range_min: float = 26.0
@export var firing_range_max: float = 38.0

@export_group("Guns")
# Max horizontal distance to the helicopter for the radar to lock.
@export var engage_range: float = 58.0
@export var lock_time: float = 1.0
# Damage per shell that bursts close to the helicopter.
@export var shot_damage: float = 0.8
@export var burst_size: int = 28
@export var burst_shot_interval: float = 0.05
@export var burst_cooldown: float = 2.2
@export var shell_flight_time: float = 0.5
# Random scatter around the aim point, in metres.
@export var spread: float = 2.5

var firing_range: float = 0.0
var in_position: bool = false
var turret: Node3D
var guns: Node3D
var radar: Node3D
var muzzles: Array = []
var next_barrel: int = 0
var shots_left: int = 0
var shot_timer: float = 0.0
var cooldown: float = 0.0
# For leading the target: the helicopter's smoothed velocity.
var last_heli_position: Vector3 = Vector3.ZERO
var heli_velocity: Vector3 = Vector3.ZERO


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

	# Drive in, then hold position (follow the helicopter if it gets away).
	if in_position and is_assault() and objective_distance() > engage_range * 0.8:
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
		shots_left = 0
		return

	if last_heli_position != Vector3.ZERO and delta > 0.0:
		heli_velocity = heli_velocity.lerp((heli.global_position - last_heli_position) / delta, 0.2)
	last_heli_position = heli.global_position

	# Aim the turret and guns where the helicopter will be when shells arrive.
	var lead := heli.global_position + heli_velocity * shell_flight_time
	var to_target := lead - guns.global_position
	var yaw := atan2(-to_target.x, -to_target.z) - global_rotation.y
	var pitch := atan2(to_target.y, Vector2(to_target.x, to_target.z).length())
	turret.rotation.y = lerp_angle(turret.rotation.y, yaw, clampf(4.0 * delta, 0.0, 1.0))
	guns.rotation.x = lerpf(guns.rotation.x, pitch, clampf(4.0 * delta, 0.0, 1.0))

	if not in_position or distance_to_heli(heli) > engage_range:
		lock_timer = 0.0
		shots_left = 0
		return

	if shots_left > 0:
		# Flares jam the radar and cut the burst short.
		if not heli.can_be_locked():
			shots_left = 0
			return
		heli.warn_lock()
		shot_timer -= delta
		while shot_timer <= 0.0 and shots_left > 0:
			shots_left -= 1
			shot_timer += burst_shot_interval
			fire_at(lead)
		if shots_left == 0:
			cooldown = burst_cooldown * randf_range(0.85, 1.2)
		return

	cooldown -= delta
	if cooldown > 0.0:
		lock_timer = 0.0
		return

	if update_lock(heli, delta, lock_time):
		shots_left = burst_size
		shot_timer = 0.0


func fire_at(lead: Vector3) -> void:
	var muzzle: Node3D = muzzles[next_barrel]
	next_barrel = (next_barrel + 1) % muzzles.size()
	var from := muzzle.global_position
	var target := lead + Vector3(randf_range(-spread, spread), randf_range(-spread, spread) * 0.5, randf_range(-spread, spread))
	var tracer := Tracer.new()
	tracer.radius = 0.13
	tracer.color = Color(1.0, 0.55, 0.25)
	MissionContext.spawn_parent(self).add_child(tracer)
	tracer.setup(from, target, shell_flight_time, 0.0, shell_burst)
	if next_barrel % 2 == 0:
		Sfx.play_3d("car_gun", from, 1.0, 1.25)


# A shell bursts: small puff, and damage if the helicopter is close.
func shell_burst(at: Vector3) -> void:
	if is_inside_tree():
		var puff := P.sphere(MissionContext.spawn_parent(self), 0.4, at, flak_smoke())
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tween := puff.create_tween()
		tween.tween_property(puff, "scale", Vector3.ONE * 2.0, 0.4).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(puff.material_override, "albedo_color:a", 0.0, 0.4)
		tween.tween_callback(puff.queue_free)
	var heli := helicopter()
	if heli != null and heli.global_position.distance_to(at) <= 3.2:
		heli.take_damage(shot_damage, "SHILKA")


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
