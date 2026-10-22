class_name MissileWarning
extends Control

# A chevron round the helicopter for every missile homing on it, pointing
# at the missile, so a shot from off to the side is seen before it lands.
# It blinks faster as the missile closes, and goes solid in the player's
# colour once a perfect dodge would catch it: the cue to dash. Missiles
# that can't be sent back (the heavy rocket) keep their own colour and
# never give the cue. Colours come from OneBit.ROLES.

# Distance from the helicopter to the chevrons, and their size (canvas units).
const RADIUS := 90.0
const SIZE := 26.0
# Blink period (seconds) is this fraction of the time to impact, kept
# within these bounds.
const BLINK_SHARE := 0.25
const BLINK_RANGE := Vector2(0.07, 0.45)
# Missiles further out than this (seconds to impact) get no chevron yet.
const MAX_LEAD := 4.0

var helicopter: Helicopter


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not is_instance_valid(helicopter) or helicopter.dead:
		return
	var center := camera.unproject_position(helicopter.global_position)
	var now := Time.get_ticks_msec() / 1000.0
	var window := ChainDodge.perfect_window
	for missile in get_tree().get_nodes_in_group("aa_missiles"):
		if missile.target != helicopter or missile.deflected or missile.lost or missile.harmless:
			continue
		var offset: Vector3 = missile.global_position - helicopter.global_position
		var closing: float = maxf((missile.velocity - helicopter.velocity).dot(-offset.normalized()), 1.0)
		var impact := maxf(offset.length() - missile.hit_radius, 0.0) / closing
		if impact > MAX_LEAD:
			continue
		var on_screen := camera.unproject_position(missile.global_position) - center
		if on_screen.length() < 1.0:
			continue
		var direction := on_screen.normalized()
		var cue: bool = missile.deflectable and missile.ignited and impact <= window
		if not cue:
			var period := clampf(impact * BLINK_SHARE, BLINK_RANGE.x, BLINK_RANGE.y)
			if fmod(now, period) > period * 0.6:
				continue
		var role: String = "player_fire" if cue else missile.body_role
		draw_chevron(center + direction * RADIUS, direction, OneBit.fill(role), OneBit.rim_color(role), 1.3 if cue else 1.0)


# A solid arrowhead pointing along `direction`, with a rim.
func draw_chevron(at: Vector2, direction: Vector2, fill: Color, rim: Color, size_scale: float) -> void:
	var side := direction.orthogonal()
	var size := SIZE * size_scale
	var points := PackedVector2Array([
		at + direction * size,
		at - direction * size * 0.4 + side * size * 0.8,
		at - direction * size * 0.1,
		at - direction * size * 0.4 - side * size * 0.8,
	])
	var outline := points.duplicate()
	outline.append(points[0])
	draw_colored_polygon(points, fill)
	draw_polyline(outline, rim, 6.0)
