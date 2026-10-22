class_name RunContext
extends Node

## A run: the game's main scene (see DESIGN.md).
##
## It owns a mission (mission.tscn, flown with the minigun only) and a
## RunDirector that leads it through the stretches. Between stretches it
## pauses for an upgrade pick (RunUpgrades); being shot down or clearing
## the last arena ends the run with its numbers, and R starts a new one.
## T on the end screen opens the test range. Esc quits.

const TEST_RANGE := "res://features/test_range/test_range.tscn"
# Hull patched up after each cleared arena.
const STRETCH_HEAL := 20

@export var mission_scene: PackedScene = preload("res://features/mission/mission.tscn")
@export var stretch_count: int = 6

var mission: MissionContext
var director: RunDirector
var screens: RunScreens
var best_chain: int = 0
var over: bool = false
# The current city's marked targets: still standing, and in all.
var targets_left: int = 0
var targets_total: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	screens = RunScreens.new()
	add_child(screens)
	RunUpgrades.save_defaults()
	start_run()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	RunUpgrades.restore_defaults()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func start_run() -> void:
	if director != null:
		director.queue_free()
	if mission != null:
		remove_child(mission)
		mission.queue_free()
	get_tree().paused = false
	Engine.time_scale = 1.0
	RunUpgrades.restore_defaults()
	best_chain = 0
	over = false

	mission = mission_scene.instantiate()
	# One weapon per helicopter: the Cobra flies with its chin minigun.
	mission.loadout = PackedStringArray(["minigun", "", "", ""])
	add_child(mission)
	mission.request_retry.connect(_on_shot_down, CONNECT_DEFERRED)
	mission.helicopter.chain_dodge.perfect_dodge.connect(func(chain: int, _missiles: Array) -> void:
		best_chain = maxi(best_chain, chain))
	mission.helicopter.position = Vector3(0.0, mission.helicopter.altitude, 0.0)
	mission.camera_rig.snap()

	director = RunDirector.new()
	director.process_mode = Node.PROCESS_MODE_PAUSABLE
	director.stretch_count = stretch_count
	add_child(director)
	director.stretch_started.connect(_on_stretch_started)
	director.arena_started.connect(func(_index: int) -> void:
		Music.play("final_arena" if director.is_last_stretch() else "arena")
		screens.show_banner("DESTROY THE TARGETS" if targets_total > 0 else "INTERCEPT"))
	director.targets_changed.connect(_on_targets_changed)
	director.held_by.connect(func(what: String) -> void:
		screens.show_banner("CLEAR THE SAMS" if what == "SAMS" else "DESTROY THE " + what))
	director.convoy_escaped.connect(func() -> void:
		screens.show_banner("CONVOY ESCAPED"))
	director.arena_cleared.connect(_on_arena_cleared)
	director.run_complete.connect(_on_run_complete)
	director.setup(mission)


func _on_stretch_started(index: int) -> void:
	update_title()
	Music.play("final_travel" if index == stretch_count - 1 else "travel")
	screens.show_banner("FINAL STRETCH" if index == stretch_count - 1 else "GO  ^")


func _on_arena_cleared(_index: int) -> void:
	# A beat to see the last kill, then the pick with the game paused.
	await get_tree().create_timer(1.2, false).timeout
	if over or mission.helicopter.dead:
		return
	# A small patch-up for every stretch cleared.
	RunUpgrades.heal(mission.helicopter, STRETCH_HEAL)
	mission.hud.spawn_popup("+%d HULL" % STRETCH_HEAL, mission.helicopter.global_position, Color.WHITE, true, true)
	get_tree().paused = true
	Music.duck(true)
	screens.show_picks("CLEARED - PICK ONE", RunUpgrades.offer(mission), func(id: String) -> void:
		RunUpgrades.apply(id, mission)
		Music.duck(false)
		get_tree().paused = false
		director.next_stretch())


func _on_run_complete() -> void:
	await get_tree().create_timer(1.5, false).timeout
	if over or mission.helicopter.dead:
		return
	end_run("RUN COMPLETE")


func _on_shot_down() -> void:
	end_run("SHOT DOWN")


func end_run(title: String) -> void:
	if over:
		return
	over = true
	get_tree().paused = true
	Music.play("run_complete" if director.state == RunDirector.State.DONE else "shot_down")
	var lines := [
		"Stretch %d / %d" % [director.stretch + 1, stretch_count],
		"Kills %d     Score %d" % [mission.guns.kills, mission.score],
		"Best chain %d" % best_chain,
	]
	screens.show_end(title, lines, start_run, func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file(TEST_RANGE))


func _on_targets_changed(left: int, total: int) -> void:
	var fell := left < targets_left
	targets_left = left
	targets_total = total
	update_title()
	if fell and left == 0:
		screens.show_banner("TARGETS DOWN")


func update_title() -> void:
	var text := "STRETCH %d / %d" % [director.stretch + 1, stretch_count]
	if targets_total > 0:
		text += "    TARGETS %d / %d" % [targets_total - targets_left, targets_total]
	mission.hud.title_label.text = text
