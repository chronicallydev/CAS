class_name Scrap
extends Node3D

# Salvage (an upgrade, see RunUpgrades): a piece of scrap left where a wreck
# came down. Flying over it patches hull. It doesn't last: it blinks near
# the end and is gone.

const REPAIR := 6.0
const LIFETIME := 12.0
# Ground distance from the point the helicopter appears over that picks it
# up (Helicopter.ground_under).
const PICKUP := 6.0

const P := preload("res://shared/props/prop_builder.gd")

var mission: MissionContext
var age: float = 0.0
var piece: Node3D


## Drops scrap at `at` with probability `chance`.
static func drop(at: Vector3, mission_context: MissionContext, chance: float) -> void:
	if mission_context == null or randf() > chance:
		return
	var scrap := Scrap.new()
	scrap.mission = mission_context
	mission_context.world.add_child.call_deferred(scrap)
	scrap.position = Vector3(at.x, 0.4, at.z)


func _ready() -> void:
	piece = Node3D.new()
	add_child(piece)
	# A white crate with a black rim and a cross on it, so it reads as a
	# pickup in 1-bit.
	P.box(piece, Vector3(1.6, 1.0, 1.6), Vector3.ZERO, OneBit.solid(Color.WHITE))
	P.box(piece, Vector3(1.7, 0.2, 0.4), Vector3(0, 0.52, 0), OneBit.solid(Color.BLACK))
	P.box(piece, Vector3(0.4, 0.2, 1.7), Vector3(0, 0.52, 0), OneBit.solid(Color.BLACK))
	OneBit.rim(piece, Color.BLACK, 0.3)


func _physics_process(delta: float) -> void:
	age += delta
	piece.position.y = 0.6 + sin(age * 4.0) * 0.25
	piece.rotation.y += delta * 2.0
	if age > LIFETIME - 3.0:
		visible = fmod(age, 0.3) < 0.2
	if age >= LIFETIME:
		queue_free()
		return
	var heli := mission.helicopter if mission != null else null
	if heli == null or heli.dead:
		return
	# Measured from where the helicopter appears over the ground (the view
	# is tilted), so flying "over" it on screen picks it up.
	var under := heli.ground_under()
	if Vector2(under.x - global_position.x, under.z - global_position.z).length() <= PICKUP:
		heli.repair(REPAIR)
		mission.hud.spawn_popup("+%d HULL" % REPAIR, global_position, Color.WHITE)
		Sfx.play_2d("ui_click", 0.0, 1.4)
		queue_free()
