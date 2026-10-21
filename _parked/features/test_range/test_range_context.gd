class_name TestRangeContext
extends Node

## The test range: a sandbox for trying every enemy and weapon.
##
## It runs a real mission (mission.tscn) in sandbox mode, so units behave
## exactly as in a campaign, but with no waves, no payout and no saving. It
## uses a throwaway copy of the services (GameServices.create_sandbox) that
## owns every helicopter and weapon; nothing done here reaches the real
## profile.
##
## The side panel (TestRangePanel) picks what to spawn and edits the
## helicopter, loadout and upgrades. Middle-click or G drops the chosen unit
## at the cursor. APPLY rebuilds the range with the new helicopter, and so
## does losing the helicopter. Esc returns to the menu.

signal request_menu

@export var mission_scene: PackedScene
@export var panel: TestRangePanel

## How many seconds of damage the DPS readout averages over.
const DPS_WINDOW := 5.0

var services: GameServices
var sandbox: GameServices
var mission: MissionContext

## Cheats, kept across rebuilds.
var god_mode: bool = true
var infinite_ammo: bool = false
## Enemies hunt the helicopter (true) or march on the rig (false).
var hunt_helicopter: bool = true

## Stats since the last reset.
var damage_taken_total: float = 0.0
var damage_by_source: Dictionary = {}  # source name -> damage
var damage_dealt_total: float = 0.0
var _dealt_log: Array = []  # [time, amount], for DPS
var _time: float = 0.0


## Called by the root context before the range enters the tree.
func bind(game_services: GameServices) -> void:
	services = game_services


func _ready() -> void:
	if services == null:
		# Run directly from the editor.
		services = GameServices.create_default()
	sandbox = GameServices.create_sandbox(services)
	panel.initialize(self)
	rebuild()


func _process(delta: float) -> void:
	_time += delta
	while not _dealt_log.is_empty() and _time - _dealt_log[0][0] > DPS_WINDOW:
		_dealt_log.pop_front()


func _unhandled_input(event: InputEvent) -> void:
	var spawn_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE
	var spawn_key: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_G
	if spawn_click or spawn_key:
		var at: Variant = cursor_ground()
		if at != null:
			spawn(panel.selected_unit, panel.spawn_count, at)
		get_viewport().set_input_as_handled()


# --- The range ---------------------------------------------------------------

## Starts the range over with the sandbox's current helicopter, loadout and
## upgrades. Spawned enemies are cleared.
func rebuild() -> void:
	if mission != null:
		remove_child(mission)
		mission.queue_free()
	get_tree().paused = false
	Engine.time_scale = 1.0

	mission = mission_scene.instantiate()
	mission.bind(sandbox, "", true)
	add_child(mission)

	mission.request_menu.connect(request_menu.emit)
	mission.request_retry.connect(rebuild, CONNECT_DEFERRED)
	mission.helicopter.damage_taken.connect(_on_damage_taken)
	mission.guns.damage_dealt.connect(_on_damage_dealt)
	apply_cheats()
	set_hunt(hunt_helicopter)
	panel.refresh()


func apply_cheats() -> void:
	if mission == null:
		return
	mission.helicopter.invulnerable = god_mode
	mission.helicopter.infinite_flares = infinite_ammo
	mission.guns.infinite_ammo = infinite_ammo


func set_hunt(hunt: bool) -> void:
	hunt_helicopter = hunt
	mission.state.is_assault = hunt


func clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()


# --- Spawning ----------------------------------------------------------------

## What the panel can spawn: [name, callable(at: Vector3)].
func units() -> Array:
	var gen := mission.generator
	var wave := func(scene: PackedScene) -> Callable:
		return func(at: Vector3) -> void: gen.spawn_enemy(scene, Vector3(at.x, gen.vertical_offset, at.z))
	return [
		["Infantry", wave.call(gen.node_scene)],
		["Stinger", wave.call(gen.stinger_scene)],
		["Car", wave.call(gen.car_scene)],
		["Tank", wave.call(gen.tank_scene)],
		["SAM truck", wave.call(gen.aa_scene)],
		["Shilka", wave.call(gen.shilka_scene)],
		["Ripple launcher", wave.call(gen.ripple_scene)],
		["Boss tank", func(at: Vector3) -> void: gen.spawn_boss(Vector3(at.x, gen.vertical_offset, at.z))],
		["Bunker", func(at: Vector3) -> void: gen.add_fort(EnemyGenerator.Bunker.new(), at)],
		["Flak gun", func(at: Vector3) -> void: gen.add_fort(EnemyGenerator.FlakGun.new(), at)],
		["SAM site", func(at: Vector3) -> void: gen.spawn_sam_site(at)],
	]


## Spawns `count` of unit `index` around `at`.
func spawn(index: int, count: int, at: Vector3) -> void:
	var spawner: Callable = units()[index][1]
	for i in count:
		var spread := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * (0.0 if i == 0 else 5.0)
		spawner.call(at + spread)


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
