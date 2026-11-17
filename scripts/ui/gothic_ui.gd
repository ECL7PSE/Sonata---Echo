extends RefCounted
## Echo's gothic UI chrome, drawn in code.
##
## Everything the old sprite sheet provided - button plates, ornate frames,
## segmented bars, keycaps, turn rings - is built here from StyleBoxFlat plus a
## small hand-drawn ornament Control (gothic_ornament.gd). Nothing is sliced from
## a PNG, so the chrome is crisp at any resolution and the whole look re-skins
## from the palette below.
##
## House style: near-black plates, one thin crimson hairline, a single cold cyan
## used only for the active state, gold reserved for the duel's live beat, and
## ornament kept to panel corners so it frames the content instead of crowding it.

const FONT := preload("res://Assets/UI/pixel_ui/font/pixel_ui_font.fnt")
const OrnamentScript := preload("res://scripts/ui/gothic_ornament.gd")

# --- palette
const NAVY := Color("#0c0f1c")
const CYAN := Color("#7cf6ff")
const DIM := Color("#93a7c4")
const TEXT := Color("#dfe4f0")
const CRIMSON := Color("#b81422")
const BORDER := Color("#6f1420")
const BORDER_DIM := Color("#4e1d29")
const PLATE := Color("#2a2438")
const PLATE_HI := Color("#3a3150")
const PLATE_LO := Color("#16121f")
const PANEL_BG := Color("#17121f")
const PANEL_DEEP := Color("#0d0a14")
const WELL := Color("#150f1c")
const MUTED := Color("#6d6683")

# --- ornament motifs (keep in step with gothic_ornament.gd's Kind enum)
const ORN_CORNERS := 0
const ORN_DIVIDER := 1
const ORN_GEAR := 2
const ORN_CROSS := 3


# ------------------------------------------------------------------ styleboxes

static func _flat(bg: Color, border: Color, radius: int, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	# Hard pixel corners: the whole look is meant to read as pixel art.
	s.anti_aliasing = false
	return s


static func _pad(s: StyleBoxFlat, h: float, v: float) -> StyleBoxFlat:
	s.content_margin_left = h
	s.content_margin_right = h
	s.content_margin_top = v
	s.content_margin_bottom = v
	return s


static func button_normal() -> StyleBoxFlat:
	return _pad(_flat(PLATE, BORDER, 4, 2), 18.0, 12.0)


static func button_hover() -> StyleBoxFlat:
	# A heavier left edge is the selection marker, so the active row reads at a
	# glance even before its label brightens.
	var s := _flat(PLATE_HI, CRIMSON, 4, 2)
	s.border_width_left = 6
	return _pad(s, 18.0, 12.0)


static func button_pressed() -> StyleBoxFlat:
	# Sitting 2px lower than normal reads as the plate being pushed in.
	var s := _flat(PLATE_LO, CRIMSON, 4, 2)
	s.border_width_left = 6
	s.content_margin_left = 18.0
	s.content_margin_right = 18.0
	s.content_margin_top = 14.0
	s.content_margin_bottom = 10.0
	return s


static func button_focus() -> StyleBoxFlat:
	# Drawn on top of the plate, grown outward, so it reads as an outline; the
	# left edge is heavier to match the hover marker.
	var s := _flat(Color(0.0, 0.0, 0.0, 0.0), CYAN, 4, 2)
	s.draw_center = false
	s.border_width_left = 6
	return s


static func button_disabled() -> StyleBoxFlat:
	return _pad(_flat(Color("#191521"), Color("#332c40"), 4, 2), 18.0, 12.0)


static func panel_style(bg := PANEL_BG, border := BORDER, radius := 10) -> StyleBoxFlat:
	return _flat(bg, border, radius, 3)


# ------------------------------------------------------------------ primitives

## A 1px inset hairline. Grown into its parent, so nothing needs a size.
static func inner_line(inset: float, color: Color, radius: int, bw: int) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.offset_left = inset
	p.offset_top = inset
	p.offset_right = -inset
	p.offset_bottom = -inset
	var s := _flat(Color(0.0, 0.0, 0.0, 0.0), color, radius, bw)
	s.draw_center = false
	p.add_theme_stylebox_override("panel", s)
	return p


## A single 1px line hugging the top or bottom inner edge: the bevel that gives
## a plate its raised look.
static func edge(inset: float, thickness: int, color: Color, top: bool) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 0.0
	p.anchor_right = 1.0
	p.offset_left = inset
	p.offset_right = -inset
	if top:
		p.anchor_top = 0.0
		p.anchor_bottom = 0.0
		p.offset_top = inset
		p.offset_bottom = inset + float(thickness)
	else:
		p.anchor_top = 1.0
		p.anchor_bottom = 1.0
		p.offset_top = -inset - float(thickness)
		p.offset_bottom = -inset
	p.add_theme_stylebox_override("panel", _flat(color, color, 0, 0))
	return p


## A drawn flourish, filling its parent. See ORN_* for the motif.
static func ornament(motif: int, color := BORDER, accent_col := CRIMSON) -> Control:
	var o := OrnamentScript.new() as Control
	o.set("kind", motif)
	o.set("line_color", color)
	o.set("accent", accent_col)
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return o


## A shadowed pixel-font label, the one text style used everywhere.
static func label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ------------------------------------------------------------------ composites

## A styled Button with the full state set and a hairline highlight.
static func make_button(text: String, min_size := Vector2(240.0, 46.0),
		font_size := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", CYAN)
	b.add_theme_color_override("font_pressed_color", CYAN)
	b.add_theme_color_override("font_focus_color", TEXT)
	b.add_theme_color_override("font_disabled_color", MUTED)
	b.add_theme_stylebox_override("normal", button_normal())
	b.add_theme_stylebox_override("hover", button_hover())
	b.add_theme_stylebox_override("pressed", button_pressed())
	b.add_theme_stylebox_override("focus", button_focus())
	b.add_theme_stylebox_override("disabled", button_disabled())
	# Bevel: a bright hairline along the top inner edge, a dark one along the
	# bottom, so the plate reads as a raised slab rather than a flat rectangle.
	b.add_child(edge(3.0, 1, Color(1.0, 1.0, 1.0, 0.11), true))
	b.add_child(edge(3.0, 1, Color(0.0, 0.0, 0.0, 0.42), false))
	Audio.connect_ui_button(b)
	return b


static func close_button(size_px := 40.0) -> Button:
	var b := make_button("", Vector2(size_px, size_px), 16)
	b.tooltip_text = "Close"
	b.add_child(ornament(ORN_CROSS, BORDER, CRIMSON))
	return b


static func gear_button(size_px := 46.0) -> Button:
	var b := make_button("", Vector2(size_px, size_px), 16)
	b.tooltip_text = "Settings"
	b.add_child(ornament(ORN_GEAR, DIM, CYAN))
	return b


## Dresses a Panel in the gothic frame: deep plate, crimson hairline, inner
## inset line and corner flourishes. The one frame every overlay shares.
static func dress(p: Panel, radius := 10, bg := PANEL_BG) -> void:
	p.add_theme_stylebox_override("panel", panel_style(bg, BORDER, radius))
	p.add_child(inner_line(7.0, Color(1.0, 1.0, 1.0, 0.05),
			maxi(radius - 4, 2), 1))
	# Kept dimmer than the frame so the flourishes read as stonework, not as
	# handles or arrows bolted to the corners.
	p.add_child(ornament(ORN_CORNERS, Color("#5e1622"), Color("#8f1524")))


## A segmented health bar: a bordered groove with one recessed well per slot.
## The caller drops its own five ColorRect fills on top, keeping the 5-slot
## contract the tests assert.
static func segmented_bar(w: float, h: float, slots: int, x0: float, y0: float,
		pitch: float, slot_w: float, slot_h: float) -> Panel:
	var frame := Panel.new()
	frame.size = Vector2(w, h)
	frame.custom_minimum_size = Vector2(w, h)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _flat(PANEL_DEEP, BORDER, 7, 3))
	frame.add_child(inner_line(5.0, Color(1.0, 1.0, 1.0, 0.05), 5, 1))
	var well := _flat(WELL, BORDER_DIM, 3, 2)
	for i in slots:
		var s := Panel.new()
		s.position = Vector2(x0 + i * pitch, y0)
		s.size = Vector2(slot_w, slot_h)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_theme_stylebox_override("panel", well)
		frame.add_child(s)
	return frame


## The slot fills for a segmented_bar. Same geometry, so they sit inside the
## wells. Given back as ColorRects because that is what the HUD test counts.
static func bar_fills(count: int, x0: float, y0: float, pitch: float, w: float,
		h: float, color := CRIMSON) -> Array[ColorRect]:
	var out: Array[ColorRect] = []
	for i in count:
		var f := ColorRect.new()
		f.color = color
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		f.position = Vector2(x0 + i * pitch, y0)
		f.size = Vector2(w, h)
		f.visible = false
		out.append(f)
	return out


## A hollow ring for the duel's turn indicator. Its modulate is driven per beat.
static func turn_dot(d: float) -> Panel:
	var p := Panel.new()
	p.size = Vector2(d, d)
	p.custom_minimum_size = Vector2(d, d)
	p.pivot_offset = Vector2(d, d) * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := _flat(Color(0.0, 0.0, 0.0, 0.0), Color("#e8e0f0"), int(d * 0.5), 2)
	s.draw_center = false
	p.add_theme_stylebox_override("panel", s)
	return p


## A judgement key: a small plate with the letter centred in it.
static func keycap(letter: String, s_px := 44.0) -> Panel:
	var p := Panel.new()
	p.size = Vector2(s_px, s_px)
	p.custom_minimum_size = Vector2(s_px, s_px)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _flat(PLATE, BORDER, 5, 2))
	p.add_child(inner_line(4.0, Color(1.0, 1.0, 1.0, 0.07), 4, 1))
	var l := label(letter, 24, TEXT)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Restyles an HSlider as a crimson groove with a hand-built pixel grip.
## The grip is generated as an ImageTexture rather than loaded from a PNG: this
## project ships no slider art, and the engine default knob is off-theme.
static func style_slider(s: Slider) -> void:
	var track := _flat(PANEL_DEEP, BORDER_DIM, 6, 2)
	track.content_margin_top = 5.0
	track.content_margin_bottom = 5.0
	var fill := _flat(CRIMSON, BORDER, 6, 2)
	fill.content_margin_top = 5.0
	fill.content_margin_bottom = 5.0
	var hot := _flat(Color("#d8202f"), CRIMSON, 6, 2)
	hot.content_margin_top = 5.0
	hot.content_margin_bottom = 5.0
	var grip := _grip_texture()
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", hot)
	s.add_theme_icon_override("grabber", grip)
	s.add_theme_icon_override("grabber_highlight", grip)
	s.add_theme_icon_override("grabber_disabled", grip)


## A 7x18 crimson grip: pixel-drawn, nearest-filtered, no external art.
static func _grip_texture() -> ImageTexture:
	var img := Image.create_empty(7, 18, false, Image.FORMAT_RGBA8)
	img.fill(CRIMSON)
	for x in 7:
		img.set_pixel(x, 0, Color("#e86170"))
		img.set_pixel(x, 1, Color("#cf3346"))
		img.set_pixel(x, 16, Color("#6f1420"))
		img.set_pixel(x, 17, Color("#4a0c14"))
	return ImageTexture.create_from_image(img)
