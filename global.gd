extends Node

const MENU_SCENE := "res://scenes/menu/menu.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const SETTINGS_PATH := "user://settings.cfg"
const HANGAR_SCENE := "res://scenes/hangar/hangar.tscn"
# Money a new player starts with.
const STARTING_MONEY := 1500

# Settings chosen in the menu. use_menu_settings stays false until the menu
# starts a game, so running main.tscn directly keeps the Inspector values.
var use_menu_settings: bool = false
var difficulty: int = 1 # EnemyGenerator.Difficulty, 1 = NORMAL
var infantry_enabled: bool = true
var car_enabled: bool = true
var tank_enabled: bool = true
var aa_enabled: bool = true
var starting_level: int = 0
# Pixel-art rendering (see scenes/pixelart/pixel_art.gd).
var pixel_art: bool = true
# Stylised blood on infantry deaths.
var blood: bool = true

# Current run.
var score: int = 0
var wave: int = 0
var is_game_over: bool = false

# Saved records.
var best_score: int = 0
var best_wave: int = 0

# Hangar: money from runs, bought helicopters and upgrade levels.
var money: int = STARTING_MONEY
var owned_helis: Array = ["cobra"]
var selected_heli: String = "cobra"
var upgrades: Dictionary = {}
# Money earned by the last finished run (shown on the game-over screen).
var last_earned: int = 0


func _ready() -> void:
	# Keep handling Esc and game over while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()


func _unhandled_input(event: InputEvent) -> void:
	# Esc during a game returns to the menu.
	if event.is_action_pressed("ui_cancel") and is_in_game():
		go_to_menu()


func is_in_game() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == GAME_SCENE


func start_game() -> void:
	use_menu_settings = true
	save_settings()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(GAME_SCENE)


func go_to_hangar() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(HANGAR_SCENE)


func go_to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	is_game_over = false
	get_tree().change_scene_to_file(MENU_SCENE)


func retry() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	is_game_over = false
	get_tree().reload_current_scene()


# Shake the game camera. With a position, the shake fades out for things
# far from the centre of the view.
func shake(amount: float, at: Variant = null) -> void:
	var camera := get_tree().get_first_node_in_group("game_camera")

	if camera == null:
		return

	if at is Vector3:
		var distance: float = Vector2(at.x, at.z).distance_to(Vector2(camera.get_focus().x, camera.get_focus().z))
		amount *= clampf(1.0 - distance / 70.0, 0.2, 1.0)

	camera.add_trauma(amount)


var hit_stop_active: bool = false


# Freeze the game for a moment (real time), for impact.
func hit_stop(seconds: float) -> void:
	if hit_stop_active or get_tree().paused:
		return
	hit_stop_active = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	hit_stop_active = false


func reset_run() -> void:
	score = 0
	wave = 0
	is_game_over = false


func add_score(points: int) -> void:
	if not is_game_over:
		score += points


# Ends the run: records bests, pauses the game and shows the game-over
# screen. Safe to call more than once.
func game_over(reason: String) -> void:
	if is_game_over:
		return
	is_game_over = true

	var new_best_score := score > best_score
	var new_best_wave := wave > best_wave
	best_score = maxi(best_score, score)
	best_wave = maxi(best_wave, wave)

	# The run's score is paid out as money for the hangar.
	last_earned = score
	money += score
	save_settings()

	var hud := get_tree().get_first_node_in_group("game_hud")

	if hud == null:
		retry()
		return

	get_tree().paused = true
	hud.show_game_over(reason, new_best_score, new_best_wave)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("game", "difficulty", difficulty)
	config.set_value("game", "infantry_enabled", infantry_enabled)
	config.set_value("game", "car_enabled", car_enabled)
	config.set_value("game", "tank_enabled", tank_enabled)
	config.set_value("game", "aa_enabled", aa_enabled)
	config.set_value("game", "starting_level", starting_level)
	config.set_value("graphics", "pixel_art", pixel_art)
	config.set_value("graphics", "blood", blood)
	config.set_value("records", "best_score", best_score)
	config.set_value("records", "best_wave", best_wave)
	config.set_value("hangar", "money", money)
	config.set_value("hangar", "owned_helis", owned_helis)
	config.set_value("hangar", "selected_heli", selected_heli)
	config.set_value("hangar", "upgrades", upgrades)
	config.save(SETTINGS_PATH)


func load_settings() -> void:
	var config := ConfigFile.new()

	if config.load(SETTINGS_PATH) != OK:
		return

	difficulty = config.get_value("game", "difficulty", difficulty)
	infantry_enabled = config.get_value("game", "infantry_enabled", infantry_enabled)
	car_enabled = config.get_value("game", "car_enabled", car_enabled)
	tank_enabled = config.get_value("game", "tank_enabled", tank_enabled)
	aa_enabled = config.get_value("game", "aa_enabled", aa_enabled)
	starting_level = config.get_value("game", "starting_level", starting_level)
	pixel_art = config.get_value("graphics", "pixel_art", pixel_art)
	blood = config.get_value("graphics", "blood", blood)
	best_score = config.get_value("records", "best_score", best_score)
	best_wave = config.get_value("records", "best_wave", best_wave)
	money = config.get_value("hangar", "money", money)
	owned_helis = config.get_value("hangar", "owned_helis", owned_helis)
	selected_heli = config.get_value("hangar", "selected_heli", selected_heli)
	upgrades = config.get_value("hangar", "upgrades", upgrades)
