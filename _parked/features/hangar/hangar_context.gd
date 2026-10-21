class_name HangarContext
extends Node

## The hangar: buy and upgrade helicopters and weapons.
##
## Connects the UI (HangarUI) to the 3D preview (HangarWorld), saves after
## every purchase, and asks the root context to go back to the menu or on
## to the campaign map.

signal request_menu
signal request_map

@export var world: HangarWorld
@export var ui: HangarUI

var services: GameServices


## Called by the root context before the hangar enters the tree.
func bind(game_services: GameServices) -> void:
	services = game_services


func _ready() -> void:
	if services == null:
		# Run directly from the editor.
		services = GameServices.create_default()

	ui.heli_viewed.connect(world.show_heli)
	ui.purchase_made.connect(services.save)
	ui.back_pressed.connect(request_menu.emit)
	ui.deploy_pressed.connect(request_map.emit)
	ui.initialize(services.loadout)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		request_menu.emit()
