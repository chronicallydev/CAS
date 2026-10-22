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
- **Arcade pace**: a full run is about 8 minutes, and dying is common.
- **The UI is 1-bit too**: drawn at the pixel art's resolution, pure black
  and white, HUD text on solid black plates.
- **The run ramps up**: each stretch brings in one new thing (the plan
  is `RunDirector.PLAN`). The first two stretches are open ground: a few
  riflemen and a car (then a tank) wandering at you, and an open-ground
  intercept. Then a village with one target, then towns growing to a
  full city, with dug-in objectives from the fourth stretch.
- **Cities stay defended**: while targets stand, helicopter
  reinforcements keep coming. Taking the targets down fast skips the
  waves not yet sent.
- **Hull**: a small patch-up after every cleared arena, plus the repair
  and plating upgrades.
- **Wrecking pays**: building kills feed the combo.
- **The minigun never overheats**: it spins up, then fires as long as
  it's held.
- **Scouts keep coming** at you over a city while its targets stand,
  a few at a time.

## Upgrades

- One pick (1 of 3) after each cleared arena; no rerolls. Every upgrade
  **changes how something works**, never just a number, and is a one-off.
- Three **categories** (gun, deflect, movement) by three **roles**
  (utility, lethality, survivability), two upgrades per slot, plus Double
  The Gun, the one upgrade that stacks (each pick doubles the guns and
  halves their accuracy):

  | | Utility | Lethality | Survivability |
  |---|---|---|---|
  | Gun | Rubber Bullets, Seeker Rounds | Shredder, Incendiary, Double The Gun | Flak Screen, Salvage |
  | Deflect | Redirect, Time Bank | Split, Overcharge | Grace, Absorb |
  | Movement | Decoy, Steer Dash | Ram, Rotor Wash | Rotor Guard, Autorotate |

- **Dealing**: one card per category. Roles are weighted by what you
  already hold (each role 1, plus 1 per upgrade of it), so a build leans
  the way you pick.
- **Combos**: hand-made pairs that add an extra effect, shown on a card
  that would complete one (`RunUpgrades.COMBOS`), e.g. Rubber Bullets +
  Incendiary: ricochets set fires.

## Enemies

Variety comes from **missile types**, not from many units.

- **Enemy helicopters**: the main enemy; dogfights in lock arenas.
  Two or three types.
- **Light SAM** and **heavy SAM**: ground missile launchers.
- The **heavy rocket** (heavy SAM, gunships) can't be sent back by a
  perfect dodge: it has to be outflown, pass after pass.
- Enemy missiles still in the air when an arena is won burst harmlessly.
- Missile types: fast straight, slow stubborn homing, splitting cluster,
  swarm.
- Other ground units (infantry, cars, tanks, mortars, Shilka) are out
  unless they earn a place.
- **Bosses**: an ace helicopter (dogfight) and a fortress or carrier
  destroyed piece by piece (target fight).
- **The fortress** (built, the final arena; about 90 s): a keep inside a
  wall ring with five emplacements (two SAM batteries, two flak guns, a
  heavy rocket rail). Deflected missiles home on the emplacements, so
  chain dodging its readable salvos is the way in. Phase 1: SAM fans and
  flak. Phase 2 (two emplacements down): keep rings, the rocket rail,
  two scouts. Phase 3 (all down): the keep opens up and fires spirals
  while scouts and riflemen pour out; it goes down in a chain of blasts.

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
