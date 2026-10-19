extends "res://scenes/Enemies/enemy_base.gd"

# Concrete pillbox guarding an enemy rig during an assault. It never moves;
# a machine gun in the firing slit sprays bursts at the helicopter while
# it's in range. Every fort has to go before the rig can be captured.
# Built from primitives in code.

const P := preload("res://scenes/environment/prop_builder.gd")
const Tracer := preload("res://scenes/Enemies/tank_shell.gd")
const HEALTH_BAR := preload("res://scenes/healthbar3D/health_bar_3d.tscn")

@export var engage_range: float = 32.0
# Damage per round that hits the helicopter.
@export var shot_damage: float = 0.7
@export var burst_size: int = 8
@export var burst_shot_interval: float = 0.09
@export var burst_cooldown: float = 2.6
@export var ground_y: float = -0.4

var gun: Node3D
var muzzle: Node3D
var burst_timer: float = 0.0
var shots_left: int = 0
var shot_timer: float = 0.0


func _init() -> void:
	max_health = 45.0
	light_armor = 0.85
	score_value = 150
	display_name = "BUNKER"
	leaves_wreck = true
	contact_damage = 0.0


func _ready() -> void:
	build_model()
	super()
	add_to_group("forts")
	burst_timer = randf_range(1.0, burst_cooldown)


func _physics_process(delta: float) -> void:
	global_position.y = ground_y
	var heli := objective()
	if heli == null or objective_distance() > engage_range:
		shots_left = 0
		return

	# Swing the gun round inside the slit.
	var to_heli := heli.global_position - gun.global_position
	gun.rotation.y = lerp_angle(gun.rotation.y, atan2(-to_heli.x, -to_heli.z) - global_rotation.y, clampf(4.0 * delta, 0.0, 1.0))

	if shots_left > 0:
		shot_timer -= delta
		if shot_timer <= 0.0:
			shots_left -= 1
			shot_timer = burst_shot_interval
			fire_at(heli)
		return

	burst_timer -= delta
	if burst_timer <= 0.0:
		burst_timer = burst_cooldown * randf_range(0.85, 1.2)
		shots_left = burst_size


func fire_at(heli: Node3D) -> void:
	var from := muzzle.global_position
	var target := heli.global_position + Vector3(randf_range(-2.5, 2.5), randf_range(-1.0, 1.0), randf_range(-2.5, 2.5))
	var tracer := Tracer.new()
	tracer.radius = 0.18
	tracer.color = Color(1.0, 0.65, 0.25)
	get_tree().current_scene.add_child(tracer)
	tracer.setup(from, target, 0.35, 0.0, shot_hit)
	Sfx.play_3d("car_gun", from)


func shot_hit(at: Vector3) -> void:
	hit_objective(at, shot_damage, 3.0)


func build_model() -> void:
	var concrete := P.material(Color(0.6, 0.58, 0.53), 0.95)
	var dark := P.material(Color(0.06, 0.06, 0.06), 1.0)
	var sandbag := P.material(Color(0.62, 0.53, 0.38), 1.0)
	var steel := P.material(Color(0.16, 0.16, 0.17), 0.5, 0.5)
	var red := P.material(Color(0.75, 0.12, 0.1), 0.8)

	# Ring of sandbags, two courses high.
	for course in 2:
		var count := 18
		for i in count:
			var angle := TAU * (i + course * 0.5) / count
			var bag := P.box(self, Vector3(1.35, 0.5, 0.75), Vector3(cos(angle) * 3.9, 0.25 + course * 0.48, sin(angle) * 3.9), sandbag)
			bag.rotation.y = -angle + PI / 2.0

	# Six-sided pillbox with a dark firing slit all the way round.
	P.cylinder(self, 2.5, 1.0, Vector3(0, 0.5, 0), concrete, Vector3.ZERO, 6)
	P.cylinder(self, 2.42, 0.45, Vector3(0, 1.22, 0), dark, Vector3.ZERO, 6)
	P.cylinder(self, 2.75, 0.55, Vector3(0, 1.72, 0), concrete, Vector3.ZERO, 6)
	P.cylinder(self, 2.0, 0.3, Vector3(0, 2.12, 0), concrete, Vector3.ZERO, 6)

	# Machine gun poking out of the slit.
	gun = Node3D.new()
	gun.position = Vector3(0, 1.22, 0)
	add_child(gun)
	P.box(gun, Vector3(0.22, 0.22, 3.3), Vector3(0, 0, -1.4), steel)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0, -3.1)
	gun.add_child(muzzle)

	# Enemy flag on the roof.
	P.cylinder(self, 0.06, 2.6, Vector3(1.2, 3.4, 0.6), steel)
	P.box(self, Vector3(0.05, 0.7, 1.1), Vector3(1.2, 4.3, 1.15), red)

	var bar := HEALTH_BAR.instantiate()
	bar.name = "HealthBar3D"
	bar.position = Vector3(0, 5.2, 0)
	add_child(bar)
