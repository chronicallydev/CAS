class_name GarrisonData
extends Resource

## The mix of enemies defending a rig. Weights are relative chances for
## each enemy type to be picked when a wave is filled; 0 = never.

@export var label: String = ""
@export_range(0.0, 10.0, 0.01) var infantry_weight: float = 0.6
@export_range(0.0, 10.0, 0.01) var car_weight: float = 0.25
@export_range(0.0, 10.0, 0.01) var tank_weight: float = 0.1
@export_range(0.0, 10.0, 0.01) var aa_weight: float = 0.1
