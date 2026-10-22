# Design

A short, minimal roguelike about helicopter pilots dodging missiles.
ARCHITECTURE.md describes the code; this file describes the game we're
heading for. Decisions marked **open** still need settling.

## Pillars

Every feature has to serve at least one of these; if it serves none, cut it.

1. **Beautiful girl pilots**: high-res sculpted characters, alive and reactive.
2. **Explosions**: big, chained, satisfying destruction.
3. **Dodging missiles**: the core verb, and it has to feel as good as possible.

Few assets, each as high quality as possible.

## Core loop: the chain dodge

- A **perfect dodge** is a dash started within a short window before a
  missile would have hit. Only perfect dodges count; plain dashes are
  just movement, so the mechanic can't be spammed.
- A perfect dodge drops the game into **heavy slow motion** (about 5%
  speed, not a full freeze, so missiles can still be read) for a short
  window. Dodge another missile inside it to **chain**; each link shortens
  the next window (e.g. 1.0s, 0.8s, 0.6s...).
- **Dodged missiles keep flying** and can hit enemy helicopters and
  targets. Dodging is the main way to deal damage; the gun is secondary.
- Chain milestones (e.g. 3 and 5) trigger the pilot's **cut-in** (below)
  and bigger rewards.

## Pilots and helicopters

- Two pilots, each with her own helicopter. **One weapon per helicopter.**
- **open**: which weapon goes where. Leaning toward a light helicopter
  with a minigun and more dodge charges, and a heavy one with rockets and
  fewer, stronger dodges, so the two play the core loop differently.
- Their personalities do most of the work in every scene they're in.

### Cut-ins

During slow motion (chain milestones, special moves) the pilot slides
across the screen like a fighting-game super. The game is already slowed,
so it never steals attention at a bad moment. Animated with shape-key
expressions plus simple transform animation (slide in, head snap, hair
whip); no full character animation.

### Hangar (pilot and helicopter select)

The pilots stand next to their helicopters and can be touched: drag their
clothes, touch their hair, poke them, and they react.

- Full-body sculpts with a light rig: a few bones for hair and loose
  clothes, driven by spring bones so they swing and settle on their own.
- Head and eyes follow the cursor; blink and breathing idles.
- Touches trigger a shape-key expression plus a small transform reaction
  (flinch, laugh, swat the hand away), in each pilot's own way.

## Structure

- A **run** is a chain of **procedurally assembled stretches**, with an
  **upgrade pick** (1 of 3) between them. No hand-made levels.
- Two **bosses** per run.
- **Moving forward is progress.** The camera only scrolls forward; going
  back is blocked. Stretches alternate:
  - **Travel**: scroll forward under fire from SAM sites, past small
    **objectives** defended by SAMs. The view won't scroll past a live
    objective (or SAM): they have to be destroyed to move on.
  - **Lock**: a **city** defended by enemy helicopters. The screen locks
    into an arena until its marked targets are destroyed and every
    helicopter wave is shot down, then "GO ->".
- **Travel objectives**, built from tanks and infantry:
  - **Fortified compound**: a few buildings with tanks and infantry dug
    in around them.
  - **Moving convoy**: tanks and trucks crossing the screen. Any that
    get off screen turn up again as extra defenders in the next city.
  - **Fuel depot**: tank farms and derricks that set each other off in
    chain explosions.
  - **Artillery / tank line**: dug-in tanks and infantry in trenches.
- **Cities**: every building can be destroyed; a few are marked targets
  (HQ, radar, ammo dump). Destroying them is where most of the
  explosions go (chain reactions, collapses, secondary blasts).
- **Buildings break in stages**: hits chip chunks off, then it burns
  and smokes, then it collapses into rubble with debris and dust, with
  infantry pouring out as it goes.
- **The minigun kills everything**, slowly against armour and
  buildings: big targets mean holding position under fire.

## Enemies

Variety comes from **missile types**, not from many units.

- **Enemy helicopters**: the main enemy; dogfights in lock arenas.
  Two or three types.
- **Light SAM** and **heavy SAM**: ground missile launchers.
- Missile types: fast straight, slow stubborn homing, splitting cluster,
  swarm.
- Other ground units (infantry, cars, tanks, mortars, Shilka) are out
  unless they earn a place.
- **Bosses**: an ace helicopter (dogfight) and a fortress or carrier
  destroyed piece by piece (target fight).

## Juice

- Minigun bullets ricocheting off the ground.
- Missile smoke trails that linger as white streaks (readable dodges,
  beautiful in 1-bit).
- Near-miss whoosh, with the missile visibly bending past.
- Kill-cam slow motion on the last enemy of a locked arena.
- Debris and secondary explosions chaining across targets.

## Asset budget

- 2 pilots: full body, rigged lightly, a few shape keys each (neutral,
  grin, shout or gritted teeth, wince, blink).
- 2 player helicopters.
- 2-3 enemy helicopter types, light and heavy SAM.
- 2 bosses.
- A few target structures, one or two terrain sets.

## Build order

1. **Chain dodge prototype** in the test range: perfect-dodge window,
   slow motion, chaining, dodged missiles hitting enemies. Find the fun
   first; everything else depends on it.
2. Enemy helicopter AI (dogfighting, firing missiles).
3. Forward-only camera with travel and lock stretches.
4. Procedural stretch assembly and upgrade picks.
5. Targets and their destruction.
6. Cut-ins (needs shape keys).
7. Bosses.
8. Hangar with interactive pilots (needs full-body rigged sculpts).
