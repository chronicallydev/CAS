# Parked

Code and content taken out of the build while the core (flying and
shooting) gets worked out. Godot ignores this folder completely (it has a
`.gdignore`), so nothing here is parsed, imported or shown in the editor,
and it can't break the build.

Every file keeps its original path under `_parked/`, so
`_parked/features/map/map_world.gd` came from `features/map/map_world.gd`.
`_parked/ARCHITECTURE.md` describes the full game as it was.

## Whole systems (moved out)

| What | Where it lived |
|---|---|
| Root context, services bundle, game config | `features/game_flow/` |
| Player profile, settings, save service | `features/profile/` |
| Main menu | `features/menu/` |
| Hangar | `features/hangar/` |
| Campaign map | `features/map/` |
| Campaign rules, rigs, garrisons | `features/campaign/` |
| Loadout service and catalog | `features/loadout/loadout.gd`, `features/loadout/data/loadout_catalog.gd`, `features/loadout/content/loadout_catalog.tres` |
| Little Bird and Hind airframes | `features/loadout/content/helicopters/` |
| Cannon, Javelin and FAB weapon data | `features/loadout/content/weapons/` |
| Javelin missile and FAB bomb | `features/mission/weapons/javelin_missile.gd`, `bomb.gd` |
| Waves, enemy generator, difficulty presets | `features/mission/waves/` |
| Mission state (score, waves, payout) | `features/mission/mission_state.gd` |
| Mission rig (the oil rig to defend) | `features/mission/rig/` |
| Pickups (cash, frenzy) | `features/mission/pickups/` |
| Stinger, Shilka, Ripple launcher | `features/mission/enemies/` |
| Forts: bunker, flak gun, SAM site | `features/mission/enemies/forts/` |

## Trimmed files (pre-strip copies)

These files are still in the build, cut down. The full versions from
before the strip are kept here:

| File | What was cut |
|---|---|
| `features/mission/mission_context.gd`, `mission.tscn` | services, campaign, waves, rig, pickups, payout, end screens |
| `features/mission/hud/game_hud.gd` | wave readout and banners, rig bar, end screens |
| `features/mission/weapons/gun_controller.gd` | cannon, Javelin, FAB, frenzy |
| `features/mission/player/helicopter.gd` | assault ingress, rig take-off |
| `features/mission/enemies/enemy_base.gd`, `infantry.gd`, `car.gd`, `tank.gd`, `aa_launcher.gd` | defending a rig (enemies now always hunt the helicopter) |
| `features/test_range/*` | sandbox services, airframe/loadout/upgrade pickers, hunt/march toggle, parked units |

## Bringing something back

1. Move the files back to their original path (`git mv _parked/<path> <path>`),
   with their `.uid` files.
2. Reconnect it. Check the matching pre-strip copy above, or `git log` /
   `git show f838511:<path>` for the last commit before the strip.
3. Run the project and fix what it now references that's still parked.
