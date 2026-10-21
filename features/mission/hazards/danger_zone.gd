extends Node3D

# A patch that is about to be hit: a square or rectangle whose fill grows
# over warning_time while its outline blinks faster, then it goes off.
# Either all at once (active_time 0, e.g. a mortar round), or it stays
# live for active_time, hurting every tick_interval (e.g. a flak barrage).
#
# The strike is at the helicopter's flight height: it takes damage if it
# is over the zone (in x/z) when it goes off. The camera looks down at an
# angle, though, so a marker drawn on the ground straight below would show
# up away from the helicopter on screen. Instead the marker is drawn where
# the zone at flight height lines up with the ground as the camera sees it
# (re-projected every frame as the camera moves), so the helicopter looks
# inside the marker exactly when it is. Enemies under the drawn marker are
# hit too, so the player can bait strikes onto them.
#
# Shared by every ground-strike attacker. Set it up, add it to the tree,
# then place it with global_position on the ground below the strike (and
# turn it with rotation.y; length runs along its -Z):
#   var zone := DangerZone.new()
#   zone.size = 8.0
#   zone.damage = 15.0
#   MissionContext.spawn_parent(self).add_child(zone)
#   zone.global_position = Vector3(x, ground_y, z)

# It went off (the start of the active time, if it has one).
signal detonated

# Width of the zone, in metres, and its length (0 = a square of `size`).
var size: float = 8.0
var length: float = 0.0
var warning_time: float = 1.5
# Seconds it stays live after going off, hurting every tick_interval.
# 0 = a single hit.
var active_time: float = 0.0
var tick_interval: float = 0.2
# Damage to the helicopter caught in it (per tick, if it stays live), and
# to each enemy under it when it goes off.
var damage: float = 15.0
var enemy_damage: float = 2.0
# Who caused it, for the test range's damage stats.
var source_name: String = "STRIKE"
# Spawned on the marker when it goes off (scale 1 = the full boom).
var explosion_scene: PackedScene
var explosion_scale: float = 1.0
# Fireball flash at flight height when it goes off (a single hit only).
var airburst: bool = true
# The helicopter counts as inside a little beyond the edge (its rotor).
var heli_margin: float = 1.0
# The fill's colour. In 1-bit, see-through black over the sand comes out as
# a darker dither that thickens as impact nears.
var color: Color = Color.BLACK

var time_left: float = 0.0
var active_left: float = 0.0
var tick_left: float = 0.0
var done: bool = false
# Height of the strike: the helicopter's flight height (set in _ready).
var strike_height: float = 0.0

# Everything drawn; moved and scaled to line up with the camera.
var marker: Node3D
var fill: MeshInstance3D
var fill_material: StandardMaterial3D
var outline_material: StandardMaterial3D


func _ready() -> void:
	if length <= 0.0:
		length = size
	time_left = warning_time
	var mission := MissionContext.of(self)
	if mission != null and mission.helicopter != null:
		strike_height = mission.helicopter.altitude
	build_visuals()
	update_marker.call_deferred()


func _process(_delta: float) -> void:
	update_marker()


func _physics_process(delta: float) -> void:
	if done:
		return

	if active_left > 0.0:
		active_left -= delta
		tick_left -= delta
		if tick_left <= 0.0:
			tick_left += tick_interval
			hurt_helicopter()
		# Live: the fill flickers.
		fill_material.albedo_color.a = randf_range(0.3, 0.5)
		if active_left <= 0.0:
			finish()
		return

	time_left -= delta
	var progress := clampf(1.0 - time_left / maxf(warning_time, 0.01), 0.0, 1.0)

	# The fill grows toward the edges as impact nears.
	var grow := lerpf(0.15, 1.0, ease(progress, 0.6))
	fill.scale = Vector3(grow, 1.0, grow)
	fill_material.albedo_color.a = lerpf(0.15, 0.4, progress)

	# Outline blinks black and white, faster and faster, solid black for the
	# last moment. Swapping colours reads on bright sand and dark ground.
	var rate := lerpf(2.5, 12.0, progress)
	var lit := time_left < 0.25 or fmod(progress * warning_time * rate, 1.0) < 0.6
	outline_material.albedo_color = Color.BLACK if lit else Color.WHITE

	if time_left <= 0.0:
		detonate()


# The centre of the strike, at flight height.
func strike_point() -> Vector3:
	return Vector3(global_position.x, strike_height, global_position.z)


# A random spot inside the zone at flight height (for flak bursts and the
# like).
func random_point() -> Vector3:
	var local := Vector3(randf_range(-0.5, 0.5) * size, 0.0, randf_range(-0.5, 0.5) * length)
	return strike_point() + global_basis * local


# Where the drawn marker sits on the ground.
func marker_position() -> Vector3:
	return marker.global_position if marker != null else global_position


# Puts the marker where the camera sees the strike zone meet the ground,
# scaled so it covers the same part of the screen.
func update_marker() -> void:
	if marker == null:
		return
	var ground := global_position
	marker.global_position = ground
	marker.scale = Vector3.ONE
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	var strike := strike_point()

	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		# Parallel sight lines: slide along the view direction, same size.
		var forward := -camera.global_basis.z
		if forward.y > -0.01:
			return
		marker.global_position = strike + forward * ((ground.y - strike.y) / forward.y)
		return

	# Perspective: along the line from the eye, growing with distance.
	var eye := camera.global_position
	var ray := strike - eye
	if ray.y > -0.01 or eye.y <= ground.y:
		return
	var t := (ground.y - eye.y) / ray.y
	marker.global_position = eye + ray * t
	marker.scale = Vector3(t, 1.0, t)


# Inside the zone at flight height (x/z only).
func contains(point: Vector3, margin: float = 0.0) -> bool:
	var local := global_basis.inverse() * (point - global_position)
	return absf(local.x) <= size * 0.5 + margin and absf(local.z) <= length * 0.5 + margin


# Inside the drawn marker on the ground (for things on the ground).
func marker_contains(point: Vector3) -> bool:
	var local := marker.global_transform.affine_inverse() * point
	return absf(local.x) <= size * 0.5 and absf(local.z) <= length * 0.5


func hurt_helicopter() -> void:
	var mission := MissionContext.of(self)
	var heli: Helicopter = mission.helicopter if mission != null else null
	if heli != null and not heli.dead and contains(heli.global_position, heli_margin):
		heli.take_damage(damage, source_name)


func detonate() -> void:
	update_marker()
	fill.scale = Vector3.ONE

	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or enemy.is_queued_for_deletion() or not marker_contains(enemy.global_position):
			continue
		if enemy.has_method("set_last_hit"):
			enemy.set_last_hit(marker_position(), enemy_damage / 4.0, false)
		enemy.take_damage(enemy_damage)

	if explosion_scene != null and get_parent() != null:
		var explosion := explosion_scene.instantiate() as Node3D
		get_parent().add_child(explosion)
		explosion.global_position = marker_position()
		explosion.scale = Vector3.ONE * explosion_scale

	detonated.emit()

	if active_time > 0.0:
		# Stays live; the first tick lands at once.
		active_left = active_time
		tick_left = 0.0
		outline_material.albedo_color = Color.BLACK
		return

	hurt_helicopter()
	if airburst:
		spawn_airburst()
	finish()


# Flashes white and dithers away; the outline goes white with it.
func finish() -> void:
	done = true
	fill_material.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	outline_material.albedo_color = Color.WHITE
	var fade := create_tween()
	fade.tween_property(fill_material, "albedo_color:a", 0.0, 0.4)
	fade.tween_callback(queue_free)


# A fireball flash at flight height, right where the helicopter would be
# hit; from the camera it sits over the marker.
func spawn_airburst() -> void:
	var radius := minf(size, length) * 0.4
	# 1-bit: a solid white ball with a black rim that swells, then pops.
	var burst := MeshInstance3D.new()
	burst.mesh = OneBit.puff(Color.WHITE, Color.BLACK, 1.0, 0.15)
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.scale = Vector3.ONE * 0.4 * radius
	add_child(burst)
	burst.global_position = strike_point()

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.4)
	light.omni_range = radius * 6.0
	light.light_energy = 6.0
	add_child(light)
	light.global_position = strike_point()

	var fade := create_tween().set_parallel()
	fade.tween_property(burst, "scale", Vector3.ONE * 1.2 * radius, 0.3).set_ease(Tween.EASE_OUT)
	fade.tween_property(light, "light_energy", 0.0, 0.35)
	fade.chain().tween_callback(burst.queue_free)


func build_visuals() -> void:
	marker = Node3D.new()
	add_child(marker)

	# Drawn just above the ground, unshaded so it reads in any light.
	fill_material = StandardMaterial3D.new()
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_material.albedo_color = Color(color.r, color.g, color.b, 0.15)
	fill_material.render_priority = 1

	# Solid, so it stays pure black or white through the palette pass.
	outline_material = OneBit.solid(Color.BLACK)
	outline_material.render_priority = 2

	fill = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, length)
	plane.material = fill_material
	fill.mesh = plane
	fill.position.y = 0.08
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(fill)

	# Four edges and a small centre cross.
	# At least a low-res pixel wide (about 0.5 m at the default zoom).
	var edge := 0.6
	var half_w := size * 0.5
	var half_l := length * 0.5
	add_bar(Vector3(0, 0, -half_l), Vector3(size + edge, 0.06, edge))
	add_bar(Vector3(0, 0, half_l), Vector3(size + edge, 0.06, edge))
	add_bar(Vector3(-half_w, 0, 0), Vector3(edge, 0.06, length + edge))
	add_bar(Vector3(half_w, 0, 0), Vector3(edge, 0.06, length + edge))
	var cross := minf(size, length) * 0.25
	add_bar(Vector3.ZERO, Vector3(cross, 0.06, edge * 0.6))
	add_bar(Vector3.ZERO, Vector3(edge * 0.6, 0.06, cross))


func add_bar(at: Vector3, bar_size: Vector3) -> void:
	var bar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = bar_size
	box.material = outline_material
	bar.mesh = box
	bar.position = at + Vector3(0, 0.1, 0)
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(bar)
