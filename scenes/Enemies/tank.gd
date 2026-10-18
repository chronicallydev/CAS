extends "res://scenes/Enemies/enemy_base.gd"

# Tank: rolls in to a firing position, stops, turns its turret toward the
# base and shells it at a fixed interval.

const TankShell := preload("res://scenes/Enemies/tank_shell.gd")

@export var speed: float = 3.5
# The tank stops somewhere in this distance range from the base.
@export var firing_range_min: float = 24.0
@export var firing_range_max: float = 34.0
@export var fire_interval: float = 3.5
@export var shell_damage: float = 5.0
@export var shell_flight_time: float = 1.2
@export var turret_turn_speed: float = 2.0
@export var shell_explosion: PackedScene
@export var ride_height: float = -0.4

@onready var turret: Node3D = $Turret
@onready var muzzle: Marker3D = $Turret/Muzzle

var firing_range: float = 0.0
var in_position: bool = false
var fire_timer: float = 0.0


func _ready() -> void:
	super()
	firing_range = randf_range(firing_range_min, firing_range_max)
	# Short delay between stopping and the first shot.
	fire_timer = fire_interval * 0.5


func _physics_process(delta: float) -> void:
	global_position.y = ride_height
	var flat_distance := Vector2(global_position.x, global_position.z).length()

	if not in_position:
		var direction := flat_direction_to_center()
		global_position += direction * speed * delta
		face_direction(direction)

		if flat_distance <= firing_range:
			in_position = true
		return

	var base := get_tree().get_first_node_in_group("Base") as Node3D

	if base == null:
		return

	# Rotate the turret toward the base around the vertical axis.
	var to_base := base.global_position - turret.global_position
	var desired_yaw := atan2(-to_base.x, -to_base.z) - global_rotation.y
	turret.rotation.y = lerp_angle(turret.rotation.y, desired_yaw, clampf(turret_turn_speed * delta, 0.0, 1.0))

	fire_timer -= delta

	if fire_timer <= 0.0 and absf(angle_difference(turret.rotation.y, desired_yaw)) < 0.1:
		fire_timer = fire_interval
		fire_at(base)


func fire_at(base: Node3D) -> void:
	var target := base.global_position + Vector3(randf_range(-2.0, 2.0), 1.0, randf_range(-2.0, 2.0))

	var shell := TankShell.new()
	get_tree().current_scene.add_child(shell)
	shell.setup(muzzle.global_position, target, shell_flight_time, 4.0, shell_hit)

	spawn_explosion(muzzle.global_position, 0.25)


func shell_hit(position: Vector3) -> void:
	spawn_explosion(position, 0.6)

	var base := get_tree().get_first_node_in_group("Base")

	if base != null and base.has_method("take_damage"):
		base.take_damage(shell_damage)


func spawn_explosion(position: Vector3, vfx_scale: float) -> void:
	if shell_explosion == null or not is_inside_tree():
		return

	var explosion := shell_explosion.instantiate() as Node3D

	if explosion == null:
		return

	get_tree().current_scene.add_child(explosion)
	explosion.global_position = position
	explosion.scale = Vector3.ONE * vfx_scale
