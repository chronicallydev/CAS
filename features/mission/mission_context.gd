class_name MissionContext
extends Node

## The battle: the helicopter, its guns and whatever is spawned to fight.
##
## This node wires its systems together: the helicopter and its guns, the
## battlefield and the HUD. Those systems don't look each other up through
## globals. They are handed what they need in setup(), or reach the mission
## through MissionContext.of(self) when they are spawned mid-game
## (projectiles, effects, enemies).
##
## Gameplay lives under the `world` node, which pauses with the tree; this
## node and the HUD keep running.
##
## The test range owns the mission: a lost helicopter only asks it for a
## reset (request_retry).

signal request_retry

@export_group("Scene")
## Parent of all gameplay nodes; also where spawned nodes are added.
@export var world: Node3D
@export var camera_rig: TopDownCamera
@export var helicopter: Helicopter
@export var guns: GunController
@export var environment: DesertEnvironment
@export var hud: GameHud

@export_group("Loadout")
## The airframe flown: its stats, look and hardpoints.
@export var airframe: HelicopterData
## The weapons that can be mounted, in fire-button order: the first type
## mounted fires with LMB, the second with RMB.
@export var weapons: Array[WeaponData] = []
## Weapon id per hardpoint of the airframe ("" = empty). Defaults to the
## Cobra's fit: minigun on the chin, rockets on both wings, belly empty.
@export var loadout: PackedStringArray = ["minigun", "rockets", "rockets", ""]

@export_group("Options")
@export var blood: bool = true

var score: int = 0
var is_over: bool = false
var _hit_stop_active: bool = false
## The time scale between hit stops: below 1 during a chain dodge's slow
## motion (see ChainDodge), which hit stops then leave alone.
var base_time_scale: float = 1.0
# Upgrades held this run, by id (see RunUpgrades): systems ask upgraded()
# and combo() to change how they work. Empty outside a run, unless the
# test range turns some on.
var upgrades: Dictionary = {}


func _ready() -> void:
	setup()


## Fits the airframe and its weapons and hands every system what it needs.
func setup() -> void:
	for property in ["speed", "acceleration", "max_health", "turn_speed", "dash_cooldown"]:
		helicopter.set(property, airframe.get(property))
	helicopter.initialize(self, airframe, mounted_weapons())
	guns.equip(mounted_types(), helicopter.weapon_muzzles)
	camera_rig.snap()
	if environment.night():
		dusk_lighting()

	hud.initialize(self)
	guns.kill_registered.connect(hud.register_kill)


## With a "night" palette (Dusk), a cool, fogless light: the desert's warm
## fog and sun would wash the dark ground out to olive.
func dusk_lighting() -> void:
	var sun := world.get_node("Atmosphere/DirectionalLight3D") as DirectionalLight3D
	sun.light_color = Color(0.86, 0.84, 1.0)
	# Long shadows only dither into noise on the dark ground.
	sun.shadow_enabled = false
	var sky := (world.get_node("Atmosphere/WorldEnvironment") as WorldEnvironment).environment.duplicate() as Environment
	sky.fog_enabled = false
	# Filmic tonemapping and the contrast boost crush dark colours to black.
	sky.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	sky.adjustment_enabled = false
	sky.ambient_light_color = Color(0.4, 0.34, 0.48)
	(world.get_node("Atmosphere/WorldEnvironment") as WorldEnvironment).environment = sky


## WeaponData per hardpoint (null where empty), for building the model.
func mounted_weapons() -> Array:
	var mounted: Array = []
	for i in airframe.hardpoints.size():
		mounted.append(weapon(loadout[i]) if i < loadout.size() else null)
	return mounted


## The weapon types mounted, in `weapons` order.
func mounted_types() -> Array[String]:
	var types: Array[String] = []
	for weapon_data in weapons:
		if loadout.has(weapon_data.id):
			types.append(weapon_data.id)
	return types


func weapon(id: String) -> WeaponData:
	for weapon_data in weapons:
		if weapon_data.id == id:
			return weapon_data
	return null


# --- Lookups for spawned nodes ---------------------------------------------

## The mission `node` belongs to (its nearest MissionContext ancestor), or
## null outside a mission.
static func of(node: Node) -> MissionContext:
	var current := node
	while current != null:
		if current is MissionContext:
			return current
		current = current.get_parent()
	return null


## Where `node` should add things it spawns (projectiles, effects, wrecks):
## its mission's world, so they are freed with the mission.
static func spawn_parent(node: Node) -> Node:
	var mission := of(node)
	if mission != null and mission.world != null:
		return mission.world
	return node.get_tree().current_scene


# --- Services for gameplay nodes --------------------------------------------

func blood_enabled() -> bool:
	return blood


## Shakes the camera. With a position, the shake fades out for things far
## from the centre of the view.
func shake(amount: float, at: Variant = null) -> void:
	if camera_rig == null:
		return
	if at is Vector3:
		var focus := camera_rig.get_focus()
		var distance: float = Vector2(at.x, at.z).distance_to(Vector2(focus.x, focus.z))
		amount *= clampf(1.0 - distance / 70.0, 0.2, 1.0)
	camera_rig.add_trauma(amount)


## Jolts the view a little toward `direction` (on the ground), then it
## springs back: for the player's own moves, where shake would be noise.
func kick(direction: Vector3, amount: float) -> void:
	if camera_rig != null:
		camera_rig.add_kick(direction, amount)


## Freezes the game for a moment (real time), for impact. A higher
## `slow` gives slow motion instead (a close call).
func hit_stop(seconds: float, slow: float = 0.05) -> void:
	if _hit_stop_active or get_tree().paused or base_time_scale < 1.0:
		return
	_hit_stop_active = true
	Engine.time_scale = slow
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = base_time_scale
	_hit_stop_active = false


func add_score(points: int) -> void:
	score += points


## The helicopter is down: ask the test range for a reset. Safe to call
## more than once.
func game_over(_reason: String) -> void:
	if is_over:
		return
	is_over = true
	request_retry.emit.call_deferred()


func upgraded(id: String) -> bool:
	return upgrades.has(id)


## Both halves of a combo held (see RunUpgrades.COMBOS).
func combo(a: String, b: String) -> bool:
	return upgrades.has(a) and upgrades.has(b)
