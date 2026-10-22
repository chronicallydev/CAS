extends EnemyBase

# Fast car: drives in to an orbit around the base, then circles it while
# slowly spiralling inward until it rams the base. Its roof gun fires
# bursts at the base while it circles, or at the helicopter if it comes
# within reach.

const Tracer := preload("res://features/mission/enemies/projectiles/tank_shell.gd")

@export var speed: float = 18.0
@export var orbit_radius_min: float = 22.0
@export var orbit_radius_max: float = 32.0
# How fast the orbit tightens, in units per second.
@export var spiral_speed: float = 0.8
# Height of the car's origin above the map origin (ground top is about -0.4).
@export var ride_height: float = -0.4
# Held in place (a convoy moves it along itself): no driving, but the
# roof gun still fires at the helicopter.
@export var dug_in: bool = false

@export_group("Gun")
# Damage per round that hits the base.
@export var shot_damage: float = 1.0
@export var burst_size: int = 5
@export var burst_shot_interval: float = 0.12
@export var burst_cooldown: float = 2.5
@export var shot_flight_time: float = 0.35
@export var hit_effect: PackedScene

@onready var gun: Node3D = get_node_or_null("Gun")
@onready var muzzle: Node3D = get_node_or_null("Gun/Muzzle")

var orbit_radius: float = 0.0
var orbiting: bool = false
var orbit_angle: float = 0.0
var orbit_sign: float = 1.0

var burst_timer: float = 0.0
var shots_left: int = 0
var shot_timer: float = 0.0


func _ready() -> void:
	super()
	orbit_radius = randf_range(orbit_radius_min, orbit_radius_max)
	orbit_sign = 1.0 if randf() < 0.5 else -1.0
	# Stagger the first burst so cars don't all fire together.
	burst_timer = randf_range(0.5, burst_cooldown)


func _physics_process(delta: float) -> void:
	global_position.y = ride_height
	if dug_in:
		if on_screen():
			update_gun(delta)
		return
	# Orbit centre: the helicopter's ground spot.
	var centre := objective_ground()

	if not orbiting:
		var direction := flat_direction_to_center()
		global_position += direction * speed * delta
		face_direction(direction)

		if objective_distance() <= orbit_radius:
			orbiting = true
			orbit_angle = atan2(global_position.z - centre.z, global_position.x - centre.x)
		return

	# The circle never closes in all the way.
	orbit_radius = maxf(orbit_radius - spiral_speed * delta, 12.0)
	orbit_angle += orbit_sign * speed / maxf(orbit_radius, 1.0) * delta

	var target := centre + Vector3(cos(orbit_angle) * orbit_radius, 0.0, sin(orbit_angle) * orbit_radius)
	target.y = ride_height
	var move := target - global_position
	# A moving centre could jump the car; drive there at most a bit over speed.
	if move.length() > speed * 1.4 * delta:
		move = move.normalized() * speed * 1.4 * delta
	global_position += move
	face_direction(Vector3(move.x, 0.0, move.z))

	update_gun(delta)


func update_gun(delta: float) -> void:
	var base := objective()
	if base == null:
		return

	# Keep the roof gun pointed at the target.
	if gun != null:
		var to_base := base.global_position - gun.global_position
		gun.rotation.y = atan2(-to_base.x, -to_base.z) - global_rotation.y

	if shots_left > 0:
		shot_timer -= delta
		if shot_timer <= 0.0:
			shots_left -= 1
			shot_timer = burst_shot_interval
			fire_at(base)
		return

	burst_timer -= delta

	if burst_timer <= 0.0:
		burst_timer = burst_cooldown
		shots_left = maxi(burst_size, 1)
		shot_timer = 0.0


func fire_at(base: Node3D) -> void:
	var from := muzzle.global_position if muzzle != null else global_position + Vector3.UP * 2.0
	var target := base.global_position + Vector3(randf_range(-2.5, 2.5), randf_range(0.0, 2.0), randf_range(-2.5, 2.5))

	var tracer := Tracer.new()
	tracer.radius = 0.3
	MissionContext.spawn_parent(self).add_child(tracer)
	tracer.setup(from, target, shot_flight_time, 0.3, shot_hit.bind(base))
	Sfx.play_3d("car_gun", from)


func shot_hit(position: Vector3, target: Node3D = null) -> void:
	if hit_effect != null and is_inside_tree():
		var effect := hit_effect.instantiate() as Node3D
		if effect != null:
			MissionContext.spawn_parent(self).add_child(effect)
			effect.global_position = position
			effect.scale = Vector3.ONE * 0.15

	hit_objective(position, shot_damage, 3.0, target)
