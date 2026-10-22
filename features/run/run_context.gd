class_name RunContext
extends Node

## A run (see DESIGN.md), started from the main menu (MainMenu).
##
## It owns a mission (mission.tscn, flown with the minigun only) and a
## RunDirector that leads it through the stretches, once the takeoff
## (TakeoffIntro, skippable) has played. Between stretches it
## pauses for an upgrade pick (RunUpgrades); being shot down or clearing
## the last arena ends the run with its numbers, and R starts a new one.
## M on the end screen, or Esc at any time, goes back to the menu.

const MENU := "res://features/menu/main_menu.tscn"
# Game seconds between an arena clearing and the upgrade pick.
const PICK_DELAY := 2.6

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
# The mini boss while it's up (its health drives the boss bar).
var ace: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	screens = RunScreens.new()
	add_child(screens)
	start_run()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _process(_delta: float) -> void:
	if ace == null:
		return
	if not is_instance_valid(ace) or ace.crashing:
		ace = null
		screens.hide_boss_bar()
		return
	screens.set_boss_health(ace.health / ace.max_health)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().paused = false
		get_tree().change_scene_to_file(MENU)


func start_run() -> void:
	if director != null:
		director.queue_free()
	if mission != null:
		remove_child(mission)
		mission.queue_free()
	get_tree().paused = false
	Engine.time_scale = 1.0
	best_chain = 0
	over = false
	ace = null
	screens.show_leftovers(0)
	screens.hide_go()
	screens.hide_boss_bar()

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
	director.arena_started.connect(_on_arena_started)
	director.boss_built.connect(_on_boss_built)
	director.ace_arrived.connect(func(unit: Node3D) -> void:
		ace = unit
		screens.show_boss_bar("ACE")
		unit.stage_changed.connect(func(stage: int) -> void:
			screens.show_banner("THE ACE GETS SERIOUS" if stage == 2 else "HEAVY ROCKETS")))
	director.targets_changed.connect(_on_targets_changed)
	director.held_by.connect(func(what: String) -> void:
		screens.hide_go()
		screens.show_banner("CLEAR THE SAMS" if what == "SAMS" else tr("DESTROY THE %s") % tr(what)))
	director.path_cleared.connect(_on_path_cleared)
	director.leftovers_changed.connect(screens.show_leftovers)
	director.convoy_escaped.connect(func() -> void:
		screens.show_banner("CONVOY ESCAPED"))
	director.arena_cleared.connect(_on_arena_cleared)
	director.run_complete.connect(_on_run_complete)
	# The run proper starts once the helicopter has taken off; the terrain
	# ahead and the first music are loaded now, while it can't be seen.
	director.prepare(mission)
	Music.prepare("travel")
	var intro := TakeoffIntro.new()
	add_child(intro)
	intro.run_starting.connect(func() -> void: director.setup(mission))
	intro.play(mission)


func _on_stretch_started(index: int) -> void:
	update_title()
	# Autorotate (an upgrade) saves you once per stretch.
	mission.helicopter.autorotate_ready = true
	Music.play("final_travel" if index == stretch_count - 1 else "travel")
	# Loaded now, with the stretch, rather than as the arena starts.
	Music.prepare("final_arena" if index == stretch_count - 1 else "arena")
	screens.show_banner("FINAL STRETCH" if index == stretch_count - 1 else "GO  ^")
	screens.show_go()


# A hold let go: a chime, and the way on (to the arena, if nothing else is
# left on the way).
func _on_path_cleared() -> void:
	var to_arena := director.sams.is_empty() and director.pending.is_empty() and director.objectives.is_empty() and director.pending_objectives.is_empty()
	screens.show_banner("ARENA AHEAD  ^" if to_arena else "GO  ^")
	screens.show_go()
	Sfx.play_2d("combo")


func _on_arena_cleared(_index: int) -> void:
	# A beat to take in the win (the last wreck coming down, the patch-up)
	# before the pick fades in with the game paused.
	screens.show_banner("ACE DOWN" if director.has_ace() else "ARENA CLEAR")
	Sfx.play_2d("combo")
	# Every cleared arena (the ace's too) patches the hull right up.
	mission.helicopter.repair(mission.helicopter.max_health)
	mission.hud.spawn_popup(tr("HULL RESTORED"), mission.helicopter.global_position, Color.WHITE, true)
	await get_tree().create_timer(PICK_DELAY, false).timeout
	if over or mission.helicopter.dead:
		return
	var cards := RunUpgrades.offer(mission)
	if cards.is_empty():
		# Everything held already: straight on.
		director.next_stretch()
		return
	for i in cards.size():
		cards[i] = cards[i].duplicate()
		cards[i].card = RunUpgrades.card_text(i + 1, cards[i], mission)
	# Beating the ace: every card on offer, not just one.
	var take_all := director.has_ace()
	get_tree().paused = true
	Music.duck(true)
	var title := "ACE DOWN - TAKE ALL THREE" if take_all else "CLEARED - PICK ONE"
	screens.show_picks(title, cards, func(id: String) -> void:
		var completed: Array = []
		for card: Dictionary in cards:
			if take_all or card.id == id:
				completed.append_array(RunUpgrades.apply(card.id, mission))
		mission.hud.show_upgrades(RunUpgrades.held_names(mission))
		Music.duck(false)
		get_tree().paused = false
		if not completed.is_empty():
			screens.show_banner(tr("COMBO: %s") % " + ".join(completed.map(func(combo: Dictionary) -> String: return tr(combo.name))))
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
		tr("Stretch %d / %d") % [director.stretch + 1, stretch_count],
		tr("Kills %d     Score %d") % [mission.guns.kills, mission.score],
		tr("Best chain %d") % best_chain,
	]
	screens.show_end(title, lines, start_run, func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file(MENU))


func _on_targets_changed(left: int, total: int) -> void:
	var fell := left < targets_left
	targets_left = left
	targets_total = total
	update_title()
	if fell and left == 0:
		screens.show_banner("TARGETS DOWN")


func update_title() -> void:
	var text := tr("STRETCH %d / %d") % [director.stretch + 1, stretch_count]
	if targets_total > 0:
		text += "    " + tr("TARGETS %d / %d") % [targets_total - targets_left, targets_total]
	mission.hud.title_label.text = text


func _on_arena_started(_index: int) -> void:
	screens.hide_go()
	Music.play("final_arena" if director.is_last_stretch() else "arena")
	if director.boss != null:
		screens.show_banner("FORTRESS")
		screens.show_boss_bar("FORTRESS")
	elif director.has_ace():
		screens.show_banner("ACE INBOUND")
	else:
		screens.show_banner("DESTROY THE TARGETS" if targets_total > 0 else "INTERCEPT")


func _on_boss_built(fortress: Fortress) -> void:
	fortress.health_changed.connect(screens.set_boss_health)
	fortress.phase_changed.connect(func(phase: int) -> void:
		screens.show_banner("KEEP EXPOSED" if phase >= 3 else "ALL GUNS FIRING"))
	fortress.defeated.connect(func() -> void:
		screens.hide_boss_bar()
		screens.show_banner("FORTRESS DOWN"))
