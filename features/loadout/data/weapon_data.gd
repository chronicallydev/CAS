class_name WeaponData
extends Resource

## One weapon sold in the hangar: its catalogue entry, how it looks on
## the airframe, and the upgrades for it. Which helicopters can use it is
## set per airframe (HelicopterData.allowed_weapons).
## The weapon's behaviour lives in the gun controller; this is only data.

## Saved in PlayerProfile (owned weapons, loadouts) and matches the gun
## controller's weapon ids, so don't rename existing ids.
@export var id: String = ""
@export var display_name: String = ""
## Short tag shown on cards: HEAVY, LIGHT, GUIDED, BOMB.
@export var weight_class: String = ""
@export_multiline var description: String = ""
## Price of one unit. Each mounted copy needs its own unit.
@export var price: int = 1000

@export_group("Model")
## Which primitive model is built on the hardpoint (see WeaponModel).
@export_enum("turret", "minigun", "rail", "pod", "bomb") var model: String = "pod"

@export_group("")
## Upgrades in the order the workshop lists them. They target properties
## on the gun controller and apply to every mounted copy.
@export var upgrades: Array[UpgradeData] = []
