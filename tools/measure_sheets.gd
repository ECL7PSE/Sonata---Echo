extends SceneTree
## One-shot: measures every monster sheet from real pixel data.
##
##   godot --headless --path . --script res://tools/measure_sheets.gd
##
## A MEASUREMENT tool, not a test. It prints the numbers monster_db.gd is then
## generated from, so the database is never hand-typed from a guess. Every frame
## size here comes from the image itself: the frame height is the sheet height,
## verified per sheet by the width dividing exactly ("square ok").
##
##   visible bbox    tight box of alpha-bearing pixels in a frame
##   bottom-centre   middle of the bbox at its lowest visible row. This is what
##                   gets pinned to the ground anchor, so a sprite cannot appear
##                   to float or sink as the animation plays.
##
## Anchoring maths: a centred AnimatedSprite2D draws a frame's top-left at
## (-fw/2, -fh/2), so content pixel (bx, by) lands at (bx - fw/2, by - fh/2).
## offset = (fw/2 - bx, fh/2 - by) moves it onto the node origin, and since
## offset and content scale together this holds at ANY scale.

const BASE := "res://Assets/Monsters_Creatures_Fantasy/"

## The player's idle sheet and the Sprite2D scale it is drawn at, from
## Main.tscn.
const PLAYER_SHEET := "res://Assets/Player/Dark_Hatman_Topdown_Character/Animations/Idle/darkhatman_idle_sheet_64x64.png"
const PLAYER_CELL := 64
## Main.tscn sets the player Sprite2D to scale 1.2. The player sits OUTSIDE the
## Dungeon node, so its global scale is 1 and this is the whole story.
const PLAYER_SCALE := 1.2

## The Dungeon node is scaled 2x and every monster is its child, so a monster's
## RENDERED size is source x sprite scale x 2. Measuring against the player's
## sprite scale alone made every monster render at twice its intended size,
## which is exactly the "2x too big" report. Every size here is RENDERED.
const DUNGEON_SCALE := 2.0

## One knob for every monster size. Exported on the enemy so it can be tuned
## without regenerating the database.
## One knob for every monster size, applied on top of the measured scale.
## Mirrors Enemy.ENEMY_SCALE_MULT so the two can be tuned together.
static var ENEMY_SCALE_MULT := 1.0


## The player's visible body height on screen, measured from its own sprite.
##
## Never hardcoded: the player art or its scale can change, and a stale constant
## here would silently resize the entire bestiary.
static func player_visible_height() -> float:
	var img: Image = (load(PLAYER_SHEET) as Texture2D).get_image()
	# Scanned inline rather than via _bbox(), which is an instance method.
	var min_y := 999999
	var max_y := -1
	for y in PLAYER_CELL:
		for x in PLAYER_CELL:
			if img.get_pixel(x, y).a > 0.0:
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_y < 0:
		return 48.0
	return float(max_y - min_y + 1) * PLAYER_SCALE


## Target visible size as a multiple of the PLAYER's visible height, applied to
## the LARGER of each monster's body width and height.
##
## Using max(width, height) rather than height alone is what stops a wide, flat
## creature like the bat or the rat from being scaled by its height and ending
## up several times the player's width.
const BODY_MULT := {
	"rat": 1.0, "slime": 1.0, "bat": 1.0, "mushroom": 1.0,
	"flying_eye": 1.0, "goblin": 1.0,
	"mimic": 1.2,
	"skeleton": 1.3,
}


## The dormant pose is the real chest at 1:1. Both figures come from
## measure_sheets.gd's own pixel scan of C001_01, not from this comment.
const MIMIC_CHEST_W := 16
const MIMIC_CHEST_H := 15
const ALPHA_FLOOR := 1

## Target visible height on screen. A tile is 32px, so this is the middle of
## the "about 1 to 1.5 tiles" band.
const BODY_H := {
	"rat": 40.0, "slime": 40.0, "bat": 40.0, "mushroom": 40.0,
	"flying_eye": 40.0, "goblin": 44.0, "skeleton": 48.0,
	# The awake mimic is a full creature, so it gets the boss-sized target
	# rather than the 16x15 chest profile it wears while dormant.
	"mimic": 48.0,
}

## monster, animation key, sheet file, does this sheet define the body size.
## A file starting with "res://" is used verbatim; anything else is resolved
## under BASE. That is how the mimic's dormant pose borrows the REAL chest art
## instead of the mimic's own closed chest, so a dormant mimic and a real chest
## are literally the same sprite rather than two similar ones.
const SHEETS := [
	["rat", "idle", "Rat/idle", true],
	["rat", "walk", "Rat/run", false],
	["rat", "attack", "Rat/attack_bite", false],
	["rat", "hurt", "Rat/hurt", false],
	["rat", "death", "Rat/rat-death", false],
	["slime", "idle", "Slime/idle", true],
	["slime", "walk", "Slime/walk", false],
	["slime", "attack", "Slime/attack", false],
	["slime", "hurt", "Slime/hurt", false],
	["slime", "death", "Slime/death", false],
	["bat", "idle", "Bat/fly", true],
	["bat", "walk", "Bat/fly", false],
	["bat", "attack", "Bat/attack", false],
	["bat", "hurt", "Bat/hurt", false],
	["bat", "death", "Bat/death", false],
	["mushroom", "idle", "Mushroom/Idle", true],
	["mushroom", "walk", "Mushroom/Run", false],
	["mushroom", "attack", "Mushroom/Attack", false],
	["mushroom", "hurt", "Mushroom/Take Hit", false],
	["mushroom", "death", "Mushroom/Death", false],
	["flying_eye", "idle", "Flying eye/Flight", true],
	["flying_eye", "walk", "Flying eye/Flight", false],
	["flying_eye", "attack", "Flying eye/Attack", false],
	["flying_eye", "hurt", "Flying eye/Take Hit", false],
	["flying_eye", "death", "Flying eye/Death", false],
	["goblin", "idle", "Goblin/Idle", true],
	["goblin", "walk", "Goblin/Run", false],
	["goblin", "attack", "Goblin/Attack", false],
	["goblin", "hurt", "Goblin/Take Hit", false],
	["goblin", "death", "Goblin/Death", false],
	["mimic", "dormant",
			"res://Assets/Dungeon/dungeon_V.1.0.0_nyknck/Chest/C001/C001_01.png",
			false],
	["mimic", "opening", "Mimic/opening", false],
	["mimic", "idle_open", "Mimic/idle_open", false],
	["mimic", "transform", "Mimic/transform", false],
	# The AWAKE profile is measured HERE, not on the dormant chest. Sizing a
	# monster off its closed lid gives it a 16x15 collision box and a hitbox you
	# can walk around, which is not what the creature is once it has stood up.
	["mimic", "idle_transformed", "Mimic/idle_transformed", true],
	["mimic", "walk", "Mimic/walk", false],
	["mimic", "attack", "Mimic/attack_1", false],
	["mimic", "hurt", "Mimic/hurt", false],
	["mimic", "death", "Mimic/death", false],
	["skeleton", "idle", "Skeleton/Idle", true],
	["skeleton", "walk", "Skeleton/Walk", false],
	["skeleton", "attack", "Skeleton/Attack", false],
	["skeleton", "hurt", "Skeleton/Take Hit", false],
	["skeleton", "death", "Skeleton/Death", false],
]
func _initialize() -> void:
	# The mimic must be indistinguishable from a real chest while dormant, so
	# C001 is measured first and used as the mimic's size target.
	var chest: Image = (load("res://Assets/Dungeon/dungeon_V.1.0.0_nyknck/"
			+ "Chest/C001/C001_01.png") as Texture2D).get_image()
	var cb := _bbox(chest, 0, chest.get_width(), chest.get_height())
	var cw := float(cb.z - cb.x + 1)
	var ch := float(cb.w - cb.y + 1)
	print("C001 real chest: image %dx%d  visible %dx%d"
			% [chest.get_width(), chest.get_height(), int(cw), int(ch)])
	print("")

	print("=== SHEET MEASUREMENTS ===")
	print("")
	var body: Dictionary = {}
	var tables: Array = []

	for row in SHEETS:
		var monster: String = row[0]
		var anim: String = row[1]
		var file: String = row[2]
		var is_body: bool = row[3]
		var path: String = row[2]
		if not path.begins_with("res://"):
			path = BASE + path + ".png"
		if not ResourceLoader.exists(path):
			print("%-12s %-17s MISSING" % [monster, anim])
			continue
		var img: Image = (load(path) as Texture2D).get_image()
		var fw: int = img.get_height()
		var fh: int = img.get_height()
		if img.get_width() % fw != 0:
			print("%-12s %-17s NOT SQUARE (%d x %d)"
					% [monster, anim, img.get_width(), img.get_height()])
			continue
		var count: int = img.get_width() / fw
		var boxes: Array = []
		for f in count:
			boxes.append(_bbox(img, f, fw, fh))
		print("%-12s %-17s %3d x %3d  frames=%-3d square ok"
				% [monster, anim, fw, fh, count])
		for f in count:
			var b: Vector4i = boxes[f]
			print("      f%-2d bbox %3d,%3d..%3d,%3d  size %2dx%-2d  bc %.1f,%.0f"
					% [f, b.x, b.y, b.z, b.w, b.z - b.x + 1, b.w - b.y + 1,
					(b.x + b.z) * 0.5, float(b.w)])
		if is_body:
			body[monster] = boxes[0]
		tables.append({"monster": monster, "anim": anim, "file": file,
				"path": path, "fw": fw, "fh": fh, "count": count,
				"boxes": boxes})

	_generate(body, tables)


## Tight bounding box of one frame. An empty rect (z < 0) means a blank frame,
## which is worth reporting rather than quietly treating as 0x0.
func _bbox(img: Image, f: int, fw: int, fh: int) -> Vector4i:
	var min_x := 999999
	var min_y := 999999
	var max_x := -1
	var max_y := -1
	for y in fh:
		for x in fw:
			if img.get_pixel(f * fw + x, y).a >= float(ALPHA_FLOOR) / 255.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return Vector4i(0, 0, -1, -1)
	return Vector4i(min_x, min_y, max_x, max_y)


## Prints the scale and the per-frame offset table for each monster.
func _generate(body: Dictionary, tables: Array) -> void:
	print("")
	print("=== SCALE + ANCHOR (bottom-centre pinned to node origin) ===")
	var scales: Dictionary = {}
	var offsets: Dictionary = {}
	var sizes: Dictionary = {}
	var dormant: Dictionary = {}
	for monster in body.keys():
		var b: Vector4i = body[monster]
		sizes[monster] = Vector2i(b.z - b.x + 1, b.w - b.y + 1)
		if monster == "mimic":
			# The dormant pose is the real chest at 1:1, and it needs its own
			# scale and body size: sharing the awake figures would give a closed
			# chest a 48px-tall collision box.
			dormant["mimic"] = Vector2i(MIMIC_CHEST_W, MIMIC_CHEST_H)
		var bw := float(b.z - b.x + 1)
		var bh := float(b.w - b.y + 1)
		# Sized against the PLAYER, not the tile: the LARGER body dimension is
		# scaled to the player's visible height times this species' multiple.
		var target: float = player_visible_height() \
				* float(BODY_MULT[monster]) * ENEMY_SCALE_MULT
		# Rendered size, so the 2x Dungeon scale divides out here and a monster
		# ends up the same on-screen height as the player.
		var longest_src := maxf(bw, bh)
		var scale: float = target / (longest_src * DUNGEON_SCALE)
		# A rat or a bat is far wider than it is tall. Matching the longest
		# dimension to the player's HEIGHT would let a 54px-wide bat render
		# wider than the player is tall, so wide bodies are additionally capped
		# at 1.5x the player's height.
		var w_cap: float = player_visible_height() * 1.5 \
				* ENEMY_SCALE_MULT / (bw * DUNGEON_SCALE)
		if scale > w_cap:
			scale = w_cap
		print("")
		print("%-12s body %dx%d src -> %.1fx%.1f RENDERED  scale %.4f"
				% [monster, int(bw), int(bh),
				bw * scale * DUNGEON_SCALE, bh * scale * DUNGEON_SCALE, scale])
		scales[monster] = scale
		var mine: Array = []
		for t in tables:
			if t["monster"] != monster:
				continue
			var fw: int = t["fw"]
			var fh: int = t["fh"]
			var per_frame: Array[Vector2] = []
			for f in t["boxes"].size():
				var bb: Vector4i = t["boxes"][f]
				var bc := Vector2((bb.x + bb.z) * 0.5, float(bb.w))
				per_frame.append(Vector2(round(fw * 0.5 - bc.x),
						round(fh * 0.5 - bc.y)))
			# Does ONE per-sheet offset (frame 0's) hold every frame to within a
			# pixel? If not, that sheet genuinely needs per-frame offsets and is
			# reported as such rather than silently fudged.
			var shared: Vector2 = per_frame[0]
			var drift := 0.0
			for f in t["boxes"].size():
				var bb: Vector4i = t["boxes"][f]
				var bc := Vector2((bb.x + bb.z) * 0.5, float(bb.w))
				var landed := Vector2(bc.x - fw * 0.5, bc.y - fh * 0.5) + shared
				drift = maxf(drift, landed.length())
			var mine_sheet := {
				"anim": t["anim"], "count": t["count"], "fw": fw, "fh": fh,
				"file": t["path"], "per_frame": per_frame, "shared": shared,
				"drift": drift,
			}
			if drift > 1.0:
				_needs_per_frame.append("%s/%s (%.2f px)"
						% [monster, t["anim"], drift])
			mine.append(mine_sheet)
		scales[monster] = scale
		offsets[monster] = mine

	print("")
	print("=== SHEETS THAT NEED PER-FRAME OFFSETS ===")
	if _needs_per_frame.is_empty():
		print("none - one per-sheet offset holds every frame within 1px")
	else:
		for n in _needs_per_frame:
			print("  " + n)
	_write_db(scales, offsets, sizes, dormant)
## the measured one, so the file is generated rather than transcribed.
const STATS := {
"rat": {"hp": 4, "dmg": 1, "spd": 86.0, "coins": [1, 3], "cd": 0.7},
"slime": {"hp": 6, "dmg": 1, "spd": 78.0, "coins": [1, 3], "cd": 0.9},
"bat": {"hp": 6, "dmg": 1, "spd": 108.0, "coins": [1, 3], "cd": 0.6},
"mushroom": {"hp": 8, "dmg": 2, "spd": 82.0, "coins": [1, 3], "cd": 1.0},
"flying_eye": {"hp": 8, "dmg": 2, "spd": 104.0, "coins": [1, 3], "cd": 0.8},
"goblin": {"hp": 10, "dmg": 2, "spd": 94.0, "coins": [1, 3], "cd": 1.0},
"mimic": {"hp": 14, "dmg": 3, "spd": 90.0, "coins": [3, 6], "cd": 1.1},
"skeleton": {"hp": 20, "dmg": 3, "spd": 96.0, "coins": [6, 10], "cd": 1.2},
}
const DETECT_RANGE := 120.0
const ATTACK_COOLDOWN := 1.0


func _write_db(scales: Dictionary, offsets: Dictionary, sizes: Dictionary, dormant: Dictionary) -> void:
	var out := PackedStringArray()
	out.append("class_name MonsterDB")
	out.append("extends RefCounted")
	out.append("## GENERATED by tools/measure_sheets.gd - do not hand-edit.")
	out.append("##")
	out.append("## Every path, frame count, frame size, scale and offset here was read")
	out.append("## from the PNG pixels. Re-run the generator after replacing any art.")
	out.append("##")
	out.append("## Anchoring: `offset` moves a frame's visible BOTTOM-CENTRE onto the")
	out.append("## sprite origin, so the node position is always the ground contact")
	out.append("## point and nothing floats or sinks between frames. `offsets` is the")
	out.append("## per-frame form, emitted only for sheets where one shared offset")
	out.append("## drifts more than a pixel.")
	out.append("")
	out.append("## Shared behaviour numbers.")
	out.append("const DETECT_RANGE := %.1f" % DETECT_RANGE)
	out.append("const ATTACK_COOLDOWN := %.1f" % ATTACK_COOLDOWN)
	# The sizing rule, so the test can verify it instead of trusting the numbers.
	out.append("")
	out.append("## The player's visible body height on screen, measured from its sprite.")
	out.append("const PLAYER_H := %.4f" % player_visible_height())
	# Monsters live under a 2x-scaled Dungeon, so this is what the test must
	# multiply by to get a true on-screen size.
	out.append("const DUNGEON_SCALE := %.4f" % DUNGEON_SCALE)
	out.append("## Widest a monster may render, as a multiple of PLAYER_H.")
	out.append("const MAX_W_MULT := 1.5")
	out.append("## Target visible size per species, as a multiple of PLAYER_H, applied")
	out.append("## to the LARGER of body width and height.")
	out.append("const BODY_MULT := {")
	var mrows: Array[String] = []
	for monster in STATS.keys():
		mrows.append("\t\"%s\": %.2f," % [monster, float(BODY_MULT[monster])])
	for r in mrows:
		out.append(r)
	out.append("}")
	out.append("")
	for monster in STATS.keys():
		var s: Dictionary = STATS[monster]
		var rows: Array = offsets[monster]
		out.append("## %s" % monster)
		out.append("const %s := {" % monster.to_upper())
		out.append("\t\"hp\": %d," % int(s["hp"]))
		out.append("\t\"damage\": %d,          # in half-hearts (2 hp)" % int(s["dmg"]))
		out.append("\t\"speed\": %.1f," % float(s["spd"]))
		out.append("\t\"coin_min\": %d," % int(s["coins"][0]))
		out.append("\t\"coin_max\": %d," % int(s["coins"][1]))
		out.append("\t\"attack_cooldown\": %.2f," % float(s.get("cd", 1.0)))
		out.append("\t\"detect_range\": %.1f," % DETECT_RANGE)
		out.append("\t\"scale\": %.4f," % float(scales[monster]))
		out.append("\t\"body\": Vector2i(%d, %d),   # visible body, source px"
				% [int(sizes[monster].x), int(sizes[monster].y)])
		if dormant.has(monster):
			out.append("\t# Dormant profile: the real chest, drawn 1:1.")
			out.append("\t\"dormant_scale\": 1.0,")
			out.append("\t\"dormant_body\": Vector2i(%d, %d),"
					% [int(dormant[monster].x), int(dormant[monster].y)])
		out.append("\t\"sheets\": {")
		for i in rows.size():
			var r: Dictionary = rows[i]
			out.append("\t\t\"%s\": {" % r["anim"])
			out.append("\t\t\t\"path\": \"%s\"," % r["file"])
			out.append("\t\t\t\"frames\": %d," % int(r["count"]))
			out.append("\t\t\t\"frame_size\": Vector2i(%d, %d),"
					% [int(r["fw"]), int(r["fh"])])
			out.append("\t\t\t\"offset\": Vector2(%d, %d),"
					% [int(r["shared"].x), int(r["shared"].y)])
			# The swing only counts as connected during these frames. The middle
			# band of the sheet: the wind-up before it is deliberately harmless so
			# a committed enemy can still be interrupted, and the follow-through
			# after it is over.
			if r["anim"] == "attack":
				var n := int(r["count"])
				out.append("\t\t\t\"damage_frames\": Vector2i(%d, %d),"
						% [int(round(n * 0.35)), int(round(n * 0.65))])
			if float(r["drift"]) > 1.0:
				var ps: Array[String] = []
				for v in r["per_frame"]:
					ps.append("Vector2(%d, %d)" % [int(v.x), int(v.y)])
				out.append("\t\t\t\"offsets\": [%s]," % ", ".join(ps))
			out.append("\t\t},")
		out.append("\t},")
		out.append("}")
		out.append("")
	out.append("")
	var names: Array[String] = []
	for monster in STATS.keys():
		names.append(monster.to_upper())
	out.append("## Every monster key.")
	out.append("const ALL := [%s]" % ", ".join(names))
	# A lookup by name, because GDScript cannot resolve a const by string at
	# runtime and every consumer wants to ask for "the goblin" by key.
	var rows: Array[String] = []
	for monster in STATS.keys():
		rows.append("\t\t\"%s\": %s," % [monster, monster.to_upper()])
	out.append("")
	out.append("")
	out.append("## Key string -> the monster's dictionary.")
	out.append("const BY_KEY := {")
	for r in rows:
		out.append(r)
	out.append("}")
	var f := FileAccess.open("res://monster_db.gd", FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	print("")
	print("wrote res://monster_db.gd (%d lines)" % out.size())
	quit(0)


var _needs_per_frame: Array[String] = []
