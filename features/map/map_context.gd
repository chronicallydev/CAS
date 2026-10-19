class_name MapContext
extends Node

## The campaign map: pick a rig, upgrade owned rigs, launch a mission.
##
## Builds the 3D map (MapWorld) and its UI (MapUI), saves after rig
## upgrades, and asks the root context to fly a mission or switch screens.

signal request_menu
signal request_hangar
signal request_mission(rig_id: String)

@export var world: MapWorld
@export var ui: MapUI

var services: GameServices
var _last_rig: String = ""


## Called by the root context before the map enters the tree. `last_rig`
## is the rig of the last mission flown, selected first.
func bind(game_services: GameServices, last_rig: String) -> void:
	services = game_services
	_last_rig = last_rig


func _ready() -> void:
	if services == null:
		# Run directly from the editor.
		services = GameServices.create_default()

	world.initialize(services.campaign)
	var loadout := services.loadout
	var armed := not loadout.mounted_types(loadout.selected_heli().id).is_empty()
	ui.initialize(services.campaign, world, _last_rig, armed)
	ui.upgrade_bought.connect(services.save)
	ui.mission_requested.connect(request_mission.emit)
	ui.menu_pressed.connect(request_menu.emit)
	ui.hangar_pressed.connect(request_hangar.emit)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		request_menu.emit()
