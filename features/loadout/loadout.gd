class_name Loadout
extends RefCounted

## The hangar's rules: what the player owns, what things cost, and how
## upgrades change the helicopter and its guns.
##
## Reads the item definitions from a LoadoutCatalog and the player's
## purchases from a PlayerProfile. Buying changes the profile only; the
## caller saves (see GameServices.save()).

var catalog: LoadoutCatalog
var profile: PlayerProfile

## Lookups built from the catalog.
var _helis: Dictionary = {}     # id -> HelicopterData
var _weapons: Dictionary = {}   # id -> WeaponData
var _upgrades: Dictionary = {}  # id -> UpgradeData


func _init(loadout_catalog: LoadoutCatalog, player_profile: PlayerProfile) -> void:
	catalog = loadout_catalog
	profile = player_profile
	for heli in catalog.helicopters:
		_helis[heli.id] = heli
	for upgrade in catalog.airframe_upgrades:
		_upgrades[upgrade.id] = upgrade
	for weapon in catalog.weapons:
		_weapons[weapon.id] = weapon
		for upgrade in weapon.upgrades:
			_upgrades[upgrade.id] = upgrade


# --- Lookups ---------------------------------------------------------------

func heli(id: String) -> HelicopterData:
	return _helis.get(id)


func weapon(id: String) -> WeaponData:
	return _weapons.get(id)


func upgrade(id: String) -> UpgradeData:
	return _upgrades.get(id)


## The helicopter the player will fly (falls back to the catalog default
## if the save names one that no longer exists).
func selected_heli() -> HelicopterData:
	return _helis.get(profile.selected_heli, _helis.get(catalog.default_helicopter))


func owns_heli(id: String) -> bool:
	return profile.owned_helis.has(id)


# --- Upgrades --------------------------------------------------------------

func level(upgrade_id: String) -> int:
	return int(profile.upgrades.get(upgrade_id, 0))


## Price of the next level, or -1 when the upgrade is maxed out.
func upgrade_cost(upgrade_id: String) -> int:
	var lvl := level(upgrade_id)
	if lvl >= catalog.max_level:
		return -1
	return upgrade(upgrade_id).cost(lvl, catalog.cost_growth)


## Total money spent on upgrades so far (refunded by the reset button).
func spent_on_upgrades() -> int:
	var total := 0
	for upgrade_id in profile.upgrades.keys():
		var def := upgrade(upgrade_id)
		if def == null:
			continue
		for lvl in level(upgrade_id):
			total += def.cost(lvl, catalog.cost_growth)
	return total


## Total levels bought across a weapon's upgrades.
func weapon_level(weapon_id: String) -> int:
	var total := 0
	for def in weapon(weapon_id).upgrades:
		total += level(def.id)
	return total


## The value an airframe stat has with the current upgrades.
func heli_stat(heli_data: HelicopterData, def: UpgradeData) -> float:
	return def.apply(heli_data.get(def.target_properties[0]), level(def.id))


# --- Purchases (change the profile; the caller saves) ----------------------

func buy_upgrade(upgrade_id: String) -> bool:
	if not profile.spend(upgrade_cost(upgrade_id)):
		return false
	profile.upgrades[upgrade_id] = level(upgrade_id) + 1
	return true


## Refunds every upgrade.
func reset_upgrades() -> void:
	profile.earn(spent_on_upgrades())
	profile.upgrades = {}


## Buys a helicopter and makes it the selected one.
func buy_heli(id: String) -> bool:
	if owns_heli(id) or not profile.spend(heli(id).price):
		return false
	profile.owned_helis.append(id)
	profile.selected_heli = id
	return true


func select_heli(id: String) -> void:
	if owns_heli(id):
		profile.selected_heli = id


# --- Weapons and hardpoints --------------------------------------------------
# Each airframe has its own loadout: a weapon id per hardpoint ("" = empty).
# Rules for a valid loadout:
#   - the airframe can use the weapon (HelicopterData.allowed_weapons);
#     any usable weapon goes on any hardpoint,
#   - the airframe carries no more copies of a weapon than the player owns,
#   - at most catalog.max_weapon_types different weapons are mixed.

func owned_count(weapon_id: String) -> int:
	return int(profile.owned_weapons.get(weapon_id, 0))


## Buys one more unit of a weapon.
func buy_weapon(weapon_id: String) -> bool:
	if not profile.spend(weapon(weapon_id).price):
		return false
	profile.owned_weapons[weapon_id] = owned_count(weapon_id) + 1
	return true


## The airframe's weapon id per hardpoint. The first call for an airframe
## sets it up from its default loadout; saved loadouts are cleaned up so
## they always follow the rules (e.g. after a catalog change).
func mounted(heli_id: String) -> Array:
	var heli_data := heli(heli_id)
	var saved: Array = profile.loadouts.get(heli_id, Array(heli_data.default_loadout))
	var result: Array = []
	result.resize(heli_data.hardpoints.size())
	result.fill("")
	for i in result.size():
		var weapon_id: String = saved[i] if i < saved.size() else ""
		if weapon_id != "" and _allowed(result, heli_data, i, weapon_id):
			result[i] = weapon_id
	profile.loadouts[heli_id] = result
	return result


## WeaponData per hardpoint (null where empty), for building the model.
func mounted_weapons(heli_id: String) -> Array:
	var weapons: Array = []
	for weapon_id in mounted(heli_id):
		weapons.append(weapon(weapon_id) if weapon_id != "" else null)
	return weapons


## The weapon types mounted on an airframe, in catalog order. The first
## fires with the left mouse button, the second with the right.
func mounted_types(heli_id: String) -> Array[String]:
	var ids := mounted(heli_id)
	var types: Array[String] = []
	for weapon_data in catalog.weapons:
		if ids.has(weapon_data.id):
			types.append(weapon_data.id)
	return types


## Copies of a weapon mounted on an airframe.
func mounted_count(heli_id: String, weapon_id: String) -> int:
	return mounted(heli_id).count(weapon_id)


## Whether `weapon_id` ("" = remove) may go on hardpoint `index`.
func can_mount(heli_id: String, index: int, weapon_id: String) -> bool:
	if weapon_id == "":
		return true
	var ids := mounted(heli_id).duplicate()
	ids[index] = ""
	return _allowed(ids, heli(heli_id), index, weapon_id)


## Everything hardpoint `index` can take right now: "" (empty) first, then
## the weapons that may go there, in catalog order.
func mount_options(heli_id: String, index: int) -> Array[String]:
	var options: Array[String] = [""]
	for weapon_data in catalog.weapons:
		if can_mount(heli_id, index, weapon_data.id):
			options.append(weapon_data.id)
	return options


func set_mount(heli_id: String, index: int, weapon_id: String) -> bool:
	if not can_mount(heli_id, index, weapon_id):
		return false
	var ids := mounted(heli_id)
	ids[index] = weapon_id
	profile.loadouts[heli_id] = ids
	return true


## Whether the airframe can carry `weapon_id` at all.
func can_use(heli_data: HelicopterData, weapon_id: String) -> bool:
	return heli_data.allowed_weapons.has(weapon_id)


## Why `weapon_id` can't go on hardpoint `index`, or "" if it can.
func mount_problem(heli_id: String, index: int, weapon_id: String) -> String:
	var heli_data := heli(heli_id)
	if not can_use(heli_data, weapon_id):
		return "Not for the %s" % heli_data.display_name
	var ids := mounted(heli_id).duplicate()
	ids[index] = ""
	if ids.count(weapon_id) >= owned_count(weapon_id):
		return "Buy another unit"
	if _types_with(ids, weapon_id) > catalog.max_weapon_types:
		return "Max %d weapon types" % catalog.max_weapon_types
	return ""


# Whether `weapon_id` may join `ids` (the rest of the loadout) on a
# hardpoint. Every hardpoint takes any usable weapon, so which one is moot.
func _allowed(ids: Array, heli_data: HelicopterData, _index: int, weapon_id: String) -> bool:
	if weapon(weapon_id) == null or not can_use(heli_data, weapon_id):
		return false
	if ids.count(weapon_id) >= owned_count(weapon_id):
		return false
	return _types_with(ids, weapon_id) <= catalog.max_weapon_types


# How many weapon types `ids` would mix with `weapon_id` added.
func _types_with(ids: Array, weapon_id: String) -> int:
	var types := {weapon_id: true}
	for other in ids:
		if other != "":
			types[other] = true
	return types.size()


# --- Applying the loadout at the start of a mission ------------------------

## Copies the selected airframe's stats, with upgrades, onto the helicopter.
func apply_to_helicopter(helicopter: Object) -> void:
	var heli_data := selected_heli()
	for def in catalog.airframe_upgrades:
		var property := def.target_properties[0]
		var value := heli_stat(heli_data, def)
		helicopter.set(property, int(value) if helicopter.get(property) is int else value)


## Applies every weapon upgrade to the gun controller's exported values.
func apply_to_guns(guns: Object) -> void:
	for weapon_data in catalog.weapons:
		for def in weapon_data.upgrades:
			def.apply_to(guns, level(def.id))
