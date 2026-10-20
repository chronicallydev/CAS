extends RefCounted

# Short-lived effects for the helicopter's moves: dash afterimages and the
# dust ring kicked up by a low dash or a slam. Both fade out and free
# themselves; spawn them under MissionContext.spawn_parent so they pause
# and go away with the mission.

const GHOST_COLOR := Color(0.55, 0.85, 1.0, 0.45)
const DUST_COLOR := Color(0.82, 0.72, 0.52, 0.65)


# A see-through copy of `body` left where it is now, fading over `life`.
static func afterimage(body: Node3D, parent: Node, life: float = 0.22) -> void:
	var ghost := body.duplicate() as Node3D
	# One material for the whole copy, so it fades as one. Unshaded, so the
	# pixel-art pass leaves it alone.
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = GHOST_COLOR
	for node in ghost.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.material_override = material
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	parent.add_child(ghost)
	ghost.global_transform = body.global_transform
	var tween := ghost.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, life)
	tween.tween_callback(ghost.queue_free)


# A flat ring of dust on the ground that spreads to `radius` and fades.
static func dust_ring(parent: Node, at: Vector3, radius: float, life: float = 0.35) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 4

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = DUST_COLOR
	torus.material = material

	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = Vector3(at.x, 0.15, at.z)
	ring.scale = Vector3(1.0, 0.15, 1.0)

	var tween := ring.create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3(radius, 0.15, radius), life) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, life)
	tween.chain().tween_callback(ring.queue_free)
