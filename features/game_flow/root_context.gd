class_name RootContext
extends Node

## The game's top-level node (root.tscn, the main scene).
##
## It owns the long-lived services (GameServices: profile, settings, save,
## loadout and campaign rules) and shows exactly one child context at a
## time: the main menu, the hangar, the campaign map, a mission or the test
## range.
##
## Contexts never switch screens themselves. They emit request signals and
## the root decides what to open next, so each context only knows about its
## own job. Every context follows the same lifecycle:
##
##   1. instantiate its scene
##   2. bind(services, ...)   - hand it what it needs, before it enters the tree
##   3. add_child(context)    - its _ready() builds and wires its own nodes
##   4. connect its request_* signals here

@export var config: GameConfig

@export_group("Contexts")
@export var menu_scene: PackedScene
@export var hangar_scene: PackedScene
@export var map_scene: PackedScene
@export var mission_scene: PackedScene
@export var test_range_scene: PackedScene

var _services: GameServices
var _current: Node
## The rig of the last mission flown ("" for free play), for retries and to
## pre-select it on the map.
var _last_rig: String = ""


func _ready() -> void:
	_services = GameServices.create(config)
	_apply_settings()
	open_menu()


# --- Contexts ----------------------------------------------------------------

func open_menu() -> void:
	var menu := _instantiate(menu_scene) as MenuContext
	menu.bind(_services)
	_show(menu)
	menu.request_map.connect(open_map)
	menu.request_hangar.connect(open_hangar)
	menu.request_test_range.connect(open_test_range)
	menu.request_quit.connect(get_tree().quit)
	menu.settings_changed.connect(_on_settings_changed)


func open_hangar() -> void:
	var hangar := _instantiate(hangar_scene) as HangarContext
	hangar.bind(_services)
	_show(hangar)
	hangar.request_menu.connect(open_menu)
	hangar.request_map.connect(open_map)


func open_map() -> void:
	var map := _instantiate(map_scene) as MapContext
	map.bind(_services, _last_rig)
	_show(map)
	map.request_menu.connect(open_menu)
	map.request_hangar.connect(open_hangar)
	map.request_mission.connect(open_mission)


## Flies a mission at `rig_id` (assault if enemy-held, defence if owned).
## An empty id starts a free-play defence with no campaign rig.
func open_mission(rig_id: String) -> void:
	_last_rig = rig_id
	var mission := _instantiate(mission_scene) as MissionContext
	mission.bind(_services, rig_id)
	_show(mission)
	mission.request_menu.connect(open_menu)
	mission.request_map.connect(open_map)
	mission.request_hangar.connect(open_hangar)
	mission.request_retry.connect(open_mission.bind(rig_id))


## The sandbox for trying units. It works on a throwaway copy of the
## services, so nothing done there is saved.
func open_test_range() -> void:
	var test_range := _instantiate(test_range_scene) as TestRangeContext
	test_range.bind(_services)
	_show(test_range)
	test_range.request_menu.connect(open_menu)


# --- Helpers -----------------------------------------------------------------

func _instantiate(scene: PackedScene) -> Node:
	return scene.instantiate()


## Replaces the current context with `context`.
func _show(context: Node) -> void:
	# A mission may have left the game paused or slowed (game over, hit-stop).
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	if _current != null:
		# Removed now (not just queued) so two contexts never overlap for a
		# frame: no doubled cameras, input or audio.
		remove_child(_current)
		_current.queue_free()
	_current = context
	add_child(context)


func _on_settings_changed() -> void:
	_apply_settings()
	_services.save()


## Settings that affect services outside any context.
func _apply_settings() -> void:
	PixelArt.enabled = _services.settings.pixel_art
