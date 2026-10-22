class_name TestRangeContext
extends Node

## The test range: the game's main scene, a sandbox for working on flight
## and shooting.
##
## It runs a real mission (mission.tscn), so units behave exactly as they
## would anywhere else, but enemies are spawned by hand. The side panel
## (TestRangePanel) picks what to spawn and toggles cheats. Middle-click or
## G drops the chosen unit at the cursor. Losing the helicopter resets the
## range. Esc quits.

@export var mission_scene: PackedScene
@export var panel: TestRangePanel

@export_group("Units")
@export var infantry_scene: PackedScene
@export var car_scene: PackedScene
@export var tank_scene: PackedScene
@export var aa_scene: PackedScene
@export var heavy_aa_scene: PackedScene = preload("res://features/mission/enemies/heavy_launcher.tscn")
@export var mortar_scene: PackedScene = preload("res://features/mission/enemies/mortar_team.tscn")
@export var shilka_scene: PackedScene = preload("res://features/mission/enemies/shilka.tscn")
@export var scout_scene: PackedScene = preload("res://features/mission/enemies/enemy_scout.tscn")
@export var gunship_scene: PackedScene = preload("res://features/mission/enemies/enemy_gunship.tscn")
## Height enemies are dropped at; each settles to its own ride height.
@export var spawn_height: float = 5.69

## How many seconds of damage the DPS readout averages over.
const DPS_WINDOW := 5.0

const Missile := preload("res://features/mission/enemies/projectiles/aa_missile.gd")
const MISSILE_EXPLOSION := preload("res://features/mission/vfx/explosion_scene.tscn")

## Missile salvos (H or the panel), for practising chain dodges: this many
## SAM missiles, launched this many seconds apart from around the
## helicopter, spread over salvo_arc degrees.
var salvo_count: int = 3
var salvo_stagger: float = 0.3
var salvo_arc: float = 180.0
var salvo_distance: float = 50.0

var mission: MissionContext

## Cheats, kept across rebuilds.
var god_mode: bool = true
var infinite_ammo: bool = false

## Movement values tuned from the panel (helicopter property -> value),
## kept across rebuilds, and what they were before any tuning.
var movement_overrides: Dictionary = {}
var movement_defaults: Dictionary = {}

## Stats since the last reset.
var damage_taken_total: float = 0.0
var damage_by_source: Dictionary = {}  # source name -> damage
var damage_dealt_total: float = 0.0
var best_chain: int = 0
var _dealt_log: Array = []  # [time, amount], for DPS
var _time: float = 0.0


func _ready() -> void:
	panel.initialize(self)
	rebuild()
	Music.play("test_range")


func _process(delta: float) -> void:
	_time += delta
	while not _dealt_log.is_empty() and _time - _dealt_log[0][0] > DPS_WINDOW:
		_dealt_log.pop_front()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
		return
	var spawn_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE
	var spawn_key: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_G
	if spawn_click or spawn_key:
		var at: Variant = cursor_ground()
		if at != null:
			spawn(panel.selected_unit, panel.spawn_count, at)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
		fire_salvo()
		get_viewport().set_input_as_handled()


# --- The range ---------------------------------------------------------------

## Starts the range over. Spawned enemies are cleared.
func rebuild() -> void:
	if mission != null:
		remove_child(mission)
		mission.queue_free()
	get_tree().paused = false
	Engine.time_scale = 1.0

	mission = mission_scene.instantiate()
	add_child(mission)

	mission.request_retry.connect(rebuild, CONNECT_DEFERRED)
	mission.helicopter.damage_taken.connect(_on_damage_taken)
	mission.guns.damage_dealt.connect(_on_damage_dealt)
	mission.helicopter.chain_dodge.perfect_dodge.connect(func(chain: int, _missiles: Array) -> void:
		best_chain = maxi(best_chain, chain))
	apply_cheats()
	apply_movement()
	panel.refresh()


func apply_cheats() -> void:
	if mission == null:
		return
	mission.helicopter.invulnerable = god_mode
	mission.helicopter.infinite_flares = infinite_ammo
	mission.guns.infinite_ammo = infinite_ammo


# --- Movement tuning ---------------------------------------------------------

## Puts the tuned movement values back on a freshly built helicopter.
func apply_movement() -> void:
	var heli := mission.helicopter
	for property in movement_overrides:
		heli.set(property, movement_overrides[property])
	heli.dash_charges_left = mini(heli.dash_charges_left, heli.dash_charges)


## Sets one movement value on the live helicopter, remembering the
## original the first time it changes.
func tune(property: String, value: float) -> void:
	var heli := mission.helicopter
	if not movement_defaults.has(property):
		movement_defaults[property] = heli.get(property)
	if heli.get(property) is int:
		value = roundi(value)
	movement_overrides[property] = value
	heli.set(property, value)
	heli.dash_charges_left = mini(heli.dash_charges_left, heli.dash_charges)


## Undoes all tuning.
func reset_movement() -> void:
	for property in movement_defaults:
		mission.helicopter.set(property, movement_defaults[property])
	movement_overrides.clear()
	movement_defaults.clear()


func clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("structures") + get_tree().get_nodes_in_group("cities"):
		enemy.queue_free()


# --- Spawning ----------------------------------------------------------------

## What the panel can spawn: [name, scene], or [name, callable] for
## things built in code (buildings, a city block).
func units() -> Array:
	return [
		["Scout heli", scout_scene],
		["Gunship heli", gunship_scene],
		["Infantry", infantry_scene],
		["Car", car_scene],
		["Tank", tank_scene],
		["SAM truck", aa_scene],
		["Heavy SAM", heavy_aa_scene],
		["Mortar team", mortar_scene],
		["Shilka (flak)", shilka_scene],
		["House", func() -> Node3D: return Building.make("house", Vector2(8.0, 8.0))],
		["Apartment block", func() -> Node3D: return Building.make("block", Vector2(14.0, 10.0))],
		["Target: HQ", func() -> Node3D: return Building.make("hq", Vector2(14.0, 12.0), true)],
		["Target: ammo dump", func() -> Node3D: return Building.make("ammo_dump", Vector2(14.0, 12.0), true)],
		["Fuel tank", func() -> Node3D: return Building.make("fuel_tank", Vector2(9.0, 9.0))],
		["City", func() -> Node3D:
			var city := City.new()
			city.awake = true
			return city],
		["Fortress (boss)", func() -> Node3D:
			var fortress := Fortress.new()
			fortress.active = true
			return fortress],
	]


## Spawns `count` of unit `index` around `at`.
func spawn(index: int, count: int, at: Vector3) -> void:
	var scene: Variant = units()[index][1]
	for i in count:
		var spread := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * (0.0 if i == 0 else 5.0)
		spawn_enemy(scene, at + spread)


func spawn_enemy(scene: Variant, at: Vector3) -> Node3D:
	var enemy: Node3D = scene.call() if scene is Callable else scene.instantiate()
	mission.world.add_child(enemy)
	# Buildings and cities stand on the ground; units settle from above.
	var height := spawn_height if enemy is EnemyBase else enemy.position.y
	enemy.position = Vector3(at.x, height, at.z)
	# Face away from the map centre, the way they'd be heading in.
	enemy.rotation.y = atan2(at.x, at.z)
	return enemy


## Launches a salvo at the helicopter from points on a ring around it,
## centred on where it's heading, one missile every salvo_stagger seconds
## (game time, so slow motion holds the rest back too).
func fire_salvo() -> void:
	var heli := mission.helicopter
	var heading := heli.velocity if heli.velocity.length() > 1.0 else -heli.global_transform.basis.z
	var center := atan2(heading.x, heading.z)
	var built := mission
	for i in salvo_count:
		if i > 0:
			await get_tree().create_timer(salvo_stagger, false).timeout
		# The range was reset meanwhile.
		if mission != built or heli.dead:
			return
		var t := 0.5 if salvo_count == 1 else float(i) / (salvo_count - 1)
		var angle := center + deg_to_rad(lerpf(-salvo_arc, salvo_arc, t) * 0.5)
		var from := heli.global_position + Vector3(sin(angle), 0.0, cos(angle)) * salvo_distance
		from.y = heli.global_position.y
		var missile := Missile.new()
		missile.target = heli
		missile.explosion_scene = MISSILE_EXPLOSION
		missile.eject_time = 0.3
		missile.source_name = "SALVO"
		mission.world.add_child(missile)
		missile.launch(from, (heli.global_position - from).normalized())


## Where the mouse cursor meets the ground, or null.
func cursor_ground() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	return Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))


## The enemy closest to the cursor (within a few metres), or null.
func enemy_under_cursor() -> Node3D:
	var at: Variant = cursor_ground()
	if at == null:
		return null
	var best: Node3D = null
	var best_distance := 7.0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		var offset: Vector3 = enemy.global_position - at
		var distance := Vector2(offset.x, offset.z).length()
		if distance < best_distance:
			best = enemy
			best_distance = distance
	return best


# --- Stats -------------------------------------------------------------------

func reset_stats() -> void:
	damage_taken_total = 0.0
	damage_by_source.clear()
	damage_dealt_total = 0.0
	best_chain = 0
	_dealt_log.clear()


func dps() -> float:
	var total := 0.0
	for entry in _dealt_log:
		total += entry[1]
	return total / DPS_WINDOW


func _on_damage_taken(amount: float, source: String) -> void:
	var name := source if source != "" else "OTHER"
	damage_taken_total += amount
	damage_by_source[name] = damage_by_source.get(name, 0.0) + amount


func _on_damage_dealt(amount: float) -> void:
	damage_dealt_total += amount
	_dealt_log.append([_time, amount])
