extends SceneTree
## Asserts monster_db.gd against the PNGs it was generated from.
##
##   godot --headless --path . --script res://tools/test_monster_db.gd
##
## The database is generated, so these checks are what stop a regeneration from
## quietly going wrong: a renamed asset, a re-exported sheet with different
## frame counts, or an offset that no longer pins the sprite to the ground.

const DB := preload("res://monster_db.gd")
## Key string -> the monster's dictionary. GDScript cannot look up a const by
## name at runtime, so the mapping is spelled out once here.
const DATA := {
	"RAT": DB.RAT, "SLIME": DB.SLIME, "BAT": DB.BAT, "MUSHROOM": DB.MUSHROOM,
	"FLYING_EYE": DB.FLYING_EYE, "GOBLIN": DB.GOBLIN, "MIMIC": DB.MIMIC,
	"SKELETON": DB.SKELETON,
}
## A frame's bottom-centre must land this close to the sprite origin.
const ANCHOR_TOLERANCE := 1.0
## Comparisons are done on values that were rounded to integers somewhere, so
## an exact `<= 1.0` can fail on 1.0000000001. This keeps the limit at a real
## 1px instead of quietly widening it.
const EPS := 0.001
## The dormant mimic must read as the same object as a real chest.
const C001_PATH := "res://Assets/Dungeon/dungeon_V.1.0.0_nyknck/Chest/C001/C001_01.png"

var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	_check_scale_rule()
	_check_animations_present()
	_check_mimic_matches_chest()
	_check_all_anchored()
	_report()


## Monsters are sized against the PLAYER, not the tile.
##
## For every species, the LARGER of body width and height, times its scale, must
## equal the player's measured visible height times that species' multiple. This
## replaced an informal "1 to 1.5 tiles" band that no test actually asserted -
## it lived only as a target in the generator, so nothing would have caught a
## species drifting out of scale.
func _check_scale_rule() -> void:
	var player_h: float = DB.PLAYER_H
	_ok(player_h > 1.0,
		"the player measures %.2fpx tall, which cannot be right" % player_h)
	print("player height  : %.2f px (measured from its own sprite)" % player_h)
	for key in DATA:
		var data: Dictionary = DATA[key]
		var lower: String = key.to_lower()
		_ok(DB.BODY_MULT.has(lower),
			"%s has no BODY_MULT entry" % key)
		var mult := float(DB.BODY_MULT[lower])
		var body: Vector2i = data["body"]
		var scale := float(data["scale"])
		# RENDERED: source x sprite scale x the 2x Dungeon scale.
		var rendered := Vector2(float(body.x) * scale * DB.DUNGEON_SCALE,
				float(body.y) * scale * DB.DUNGEON_SCALE)
		var longest := maxf(rendered.x, rendered.y)
		var target := player_h * mult
		_ok(absf(longest - target) <= 0.05,
			"%s renders %.2fpx on its longest side, expected %.2fpx "
			% [key, longest, target]
			+ "(%.2fx player)" % mult)
		_ok(rendered.x <= player_h * DB.MAX_W_MULT + 0.05,
			"%s renders %.2fpx wide, over the %.2fpx cap"
					% [key, rendered.x, player_h * DB.MAX_W_MULT])
		print("size %-12s scale %.4f  src %dx%d -> %.1fx%.1f RENDERED  "
				% [key, scale, body.x, body.y, rendered.x, rendered.y]
				+ "(%.2fx player)" % mult)
	# The dormant mimic is exempt: it IS a chest and stays pixel-identical.
	var dormant: Dictionary = DB.MIMIC["sheets"]["dormant"]
	_ok(float(DB.MIMIC["dormant_scale"]) == 1.0,
		"the dormant mimic must stay 1:1 with the real chest")


func _ok(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_fails.append(message)
	return condition


func _report() -> void:
	print("")
	print("assertions     : %d" % _checks)
	if _fails.is_empty():
		print("RESULT: OK")
		quit(0)
	else:
		for f in _fails:
			print("FAIL: " + f)
		print("RESULT: %d problem(s)" % _fails.size())
		quit(1)


## Every monster must carry the full animation set its behaviour needs.
##
## The mimic is deliberately different: it has no single `idle`, because what it
## shows while idle depends on how far through the dormant -> transform chain it
## is. Demanding an `idle` of it would mean inventing a sheet that does not exist.
func _check_animations_present() -> void:
	for key in DATA:
		var sheets: Dictionary = DATA[key]["sheets"]
		var want := ["walk", "attack", "hurt", "death"]
		if key == "MIMIC":
			want += ["dormant", "opening", "idle_open", "transform",
					"idle_transformed"]
		else:
			want += ["idle"]
		for a in want:
			_ok(sheets.has(a), "%s has no '%s' animation" % [key, a])
		if key != "MIMIC":
			_ok(not sheets.has("dormant"),
				"%s should not have mimic-only stages" % key)


## The dormant mimic must BE the real chest, not something that resembles it.
##
## Both poses are the same PNG at scale 1, so a player who has learned to read
## chests cannot tell them apart until the burst. The mimic's own closed-chest art
## was discarded for this reason: it measured 31x20 and could never match C001's
## 16x15 under uniform scale.
func _check_mimic_matches_chest() -> void:
	var chest := _visible_box(C001_PATH)
	var mimic: Dictionary = DB.MIMIC["sheets"]["dormant"]
	_ok(mimic["path"] == C001_PATH,
		"the dormant mimic does not use C001_01 (got %s)" % mimic["path"])
	_ok(float(DB.MIMIC["dormant_scale"]) == 1.0,
		"the dormant mimic is scaled %.4f; it must be 1.0 to be pixel-identical"
		% float(DB.MIMIC["dormant_scale"]))
	var mimg := _image(mimic["path"])
	var fw: int = mimic["frame_size"].x
	var mbox := _bbox(mimg, 0, fw, fw)
	var cw := float(chest.z - chest.x + 1)
	var ch := float(chest.w - chest.y + 1)
	var mw := float(mbox.z - mbox.x + 1)
	var mh := float(mbox.w - mbox.y + 1)
	print("C001 chest     : %dx%d px on screen" % [int(cw), int(ch)])
	print("MIMIC dormant  : %dx%d px on screen (scale %.2f), same sheet"
			% [int(mw), int(mh), float(DB.MIMIC["dormant_scale"])])
	_ok(absf(mw - cw) <= 1.0 + EPS, "dormant mimic is %dx%d, C001 is %dx%d"
			% [int(mw), int(mh), int(cw), int(ch)])
	_ok(absf(mh - ch) <= 1.0 + EPS, "dormant mimic is %dx%d, C001 is %dx%d"
			% [int(mw), int(mh), int(cw), int(ch)])

	# The frame the burst starts on is the hinge between the two looks, so it
	# has to land on the same anchor or the chest jumps at the moment of waking.
	var opening: Dictionary = DB.MIMIC["sheets"]["opening"]
	var oimg := _image(opening["path"])
	var ofw: int = opening["frame_size"].x
	var ofh: int = opening["frame_size"].y
	var ob := _bbox(oimg, 0, ofw, ofh)
	var obc := Vector2((ob.x + ob.z) * 0.5, float(ob.w))
	var ooff: Vector2 = opening["offset"]
	var olanded := Vector2(obc.x - ofw * 0.5, obc.y - ofh * 0.5) + ooff
	print("MIMIC opening  : f0 bbox %dx%d, bottom-centre error %.2f px"
			% [ob.z - ob.x + 1, ob.w - ob.y + 1, olanded.length()])
	_ok(olanded.length() <= ANCHOR_TOLERANCE + EPS,
		"mimic opening f0 bottom-centre is %.2fpx off the anchor"
		% olanded.length())


## The heart of the file: every frame of every sheet must sit on the anchor.
func _check_all_anchored() -> void:
	var worst_overall := 0.0
	var worst_where := ""
	var per_sheet := 0
	for key in DATA:
		var data: Dictionary = DATA[key]
		var sheets: Dictionary = data["sheets"]
		for anim in sheets.keys():
			var sh: Dictionary = sheets[anim]
			var path: String = sh["path"]
			if not _ok(ResourceLoader.exists(path),
					"%s/%s: missing %s" % [key, anim, path]):
				continue
			var img := _image(path)
			var fw: int = sh["frame_size"].x
			var fh: int = sh["frame_size"].y
			# The frame count in the db must match the file it points at.
			_ok(fw == img.get_width() / maxi(img.get_width() / fw, 1),
				"%s/%s frame_size does not tile the image" % [key, anim])
			var want_frames: int = sh["frames"]
			var got_frames: int = int(img.get_width() / fw)
			_ok(want_frames == got_frames,
				"%s/%s declares %d frames, the sheet has %d"
				% [key, anim, want_frames, got_frames])
			var per_frame: Array = sh.get("offsets", [])
			for f in got_frames:
				per_sheet += 1
				var b := _bbox(img, f, fw, fh)
				# Counted unconditionally, then used to skip the geometry. Written
				# as a bare _fails.append under the guard it contributed NOTHING on a
				# passing run, so a sheet full of blank frames cost the suite zero
				# assertions instead of one per frame.
				_ok(b.z >= 0, "%s/%s frame %d is blank"
						% [key, anim, f])
				if b.z < 0:
					continue
				# offset-corrected bottom-centre, in sprite-local space
				var bc := Vector2((b.x + b.z) * 0.5, float(b.w))
				var off: Vector2 = sh["offset"]
				if per_frame.size() > f:
					off = per_frame[f]
				var landed := Vector2(bc.x - fw * 0.5, bc.y - fh * 0.5) + off
				var err := landed.length()
				if err > worst_overall:
					worst_overall = err
					worst_where = "%s/%s f%d" % [key, anim, f]
				_ok(err <= ANCHOR_TOLERANCE + EPS,
					"%s/%s frame %d bottom-centre is %.2fpx off the anchor"
					% [key, anim, f, err])
				# Flipped, the content walks the other way, so the x has to be
				# negated or every left-facing enemy drifts off its anchor. This
				# mirrors Enemy.frame_offset, which negates at runtime.
				_ok(absf(landed.x) <= ANCHOR_TOLERANCE + EPS,
					"%s/%s frame %d is %.2fpx off the anchor with flip_h set"
					% [key, anim, f, absf(landed.x)])
	print("frames anchored: %d across every sheet" % per_sheet)
	print("worst anchor   : %.2f px  (%s)" % [worst_overall, worst_where])


func _image(path: String) -> Image:
	return (load(path) as Texture2D).get_image()


func _visible_box(path: String) -> Vector4i:
	var img := _image(path)
	return _bbox(img, 0, img.get_width(), img.get_height())


func _bbox(img: Image, f: int, fw: int, fh: int) -> Vector4i:
	var min_x := 999999
	var min_y := 999999
	var max_x := -1
	var max_y := -1
	for y in fh:
		for x in fw:
			if img.get_pixel(f * fw + x, y).a > 0.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return Vector4i(0, 0, -1, -1)
	return Vector4i(min_x, min_y, max_x, max_y)