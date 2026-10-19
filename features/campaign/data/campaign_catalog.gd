class_name CampaignCatalog
extends Resource

## The campaign map's rigs and the rules for capturing and upgrading them.
## Edit campaign_catalog.tres (and the rig resources it lists) to change
## the campaign.

## In map order. The first rig in this list is also index 0 for the map's
## region and marker drawing.
@export var rigs: Array[RigData] = []
## The rig a new player starts with.
@export var home_rig: String = "home"
## Money for capturing a rig, as a multiple of its base income.
@export var capture_bonus: float = 3.0

@export_group("Rig upgrades")
@export var max_level: int = 5
## Output: each level adds this share of the rig's base income...
@export var output_per_level: float = 0.3
## ...and costs income * output_cost_factor * level².
@export var output_cost_factor: float = 2.0
## Hull: each level adds this much rig health when defending...
@export var hull_per_level: float = 25.0
## ...and costs hull_base_cost * level².
@export var hull_base_cost: int = 300
