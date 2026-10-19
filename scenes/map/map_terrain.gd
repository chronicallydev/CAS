extends RefCounted

# Desert terrain for the campaign map: a heightmap mesh (dunes, mountain
# ranges, a dry wadi, a salt flat and the gulf coast) and the region
# textures that say which rig owns which patch of land. Everything comes
# from fixed seeds, so the map looks the same every time.

const Campaign := preload("res://scenes/map/campaign.gd")

# Size of the playable map in world units; rig positions (0-1) map onto it.
const MAP_SIZE := Vector2(120.0, 80.0)
# The terrain mesh reaches past the map so its edges stay out of view.
const TERRAIN_MIN := Vector2(-95.0, -75.0)
const TERRAIN_MAX := Vector2(95.0, 75.0)
const STEP := 1.0

# Area covered by the region textures, and texels per world unit.
const REGION_MIN := Vector2(-78.0, -52.0)
const REGION_MAX := Vector2(78.0, 52.0)
const REGION_RES := 4.0
# Land further than this from every rig belongs to nobody.
const REGION_REACH := 23.0
# Distance-to-border values are stored up to this many texels.
const BORDER_RANGE := 16.0

const SAND := Color(0.78, 0.63, 0.44)
const SAND_DARK := Color(0.66, 0.51, 0.34)
const ROCK := Color(0.52, 0.41, 0.32)
const ROCK_DARK := Color(0.36, 0.29, 0.24)
const GRAVEL := Color(0.62, 0.55, 0.45)
const SALT := Color(0.9, 0.87, 0.8)
const WET := Color(0.56, 0.45, 0.32)
const SEABED := Color(0.42, 0.38, 0.3)
const ROAD := Color(0.56, 0.43, 0.3)

# The dry riverbed, from the northern mountains down to the gulf.
const WADI := [Vector2(-38, -60), Vector2(-31, -24), Vector2(-17, -5), Vector2(-4, 11),
	Vector2(12, 23), Vector2(30, 35), Vector2(52, 58)]

var noise := FastNoiseLite.new()
var dune_noise := FastNoiseLite.new()
var mountain_noise := FastNoiseLite.new()
var warp_noise := FastNoiseLite.new()

var columns: int
var rows: int
var heights := PackedFloat32Array()
# Rig positions in world space (x, z), in Campaign.RIG_ORDER order.
var rig_points: Array = []
var roads: Array = [] # [from, to] pairs

var region_columns: int
var region_rows: int
# Region index per texel (-1 = nobody), row-major.
var region_ids := PackedInt32Array()


func _init() -> void:
	noise.seed = 11
	noise.frequency = 0.025
	dune_noise.seed = 23
	dune_noise.frequency = 0.07
	mountain_noise.seed = 5
	mountain_noise.frequency = 0.045
	mountain_noise.fractal_octaves = 4
	warp_noise.seed = 77
	warp_noise.frequency = 0.06
	warp_noise.fractal_octaves = 3

	for id in Campaign.RIG_ORDER:
		rig_points.append(rig_world(id))
	for i in Campaign.RIG_ORDER.size():
		var id: String = Campaign.RIG_ORDER[i]
		for link in Campaign.RIGS[id]["links"]:
			var j := Campaign.RIG_ORDER.find(link)
			if j > i:
				roads.append([rig_points[i], rig_points[j]])

	build_heights()
	build_regions()


static func rig_world(id: String) -> Vector2:
	var pos: Vector2 = Campaign.RIGS[id]["pos"]
	return (pos - Vector2(0.5, 0.5)) * MAP_SIZE


# --- Heights -------------------------------------------------------------

static func segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func polyline_distance(p: Vector2, points: Array) -> float:
	var best := INF
	for i in points.size() - 1:
		best = minf(best, segment_distance(p, points[i], points[i + 1]))
	return best


func wadi_mask(p: Vector2) -> float:
	var wobble := warp_noise.get_noise_2d(p.x, p.y) * 2.0
	return 1.0 - smoothstep(1.4, 4.2, polyline_distance(p, WADI) + wobble)


func mountain_mask(p: Vector2) -> float:
	var wobble := noise.get_noise_2d(p.x * 2.0, p.y * 2.0) * 5.0
	# A range along the north edge...
	var mask := smoothstep(-27.0, -42.0, p.y + wobble)
	# ...and a few massifs.
	for blob in [[Vector2(24, -6), 11.0], [Vector2(-52, -20), 10.0], [Vector2(-8, 46), 12.0], [Vector2(70, -10), 14.0]]:
		var d: float = p.distance_to(blob[0]) + wobble
		mask = maxf(mask, 1.0 - smoothstep(blob[1] * 0.35, blob[1], d))
	return mask


func coast_amount(p: Vector2) -> float:
	var c := p.x + 0.55 * p.y + noise.get_noise_2d(p.x * 1.5, p.y * 1.5) * 7.0 - 50.0
	return smoothstep(0.0, 9.0, c)


func dune(p: Vector2) -> float:
	return dune_noise.get_noise_2d(p.x, p.y * 0.55)


func raw_height(p: Vector2) -> float:
	var h := 2.0 + noise.get_noise_2d(p.x, p.y) * 1.0 + dune(p) * 0.6

	var ridged := 1.0 - absf(mountain_noise.get_noise_2d(p.x, p.y))
	h += mountain_mask(p) * (2.5 + ridged * ridged * 11.0)
	h -= wadi_mask(p) * 1.3
	var coast := coast_amount(p)
	h -= coast * 8.5
	# The wadi is dry: inland ground never dips below the sea.
	if coast < 0.05:
		h = maxf(h, 0.6)

	# The salt flat is dead level.
	var salt := 1.0 - smoothstep(6.0, 13.0, p.distance_to(rig_world("saltflat")))
	h = lerpf(h, 1.5, salt)

	# Flat pads for the rigs; the ridge derrick sits up on the high ground.
	for i in rig_points.size():
		var pad := 1.0 - smoothstep(3.5, 7.5, p.distance_to(rig_points[i]))
		var target := 5.0 if Campaign.RIG_ORDER[i] == "ridge" else 2.0
		h = lerpf(h, target, pad)
	return h


func build_heights() -> void:
	columns = int((TERRAIN_MAX.x - TERRAIN_MIN.x) / STEP) + 1
	rows = int((TERRAIN_MAX.y - TERRAIN_MIN.y) / STEP) + 1
	heights.resize(columns * rows)
	for r in rows:
		for c in columns:
			heights[r * columns + c] = raw_height(TERRAIN_MIN + Vector2(c, r) * STEP)


# Bilinear height lookup, usable anywhere on the terrain.
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - TERRAIN_MIN.x) / STEP, 0.0, columns - 1.001)
	var fz := clampf((z - TERRAIN_MIN.y) / STEP, 0.0, rows - 1.001)
	var c := int(fx)
	var r := int(fz)
	var tx := fx - c
	var tz := fz - r
	var a := lerpf(heights[r * columns + c], heights[r * columns + c + 1], tx)
	var b := lerpf(heights[(r + 1) * columns + c], heights[(r + 1) * columns + c + 1], tx)
	return lerpf(a, b, tz)


func road_mask(p: Vector2) -> float:
	var q := p + Vector2(warp_noise.get_noise_2d(p.x, p.y), warp_noise.get_noise_2d(p.y, p.x)) * 1.5
	var best := INF
	for road in roads:
		best = minf(best, segment_distance(q, road[0], road[1]))
	return 1.0 - smoothstep(0.35, 0.8, best)


func ground_color(p: Vector2, h: float, slope: float) -> Color:
	var color := SAND.lerp(SAND_DARK, clampf(-dune(p) * 1.4, 0.0, 1.0) * 0.7)

	var rocky := maxf(clampf((h - 3.4) / 3.0, 0.0, 1.0), clampf((slope - 0.45) / 0.7, 0.0, 1.0))
	color = color.lerp(ROCK, rocky)
	color = color.lerp(ROCK_DARK, clampf((h - 8.0) / 5.0, 0.0, 1.0) * 0.8)

	color = color.lerp(GRAVEL, wadi_mask(p) * 0.9)
	var salt := 1.0 - smoothstep(5.0, 12.0, p.distance_to(rig_world("saltflat")) + noise.get_noise_2d(p.x * 3.0, p.y * 3.0) * 3.0)
	color = color.lerp(SALT, salt)

	if h > 0.5 and h < 4.5:
		color = color.lerp(ROAD, road_mask(p) * 0.9)

	# Damp sand at the waterline and the seabed below it.
	color = color.lerp(WET, 1.0 - smoothstep(0.1, 0.7, absf(h - 0.15)))
	if h < -0.2:
		color = color.lerp(SEABED, clampf(-h / 2.0, 0.0, 1.0))

	# A little speckle so flat sand isn't a single colour.
	var speckle := noise.get_noise_2d(p.x * 9.0, p.y * 9.0) * 0.04
	return Color(color.r + speckle, color.g + speckle, color.b + speckle * 0.8)


func build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for r in rows:
		for c in columns:
			var p := TERRAIN_MIN + Vector2(c, r) * STEP
			var h := heights[r * columns + c]
			var hx := heights[r * columns + mini(c + 1, columns - 1)] - heights[r * columns + maxi(c - 1, 0)]
			var hz := heights[mini(r + 1, rows - 1) * columns + c] - heights[maxi(r - 1, 0) * columns + c]
			var slope := Vector2(hx, hz).length() / (2.0 * STEP)
			st.set_color(ground_color(p, h, slope))
			st.set_uv(p)
			st.add_vertex(Vector3(p.x, h, p.y))

	for r in rows - 1:
		for c in columns - 1:
			var i := r * columns + c
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + columns)
			st.add_index(i + 1)
			st.add_index(i + columns + 1)
			st.add_index(i + columns)

	st.generate_normals()
	return st.commit()


# --- Regions -------------------------------------------------------------

# Each rig owns the land nearest to it, measured through a warped field so
# the borders come out ragged. The sea and far-off land belong to nobody.
func build_regions() -> void:
	region_columns = int((REGION_MAX.x - REGION_MIN.x) * REGION_RES)
	region_rows = int((REGION_MAX.y - REGION_MIN.y) * REGION_RES)
	region_ids.resize(region_columns * region_rows)

	for r in region_rows:
		for c in region_columns:
			var p := texel_world(c, r)
			var warp := Vector2(warp_noise.get_noise_2d(p.x, p.y), warp_noise.get_noise_2d(p.x + 140.0, p.y - 60.0)) * 6.0
			var q := p + warp
			var best := -1
			var best_distance := REGION_REACH
			for i in rig_points.size():
				var d: float = q.distance_to(rig_points[i])
				if d < best_distance:
					best_distance = d
					best = i
			if height_at(p.x, p.y) < 0.15:
				best = -1
			region_ids[r * region_columns + c] = best


func texel_world(c: int, r: int) -> Vector2:
	return REGION_MIN + (Vector2(c, r) + Vector2(0.5, 0.5)) / REGION_RES


func region_at(x: float, z: float) -> int:
	var c := int((x - REGION_MIN.x) * REGION_RES)
	var r := int((z - REGION_MIN.y) * REGION_RES)
	if c < 0 or r < 0 or c >= region_columns or r >= region_rows:
		return -1
	return region_ids[r * region_columns + c]


func region_id_texture() -> ImageTexture:
	var image := Image.create(region_columns, region_rows, false, Image.FORMAT_R8)
	for r in region_rows:
		for c in region_columns:
			image.set_pixel(c, r, Color((region_ids[r * region_columns + c] + 1) / 255.0, 0, 0))
	return ImageTexture.create_from_image(image)


# Distance (in texels) from each texel to the edge of its region, found
# with a two-pass chamfer transform. Read in the shader to draw borders.
func region_border_texture() -> ImageTexture:
	var count := region_columns * region_rows
	var distance := PackedFloat32Array()
	distance.resize(count)

	for r in region_rows:
		for c in region_columns:
			var i := r * region_columns + c
			var id := region_ids[i]
			var edge := false
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nc: int = c + offset.x
				var nr: int = r + offset.y
				if nc < 0 or nr < 0 or nc >= region_columns or nr >= region_rows or region_ids[nr * region_columns + nc] != id:
					edge = true
					break
			distance[i] = 0.0 if edge else BORDER_RANGE

	var diagonal := 1.414
	for r in region_rows:
		for c in region_columns:
			var i := r * region_columns + c
			var d := distance[i]
			if c > 0: d = minf(d, distance[i - 1] + 1.0)
			if r > 0:
				d = minf(d, distance[i - region_columns] + 1.0)
				if c > 0: d = minf(d, distance[i - region_columns - 1] + diagonal)
				if c < region_columns - 1: d = minf(d, distance[i - region_columns + 1] + diagonal)
			distance[i] = d
	for r in range(region_rows - 1, -1, -1):
		for c in range(region_columns - 1, -1, -1):
			var i := r * region_columns + c
			var d := distance[i]
			if c < region_columns - 1: d = minf(d, distance[i + 1] + 1.0)
			if r < region_rows - 1:
				d = minf(d, distance[i + region_columns] + 1.0)
				if c < region_columns - 1: d = minf(d, distance[i + region_columns + 1] + diagonal)
				if c > 0: d = minf(d, distance[i + region_columns - 1] + diagonal)
			distance[i] = d

	var image := Image.create(region_columns, region_rows, false, Image.FORMAT_R8)
	for r in region_rows:
		for c in region_columns:
			image.set_pixel(c, r, Color(minf(distance[r * region_columns + c], BORDER_RANGE) / BORDER_RANGE, 0, 0))
	return ImageTexture.create_from_image(image)


# Average position of each region's land, for placing clouds.
func region_centres() -> Array:
	var sums: Array = []
	var counts: Array = []
	for i in rig_points.size():
		sums.append(Vector2.ZERO)
		counts.append(0)
	for r in range(0, region_rows, 3):
		for c in range(0, region_columns, 3):
			var id := region_ids[r * region_columns + c]
			if id >= 0:
				sums[id] += texel_world(c, r)
				counts[id] += 1
	var centres: Array = []
	for i in rig_points.size():
		centres.append(sums[i] / maxf(counts[i], 1.0))
	return centres
