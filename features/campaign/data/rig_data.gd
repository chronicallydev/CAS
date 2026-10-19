class_name RigData
extends Resource

## One oil rig on the campaign map: where it is, what defends it, and what
## it pays once captured.

## Saved in PlayerProfile.owned_rigs, so don't rename existing ids.
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Position on the campaign map, 0-1 on each axis (x = east, y = south).
@export var map_position: Vector2 = Vector2(0.5, 0.5)
## Ids of the rigs connected to this one. A rig can be attacked once a
## linked rig is owned.
@export var links: PackedStringArray = []

@export_group("Mission")
## The wave level the fight starts at (shown as threat level + 1).
@export var threat_level: int = 0
## Waves to clear to capture the rig.
@export var waves: int = 3
@export var garrison: GarrisonData
## Battlefield look (see desert_environment.gd).
@export_enum("desert", "wadi", "saltflat", "ridge", "refinery", "terminal", "oilfield") var biome: String = "desert"
## Forts dug in around the rig; all must be destroyed to capture it.
@export var bunkers: int = 0
@export var flak_guns: int = 0

@export_group("Economy")
## Money paid after every mission while the rig is owned (before upgrades).
@export var income: int = 200
