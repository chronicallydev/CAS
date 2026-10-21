class_name PlayerProfile
extends Resource

## Everything the player has earned across runs: money, helicopters,
## upgrades, captured rigs and records.
##
## This is plain data. The Loadout and Campaign services read and change it,
## and SaveService writes it to disk. Contexts never keep their own copy;
## they all share the one instance owned by GameServices.

## Money available in the hangar and on the campaign map.
@export var money: int = 0

@export_group("Hangar")
## Ids of the helicopters bought so far (see HelicopterData.id).
@export var owned_helis: Array[String] = []
## The helicopter flown on the next mission.
@export var selected_heli: String = ""
## Weapon id -> units bought (see WeaponData.id). A unit can be mounted
## on every airframe, since only one is flown at a time.
@export var owned_weapons: Dictionary = {}
## Helicopter id -> weapon id per hardpoint ("" = empty).
@export var loadouts: Dictionary = {}
## Upgrade id -> level bought (see UpgradeData.id).
@export var upgrades: Dictionary = {}

@export_group("Campaign")
## Ids of the oil rigs the player holds (see RigData.id).
@export var owned_rigs: Array[String] = []
## Rig id -> {upgrade key -> level}, for rig output and hull upgrades.
@export var rig_upgrades: Dictionary = {}

@export_group("Records")
@export var best_score: int = 0
@export var best_wave: int = 0


## A fresh profile for a new player.
static func create_new(starting_money: int, starting_heli: String, starting_weapons: Dictionary, home_rig: String) -> PlayerProfile:
	var profile := PlayerProfile.new()
	profile.money = starting_money
	profile.owned_helis.assign([starting_heli])
	profile.selected_heli = starting_heli
	profile.owned_weapons = starting_weapons.duplicate()
	profile.owned_rigs.assign([home_rig])
	return profile


func can_afford(cost: int) -> bool:
	return cost >= 0 and money >= cost


## Takes the money if there is enough. Returns false (and spends nothing)
## otherwise.
func spend(cost: int) -> bool:
	if not can_afford(cost):
		return false
	money -= cost
	return true


func earn(amount: int) -> void:
	money += amount


## Keeps the best score and wave. Returns which records were beaten:
## {"score": bool, "wave": bool}.
func record_run(score: int, wave: int) -> Dictionary:
	var beaten := {"score": score > best_score, "wave": wave > best_wave}
	best_score = maxi(best_score, score)
	best_wave = maxi(best_wave, wave)
	return beaten
