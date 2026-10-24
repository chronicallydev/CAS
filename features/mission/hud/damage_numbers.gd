class_name DamageNumbers
extends Control

# Damage numbers flying out of whatever the guns hit, one per hit, so held
# fire visibly chews into a target instead of soaking in. Each pops out of
# the target big, arcs up and to the side, falls and shrinks away. White
# with a solid black drop shadow (a soft outline or a fade would dither at
# the HUD's pixel size); the killing hit's number is bigger and red with
# a colour palette.

# How long a number flies (seconds), how fast it leaves (canvas units per
# second: up, and either way sideways) and how hard it falls back.
const LIFE := 0.6
const RISE := Vector2(260.0, 380.0)
const SPREAD := 220.0
const FALL := 900.0
# Height (metres) over the target the numbers start from: below its bar.
const LIFT := 0.5
const FONT_SIZE := 20


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A number for `amount` damage dealt to `target`; `killed` if it was the
## killing hit.
func add(target: Node3D, amount: float, killed: bool) -> void:
	if amount <= 0.0:
		return
	var label := Label.new()
	label.text = str(maxi(roundi(amount), 1))
	label.add_theme_font_size_override("font_size", UiStyle.px(FONT_SIZE * (2 if killed else 1)))
	label.add_theme_color_override("font_color", Color.WHITE if not killed or OneBit.mono() else OneBit.colour("red"))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	var shadow := roundi(PixelArt.ui_pixel_units())
	label.add_theme_constant_override("shadow_offset_x", shadow)
	label.add_theme_constant_override("shadow_offset_y", shadow)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.reset_size()
	label.pivot_offset = label.size * 0.5

	var anchor := target.global_position + Vector3.UP * LIFT
	var velocity := Vector2(randf_range(-SPREAD, SPREAD), -randf_range(RISE.x, RISE.y))
	var fly := func(t: float) -> void:
		var camera := get_viewport().get_camera_3d()
		if camera == null or not is_instance_valid(label):
			return
		var drift := velocity * t + Vector2(0.0, FALL * t * t * 0.5)
		label.position = camera.unproject_position(anchor) + drift - label.size * 0.5
	fly.call(0.0)

	label.scale = Vector2.ONE * 1.6
	var tween := label.create_tween().set_parallel()
	tween.tween_method(fly, 0.0, LIFE, LIFE)
	tween.tween_property(label, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ZERO, LIFE * 0.25).set_delay(LIFE * 0.75)
	tween.chain().tween_callback(label.queue_free)
