extends "res://features/mission/enemies/enemy_helicopter.gd"

# The ace (the mini boss, see RunDirector's PLAN): an enemy helicopter that
# fights in stages as its hull goes down.
#   1 - sizing you up: hangs back, pairs of missiles, long reloads, never
#       sends a deflection back
#   2 - the gloves come off: closes in, four-missile salvos, quick locks,
#       starts reflecting and dashing
#   3 - heavy rockets: a salvo of heavy rockets (undeflectable, dodge them
#       pass after pass), then a missile salvo to deflect, and so on
# The look and flight are the scene's exports; the fighting is STAGES.

signal stage_changed(stage: int)

# Hull fraction each stage starts below, and how it fights in it.
const STAGES := [
	{"below": 1.01, "salvo": 2, "reload": 7.0, "lock": 1.8, "range": Vector2(42.0, 55.0),
		"reflect": 0.0, "dash": 0.3},
	{"below": 0.7, "salvo": 4, "reload": 4.5, "lock": 1.3, "range": Vector2(28.0, 40.0),
		"reflect": 0.3, "dash": 0.4},
	{"below": 0.35, "salvo": 3, "reload": 4.0, "lock": 1.2, "range": Vector2(30.0, 42.0),
		"reflect": 0.3, "dash": 0.45},
]
# Seconds before its first salvo, and the breather it takes on reaching a
# new stage (it announces it, then starts).
const FIRST_SHOT := 5.0
const STAGE_PAUSE := 2.5
# Stage 3: rockets per heavy salvo, the gap between them, and how many of
# its heavy rockets may be up at once (more waits for a missile salvo).
const ROCKET_SALVO := 3
const ROCKET_SPACING := 0.5
const MAX_ROCKETS := 3

var stage: int = 0
# Stage 3 alternates: the next salvo is heavy rockets.
var rockets_next: bool = true


func _ready() -> void:
	super()
	apply_stage(0)
	reload_timer = FIRST_SHOT


func apply_stage(index: int) -> void:
	stage = index
	var settings: Dictionary = STAGES[index]
	salvo_size = settings.salvo
	reload_time = settings.reload
	lock_time = settings.lock
	range_min = settings.range.x
	range_max = settings.range.y
	preferred_range = randf_range(range_min, range_max)
	reflect_chance = settings.reflect
	dash_chance = settings.dash


func take_damage(amount: float, light_weapon: bool = false) -> bool:
	var killed := super(amount, light_weapon)
	if killed or crashing:
		return killed
	var fraction := health / maxf(max_health, 0.001)
	var reached := stage
	while reached + 1 < STAGES.size() and fraction < STAGES[reached + 1].below:
		reached += 1
	if reached != stage:
		apply_stage(reached)
		# A breather, and it drops any lock it was building.
		if not firing:
			reload_timer = STAGE_PAUSE
		lock_timer = 0.0
		rockets_next = true
		stage_changed.emit(stage + 1)
	return killed


func fire_salvo(heli: Helicopter) -> void:
	var rockets := stage == STAGES.size() - 1 and rockets_next and live_rockets() < MAX_ROCKETS
	if stage == STAGES.size() - 1:
		rockets_next = not rockets
	heavy_rockets = rockets
	var spacing := salvo_spacing
	if rockets:
		salvo_size = ROCKET_SALVO
		salvo_spacing = ROCKET_SPACING
	await super(heli)
	# From the stage it's in now: it may have moved on mid-salvo.
	salvo_size = STAGES[stage].salvo
	salvo_spacing = spacing
	heavy_rockets = false


func live_rockets() -> int:
	var count := 0
	for missile in get_tree().get_nodes_in_group("aa_missiles"):
		if missile is HeavyRocket and not missile.harmless:
			count += 1
	return count
