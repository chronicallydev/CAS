class_name Fortress
extends Node3D

# The run's final boss (see DESIGN.md): a fortress filling the last arena,
# taken apart piece by piece in about 90 seconds. A keep stands in a ring
# of walls, with five weapon emplacements (fortress_part.gd) around it:
# two SAM batteries in front, two flak guns on the flanks, a heavy rocket
# rail behind. Every part is a marked target; deflected missiles home on
# them and hit hard, so chain dodging is the best way in.
#   phase 1 - SAM batteries take turns firing fans of missiles, spaced for
#             chaining perfect dodges; the flak guns fire bursts
#   phase 2 - two parts down: the keep adds rings of missiles, the rocket
#             rail starts firing, and two scouts fly in
#   phase 3 - every part down: the keep opens up (it can only be hurt now)
#             and fires spirals; scouts and riflemen pour out
# The keep coming down sets off explosions across the whole fortress,
# then defeated fires. One big attack at a time, picked in turn, keeps the
# missiles readable; the flak fires on its own clock.

signal health_changed(fraction: float)
signal phase_changed(phase: int)
signal defeated

const Missile := preload("res://features/mission/enemies/projectiles/aa_missile.gd")
const HeavyRocket := preload("res://features/mission/enemies/projectiles/heavy_rocket.gd")
const Tracer := preload("res://features/mission/enemies/projectiles/tank_shell.gd")
const JavelinExplosion := preload("res://features/mission/vfx/javelin_explosion.gd")
const EXPLOSION := preload("res://features/mission/vfx/explosion_scene.tscn")
const ScoutScene := preload("res://features/mission/enemies/enemy_scout.tscn")
const InfantryScene := preload("res://features/mission/enemies/infantry.tscn")
const P := preload("res://shared/props/prop_builder.gd")

# [weapon, position, footprint (x, z)] for each emplacement. +z faces the
# player, who comes in from the bottom of the screen.
const LAYOUT := [
	["sam", Vector3(-24.0, 0.0, 8.0), Vector2(8.0, 7.0)],
	["sam", Vector3(24.0, 0.0, 8.0), Vector2(8.0, 7.0)],
	["flak", Vector3(-30.0, 0.0, -10.0), Vector2(6.0, 6.0)],
	["flak", Vector3(30.0, 0.0, -10.0), Vector2(6.0, 6.0)],
	["heavy", Vector3(0.0, 0.0, -24.0), Vector2(9.0, 7.0)],
]

@export var part_health: float = 100.0
@export var keep_health: float = 240.0
# Seconds between big attacks, by phase.
@export var attack_gap: Array[float] = [5.0, 4.5, 4.0]
@export var missile_damage: float = 20.0
@export var flak_interval: float = 2.8
@export var flak_damage: float = 3.0
@export var ground_y: float = -0.408

var mission: MissionContext
var keep: Building
var parts: Array[FortressPart] = []
var phase: int = 1
var total_health: float = 0.0
var attack_timer: float = 3.0
# Which kind of big attack comes next (cycled).
var attack_turn: int = 0
var flak_timers: Dictionary = {}
var busy: bool = false
var down: bool = false
# Asleep until the run director starts its arena: it holds fire, and its
# parts and keep take no damage.
var active: bool = false:
	set(value):
		active = value
		for building: Building in parts + ([keep] if keep != null else []):
			building.dormant = not value


func _ready() -> void:
	mission = MissionContext.of(self)
	build_walls()
	keep = Building.make("hq", Vector2(20.0, 14.0), false)
	keep.size.y = 12.0
	keep.max_health = keep_health
	# Sealed until every emplacement is gone.
	keep.light_armor = 1.0
	keep.display_name = "KEEP"
	keep.score_value = 1000
	keep.occupants = 0
	keep.explosive = true
	keep.blast_radius = 26.0
	keep.ground_y = ground_y
	keep.position = Vector3(0, 0, -6.0)
	keep.dormant = not active
	add_child(keep)
	keep.destroyed.connect(func(_b: Building) -> void: finale())
	for entry in LAYOUT:
		var part := FortressPart.new()
		part.weapon = entry[0]
		part.size = Vector3(entry[2].x, 3.5, entry[2].y)
		part.max_health = part_health
		part.light_armor = 0.6
		part.score_value = 300
		part.occupants = 2
		part.ground_y = ground_y
		part.position = entry[1]
		part.dormant = not active
		add_child(part)
		parts.append(part)
		part.destroyed.connect(func(_b: Building) -> void: on_part_down())
	total_health = part_health * parts.size() + keep_health


# A low wall round the whole site, open at the front.
func build_walls() -> void:
	var stone := Building.material(Color(0.55, 0.52, 0.48))
	var y := ground_y + 1.0
	P.box(self, Vector3(78.0, 2.0, 1.4), Vector3(0, y, -32.0), stone)
	for side in [-1.0, 1.0]:
		P.box(self, Vector3(1.4, 2.0, 50.0), Vector3(side * 39.0, y, -7.0), stone)
		P.box(self, Vector3(24.0, 2.0, 1.4), Vector3(side * 27.0, y, 18.0), stone)
	# A dark courtyard under it all, so the site reads as one thing.
	P.box(self, Vector3(76.0, 0.05, 48.0), Vector3(0, ground_y + 0.02, -7.0), Building.material(Color(0.32, 0.3, 0.29))).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func standing_parts() -> Array:
	return parts.filter(func(p: FortressPart) -> bool: return p.stage != Building.Stage.COLLAPSED)


func health_fraction() -> float:
	var left := maxf(keep.health, 0.0)
	for part in parts:
		left += maxf(part.health, 0.0)
	return left / total_health


func helicopter() -> Helicopter:
	if mission == null or mission.helicopter == null or mission.helicopter.dead:
		return null
	return mission.helicopter


# --- Each frame ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if down or not active:
		return
	health_changed.emit(health_fraction())
	var heli := helicopter()
	if heli == null:
		return
	update_flak(delta)
	if busy:
		return
	attack_timer -= delta
	if attack_timer <= 0.0:
		big_attack()


func on_part_down() -> void:
	var left := standing_parts().size()
	if phase == 1 and left <= parts.size() - 2:
		set_phase(2)
	if left == 0:
		set_phase(3)


func set_phase(next: int) -> void:
	if next <= phase:
		return
	phase = next
	attack_timer = minf(attack_timer, 1.5)
	phase_changed.emit(phase)
	match phase:
		2:
			send_scouts(2)
		3:
			# The keep opens up: now it can be hurt, and it's marked.
			keep.light_armor = 0.5
			keep.target = true
			keep.add_to_group("deflect_targets")
			TargetMarker.follow(keep, keep.size.y + 6.0)
			send_scouts(2)
			send_riflemen(6)
			if mission != null:
				mission.shake(0.5, keep.global_position)
			Sfx.play_3d("base_hit", keep.global_position, 4.0)


# --- Attacks -------------------------------------------------------------------

# The next big attack this phase allows, taking turns: a SAM fan, then
# (from phase 2) a keep ring and a heavy rocket, then (phase 3) a spiral.
func big_attack() -> void:
	var options: Array[Callable] = []
	var sams := standing_parts().filter(func(p: FortressPart) -> bool: return p.weapon == "sam")
	var heavy := standing_parts().filter(func(p: FortressPart) -> bool: return p.weapon == "heavy")
	if not sams.is_empty():
		options.append(func() -> void: await fan(sams.pick_random(), 3 if phase == 1 else 4))
	if phase >= 2:
		options.append(func() -> void: await ring(6))
		if not heavy.is_empty():
			options.append(func() -> void: heavy_rocket(heavy[0]))
	if phase >= 3:
		options.append(func() -> void: await spiral(8))
	if options.is_empty():
		attack_timer = 1.0
		return
	var attack: Callable = options[attack_turn % options.size()]
	attack_turn += 1
	busy = true
	await attack.call()
	busy = false
	attack_timer = attack_gap[clampi(phase - 1, 0, attack_gap.size() - 1)]


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


# A fan of missiles from one battery, spread across the helicopter's
# side, one every 0.28 s: each arrives just after the last, for a chain.
func fan(part: FortressPart, count: int) -> void:
	var heli := helicopter()
	if heli == null:
		return
	var to_heli := heli.global_position - part.global_position
	to_heli.y = 0.0
	var base := atan2(to_heli.x, to_heli.z)
	for i in count:
		if down or not is_instance_valid(part) or part.stage == Building.Stage.COLLAPSED:
			return
		var angle := base + deg_to_rad(lerpf(-40.0, 40.0, float(i) / maxf(count - 1, 1)))
		var out := Vector3(sin(angle), 0.0, cos(angle))
		launch_missile(part.muzzle(), (out + Vector3.UP * 1.3).normalized())
		await wait(0.28)


# A ring of missiles out of the keep's roof, all round, a beat apart.
func ring(count: int) -> void:
	var top := keep.global_position + Vector3(0, keep.size.y + 1.0, 0)
	var start := randf() * TAU
	for i in count:
		if down:
			return
		var angle := start + TAU * i / count
		launch_missile(top, (Vector3(cos(angle), 0.0, sin(angle)) + Vector3.UP * 1.6).normalized())
		await wait(0.12)


# The exposed keep's last gasp: a long spiral, faster than the ring.
func spiral(count: int) -> void:
	var top := keep.global_position + Vector3(0, keep.size.y + 1.0, 0)
	var start := randf() * TAU
	for i in count:
		if down:
			return
		var angle := start + i * 0.9
		launch_missile(top, (Vector3(cos(angle), 0.0, sin(angle)) + Vector3.UP * 1.2).normalized())
		await wait(0.18)


func launch_missile(from: Vector3, direction: Vector3) -> void:
	var heli := helicopter()
	if heli == null:
		return
	var missile := Missile.new()
	missile.target = heli
	missile.damage = missile_damage
	missile.eject_speed = 12.0
	missile.eject_time = 0.55
	missile.lifetime = 8.0
	missile.explosion_scene = EXPLOSION
	missile.ground_y = ground_y
	missile.source_name = "FORTRESS"
	MissionContext.spawn_parent(self).add_child(missile)
	missile.launch(from, direction)


func heavy_rocket(part: FortressPart) -> void:
	var heli := helicopter()
	if heli == null:
		return
	var rocket := HeavyRocket.new()
	rocket.target = heli
	rocket.explosion_scene = EXPLOSION
	rocket.ground_y = ground_y
	MissionContext.spawn_parent(self).add_child(rocket)
	rocket.launch(part.muzzle(), (part.muzzle() - part.global_position).normalized() + Vector3.UP)


# Each flak gun fires a burst of rounds at the helicopter on its own clock.
func update_flak(delta: float) -> void:
	for part in standing_parts():
		if part.weapon != "flak":
			continue
		var left: float = flak_timers.get(part, randf_range(0.5, flak_interval)) - delta
		if left <= 0.0:
			left = flak_interval
			flak_burst(part)
		flak_timers[part] = left


func flak_burst(part: FortressPart) -> void:
	for i in 8:
		var heli := helicopter()
		if down or heli == null or not is_instance_valid(part) or part.stage == Building.Stage.COLLAPSED:
			return
		var from := part.muzzle()
		var to := heli.global_position + Vector3(randf_range(-3.0, 3.0), randf_range(-1.0, 1.0), randf_range(-3.0, 3.0))
		var tracer := Tracer.new()
		tracer.radius = 0.25
		tracer.length = 2.4
		MissionContext.spawn_parent(self).add_child(tracer)
		tracer.setup(from, to, 0.32, 0.0, flak_hit)
		Sfx.play_3d("car_gun", from, 2.0, 0.8)
		await wait(0.09)


func flak_hit(at: Vector3) -> void:
	var heli := helicopter()
	if heli != null and heli.global_position.distance_to(at) <= 3.0:
		heli.take_damage(flak_damage, "FLAK")


# --- Adds ----------------------------------------------------------------------

func send_scouts(count: int) -> void:
	for i in count:
		var scout := ScoutScene.instantiate() as Node3D
		MissionContext.spawn_parent(self).add_child(scout)
		var side := -1.0 if i % 2 == 0 else 1.0
		scout.global_position = global_position + Vector3(side * randf_range(30.0, 50.0), 5.69, -60.0)


func send_riflemen(count: int) -> void:
	for i in count:
		var soldier := InfantryScene.instantiate() as Node3D
		MissionContext.spawn_parent(self).add_child(soldier)
		var angle := TAU * i / count
		soldier.global_position = keep.global_position + Vector3(cos(angle) * 13.0, 0.0, sin(angle) * 10.0)


# --- The end -------------------------------------------------------------------

# The keep is down: blasts ripple out across the site, the adds still up
# go down with it, then it's over.
func finale() -> void:
	down = true
	health_changed.emit(0.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("take_damage"):
			enemy.take_damage(9999.0)
	var spots: Array = []
	for part in parts:
		spots.append(part.global_position)
	for i in 6:
		spots.append(global_position + Vector3(randf_range(-34.0, 34.0), 0.0, randf_range(-30.0, 14.0)))
	spots.shuffle()
	for at: Vector3 in spots:
		var blast := JavelinExplosion.new()
		blast.size = randf_range(1.2, 2.0)
		blast.shake = 0.4
		MissionContext.spawn_parent(self).add_child(blast)
		blast.global_position = at + Vector3(0, 1.0, 0)
		if mission != null:
			mission.hit_stop(0.04)
		await wait(randf_range(0.18, 0.32))
	await wait(1.2)
	defeated.emit()
