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
## The dormant mimic must read as the same object as a real chest.
const C001_PATH := "res://Assets/Dungeon/dungeon_V.1.0.0_nyknck/Chest/C001/C001_01.png"

var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	_check_animations_present()
	_check_mimic_matches_chest()
	_check_all_anchored()
	_report()


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


## The closed mimic chest and the real chest must be the same size on screen.
func _check_mimic_matches_chest() -> void:
	var chest := _visible_box(C001_PATH)
	var mimic: Dictionary = DB.MIMIC["sheets"]["dormant"]
	var mimg := _image(mimic["path"])
	var fw: int = mimic["frame_size"].x
	var mbox := _bbox(mimg, 0, fw, fw)
	var scale: float = DB.MIMIC["scale"]
	var mw := (mbox.z - mbox.x + 1) * scale
	var mh := (mbox.w - mbox.y + 1) * scale
	var cw := float(chest.z - chest.x + 1)
	var ch := float(chest.w - chest.y + 1)
	print("C001 chest     : %.0fx%.0f px on screen" % [cw, ch])
	print("MIMIC dormant  : %.1fx%.1f px on screen (scale %.4f)"
			% [mw, mh, scale])
	_ok(absf(mw - cw) <= 1.0,
		"dormant mimic is %.1fpx wide, C001 is %.0fpx" % [mw, cw])
	# The HEIGHT is the open question and is deliberately left failing until it
	# is decided. The mimic's closed chest is 31x20 in the source (aspect 1.55)
	# while C001 is 16x15 (aspect 1.07), so NO uniform scale hits both. The db
	# currently matches WIDTH, which guarantees a dormant mimic never looks
	# larger than a real chest, at the cost of reading a little flatter.
	# The alternatives are: match height instead (23.3 x 15.0), or scale
	# non-uniformly to an exact 16 x 15 and accept ~1.46x vertical distortion.
	if absf(mh - ch) > 1.0:
		var src_w := float(mbox.z - mbox.x + 1)
		var src_h := float(mbox.w - mbox.y + 1)
		# Matching height instead of width: 31 * (15/20).
		var by_height := src_w * (ch / src_h)
		_fails.append("UNDECIDED: dormant mimic is %.1fpx tall, C001 is %.0fpx. "
				% [mh, ch]
				+ "Source is %dx%d, so uniform scale cannot match both. Choose: "
						% [int(src_w), int(src_h)]
				+ "width-match (current, %.1fx%.1f), height-match (%.1fx%.1f), "
						% [mw, mh, by_height, ch]
				+ "or non-uniform 16x15 (~1.46x vertical distortion).")


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
				if b.z < 0:
					_fails.append("%s/%s frame %d is blank"
							% [key, anim, f])
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
				_ok(err <= ANCHOR_TOLERANCE,
					"%s/%s frame %d bottom-centre is %.2fpx off the anchor"
					% [key, anim, f, err])
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