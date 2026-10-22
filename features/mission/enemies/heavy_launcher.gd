extends "res://features/mission/enemies/aa_launcher.gd"

# Heavy rocket truck: a SAM truck with one fat tube. It fires a single
# heavy rocket (heavy_rocket.gd) that keeps coming back until it has been
# dodged several times. It won't lock again
# while its rocket is still flying.

const HeavyRocket := preload("res://features/mission/enemies/projectiles/heavy_rocket.gd")

var rocket: Node3D


func can_fire() -> bool:
	return not is_instance_valid(rocket)


func make_missile() -> Node3D:
	rocket = HeavyRocket.new()
	rocket.damage = missile_damage
	rocket.source_name = "HEAVY SAM"
	return rocket
