extends Node

const MENU_SCENE := "res://scenes/menu/menu.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const SETTINGS_PATH := "user://settings.cfg"

# Settings chosen in the menu. use_menu_settings stays false until the menu
# starts a game, so running main.tscn directly keeps the Inspector values.
var use_menu_settings: bool = false
var difficulty: int = 1 # EnemyGenerator.Difficulty, 1 = NORMAL
var infantry_enabled: bool = true
var car_enabled: bool = true
var tank_enabled: bool = true
var starting_level: int = 0


func _ready() -> void:
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
	get_tree().change_scene_to_file(GAME_SCENE)


func go_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("game", "difficulty", difficulty)
	config.set_value("game", "infantry_enabled", infantry_enabled)
	config.set_value("game", "car_enabled", car_enabled)
	config.set_value("game", "tank_enabled", tank_enabled)
	config.set_value("game", "starting_level", starting_level)
	config.save(SETTINGS_PATH)


func load_settings() -> void:
	var config := ConfigFile.new()

	if config.load(SETTINGS_PATH) != OK:
		return

	difficulty = config.get_value("game", "difficulty", difficulty)
	infantry_enabled = config.get_value("game", "infantry_enabled", infantry_enabled)
	car_enabled = config.get_value("game", "car_enabled", car_enabled)
	tank_enabled = config.get_value("game", "tank_enabled", tank_enabled)
	starting_level = config.get_value("game", "starting_level", starting_level)
