class_name Campaign
extends RefCounted

## The campaign's rules: which rigs the player holds, which can be attacked,
## what they pay, and where things come from on the battlefield.
##
## Rig definitions come from a CampaignCatalog; ownership and rig upgrade
## levels come from the PlayerProfile. Every owned rig pays out after every
## mission, win or lose. Buying changes the profile only; the caller saves.

## Rig upgrade keys, as stored in PlayerProfile.rig_upgrades.
const OUTPUT := "output"
const HULL := "hull"
const UPGRADE_LABELS := {OUTPUT: "Output", HULL: "Rig hull"}

## Map positions are 0-1 on each axis; the map is 1.5 times wider than tall.
const MAP_ASPECT := Vector2(1.5, 1.0)

var catalog: CampaignCatalog
var profile: PlayerProfile

var _rigs: Dictionary = {}  # id -> RigData
## Rig ids in map order (index = marker / region index on the map).
var rig_order: Array[String] = []


func _init(campaign_catalog: CampaignCatalog, player_profile: PlayerProfile) -> void:
	catalog = campaign_catalog
	profile = player_profile
	for rig_data in catalog.rigs:
		_rigs[rig_data.id] = rig_data
		rig_order.append(rig_data.id)


# --- Lookups ---------------------------------------------------------------

func rig(id: String) -> RigData:
	return _rigs.get(id)


func has_rig(id: String) -> bool:
	return _rigs.has(id)


func rig_count() -> int:
	return rig_order.size()


func owned_count() -> int:
	return profile.owned_rigs.size()


func is_owned(id: String) -> bool:
	return profile.owned_rigs.has(id)


## A rig can be attacked once a linked rig is owned.
func can_attack(id: String) -> bool:
	if is_owned(id):
		return false
	for link in rig(id).links:
		if is_owned(link):
			return true
	return false


# --- Economy ---------------------------------------------------------------

func level(id: String, key: String) -> int:
	return int(profile.rig_upgrades.get(id, {}).get(key, 0))


## Money the rig pays after each mission, with output upgrades.
func income(id: String) -> int:
	var base := rig(id).income
	return int(round(base * (1.0 + catalog.output_per_level * level(id, OUTPUT))))


func total_income() -> int:
	var total := 0
	for id in profile.owned_rigs:
		if has_rig(id):
			total += income(id)
	return total


## Extra rig health from hull upgrades.
func hull_bonus(id: String) -> float:
	return catalog.hull_per_level * level(id, HULL)


func upgrade_cost(id: String, key: String) -> int:
	var next := level(id, key) + 1
	if key == OUTPUT:
		return int(rig(id).income * catalog.output_cost_factor * next * next)
	return int(catalog.hull_base_cost * next * next)


## Spends the money and raises the level. Returns false if not possible.
func buy_upgrade(id: String, key: String) -> bool:
	if not is_owned(id) or level(id, key) >= catalog.max_level:
		return false
	if not profile.spend(upgrade_cost(id, key)):
		return false
	var levels: Dictionary = profile.rig_upgrades.get(id, {}).duplicate()
	levels[key] = level(id, key) + 1
	profile.rig_upgrades[id] = levels
	return true


func capture_bonus(id: String) -> int:
	return int(rig(id).income * catalog.capture_bonus)


## Marks a rig as owned. Returns the capture bonus (0 if already owned).
func capture(id: String) -> int:
	if is_owned(id):
		return 0
	profile.owned_rigs.append(id)
	return capture_bonus(id)


# --- Mission geography -----------------------------------------------------
# Directions on the battlefield (x = east, y = south, as on the map) worked
# out from where rigs sit on the campaign map.

func heading(from_id: String, to_id: String) -> Vector2:
	var delta: Vector2 = (rig(to_id).map_position - rig(from_id).map_position) * MAP_ASPECT
	return delta.normalized() if delta.length() > 0.001 else Vector2.RIGHT


## Where the helicopter flies in from: the direction of the owned rig the
## attack is launched from (the first owned link), as seen from the target.
func approach_side(id: String) -> Vector2:
	for link in rig(id).links:
		if is_owned(link):
			return heading(id, link)
	return Vector2(0, 1)


## Directions enemy reinforcements come from: toward enemy-held neighbours.
## An assaulted rig with none is reinforced from the far side.
func enemy_sides(id: String) -> Array:
	var sides: Array = []
	for link in rig(id).links:
		if not is_owned(link) and link != id:
			sides.append(heading(id, link))
	if sides.is_empty():
		sides.append(-approach_side(id) if not is_owned(id) else Vector2.from_angle(randf() * TAU))
	if not is_owned(id):
		# The garrison also fights back from behind the rig.
		sides.append(-approach_side(id))
	return sides


## "north", "south-east"... for a direction (x = east, y = south).
static func compass(direction: Vector2) -> String:
	const NAMES := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	var degrees := fposmod(rad_to_deg(atan2(direction.x, -direction.y)), 360.0)
	return NAMES[int(round(degrees / 45.0)) % 8]
