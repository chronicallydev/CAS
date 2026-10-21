extends EnemyBase

# Twin-barrel flak gun (a ZU-23 style mount) dug in behind sandbags around
# an enemy rig during an assault. It leads the helicopter and walks streams
# of shells that burst in grey puffs, so hovering is deadly and moving
# saves you. Part of the assault objective. Built from primitives in code.

const P := preload("res://shared/props/prop_builder.gd")
const Tracer := preload("res://features/mission/enemies/projectiles/tank_shell.gd")
const HEALTH_BAR := preload("res://shared/health_bar/health_bar_3d.tscn")

@export var engage_range: float = 42.0
# Damage per shell that bursts close to the helicopter.
@export var shot_damage: float = 1.1
@export var burst_size: int = 12
@export var burst_shot_interval: float = 0.07
@export var burst_cooldown: float = 2.2
@export var shell_flight_time: float = 0.55
@export var ground_y: float = -0.4

var mount: Node3D
var cradle: Node3D
var muzzles: Array = []
var burst_timer: float = 0.0
var shots_left: int = 0
var shot_timer: float = 0.0
var next_barrel: int = 0
# For leading the target: where the helicopter was last frame.
var last_heli_position: Vector3 = Vector3.ZERO
var heli_velocity: Vector3 = Vector3.ZERO


func _init() -> void:
	max_health = 32.0
	light_armor = 0.5
	score_value = 200
	display_name = "FLAK"
	leaves_wreck = true
	contact_damage = 0.0


func _ready() -> void:
	build_model()
	super()
	add_to_group("forts")
	burst_timer = randf_range(1.5, burst_cooldown + 1.0)


func _physics_process(delta: float) -> void:
	global_position.y = ground_y
	var heli := objective()
	if heli == null:
		shots_left = 0
		return

	if last_heli_position != Vector3.ZERO and delta > 0.0:
		heli_velocity = heli_velocity.lerp((heli.global_position - last_heli_position) / delta, 0.2)
	last_heli_position = heli.global_position

	# Aim where the helicopter will be when the shells arrive.
	var lead := heli.global_position + heli_velocity * shell_flight_time
	var to_target := lead - cradle.global_position
	var yaw := atan2(-to_target.x, -to_target.z) - global_rotation.y
	var pitch := atan2(to_target.y, Vector2(to_target.x, to_target.z).length())
	mount.rotation.y = lerp_angle(mount.rotation.y, yaw, clampf(3.0 * delta, 0.0, 1.0))
	cradle.rotation.x = lerpf(cradle.rotation.x, pitch, clampf(3.0 * delta, 0.0, 1.0))

	if objective_distance() > engage_range:
		shots_left = 0
		return

	if shots_left > 0:
		shot_timer -= delta
		if shot_timer <= 0.0:
			shots_left -= 1
			shot_timer = burst_shot_interval
			fire_at(lead)
		return

	burst_timer -= delta
	if burst_timer <= 0.0:
		burst_timer = burst_cooldown * randf_range(0.85, 1.25)
		shots_left = burst_size


func fire_at(lead: Vector3) -> void:
	var muzzle: Node3D = muzzles[next_barrel]
	next_barrel = (next_barrel + 1) % muzzles.size()
	var from := muzzle.global_position
	var target := lead + Vector3(randf_range(-3.0, 3.0), randf_range(-1.5, 1.5), randf_range(-3.0, 3.0))
	var tracer := Tracer.new()
	tracer.radius = 0.16
	tracer.color = Color(1.0, 0.45, 0.2)
	MissionContext.spawn_parent(self).add_child(tracer)
	tracer.setup(from, target, shell_flight_time, 0.0, shell_burst)
	Sfx.play_3d("car_gun", from)


# A shell bursts: grey puff, and damage if the helicopter is close.
func shell_burst(at: Vector3) -> void:
	if is_inside_tree():
		var puff := P.sphere(MissionContext.spawn_parent(self), 0.6, at, flak_smoke())
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tween := puff.create_tween()
		tween.tween_property(puff, "scale", Vector3.ONE * 2.6, 0.5).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(puff.material_override, "albedo_color:a", 0.0, 0.5)
		tween.tween_callback(puff.queue_free)
	hit_objective(at, shot_damage, 3.5)


func flak_smoke() -> StandardMaterial3D:
	var mat := P.material(Color(0.25, 0.24, 0.23, 0.8), 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func build_model() -> void:
	var sandbag := P.material(Color(0.6, 0.52, 0.37), 1.0)
	var olive := P.material(Color(0.3, 0.33, 0.22), 0.8)
	var steel := P.material(Color(0.14, 0.14, 0.15), 0.5, 0.5)
	var tyre := P.material(Color(0.08, 0.08, 0.08), 1.0)

	# Horseshoe of sandbags, open at the back.
	for course in 2:
		var count := 14
		for i in count:
			var angle := PI * 0.25 + PI * 1.5 * (i + course * 0.5) / count
			var bag := P.box(self, Vector3(1.2, 0.5, 0.7), Vector3(cos(angle) * 3.2, 0.25 + course * 0.48, sin(angle) * 3.2), sandbag)
			bag.rotation.y = -angle + PI / 2.0

	# Carriage on two wheels.
	P.box(self, Vector3(1.6, 0.35, 2.4), Vector3(0, 0.55, 0), olive)
	for x in [-1.0, 1.0]:
		P.cylinder(self, 0.45, 0.3, Vector3(x, 0.45, 0.2), tyre, Vector3(0, 0, 90))

	# Turning mount with the gunner's seat and a pitching twin-barrel cradle.
	mount = Node3D.new()
	mount.position = Vector3(0, 0.75, 0)
	add_child(mount)
	P.cylinder(mount, 0.7, 0.3, Vector3(0, 0.15, 0), olive)
	P.box(mount, Vector3(0.5, 0.5, 0.5), Vector3(0, 0.55, 0.6), olive)
	P.box(mount, Vector3(1.4, 0.7, 0.12), Vector3(0, 0.75, -0.2), olive)

	cradle = Node3D.new()
	cradle.position = Vector3(0, 0.95, 0)
	mount.add_child(cradle)
	P.box(cradle, Vector3(0.9, 0.4, 1.2), Vector3(0, 0, 0), olive)
	for x in [-0.25, 0.25]:
		var barrel := P.cylinder(cradle, 0.07, 3.0, Vector3(x, 0.05, -1.9), steel, Vector3(90, 0, 0), 8)
		barrel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var muzzle := Node3D.new()
		muzzle.position = Vector3(x, 0.05, -3.4)
		cradle.add_child(muzzle)
		muzzles.append(muzzle)

	var bar := HEALTH_BAR.instantiate()
	bar.name = "HealthBar3D"
	bar.position = Vector3(0, 4.4, 0)
	add_child(bar)
