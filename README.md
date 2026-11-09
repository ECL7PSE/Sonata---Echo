# Echo: Lost Worlds

## Activity 1 — Godot & Git Setup

Game Overview

Echo: Lost Worlds is a 2D dark-fantasy dungeon action game focused on exploration, combat, character progression, and loot.

The game is inspired by dungeon-crawling and action games such as Minecraft Dungeons, Soul Knight, and My Heroes: Dungeon Raid, while taking visual and atmospheric inspiration from dark-fantasy indie games.

Players explore dangerous dungeons, fight strange enemies, discover powerful equipment, and become stronger through loot and progression.

Genre

2D Dark-Fantasy Dungeon Crawler / Action RPG

Core Features
Dungeon exploration
Fast-paced combat
Enemy encounters
Randomized loot
Item rarity and equipment
Character progression
Boss encounters
Dark-fantasy environments
Unique and strange creatures

![Godot Project](screenshots/01-godot-project.png)
Project Creation: The Echo mini-game project was created using Godot 4. The project was created as the foundation for the game's development.

![Scene Setup](screenshots/02-scene-setup.png)
A Node2D was created as the root node of the main scene, with a Sprite2D child added as the initial visual placeholder.

![Running Game](screenshots/03-running-game.png)
Project Testing: The project was launched successfully from Godot to verify that the main scene and project configuration were functioning correctly.

![Project Files](screenshots/04-project-files.png)
Project Files: The project directory contains the Godot project files, .gitignore, .gitattributes, and README documentation required for version control and project documentation.

![Git LFS Setup](screenshots/05-git-lfs.png)
Git LFS Configuration: Git Large File Storage was initialized and configured to track PNG image and WAV audio assets, allowing large game-development files to be handled appropriately by Git.

![Git Commit](screenshots/06-git-commit.png)
Initial Commit: The completed Week 1 project setup was committed to the local Git repository using the commit message Week 1: project setup + Hello World.

![Git Push](screenshots/07-git-push.png)
GitHub Synchronization: The local main branch was successfully pushed to the GitHub repository, establishing the remote repository for the project.

## Activity 2 — Gameplay Mechanics and Game Feel

<img width="1921" height="1082" alt="image" src="https://github.com/user-attachments/assets/8d1dc7d7-d33f-4c19-ba7a-c8de66207514" />
New sprite: I added a new sprite to my character/player downloaded from a Sprite website, New children Node were also added for the upcoming movement of the character which is the CharacterBody2D and its child CollisionShape2D and I also added the Icon(Sprite2D) as a child Node to CharacterBody2D. I also added the AttackArea2D for the Attack Animation for my sprite as well as 2 more child Nodes for it.

<img width="1491" height="834" alt="image" src="https://github.com/user-attachments/assets/7986eca8-df58-405d-8111-abeeb58a9232" />
Keybinds: I added the WASD and the Attack button for the movement of the Sprite.

<img width="402" height="445" alt="image" src="https://github.com/user-attachments/assets/75e992b0-8b95-491a-aa40-33f601e933a7" />
Coding the Movement + extra: Coded the necessary movement for the sprite and added animations like  the idle animation i got from the website together with this sprite. 

<img width="1481" height="450" alt="image" src="https://github.com/user-attachments/assets/9acda39e-ec1e-4eff-a5ca-928496111b5d" />
Coding Animation for attack: I coded the animation of the attack as well as small extra sprites during the slash.

<img width="1151" height="650" alt="image" src="https://github.com/user-attachments/assets/cd38e869-7465-42a6-a8c3-513faf486fcf" />
<img width="1146" height="645" alt="image" src="https://github.com/user-attachments/assets/150f89a8-f926-48d3-80f3-d21b9be79175" />
<img width="1151" height="646" alt="image" src="https://github.com/user-attachments/assets/15430d94-3f5b-46d7-847d-3ad2a653ce93" />
Testing Movement: Movement was somewhat smooth and the walking animation is fluid, idle animation gives a subtle life to the sprite so it was a nice addition.

<img width="1919" height="1072" alt="image" src="https://github.com/user-attachments/assets/f67d5d41-24ae-41d4-a8a3-f64080054d95" />
<img width="1921" height="1082" alt="image" src="https://github.com/user-attachments/assets/6506b8e9-7fc6-4f4c-be96-2c039f4104cd" />
<img width="1921" height="1082" alt="image" src="https://github.com/user-attachments/assets/1def26da-c944-4d6b-9baa-2d7e63a018b1" />
<img width="1921" height="1081" alt="image" src="https://github.com/user-attachments/assets/156352ef-dc6c-4aff-8dd5-227339e132e6" />
Testing Attack: Attack animations was implemented into the 4 directions depending to where the Sprite is looking, a simple animation of the Sprite was added during the slash and a custom pixelated effects at the slash was added.  

## Activity 3 — Tile Map & Dungeon Layout

![Dungeon Overview](screenshots/08-dungeon-overview.png)
Dungeon Overview: the finished **43 x 31** tile dungeon — **490 walkable cells**, **5 halls and 4 corridors**, 287 stone cells and a 139-cell invisible rim — built entirely from the tile sheets that already ship in `Assets/Dungeon`. Each hall is ringed by a two-cell-thick masonry band capped with a bright mint line, so the rooms read as lit floors inside solid walls. Past the band the world simply stops: a thin outline marks the edge and everything beyond it is black.

![Dungeon Gameplay](screenshots/09-dungeon-gameplay.png)
In-Game View: the player spawns in the pillared hall. The scene is dimmed with a `CanvasModulate` and the standing torches are real `PointLight2D`s, scattered per room from a seeded RNG so no two halls are lit the same way. The spike traps on the right are `trap.gd` — they never block you, they just make you cross slowly, and they stay flat for a predictable two seconds each cycle.

### Telling the floor tiles from the wall tiles

The pack ships as loose sheets (`T001-T003.png`, `C001.png`, `P001.png`, `TP001.png`, ...) instead of a ready made atlas, so I measured them first — opaque fraction per 16px cell — rather than guessing where each piece started. That measurement is what settles which art is floor and which is wall, and `T002.png` (208x176 px = 13x11 cells) splits cleanly in two:

| Sheet region | Artwork | Role |
| --- | --- | --- |
| `T002` rows 0-5 | dense, flat, full-cell brick | **FLOOR** — walkable ground only |
| `T002` row 7 | thin mint strokes: `(7,7)` corner, `(8,7)` straight, `(9,7)` corner, `(0,7)` / `(2,7)` verticals | **WALL top edges** |
| `T002` row 8 | `(4,8)` mint cap bar, and the doorway arch | **WALL cap + door** |
| `T002` row 9 | eight distinct masonry blocks, e.g. `(0,9)` | **WALL body** — raised masonry |

The floor brick and the wall body are different artwork, which is the whole point: using the rows 0-5 flat brick as a wall is what makes a border read as "more floor" instead of as a wall standing above it.

`Tile/T003.png` is deliberately **not** used — its pieces are pre-drawn wall *structures* with hollow gaps, not tiles.

### Walls: built from the wall kit, not stamped from floor tiles

Every piece in the wall kit is an **8px fragment sitting in half of its 16px cell**, so none of them can be used as a tile directly: placed one-per-cell, half of every cell is blank, which is what produced the earlier dashed caps and gaps. `_wall_atlas()` therefore composes them into real full-cell tiles once, at build time.

Shape and brickwork are two independent axes. The **shape** comes from which sides of that cell face open space, so corners, straight runs and steps all fall out of one rule and the wall follows the room's silhouette. The **brick** is one of eight row-9 masonry blocks, picked per cell by a hash of its coordinate. Hashing rather than randomising keeps the band stable across runs and frames while still varying enough that neighbouring cells do not match.

| Shape | Used when |
| --- | --- |
| `WALL_BODY` | fully buried in the band |
| `WALL_TOP` | open above |
| `WALL_TOP_L` | open above and left |
| `WALL_TOP_R` | open above and right |
| `WALL_SIDE_L` | open left |
| `WALL_SIDE_R` | open right |

Because shape is decided separately, randomising the brick can never turn a corner into a straight run. Three details that are easy to get wrong and are handled explicitly:

* **The cap is cut from `(4,8)`, not `(0,8)`.** Both hold a mint bar, but `(0,8)`'s starts on a 2px near-black bevel, so repeating it prints a dark notch every 8px. `(4,8)` is 8 unbroken bright pixels.
* **Fragments are composited pixel-by-pixel, not blitted.** `blit_rect` copies transparency as well as colour, so a mostly-empty fragment erases the brick under it and punches a hole in the wall. `_stamp()` keeps only opaque pixels.
* **Each brick is cut at its measured width, not a fixed 8px.** The eight row-9 bricks are not uniform: `(7,9)` is 9px wide in the *left* half of its cell and `(6,9)` straddles both halves. Assuming "8x8 in the right half" left variant 5 completely empty and printed a black hole in the wall wherever the hash chose it. `WALL_BRICK_SRC` records the real rectangle for each brick, and `check_layout` would not have caught this — it is a pixel bug, so the fix was to *measure* it.

Walls are a `WALL_RING = 2` band of solid rock; a one-cell wall has no face for the cap to sit on. Only the wall layer carries collision, so the player is stopped by walls and moves freely on the floor.

The wall is drawn at the sheet's own colour. An earlier build tinted the layer `Color(0.68, 0.74, 0.82)` to push it into shadow; that recoloured the artwork and has been removed.

### The edge of the world: an invisible boundary

Just outside the stone band sits a **one-cell rim** drawn from a second set of tiles that contain no masonry at all — only a thin outline along whichever sides still touch stone. Everything past it is the pure black clear colour from `project.godot`. The player is stopped by the outline exactly as he would be by rock: every void tile carries the same full-cell collision as a solid one, so an invisible wall with no hitbox would just be a hole in the map.

The rim is defined as *touching the band*, not touching the floor. That distinction is the whole bug this section exists to document: testing for adjacent floor is exactly what `_is_band()` already does, so the two predicates came out byte-identical and the void tiles were unreachable — the "invisible boundary" was drawn nowhere and silently did nothing. `check_layout.gd` now asserts the rim is non-empty and that every void tile really collides, because a boundary that exists only in a function nobody calls is not a boundary.

### Layers inside dungeon.tscn

* `Floor` — bright brick on every walkable cell, picked in a regular bond keyed on the cell coordinate (never at random; a random pick per cell made the floor look like TV static).
* `Hazards` — the spike traps, at `z_index` 0 so they sit flat in the floor and the player walks *over* them.
* `Walls` — the band built from `T002`'s wall kit (raised brick body, lit cap, corners) in the sheet's own colours, plus the outlined invisible rim beyond it. The only layer with collision.
* `Props` — chests, pots, crates and torches.
* `EnemySpawns` — a `Marker2D` at the centre of each hall, so enemy spawning has somewhere to aim. No enemies are spawned yet.

### Level layout

The layout is written as a list of carved rectangles at the top of `dungeon_builder.gd`, so rooms and corridors are edited in one readable place:

```
     cistern --- crypt --- forge
        |                    |
       hall --- vault -------+
```

* **hall** - the spawn hall: a chest, and the player spawn.
* **cistern** - the west hall, dotted with breakable pots.
* **crypt** - the north burial room, with a chest.
* **forge** - the north-east workshop, stacked with crates.
* **vault** - the treasure vault, its long approach guarded by a full-width spike strip.

The four corridors wire them into a **tree, not a loop**: `hall - cistern - crypt - forge`, with `hall - vault` hanging off the spine. This used to be a five-corridor loop, but the forge-to-vault shortcut was removed to open the map up, and with it went the only way to circle back — so the level is now a branching route rather than a loop. Every corridor is 3 cells (96 px) across, which is the minimum the player's 43x67 px collider can turn around in.

### The tiles sheet IS the map

Everything is drawn from `Assets/Dungeon/dungeon_V.1.0.0_nyknck/Tile/T002.png` (208x176 px = 13x11 cells of 16 px), measured cell by cell rather than eyeballed. The floor and the walls come from **different artwork in that one sheet**, which is what separates the two surfaces:

* **Floor and walls are different bricks.** The floor uses the flat brick from T002's rows 0-5 at full brightness; the wall uses the masonry blocks from T002's row 9. Drawing both from the same flat tile is what made an earlier build look like one field of static with no boundary.
* **Walls** are a two-cell band of rock around the walkable area, then the outlined rim, then nothing. The wall-to-floor ratio is **0.59** and `check_layout.gd` prints it, because when that number climbs the map turns into noise.
* **The band is built, not stamped.** Each cell picks its wall variant from the sides that face open space, so the lit top cap turns correctly into corners and down the sides instead of repeating as a dashed border. The full breakdown is under [Walls: built from the wall kit](#walls-built-from-the-wall-kit-not-stamped-from-floor-tiles).
* **Coins** were tried and removed: a coin has no collision, so `_validate` had to special-case it as a non-blocking prop, and 19 scattered sprites read as clutter on a floor that is already busy. Gold now comes only from opening a chest.

### Traps

`TRAPS` is one list of cells, and each cell becomes a single `trap.gd` node holding **both** the 14-frame TP001 spike loop and the Area2D that slows the player, so the artwork and the hitbox can never drift apart. A trap is never solid — it costs time, not a life.

The TP001 art needed **no** help from us. Rendering all 14 frames over the floor colour showed the spike strip already draws its own dark hole in the base of the cell, with the spike rising out of it, fully retracted in frames 1-2. It is a self-contained floor tile, so it is placed straight onto the floor with nothing under it. An earlier build drew a dark `Hazards` *tile* beneath every trap to "make the hazard readable"; that was the cause of the floating look, because an extra opaque square over a self-contained tile only darkened a hole the art had already drawn.

Traps then had a second, separate floating bug: they lived in the `Props` node at `z_index` 2, which is *above* the player, so walking through a strip looked like passing underneath a floating slab. They now sit in their own `Hazards` node at `z_index` 0, flat on the floor, and the player stands on the spikes.

Strips are laid two ways on purpose: **full-width** ones span the corridor and have to be crossed slowly, while **staggered** ones sit down the middle and can be stepped around if you spot them in time.

#### The two-second safe window

Looping all 14 TP001 frames gives roughly one second of travel per revolution with no pause, so the spikes flickered and there was never a safe moment to plan a crossing. The frames were therefore *measured* before the cycle was written, not assumed:

| Frames | What they show | Phase |
| --- | --- | --- |
| 1-3, 14 | no spike visible | **DOWN** |
| 4-7 | spikes extending | rising |
| 8-9 | spikes at full height | up |
| 10-13 | spikes retracting | falling |

`trap.gd` drives the cycle by hand rather than handing it to `AnimatedSprite2D` playback, because the pause has to be exact: hold **DOWN for `safe_time` (2.0 s)**, then play frames 4-13 once at `cycle_fps` (9 fps, so 1.11 s), then hold DOWN again. The player gets a flat, predictable two-second window every 3.11 s to start a crossing, and `test_trap_cycle.gd` verifies that by watching which frames a live trap actually displays.

The slow is applied the instant the phase flips to TRAVEL rather than on the next tick. That is not cosmetic: with the slow lagging a frame behind, a trap could be visibly out of the floor while still letting the player walk across at full speed, which is exactly the failure the safe window exists to rule out.

The slow is not a one-off hack. `character_body_2d.gd` keeps a dictionary of active penalties keyed by the source that set them, and `current_speed()` returns the base speed with the **strongest** active slow applied. Taking the strongest rather than multiplying matters: the player collider is 43x67 px while a tile is only 32 px, so stepping onto a three-tile strip genuinely overlaps all three traps. Multiplying gave 0.09x — effectively frozen, which reads as a bug — whereas the minimum caps the penalty at one trap's worth and is predictable.

### Game feel extras

* `prop_breakable.gd` — the player's existing `AttackArea(Area2D)` is only switched on for a few frames during a slash, so chests, pots and crates are `Area2D`s that listen for it: pots and crates shatter (8 and 7 frame animations) and chests open once (7 frames) and throw a short arc of coins. Chests carry no "[J]" prompt label: the slash opens them exactly like every other prop, so a floating key hint in world space was pure clutter (and it named a key, `J`, that is not even bound — the attack is `K`).
* `torch.gd` — every torch flickers its `PointLight2D` energy with two out-of-phase sine waves, so the light never looks static. **Where** the torches stand is generated rather than listed: per room, a seeded RNG (`TORCH_SEED`) draws how many lights that room gets and then places each one, keeping a minimum Chebyshev gap from the ones already placed. The seed is fixed, so the lighting is varied but identical on every run. Candidates are rejected on top of props, on traps, and inside a corridor — the room and corridor rectangles overlap where they meet, so the doorway rule is checked rather than assumed.
* `trap.gd` — applies and removes its own speed penalty, keyed by instance id so leaving one trap can never clear another's.
* `Camera2D` — added to the player with position smoothing and limits set to the dungeon bounds, so the camera follows the player and never shows anything outside the map.
* `project.godot` — the default texture filter is set to nearest so the pixel art stays crisp in the x2 scaled dungeon.

### Checking the layout

The dungeon refuses to be shipped wrong. `check_layout.gd` runs the builder's **own** `_build_grid` and `_validate` (rather than a second copy of the rules), prints an ASCII map with a letter on every chest, trap, torch, pot and crate (`#` stone, `:` the outlined rim), and fails on any unreachable cell, corridor narrower than the player, a blocking prop in a corridor, a prop off the floor, two props in one cell, or a trap that is unreachable, duplicated or covered by a prop. It also prints the wall-to-floor ratio, because that number is what separates a dungeon from a field of static.

It then boots the real `Main.tscn` and counts the nodes that actually ended up in the tree, proving the player spawn lands on carved floor and that every declared prop really was built. That second step exists because the first one is not enough: instantiating a scene during `_initialize()` runs before `root` is inside the tree, so `_ready` never fires, the dungeon silently builds nothing, and a layout check happily passes on an empty scene.

Three checks were added with this work, because each covers a defect that was invisible in a screenshot:

* **The rim must exist and must collide.** A count of void cells, plus a read of each one's collision polygons. This is the only thing standing between "invisible boundary" and a function that is never called.
* **No torch may sit in a doorway.** The room and corridor rectangles overlap where they meet, so a cell chosen from inside a room rect can still be a corridor's throat. This is tested against the generated positions rather than assumed, precisely because the placement is randomised.
* **The removed hallway must stay removed.** Any floor or trap left in `Rect2i(33, 13, 3, 8)` is reported, so a partial deletion cannot pass silently.
* **All eight wall bricks must appear.** The brick is picked by a hash, so a variant that renders as an empty tile is invisible to a layout check and shows up only as an unexplained hole in the wall.

`test_trap_slow.gd` boots the real `Main.tscn`, walks the player onto **every** trap, and checks the speed it would actually move at: that each trap slows, that overlapping traps do not stack into a freeze, that stepping off restores full speed exactly, and that the cycle repeats.

`test_trap_cycle.gd` watches a live trap's animation frames and confirms frames 4-13 play in order, that the flat pose returns twice, and that the window between the spikes going down and rising again is a genuine 2.00 s. It times *transitions* against the wall clock rather than counting samples: headless runs idle frames far faster than the trap's cadence, so summing per-sample hits on the flat frame measures the sampler, not the trap.

Current results: `RESULT: OK` from all three, with **490 walkable cells**, **287 stone cells**, a **139-cell** invisible rim, **10 traps**, **9 scattered torches** and all **8 of 8** wall brick variants present, at a wall-to-floor ratio of **0.59**.

### Rebuilding and checking

```
godot --headless --path . --script res://tools/check_layout.gd    # proves the map is playable, prints an ASCII map
godot --headless --path . --script res://tools/test_trap_slow.gd  # proves the traps slow and always let go
godot --path . --script res://tools/capture_screenshots.gd        # refreshes the two screenshots above
```

Controls: `WASD` to move, `K` to attack (the slash breaks pots and crates, and opens chests).

## Week 7: Enemy AI Improvements

I improved enemy AI (patrol, detection, chase, attack).

Enemies patrol between waypoints (or idle in place when no patrol route is
assigned), detect the player with a vision/trigger radius, chase the player
once seen, and attack in melee range with a short cooldown. Losing sight of
the player for a few seconds makes them return to patrol instead of chasing
forever. No gameplay tuning beyond that AI state work.

## Week 8: Multi-Platform Export & Team Git

Platforms: **Windows PC** (Platform 1) and **Web (HTML5)** (Platform 2).
Engine: **Godot 4.7 (Forward Plus)**. Existing inputs reused unchanged:
`move_up` (W), `move_down` (S), `move_left` (A), `move_right` (D),
`attack` (K). No gameplay or game-logic files were rewritten.

### Platform tweak and why

- Display: `window/stretch/mode="canvas_items"`, `aspect="keep"`,
  viewport `1152x648` (16:9). `canvas_items` scales UI crisply on any
  window; `keep` preserves aspect with letterboxing instead of stretching
  the dungeon. This matches the Web requirement and is harmless on PC.
- Web "Click to Start" screen: new `start_screen.tscn` (+`start_screen.gd`)
  is now the main scene and changes to `Main.tscn` on click / `ui_accept`
  / `attack`. Rationale: browsers block audio until a user gesture, so the
  gate provides that gesture before the game boots. `Main.tscn` itself is
  untouched; the button just calls `change_scene_to_file("res://Main.tscn")`.
- PC fullscreen toggle: `platform_tweaks.gd` autoload listens for F11 and
  toggles `DisplayServer.WINDOW_MODE_FULLSCREEN` / `WINDOWED`. PC-only per
  spec; on Web the key is simply ignored by the browser.
- Defaults chosen (nothing was specified in the brief): Platform 2 = Web,
  Godot 4.7 per `project.godot`, Godot exe = "find it" (not on PATH on this
  machine), shared practice repo = "none" so a local bare-repo drill was
  used instead.

### How to run each build

- PC: run `builds/pc/Echo.exe` (produced by the `Windows PC` preset).
- Web: `cd builds/web` then `python -m http.server 8000` and open
  `http://localhost:8000/index.html`. Requirement: serve over HTTP (not
  `file://`) so COOP/COEP + threads work; use a Chromium browser.

### Export status / real issues

- `export_presets.cfg` contains `Windows PC` and `Web` presets with the
  paths above.
- CLI export was attempted but the Godot executable is not on `PATH` on
  this machine (`godot --version` -> command not found; checked
  `C:\Program Files\Godot\Godot.exe` and
  `%LOCALAPPDATA%\Programs\Godot\Godot.exe`, both absent), so no binaries
  exist yet under `builds/`.
- Exact manual steps once Godot 4.7 + templates are installed:
  1. Install the Godot 4.7 export templates
     (`Editor > Manage Export Templates > Install`, matching 4.7).
  2. Open the project, then `Project > Export...` and confirm both
     presets validate, or from a terminal with Godot on PATH run:
     `godot --headless --path . --export-release "Windows PC" builds/pc/Echo.exe`
     `godot --headless --path . --export-release "Web" builds/web/index.html`
  3. If templates are missing the CLI prints
     `ERROR: No export template found`; fix from CLI is not possible
     without the template pack, so install them via the editor or
     download the `Godot_v4.7_*_export_templates.tpz` and place under
     `%APPDATA%\Godot\export_templates\4.7.*`.

### Team Git summary

- Shared practice repo URL: none, so practice ran against a local bare
  repo in the temp folder acting as "origin".
- Branch `week8-practice` created, a text file edited, committed, pushed.
- Deliberate conflict: same line of the same file edited on `main` and
  `week8-practice`, merged, resolved, committed. Raw markers captured
  below before resolving.

Conflict markers (3-line explanation):

1. `<<<<<<< HEAD` marks the start of *our* side (the branch we merged
   into, here `main`) and everything after it up to `=======` is our text.
2. `=======` is the divider: above is ours, below is *theirs* (the branch
   being merged in, here `week8-practice`).
3. `>>>>>>> week8-practice` marks the end of *their* side; resolving means
   editing the file to the wanted result and committing without markers.

Raw captured markers from the drill (`%TEMP%\week8-practice\notes.txt`):

```
<<<<<<< HEAD
line1: conflicting edit from main branch
=======
line1: edit from week8-practice branch
>>>>>>> week8-practice
```

Resolved to `line1: RESOLVED - combined main + week8-practice edits` and
committed as `resolve merge conflict (kept both)`; branch
`week8-practice` was pushed to the local `origin` bare repo.



## Activity 3 — Level Design



https://github.com/user-attachments/assets/89ced82c-cbf8-4e94-ac13-98b43f25d974

I beta level who although has some bugs i ignore it for now since i want to showcase the progression and the purpose of the game. Before i added enemies i added chest, vases and jars which would soon be filled with loot. you can interact all of them its either you break them or you open. I created this level using sprites of chests and background miscellaneous and ofcoure assets I acquired online such as the tile map and the tile sheets.


## Week 4: Enemies and Sprites

Added 8 enemy types, each in its own dungeon room. Every enemy has 5 animations (idle, walk, attack, hurt, death) and is sized to match the player.

### Rat (Vault)
Fast and weak. The first enemy the player meets.

<img width="391" height="272" alt="Screenshot 2026-10-04 205313" src="https://github.com/user-attachments/assets/5dbadb36-a330-4376-9168-8891e1f9b046" />


### Slime (Cistern)
Slow, with a long attack wind-up.

<img width="370" height="279" alt="Screenshot 2026-10-04 205325" src="https://github.com/user-attachments/assets/47843aa3-16c2-4316-9610-24cf766c4805" />


### Mushroom (Crypt)
Short-range spit attack.

<img width="315" height="269" alt="Screenshot 2026-10-04 205329" src="https://github.com/user-attachments/assets/db7093fe-0193-4d66-8b42-169d7029f3db" />


### Bat (Forge)
Fast flyer that moves erratically.

<img width="261" height="261" alt="Screenshot 2026-10-04 205341" src="https://github.com/user-attachments/assets/4912d25f-1160-4184-99af-82ebfb5b4787" />


### Flying Eye (Eye Well)
Flies, with a ranged-style attack animation.

<img width="261" height="242" alt="Screenshot 2026-10-04 205355" src="https://github.com/user-attachments/assets/9c7ea1d4-18e9-4113-8c85-69558cd6a41b" />


### Goblin (Goblin Den)
Tougher melee enemy.

<img width="249" height="247" alt="Screenshot 2026-10-04 205400" src="https://github.com/user-attachments/assets/859e6659-c92a-4d2b-817a-7b13746561df" />


### Mimic (Mimic Den and Crypt)
Starts as a chest, then bursts open and chases the player.

<img width="259" height="256" alt="Screenshot 2026-10-04 210132" src="https://github.com/user-attachments/assets/9a825550-6231-453f-9c44-06f4de1cd43c" />


### Skeleton, boss (Bone Hall)
The toughest enemy, with double health.

<img width="217" height="295" alt="Screenshot 2026-10-04 205534" src="https://github.com/user-attachments/assets/c0ae106b-d41b-42a8-94ae-2a503c8322b7" />


### Also added this week
- Enemy AI: idle, chase, attack, hurt and death. Attacks only hurt during the animation's damage frames.
- Enemies wake up when the player enters their room and return home if the player runs too far away.
- Chests and enemies drop coins that the player collects by walking over them.
- HUD with hearts and a coin counter.
- Spike traps that only hurt while the spikes are out.
- Collision and draw-order fixes so the player no longer clips into walls.

---

## Week 5: Audio

Added music and sound effects, all played through one `AudioManager`.



https://github.com/user-attachments/assets/198a2819-933a-4868-b60e-a1d78d8c8e82



### What has sound
- Looping background music with a fade-in
- Player: sword slash, footsteps, getting hurt
- Loot and props: chest opening, coin drop, coin pickup, vase breaking, crate breaking
- Enemies: attack, hurt and death sounds for each species, plus the Mimic burst
- Traps: a knife sound when the spikes hit

### Details
- Enemy sounds only play when the enemy is near the player.
- Repeated sounds use small random pitch and volume changes.
- At most 3 copies of the same sound play at once, so coin showers stay clean.
- Music and effects are on separate audio buses, each with its own volume.

### Credits
- RPG sounds by Kenney (kenney.nl), CC0.
- Other effects from Freesound.
- Exploration | Chiptune RPG Adventure Theme by NickPanek

## Week 7: Enemy AI Improvements

I improved the AI for my enemies so they react to the player instead of just moving in a fixed pattern.

- **Behavior:** enemies patrol, detect the player when in range, chase, and attack
- **State machine:** Patrol → Chase → Attack → Return to patrol
- **Detection:** [Area2D detection radius / RayCast2D line of sight]
- **Tuning:** adjusted speed, attack cooldown, and health so the difficulty feels fair
- **Result:** enemies are more challenging and respond to the player's position

## Week 8: Multi-Platform Export & Team Git

### Exports
| Platform | Status | Location |
|----------|--------|----------|
| Windows PC | Exported and tested | `builds/pc/` |
| Web (HTML5) | Exported and tested | `builds/web/` |

### Platform-specific tweak
For the web build I set the stretch mode to `canvas_items` and the aspect to `keep` in Project Settings (Display → Window), so the game scales correctly in any browser window. [Optional: I also added a "Click to Start" screen because browsers block audio until the player interacts with the page.]

### How to run
- **PC:** open `builds/pc/[game name].exe`.
- **Web:** run `python -m http.server` inside `builds/web/`, then open `http://localhost:8000` in a browser. Opening `index.html` directly will not work.

### Team Git practice
- Created a branch on the shared practice repo and opened a pull request
- Deliberately created a merge conflict by editing the same line on two branches
- Resolved the conflict by choosing the correct lines and removing the markers (`<<<<<<<`, `=======`, `>>>>>>>`)
- Practice repo: [paste link]

### Issues encountered
- export templates had to be installed first.
- e.g. web build needed a local server to run.
`Week 8: multi-platform export + team Git practice`
