extends EnemyBase

# Mortar team: two soldiers with a tube on a baseplate. They walk in, set
# up at range and lob salvos: the first round at wherever the helicopter is
# when it leaves the tube, the rest a little ahead of it (see lead). Every
# round marks its landing spot with a red square (danger_zone.gd) a moment
# before it hits, so hovering or drifting slowly gets punished and real
# flying saves you. Too close and the tube
# can't elevate far enough, so flying right over them is safe. Their
# rounds hurt anything in the square, other enemies included.
# Built from primitives in code.

const P := preload("res://shared/props/prop_builder.gd")
const DangerZone := preload("res://features/mission/hazards/danger_zone.gd")
const Shell := preload("res://features/mission/enemies/projectiles/mortar_shell.gd")

@export var speed: float = 4.0
@export var ground_y: float = -0.4
# They set up somewhere in this distance range from the helicopter, and
# pack up and follow once it's further than engage_range.
@export var firing_range_min: float = 32.0
@export var firing_range_max: float = 48.0
@export var engage_range: float = 85.0
# No shots at a helicopter closer than this.
@export var min_range: float = 10.0
@export var setup_time: float = 1.2

@export_group("Salvo")
@export var shots_per_salvo: int = 3
@export var shot_interval: float = 0.7
@export var reload_time: float = 4.5
# Rounds land within this many metres of the aim point.
@export var scatter: float = 1.2
# After the first round of a salvo, aim this fraction of the way to where
# the helicopter will be at impact. Small, so drifting gets punished but
# real flying still clears the square.
@export_range(0.0, 1.0, 0.05) var lead: float = 0.5
@export var zone_size: float = 10.0
@export var warning_time: float = 1.5
@export var shell_damage: float = 15.0
@export var shell_explosion: PackedScene

var firing_range: float = 0.0
var in_position: bool = false
var setup_left: float = 0.0
var reload_left: float = 0.0
var shot_left: float = 0.0
var shots_left: int = 0

var tube_pivot: Node3D
var tube: Node3D
var muzzle: Node3D
var loader_arm: Node3D


func _ready() -> void:
	super()
	build_model()
	firing_range = randf_range(firing_range_min, firing_range_max)
	reload_left = randf_range(0.5, 1.5)


func _physics_process(delta: float) -> void:
	global_position.y = ground_y
	if in_position and objective_distance() > engage_range:
		in_position = false

	if not in_position:
		var direction := flat_direction_to_center()
		global_position += direction * speed * delta
		face_direction(direction)
		if objective() != null and objective_distance() <= firing_range:
			in_position = true
			setup_left = setup_time
		return

	var heli := helicopter()
	if heli == null:
		return

	# Swing the tube round toward the helicopter.
	var to_heli := heli.global_position - global_position
	var desired_yaw := atan2(-to_heli.x, -to_heli.z) - global_rotation.y
	tube_pivot.rotation.y = lerp_angle(tube_pivot.rotation.y, desired_yaw, clampf(3.0 * delta, 0.0, 1.0))

	if setup_left > 0.0:
		setup_left -= delta
		return

	if shots_left <= 0:
		reload_left -= delta
		if reload_left <= 0.0 and objective_distance() >= min_range:
			shots_left = shots_per_salvo
			shot_left = 0.0
		return

	shot_left -= delta
	if shot_left <= 0.0:
		if objective_distance() >= min_range:
			# The first round marks where you are; the rest lead you.
			fire_at(heli, 0.0 if shots_left == shots_per_salvo else lead)
		shots_left -= 1
		shot_left = shot_interval
		if shots_left <= 0:
			reload_left = reload_time


# `lead_fraction` of the way to where the helicopter will be when the
# round lands, if it holds its course.
func fire_at(heli: Node3D, lead_fraction: float = 0.0) -> void:
	var ahead: Vector3 = heli.velocity * warning_time * lead_fraction
	var offset := Vector2.from_angle(randf() * TAU) * randf() * scatter
	var aim := Vector3(heli.global_position.x + ahead.x + offset.x, ground_y, heli.global_position.z + ahead.z + offset.y)

	var zone := DangerZone.new()
	zone.size = zone_size
	zone.warning_time = warning_time
	zone.damage = shell_damage
	zone.source_name = "MORTAR"
	zone.explosion_scene = shell_explosion
	var parent := MissionContext.spawn_parent(self)
	parent.add_child(zone)
	zone.global_position = aim

	var shell := Shell.new()
	shell.zone = zone
	parent.add_child(shell)
	shell.global_position = muzzle.global_position

	# The whistle falls in pitch and ends as the round lands.
	Sfx.play_3d("bomb_whistle", aim, 0.0, 1.7 / warning_time, 0.02)
	Sfx.play_3d("mortar_thump", muzzle.global_position)
	spawn_muzzle_puff()
	if mission != null:
		mission.shake(0.06, global_position)

	# The tube jolts down and the loader drops in the next round.
	var kick := create_tween()
	kick.tween_property(tube, "position:y", -0.15, 0.05)
	kick.tween_property(tube, "position:y", 0.0, 0.3)
	var reload_swing := create_tween()
	reload_swing.tween_property(loader_arm, "rotation:x", 1.6, 0.15)
	reload_swing.tween_property(loader_arm, "rotation:x", 0.6, 0.4)


func spawn_muzzle_puff() -> void:
	var puff := CPUParticles3D.new()
	puff.amount = 14
	puff.lifetime = 1.4
	puff.one_shot = true
	puff.explosiveness = 0.95
	puff.local_coords = false
	puff.direction = Vector3.UP
	puff.spread = 30.0
	puff.initial_velocity_min = 2.0
	puff.initial_velocity_max = 5.0
	puff.damping_min = 3.0
	puff.damping_max = 4.0
	puff.gravity = Vector3(0, 0.6, 0)
	puff.scale_amount_min = 1.0
	puff.scale_amount_max = 1.8
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.85, 0.82, 0.76, 0.55)
	mesh.material = material
	puff.mesh = mesh
	var parent := MissionContext.spawn_parent(self)
	parent.add_child(puff)
	puff.global_position = muzzle.global_position
	puff.emitting = true
	get_tree().create_timer(puff.lifetime + 0.2).timeout.connect(puff.queue_free)


# The ready rounds cook off.
func die() -> void:
	if shell_explosion != null:
		var explosion := shell_explosion.instantiate() as Node3D
		MissionContext.spawn_parent(self).add_child(explosion)
		explosion.global_position = global_position
		explosion.scale = Vector3.ONE * 0.8
	queue_free()


func build_model() -> void:
	var uniform := P.material(Color(0.36, 0.39, 0.26), 0.9)
	var helmet := P.material(Color(0.28, 0.31, 0.2), 0.7)
	var skin := P.material(Color(0.76, 0.56, 0.42), 0.8)
	var metal := P.material(Color(0.2, 0.21, 0.2), 0.5, 0.6)
	var sandbag := P.material(Color(0.62, 0.55, 0.4), 1.0)
	var crate := P.material(Color(0.4, 0.33, 0.2), 0.9)

	# Scaled up like the infantry so it reads from the air.
	var model := Node3D.new()
	model.scale = Vector3.ONE * 1.8
	add_child(model)

	# Baseplate, a low ring of sandbags and an ammo crate.
	P.cylinder(model, 0.45, 0.08, Vector3(0, 0.04, 0), metal)
	for i in 7:
		var angle := PI * 0.15 + i * PI * 0.25
		var at := Vector3(cos(angle), 0.15, sin(angle)) * 1.25
		at.y = 0.15
		P.box(model, Vector3(0.55, 0.3, 0.3), at, sandbag, Vector3(0, -rad_to_deg(angle) + 90.0, 0))
	P.box(model, Vector3(0.5, 0.3, 0.35), Vector3(0.8, 0.15, 0.45), crate)

	# The tube, angled up steeply; it turns on the pivot.
	tube_pivot = Node3D.new()
	tube_pivot.position = Vector3(0, 0.1, 0)
	model.add_child(tube_pivot)
	tube = Node3D.new()
	tube.rotation_degrees.x = 60.0
	tube_pivot.add_child(tube)
	P.cylinder(tube, 0.09, 1.1, Vector3(0, 0, -0.55), metal, Vector3(90, 0, 0), 10)
	P.pipe(tube_pivot, Vector3(0, 0.0, -0.4), Vector3(0.18, 0.0, -0.35), 0.025, metal)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0, -1.15)
	tube.add_child(muzzle)

	# Crew: a gunner kneeling by the tube, a loader with a round ready.
	add_crewman(model, Vector3(-0.55, 0, 0.25), uniform, helmet, skin)
	var loader := add_crewman(model, Vector3(0.5, 0, -0.35), uniform, helmet, skin)
	loader_arm = Node3D.new()
	loader_arm.position = Vector3(0.0, 0.85, 0.0)
	loader_arm.rotation.x = 0.6
	loader.add_child(loader_arm)
	P.box(loader_arm, Vector3(0.11, 0.5, 0.12), Vector3(0, -0.25, 0), uniform)


# A kneeling soldier (about 1.1 m tall before scaling).
func add_crewman(parent: Node3D, at: Vector3, uniform: Material, helmet: Material, skin: Material) -> Node3D:
	var man := Node3D.new()
	man.position = at
	parent.add_child(man)
	P.box(man, Vector3(0.42, 0.55, 0.26), Vector3(0, 0.62, 0), uniform)
	P.box(man, Vector3(0.36, 0.18, 0.5), Vector3(0, 0.12, -0.1), uniform)
	P.sphere(man, 0.12, Vector3(0, 1.02, 0), skin)
	P.sphere(man, 0.16, Vector3(0, 1.08, 0.01), helmet, Vector3(1.0, 0.65, 1.05))
	return man
