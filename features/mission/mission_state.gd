class_name MissionState
extends RefCounted

## The state of the mission being flown: what it is (rig, assault or
## defence) and how it's going (score, wave, game over, payout).
##
## Created by the MissionContext when a mission starts and dropped when it
## ends. Nothing in it is saved; the payout is added to the PlayerProfile.

## The rig being fought over, or null for a free-play defence.
var rig: RigData
## Attacking an enemy rig (true) or defending an owned one (false).
var is_assault: bool = false

var score: int = 0
var wave: int = 0
var is_over: bool = false

## Money earned when the mission ended, and where it came from.
var earned: int = 0
var payout: Dictionary = {"kills": 0, "income": 0, "capture": 0}


func _init(mission_rig: RigData = null, assault: bool = false) -> void:
	rig = mission_rig
	is_assault = assault


## True for campaign missions (fought over a rig), false for free play.
func is_campaign() -> bool:
	return rig != null


func add_score(points: int) -> void:
	if not is_over:
		score += points
