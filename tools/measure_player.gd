extends SceneTree
## Prints the idle frame's real alpha bounding box, in rendered px.
##
## The collision box has to be aligned to where the hat actually IS, not to
## where the 16x16 frame happens to be. A sprite sheet routinely has a few
## transparent rows of padding at the top, and aligning to the frame would
## leave the box short by exactly that padding - which is invisible in the
## editor and shows up in game as the hat clipping the wall cap.
##
## Reports both the frame box and the inked box, and the scale 1.2 applied by
## Main.tscn.

const TEX := "res://Assets/Player/Dark_Hatman_Topdown_Character/Animations/Idle/darkhatman_idle_sheet_64x64.png"
const SCALE := 1.2


func _initialize() -> void:
	var tex: Texture2D = load(TEX)
	if tex == null:
		print("RESULT: cannot load %s" % TEX)
		quit(1)
		return
	var img: Image = tex.get_image()
	var fw := img.get_width() / 4
	var fh := img.get_height() / 4
	# A 4x4 grid is COLUMN-major: frame n sits at column n%4, row n/4.
	# Getting this backwards samples an empty cell and reports the sprite as
	# fully transparent, which is exactly what the first run of this did.
	var FRAME := 4
	var fx := (FRAME % 4) * fw
	var fy := (FRAME / 4) * fh

	var minx := 1 << 30
	var miny := 1 << 30
	var maxx := -1
	var maxy := -1
	for y in fh:
		for x in fw:
			if img.get_pixel(x + fx, y + fy).a > 0.02:
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
				miny = mini(miny, y)
				maxy = maxi(maxy, y)

	print("sheet        : %dx%d, 4x4 frames of %dx%d"
			% [img.get_width(), img.get_height(), fw, fh])
	if maxx < 0:
		print("RESULT: frame 4 is fully transparent")
		quit(1)
		return

	# Texture space is centred on the node origin, so the ink spans
	# -fw/2..+fw/2 and -fh/2..+fh/2 in unscaled local px.
	var top_local := (miny - fh * 0.5) * SCALE
	var bot_local := (maxy - fh * 0.5) * SCALE
	var left_local := (minx - fw * 0.5) * SCALE
	var right_local := (maxx - fw * 0.5) * SCALE

	print("frame 4 ink  : x %d..%d, y %d..%d (frame px)" % [minx, maxx, miny, maxy])
	print("top padding  : %d frame px above the hat (%.2f rendered)" % [miny, miny * SCALE])
	print("local ink    : x %.2f..%.2f  y %.2f..%.2f (rendered, scale %.1f)"
			% [left_local, right_local, top_local, bot_local, SCALE])
	print("ink size     : %.2f wide x %.2f tall (rendered)"
			% [right_local - left_local, bot_local - top_local])
	print("suggested box: size %.0f x %.0f, position y %.1f"
			% [right_local - left_local, bot_local - top_local,
			(top_local + bot_local) * 0.5])
	print("RESULT: OK")