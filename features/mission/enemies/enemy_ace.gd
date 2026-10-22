extends "res://features/mission/enemies/enemy_helicopter.gd"

# The ace (the mini boss, see RunDirector's PLAN): an enemy helicopter that
# fights in stages.
#   1 - sizing you up (SIZING_UP seconds): hangs back, pairs of missiles,
#       long reloads, never sends a deflection back, and nothing hurts it
#       yet ("IMMUNE"), so the fight starts with learning its salvos
#   2 - the gloves come off: closes in, four-missile salvos, quick locks,
#       starts reflecting and dashing; now it can be hurt
#   3 - heavy rockets (below STAGES[2].below hull): a salvo of heavy
#       rockets (undeflectable, dodge them pass after pass), then a missile
#       salvo to deflect, and so on
# The look and flight are the scene's exports; the fighting is STAGES.

signal stage_changed(stage: int)

# How each stage fights; from stage 3 on, the hull fraction it starts below.
const STAGES := [
	{"salvo": 2, "reload": 7.0, "lock": 1.8, "range": Vector2(42.0, 55.0),
		"reflect": 0.0, "dash": 0.3},
	{"salvo": 4, "reload": 4.5, "lock": 1.3, "range": Vector2(28.0, 40.0),
		"reflect": 0.3, "dash": 0.4},
	{"below": 0.45, "salvo": 3, "reload": 4.0, "lock": 1.2, "range": Vector2(30.0, 42.0),
		"reflect": 0.3, "dash": 0.45},
]
# Seconds of stage 1, before its first salvo, and the breather it takes on
# reaching a new stage (it announces it, then starts).
const SIZING_UP := 12.0
const FIRST_SHOT := 5.0
const STAGE_PAUSE := 2.5
# Stage 3: rockets per heavy salvo, the gap between them, and how many of
# its heavy rockets may be up at once (more waits for a missile salvo).
const ROCKET_SALVO := 3
const ROCKET_SPACING := 0.5
const MAX_ROCKETS := 3
# Least gap between "IMMUNE" pop-ups, in msec.
const IMMUNE_POPUP_MS := 600

var stage: int = 0
var sizing_left: float = SIZING_UP
# Stage 3 alternates: the next salvo is heavy rockets.
var rockets_next: bool = true
var last_immune_ms: int = -100000


func _ready() -> void:
	super()
	apply_stage(0)
	reload_timer = FIRST_SHOT


func _physics_process(delta: float) -> void:
	super(delta)
	if stage == 0 and not crashing:
		sizing_left -= delta
		if sizing_left <= 0.0:
			enter_stage(1)


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


# A new stage: a breather, a dropped lock, and the announcement.
func enter_stage(index: int) -> void:
	apply_stage(index)
	if not firing:
		reload_timer = STAGE_PAUSE
	lock_timer = 0.0
	rockets_next = true
	stage_changed.emit(stage + 1)


func take_damage(amount: float, light_weapon: bool = false) -> bool:
	if stage == 0:
		# Hits glance off while it's sizing you up.
		if mission != null and Time.get_ticks_msec() - last_immune_ms > IMMUNE_POPUP_MS:
			last_immune_ms = Time.get_ticks_msec()
			mission.hud.spawn_popup(tr("IMMUNE"), global_position, Color.WHITE)
		return false
	var killed := super(amount, light_weapon)
	if killed or crashing:
		return killed
	var last := STAGES.size() - 1
	if stage < last and health / maxf(max_health, 0.001) < STAGES[last].below:
		enter_stage(last)
	return killed


func fire_salvo(heli: Helicopter) -> void:
	var last := STAGES.size() - 1
	var rockets := stage == last and rockets_next and live_rockets() < MAX_ROCKETS
	if stage == last:
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
