class_name MissionContext
extends Node

## The battle: one mission flown over a rig (or a free-play defence).
##
## This node owns the mission's state (MissionState) and wires its systems
## together: the helicopter and its guns, the enemy generator, the rig, the
## battlefield and the HUD. Those systems don't look each other up through
## globals. They are handed what they need in setup(), or reach the mission
## through MissionContext.of(self) when they are spawned mid-game
## (projectiles, effects, enemies).
##
## Gameplay lives under the `world` node, which pauses with the tree; this
## node and the HUD keep running so the end screen and Esc still work.
##
## Leaving is up to the root context: this only emits request_* signals.

signal request_menu
signal request_map
signal request_hangar
signal request_retry

@export_group("Scene")
## Parent of all gameplay nodes; also where spawned nodes are added.
@export var world: Node3D
@export var camera_rig: TopDownCamera
@export var helicopter: Helicopter
@export var guns: GunController
@export var generator: EnemyGenerator
@export var rig: MissionRig
@export var environment: DesertEnvironment
@export var hud: GameHud
## Drops pickups (cash, recharge, frenzy) where enemies die.
@export var pickups: PickupDropper

var services: GameServices
var state: MissionState

var _rig_id: String = ""
## Test range: no waves, no payout or records, and a lost helicopter or rig
## just asks for a reset (request_retry).
var sandbox: bool = false
## Started from the editor (F6) rather than by the root context.
var _standalone: bool = false
var _hit_stop_active: bool = false


## Called by the root context before the mission enters the tree.
## `rig_id` is the rig fought over, or "" for a free-play defence.
## `sandbox_mode` is for the test range (see `sandbox`).
func bind(game_services: GameServices, rig_id: String, sandbox_mode: bool = false) -> void:
	services = game_services
	_rig_id = rig_id
	sandbox = sandbox_mode


func _ready() -> void:
	if services == null:
		# Run directly from the editor: use the save on disk, free play,
		# and keep the generator's Inspector values.
		services = GameServices.create_default()
		_standalone = true
	setup()


## Builds the mission state and hands every system what it needs.
func setup() -> void:
	var campaign := services.campaign
	var mission_rig: RigData = campaign.rig(_rig_id) if campaign.has_rig(_rig_id) else null
	state = MissionState.new(mission_rig, mission_rig != null and not campaign.is_owned(_rig_id))

	if state.is_campaign():
		environment.biome = mission_rig.biome

	# The airframe, its look, its mounted weapons and every upgrade bought
	# in the hangar. The guns fire from the muzzles of the mounted weapons.
	var loadout := services.loadout
	var airframe := loadout.selected_heli()
	loadout.apply_to_helicopter(helicopter)
	loadout.apply_to_guns(guns)
	helicopter.initialize(self, airframe, loadout.mounted_weapons(airframe.id))
	guns.equip(loadout.mounted_types(airframe.id), helicopter.weapon_muzzles)
	camera_rig.snap()

	var hull_bonus := campaign.hull_bonus(_rig_id) if state.is_campaign() and not state.is_assault else 0.0
	rig.initialize(self, hull_bonus)

	if sandbox:
		# The test range spawns enemies by hand; the rig can't be lost.
		generator.mission = self
		rig.max_health = 1000000.0
		rig.health = rig.max_health
	else:
		generator.start(self,
				null if _standalone else services.difficulty(),
				null if _standalone else services.settings)

	hud.initialize(self)
	guns.kill_registered.connect(hud.register_kill)
	guns.kill_registered.connect(pickups.on_kill)
	hud.retry_pressed.connect(request_retry.emit)
	hud.map_pressed.connect(request_map.emit)
	hud.hangar_pressed.connect(request_hangar.emit)
	hud.menu_pressed.connect(request_menu.emit)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		request_menu.emit()


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

func is_assault() -> bool:
	return state != null and state.is_assault


func blood_enabled() -> bool:
	return services.settings.blood


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


## Freezes the game for a moment (real time), for impact.
func hit_stop(seconds: float) -> void:
	if _hit_stop_active or get_tree().paused:
		return
	_hit_stop_active = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_hit_stop_active = false


func add_score(points: int) -> void:
	state.add_score(points)


## A pickup was flown over (see pickup.gd). `value` is money for cash.
func collect_pickup(kind: int, value: int, at: Vector3) -> void:
	var kinds = PickupDropper.Pickup.Kind
	if kind == kinds.CASH:
		state.pickup_cash += value
		hud.spawn_popup("+$%d" % value, at, Color(0.45, 0.95, 0.45))
		Sfx.play_2d("kill_tick")
	elif kind == kinds.RECHARGE:
		helicopter.recharge_abilities()
		hud.spawn_popup("FLARES + DASH + SLAM READY", at, Color(0.45, 0.8, 1.0))
		Sfx.play_2d("combo")
	else:
		guns.start_frenzy(6.0)
		hud.spawn_popup("FRENZY!", at, Color(1.0, 0.45, 0.25), true)
		Sfx.play_2d("combo")


# --- Ending the mission -------------------------------------------------------

## Ends the run in defeat: records bests, pays out and shows the end
## screen. Safe to call more than once.
func game_over(reason: String) -> void:
	if state.is_over:
		return
	state.is_over = true
	if sandbox:
		request_retry.emit.call_deferred()
		return

	var beaten := services.profile.record_run(state.score, state.wave)
	_pay_out(false)
	get_tree().paused = true
	hud.show_game_over(reason, beaten["score"] or beaten["wave"])


## The assault's last wave and forts are down: the rig is captured.
func mission_won() -> void:
	if state.is_over:
		return
	state.is_over = true

	_pay_out(true)
	get_tree().paused = true
	hud.show_victory(state.rig.display_name)


## The score is paid out as money, plus cash pickups, income from every
## owned rig (win or lose) and a bonus for a capture.
func _pay_out(captured: bool) -> void:
	state.payout = {"kills": state.score, "pickups": state.pickup_cash, "income": 0, "capture": 0}
	if state.is_campaign():
		if captured:
			state.payout["capture"] = services.campaign.capture(state.rig.id)
		state.payout["income"] = services.campaign.total_income()

	state.earned = state.payout["kills"] + state.payout["pickups"] + state.payout["income"] + state.payout["capture"]
	services.profile.earn(state.earned)
	services.save()
