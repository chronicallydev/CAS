class_name HardpointData
extends Resource

## A slot on an airframe where one weapon can be mounted. Any weapon the
## airframe can use (HelicopterData.allowed_weapons) fits any slot.

## Where on the airframe the slot sits. Only changes the look: wing slots
## hang from a pylon, a minigun on the chin gets a turret ball.
enum Kind { CHIN, WING, BELLY }

## Shown in the hangar's loadout list, e.g. "Left wing".
@export var label: String = ""
@export var kind: Kind = Kind.WING
## Where the weapon attaches, in the model's own space (before the
## airframe's model_scale). x = right, y = up, -z = nose.
@export var position: Vector3 = Vector3.ZERO
