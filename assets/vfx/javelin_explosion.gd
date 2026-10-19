extends Node3D

# Large layered explosion for the Javelin: flash, light, shockwave ring,
# fireball, sparks, debris and a rising smoke column. Built in code and
# frees itself when finished.

@export var size: float = 1.0
@export var lifetime: float = 5.0


func _ready() -> void:
	var soft_texture := make_soft_texture()

	add_light()
	add_flash()
	add_shockwave()
	add_fireball(soft_texture)
	add_sparks()
	add_debris()
	add_smoke(soft_texture)

	# Louder and deeper than a normal explosion.
	Sfx.play_3d("explosion", position, 4.0, 0.8)
	Global.shake(0.5, position)

	await get_tree().create_timer(lifetime).timeout
	queue_free()


# Round white blob that fades to transparent at the edges.
func make_soft_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.4, Color(1, 1, 1, 0.8))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


func make_billboard_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.no_depth_test = false
	return material


func make_curve(points: Array) -> Curve:
	var curve := Curve.new()
	curve.max_value = 3.0
	for point in points:
		curve.add_point(point)
	return curve


func make_ramp(offsets: Array, colors: Array) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	return gradient


func make_burst(amount: int, particle_lifetime: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = particle_lifetime
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.local_coords = false
	# Effects should not cast shadows (they show up as dark streaks).
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	return particles


func add_light() -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 16.0
	light.omni_range = 30.0 * size
	light.position = Vector3(0, 2.0 * size, 0)
	add_child(light)

	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)


func add_flash() -> void:
	var flash := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.85, 0.45, 0.9)
	mesh.material = material
	flash.mesh = mesh
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.scale = Vector3.ONE * 0.5 * size
	add_child(flash)

	var tween := create_tween().set_parallel()
	tween.tween_property(flash, "scale", Vector3.ONE * 9.0 * size, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(flash.queue_free)


func add_shockwave() -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.9
	mesh.outer_radius = 1.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.55, 0.45, 0.35, 0.6)
	mesh.material = material
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0, 0.3, 0)
	ring.scale = Vector3(1, 0.2, 1) * size
	add_child(ring)

	var tween := create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3(18.0, 1.0, 18.0) * size, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.7)
	tween.chain().tween_callback(ring.queue_free)


func add_fireball(texture: Texture2D) -> void:
	var fire := make_burst(90, 1.6)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(6.0, 6.0) * size
	mesh.material = make_billboard_material(texture)
	fire.mesh = mesh
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 2.5 * size
	fire.direction = Vector3.UP
	fire.spread = 90.0
	fire.initial_velocity_min = 8.0 * size
	fire.initial_velocity_max = 22.0 * size
	fire.gravity = Vector3(0, 3.0, 0)
	fire.damping_min = 10.0
	fire.damping_max = 16.0
	fire.scale_amount_min = 0.8
	fire.scale_amount_max = 1.8
	fire.scale_amount_curve = make_curve([Vector2(0, 0.4), Vector2(0.2, 1.0), Vector2(1, 1.4)])
	fire.angle_min = 0.0
	fire.angle_max = 360.0
	fire.color_ramp = make_ramp(
		[0.0, 0.1, 0.35, 0.7, 1.0],
		[
			Color(1.0, 0.95, 0.6, 1.0),
			Color(1.0, 0.8, 0.3, 1.0),
			Color(1.0, 0.4, 0.1, 0.9),
			Color(0.75, 0.3, 0.12, 0.5),
			Color(0.55, 0.4, 0.35, 0.0),
		]
	)
	fire.emitting = true


func add_sparks() -> void:
	var sparks := make_burst(120, 1.5)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.25, 2.0, 0.25) * size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	sparks.mesh = mesh
	sparks.particle_flag_align_y = true
	sparks.direction = Vector3.UP
	sparks.spread = 75.0
	sparks.initial_velocity_min = 20.0 * size
	sparks.initial_velocity_max = 40.0 * size
	sparks.gravity = Vector3(0, -25.0, 0)
	sparks.damping_min = 1.0
	sparks.damping_max = 2.0
	sparks.scale_amount_curve = make_curve([Vector2(0, 1.0), Vector2(1, 0.0)])
	sparks.color_ramp = make_ramp(
		[0.0, 0.5, 1.0],
		[Color(1.0, 1.0, 0.7), Color(1.0, 0.6, 0.15), Color(0.8, 0.2, 0.05)]
	)
	sparks.emitting = true


func add_debris() -> void:
	var debris := make_burst(40, 2.5)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.9, 0.6, 0.7) * size
	var material := StandardMaterial3D.new()
	# Hot embers that cool from bright orange to warm brown.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	debris.color_ramp = make_ramp(
		[0.0, 0.4, 1.0],
		[Color(1.0, 0.75, 0.3), Color(0.95, 0.45, 0.15), Color(0.6, 0.35, 0.2)]
	)
	debris.mesh = mesh
	debris.direction = Vector3.UP
	debris.spread = 60.0
	debris.initial_velocity_min = 10.0 * size
	debris.initial_velocity_max = 22.0 * size
	debris.gravity = Vector3(0, -30.0, 0)
	debris.angular_velocity_min = -540.0
	debris.angular_velocity_max = 540.0
	debris.scale_amount_min = 0.6
	debris.scale_amount_max = 1.6
	debris.emitting = true


func add_smoke(texture: Texture2D) -> void:
	var smoke := make_burst(60, 4.5)
	smoke.explosiveness = 0.85
	var mesh := QuadMesh.new()
	mesh.size = Vector2(7.0, 7.0) * size
	mesh.material = make_billboard_material(texture)
	smoke.mesh = mesh
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 3.5 * size
	smoke.direction = Vector3.UP
	smoke.spread = 35.0
	smoke.initial_velocity_min = 4.0 * size
	smoke.initial_velocity_max = 10.0 * size
	smoke.gravity = Vector3(0, 1.5, 0)
	smoke.damping_min = 1.5
	smoke.damping_max = 2.5
	smoke.angle_min = 0.0
	smoke.angle_max = 360.0
	smoke.angular_velocity_min = -30.0
	smoke.angular_velocity_max = 30.0
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 1.6
	smoke.scale_amount_curve = make_curve([Vector2(0, 0.6), Vector2(1, 3.0)])
	smoke.color_ramp = make_ramp(
		[0.0, 0.15, 0.6, 1.0],
		[
			Color(0.45, 0.38, 0.33, 0.0),
			Color(0.42, 0.38, 0.35, 0.75),
			Color(0.35, 0.34, 0.33, 0.45),
			Color(0.5, 0.5, 0.5, 0.0),
		]
	)
	smoke.emitting = true
