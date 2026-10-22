class_name TargetMarker
extends Node3D

# A white down-arrow with a black rim, bobbing and turning over something
# that has to be destroyed, so it reads in 1-bit on any ground. It lives
# beside its target rather than under it (wrecks copy an enemy's children,
# and hit flashes recolour them), follows it, and frees itself once the
# target is gone: freed, collapsed (a Building) or out of "enemies".

const P := preload("res://shared/props/prop_builder.gd")

var target: Node3D
# Metres above the target's origin.
var height: float = 6.0
var time: float = 0.0


## Puts a marker `height` above `node`, unless it already has one.
static func follow(node: Node3D, marker_height: float) -> TargetMarker:
	if node.has_meta("target_marker"):
		return null
	var marker := TargetMarker.new()
	marker.target = node
	marker.height = marker_height
	node.set_meta("target_marker", true)
	# Deferred: callers may be mid-_ready inside the tree it joins.
	MissionContext.spawn_parent(node).add_child.call_deferred(marker)
	return marker


func _ready() -> void:
	var arrow := CylinderMesh.new()
	arrow.top_radius = 1.6
	arrow.bottom_radius = 0.0
	arrow.height = 2.6
	arrow.radial_segments = 4
	arrow.rings = 1
	P.add_mesh(self, arrow, Vector3.ZERO, OneBit.solid(Color.WHITE))
	OneBit.rim(self, Color.BLACK, 0.45)
	time = randf() * TAU
	place()


func _process(delta: float) -> void:
	time += delta
	if not target_alive():
		queue_free()
		return
	place()


func place() -> void:
	global_position = target.global_position + Vector3(0, height + sin(time * 3.0) * 0.6, 0)
	rotation = Vector3(0, time * 1.5, 0)


func target_alive() -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	if target is Building:
		return target.stage != Building.Stage.COLLAPSED
	return target.is_in_group("enemies")
