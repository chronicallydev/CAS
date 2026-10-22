class_name Burn
extends Node3D

# Incendiary (an upgrade, see RunUpgrades): a fire on a vehicle or building
# that keeps hurting it for a few seconds. On a building it can jump to the
# ones next door, so a city goes up street by street. It sits beside its
# target rather than under it (wrecks copy an enemy's children) and follows.

const DURATION := 4.0
const DAMAGE_PER_SECOND := 3.0
const TICK := 0.25
# Chance per second that a burning building sets each neighbour alight.
const SPREAD_RADIUS := 12.0
const SPREAD_CHANCE := 0.35

var target: Node3D
var mission: MissionContext
var left: float = DURATION
var tick_left: float = TICK
var height: float = 1.5


## Sets `node` alight, or keeps an existing fire on it going.
static func ignite(node: Node3D, mission_context: MissionContext) -> void:
	if node.has_meta("burn") and is_instance_valid(node.get_meta("burn")):
		node.get_meta("burn").left = DURATION
		return
	var burn := Burn.new()
	burn.target = node
	burn.mission = mission_context
	burn.height = node.size.y if node is Building else 1.5
	node.set_meta("burn", burn)
	# Deferred: hits land while the scene is mid-update.
	MissionContext.spawn_parent(node).add_child.call_deferred(burn)


func _ready() -> void:
	var fire := CPUParticles3D.new()
	fire.amount = 16
	fire.lifetime = 0.6
	fire.local_coords = false
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 1.0
	fire.direction = Vector3.UP
	fire.spread = 20.0
	fire.gravity = Vector3(0, 4.0, 0)
	fire.initial_velocity_min = 1.0
	fire.initial_velocity_max = 2.5
	fire.scale_amount_min = 0.7
	fire.scale_amount_max = 1.3
	# 1-bit fire: white with black rims.
	fire.mesh = OneBit.puff(Color.WHITE, Color.BLACK, 0.5)
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fire)
	if is_instance_valid(target):
		place()


func _physics_process(delta: float) -> void:
	if not target_alive():
		queue_free()
		return
	place()
	left -= delta
	if left <= 0.0:
		target.remove_meta("burn")
		queue_free()
		return
	tick_left -= delta
	if tick_left > 0.0:
		return
	tick_left = TICK
	var killed: bool = target.take_damage(DAMAGE_PER_SECOND * TICK)
	if killed and mission != null and mission.guns != null:
		mission.guns.register_kill(target, target.score_value)
		return
	if target is Building:
		spread()


func spread() -> void:
	for node in get_tree().get_nodes_in_group("structures"):
		var neighbour := node as Building
		if neighbour == null or neighbour == target or neighbour.dormant or neighbour.has_meta("burn"):
			continue
		if neighbour.ground_distance(target.global_position) > SPREAD_RADIUS:
			continue
		if randf() < SPREAD_CHANCE * TICK:
			Burn.ignite(neighbour, mission)


func place() -> void:
	global_position = target.global_position + Vector3(0, height, 0)


func target_alive() -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	if target is Building:
		return target.stage != Building.Stage.COLLAPSED
	return target.is_in_group("enemies")
