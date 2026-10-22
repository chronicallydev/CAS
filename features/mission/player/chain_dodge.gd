class_name ChainDodge
extends Node

# The chain dodge (see DESIGN.md): a dash started just before a missile
# would hit is a perfect dodge. The game drops into slow motion, the dash
# charge comes back, and a dash out of the slow motion can be the next
# perfect dodge, against the next missile of a salvo. Each link shortens the
# next window. A perfect-dodged missile is deflected: it gives up on the
# helicopter and goes after the nearest enemy ahead of it.
#
# Owned by the helicopter, which calls on_dash() for every dash. The tuning
# is static so the test range's sliders last across resets.

# Seconds before impact (game time) that still count as perfect.
static var perfect_window: float = 0.3
# Missiles further than this never count, however fast they close.
static var max_distance: float = 18.0
# World speed during the slow motion.
static var slow_scale: float = 0.05
# Real seconds of slow motion for the first link, and the factor each
# further link multiplies it by, down to min_slow_time.
static var slow_time: float = 1.0
static var slow_shrink: float = 0.8
static var min_slow_time: float = 0.35
# Game seconds after the slow motion ends that the chain stays alive.
static var chain_timeout: float = 1.5
static var refund_dash: bool = true
# Deflected missiles home on enemies; off, they just fly on and burst.
static var deflect_homing: bool = true

## A tuning value by name, for the test range's sliders (static vars
## can't be reached with get()).
static func tuning(property: String) -> float:
	match property:
		"perfect_window": return perfect_window
		"max_distance": return max_distance
		"slow_scale": return slow_scale
		"slow_time": return slow_time
		"slow_shrink": return slow_shrink
		"min_slow_time": return min_slow_time
		"chain_timeout": return chain_timeout
	push_error("No chain dodge tuning value '%s'" % property)
	return 0.0


static func tune(property: String, value: float) -> void:
	match property:
		"perfect_window": perfect_window = value
		"max_distance": max_distance = value
		"slow_scale": slow_scale = value
		"slow_time": slow_time = value
		"slow_shrink": slow_shrink = value
		"min_slow_time": min_slow_time = value
		"chain_timeout": chain_timeout = value
		_: push_error("No chain dodge tuning value '%s'" % property)


# The feedback (DodgeFx on the HUD) hangs off these.
signal perfect_dodge(chain: int, missiles: Array)
signal slow_ended
signal chain_ended(chain: int)

var helicopter: Helicopter
var mission: MissionContext
var chain: int = 0
# Real seconds of slow motion left (0 = normal speed).
var slow_left: float = 0.0
# Game seconds left to keep the chain going.
var chain_left: float = 0.0
# Grace (an upgrade): real seconds left in which a hit is deflected anyway.
var grace_left: float = 0.0

# Grace's window after a perfect dodge (real seconds), and Time Bank's
# extra slow motion per missile dodged (it also stops the shrinking).
const GRACE_TIME := 1.0
const TIME_BANK_PER_MISSILE := 0.35


func setup(heli: Helicopter, mission_context: MissionContext) -> void:
	helicopter = heli
	mission = mission_context
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_slowed() -> bool:
	return slow_left > 0.0


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	grace_left = maxf(grace_left - delta / maxf(Engine.time_scale, 0.001), 0.0)
	if slow_left > 0.0:
		# Engine.time_scale scales delta; count the slow motion in real time.
		slow_left -= delta / maxf(Engine.time_scale, 0.001)
		if slow_left <= 0.0:
			end_slow()
	elif chain > 0:
		chain_left -= delta
		if chain_left <= 0.0:
			end_chain()


## Called by the helicopter as it starts a dash, with its velocity from
## just before (the dash's own velocity would make a dash straight away
## from a missile look like it was never going to hit). True if perfect.
func on_dash(velocity_before: Vector3) -> bool:
	var dodged := incoming_missiles(velocity_before)
	if dodged.is_empty():
		# Dashed out of the slow motion without a missile to dodge.
		if is_slowed():
			end_slow()
		return false

	for missile in dodged:
		missile.deflect(deflect_homing)
	chain += 1
	chain_left = chain_timeout
	if refund_dash:
		helicopter.dash_charges_left = mini(helicopter.dash_charges_left + 1, helicopter.dash_charges)
	var slow := maxf(slow_time * pow(slow_shrink, chain - 1), min_slow_time)
	if upgraded("time_bank"):
		slow = slow_time + TIME_BANK_PER_MISSILE * dodged.size()
		mission.hud.spawn_popup("TIME BANK +%.1fs" % (slow - slow_time), helicopter.global_position, Color.WHITE, false, true)
	start_slow(slow)
	if upgraded("grace"):
		grace_left = GRACE_TIME
	perfect_dodge.emit(chain, dodged)
	return true


## Missiles chasing the helicopter that would hit within perfect_window,
## with the helicopter moving at `heli_velocity` (default: as it is now).
func incoming_missiles(heli_velocity: Variant = null) -> Array:
	var velocity: Vector3 = heli_velocity if heli_velocity is Vector3 else helicopter.velocity
	var found: Array = []
	var heli_position := helicopter.global_position
	for missile in get_tree().get_nodes_in_group("aa_missiles"):
		if missile.lost or missile.deflected or not missile.deflectable or not missile.ignited or missile.target != helicopter:
			continue
		var offset: Vector3 = heli_position - missile.global_position
		var distance := offset.length()
		# How fast the gap is closing.
		var closing: float = (missile.velocity - velocity).dot(offset / maxf(distance, 0.01))
		if closing <= 0.0:
			continue
		# A fast missile (a rallied one) covers more than max_distance
		# inside the window; the limit stretches to what it can cover.
		if distance > maxf(max_distance, closing * perfect_window + missile.hit_radius):
			continue
		var impact := maxf(distance - missile.hit_radius, 0.0) / closing
		if impact <= perfect_window:
			found.append(missile)
	return found


## The closest missile still chasing the helicopter, or null.
func next_missile() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for missile in get_tree().get_nodes_in_group("aa_missiles"):
		if missile.deflected or missile.lost or missile.target != helicopter:
			continue
		var distance: float = missile.global_position.distance_to(helicopter.global_position)
		if distance < best_distance:
			best = missile
			best_distance = distance
	return best


func start_slow(seconds: float) -> void:
	slow_left = seconds
	mission.base_time_scale = slow_scale
	Engine.time_scale = slow_scale


func end_slow() -> void:
	slow_left = 0.0
	mission.base_time_scale = 1.0
	Engine.time_scale = 1.0
	slow_ended.emit()


func end_chain() -> void:
	var length := chain
	chain = 0
	chain_ended.emit(length)


## The helicopter was hit: the chain is broken.
func break_chain() -> void:
	if slow_left > 0.0:
		end_slow()
	if chain > 0:
		end_chain()


func upgraded(id: String) -> bool:
	return mission != null and mission.upgraded(id)
