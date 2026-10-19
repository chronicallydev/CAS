class_name GameSettings
extends Resource

## Options picked in the main menu. Saved with the profile by SaveService.

## Index into GameConfig.difficulty_presets (0 = Easy, 1 = Normal, ...).
@export var difficulty: int = 1

@export_group("Free play")
## Enemy types allowed outside campaign missions, and the wave to start on.
## Not shown in the menu yet, but saved so they can be tweaked by hand.
@export var infantry_enabled: bool = true
@export var car_enabled: bool = true
@export var tank_enabled: bool = true
@export var aa_enabled: bool = true
@export var starting_level: int = 0

@export_group("Graphics")
## Low-res 3D pixel-art rendering (see shared/pixelart/pixel_art.gd).
@export var pixel_art: bool = true
## Stylised blood on infantry deaths.
@export var blood: bool = true
