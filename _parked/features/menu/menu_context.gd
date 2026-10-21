class_name MenuContext
extends Node

## The main menu. Shows records and options (MainMenu) and asks the root
## context to open the map, the hangar or the test range, or to quit.
##
## Options picked here are written into GameSettings before leaving; the
## root applies and saves them when settings_changed is emitted.

signal request_map
signal request_hangar
signal request_test_range
signal request_quit
signal settings_changed

@export var main_menu: MainMenu

var services: GameServices


## Called by the root context before the menu enters the tree.
func bind(game_services: GameServices) -> void:
	services = game_services


func _ready() -> void:
	if services == null:
		# Run directly from the editor.
		services = GameServices.create_default()

	main_menu.initialize(services.profile, services.campaign, services.settings, services.config.difficulty_presets)
	main_menu.play_pressed.connect(_leave.bind(request_map))
	main_menu.hangar_pressed.connect(_leave.bind(request_hangar))
	main_menu.test_range_pressed.connect(_leave.bind(request_test_range))
	main_menu.quit_pressed.connect(request_quit.emit)


## Keeps the chosen options, then asks for the next screen.
func _leave(request: Signal) -> void:
	main_menu.write_settings(services.settings)
	settings_changed.emit()
	request.emit()
