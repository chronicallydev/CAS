extends EnemyBase

# Launcher of a SAM site: a turntable with two big missile tubes. While its
# site's radar (sam_radar.gd) is alive it locks on from long range, often
# from off-screen, and fires a two-missile salvo of heavy SAMs. Once the
# radar is gone it goes dark and can't lock any more, but it still has to be
# destroyed to take the rig. Answer: kill the radar first, or flare the
# salvo. Built from primitives in code.

const P := preload("res://shared/props/prop_builder.gd")
const HEALTH_BAR := preload("res://shared/health_bar/health_bar_3d.tscn")
const Missile := preload("res://features/mission/enemies/projectiles/aa_missile.gd")

@export var ground_y: float = -0.4

@export_group("Missiles")
# Max horizontal distance to the helicopter for a lock; beyond the view.
@export var engage_range: float = 110.0
@export var lock_time: float = 2.0
@export var reload_time: float = 9.0
@export var salvo_size: int = 2
@export var salvo_interval: float = 0.45
@export var missile_damage: float = 18.0
@export var missile_speed: float = 30.0
@export var missile_turn_rate: float = 1.15
@export var missile_lifetime: float = 8.0
@export var missile_explosion: PackedScene = preload("res://features/mission/vfx/explosion_scene.tscn")

# The site's radar, set by the enemy generator.
var radar: Node3D
var launcher: Node3D
var rails: Node3D
var muzzles: Array = []
var lamp: MeshInstance3D
var reload_timer: float = 0.0
var salvo_left: int = 0
var salvo_timer: float = 0.0
var dark: bool = false


func _init() -> void:
	max_health = 28.0
	light_armor = 0.6
	score_value = 150
	display_name = "LAUNCHER"
	leaves_wreck = true
	detach_parts = PackedStringArray(["Launcher"])
	contact_damage = 0.0


func _ready() -> void:
	build_model()
	super()
	add_to_group("forts")
	reload_timer = randf_range(2.0, 5.0)


func radar_active() -> bool:
	return radar != null and is_instance_valid(radar) and radar.is_active()


func _physics_process(delta: float) -> void:
	global_position.y = ground_y

	if not radar_active():
		lock_timer = 0.0
		salvo_left = 0
		if not dark:
			go_dark()
		return

	var heli := helicopter()
	if heli == null:
		lock_timer = 0.0
		return

	# Swing the turntable toward the helicopter.
	var to_heli := heli.global_position - launcher.global_position
	var yaw := atan2(-to_heli.x, -to_heli.z) - global_rotation.y
	launcher.rotation.y = lerp_angle(launcher.rotation.y, yaw, clampf(1.5 * delta, 0.0, 1.0))

	if salvo_left > 0:
		salvo_timer -= delta
		if salvo_timer <= 0.0:
			fire_at(heli, salvo_size - salvo_left)
			salvo_left -= 1
			salvo_timer = salvo_interval
		return

	reload_timer -= delta
	if reload_timer > 0.0 or distance_to_heli(heli) > engage_range:
		lock_timer = 0.0
		return

	if update_lock(heli, delta, lock_time, true):
		salvo_left = salvo_size
		salvo_timer = 0.0
		reload_timer = reload_time


func fire_at(heli: Node3D, index: int) -> void:
	var muzzle: Node3D = muzzles[index % muzzles.size()]
	var missile := Missile.new()
	missile.target = heli
	missile.speed = missile_speed
	missile.turn_rate = missile_turn_rate
	missile.lifetime = missile_lifetime
	missile.damage = missile_damage
	missile.source_name = "SAM SITE"
	missile.explosion_scene = missile_explosion
	missile.ground_y = ground_y
	missile.size = 1.3
	missile.boost_time = 0.6
	MissionContext.spawn_parent(self).add_child(missile)
	missile.launch(muzzle.global_position, -muzzle.global_transform.basis.z)
	Sfx.play_3d("missile_launch", muzzle.global_position, 3.0, 0.8)


# The radar is gone: tubes droop, the lamp goes out.
func go_dark() -> void:
	dark = true
	lamp.visible = false
	var tween := create_tween()
	tween.tween_property(rails, "rotation_degrees:x", 5.0, 1.2).set_ease(Tween.EASE_OUT)


func build_model() -> void:
	var concrete := P.material(Color(0.62, 0.6, 0.55), 1.0)
	var paint := P.material(Color(0.4, 0.42, 0.3), 0.8)
	var steel := P.material(Color(0.15, 0.15, 0.16), 0.5, 0.5)
	var white := P.material(Color(0.88, 0.88, 0.84), 0.6)
	var red := P.material(Color(0.8, 0.15, 0.1), 0.6)

	P.box(self, Vector3(5.5, 0.3, 5.5), Vector3(0, 0.15, 0), concrete)

	launcher = Node3D.new()
	launcher.name = "Launcher"
	launcher.position = Vector3(0, 0.3, 0)
	add_child(launcher)
	P.cylinder(launcher, 1.4, 0.6, Vector3(0, 0.3, 0), paint)
	P.box(launcher, Vector3(1.0, 1.4, 1.0), Vector3(0, 1.2, 0.4), paint)

	# Two big tubes, raised toward the sky.
	rails = Node3D.new()
	rails.position = Vector3(0, 1.9, 0.4)
	rails.rotation_degrees.x = 35.0
	launcher.add_child(rails)
	for x in [-0.6, 0.6]:
		P.cylinder(rails, 0.38, 4.4, Vector3(x, 0, -0.8), white, Vector3(90, 0, 0), 12)
		P.cylinder(rails, 0.4, 0.2, Vector3(x, 0, -3.0), red, Vector3(90, 0, 0), 12)
		var muzzle := Node3D.new()
		muzzle.position = Vector3(x, 0, -3.2)
		rails.add_child(muzzle)
		muzzles.append(muzzle)
	P.box(rails, Vector3(0.3, 0.3, 3.6), Vector3(0, -0.45, -0.6), steel)

	lamp = P.sphere(launcher, 0.18, Vector3(0, 2.05, 0.95), P.glow_material(Color(1.0, 0.15, 0.1), 4.0))

	var bar := HEALTH_BAR.instantiate()
	bar.name = "HealthBar3D"
	bar.position = Vector3(0, 5.6, 0)
	add_child(bar)
