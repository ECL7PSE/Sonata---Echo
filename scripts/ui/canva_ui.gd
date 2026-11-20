extends RefCounted
## Echo's hand-made modal skin, shared by the title screen and the pause menu.
##
## The look comes from the Canva design in res://Assets/UI/start_screen/: a navy
## plate behind a single maroon hairline, teal lowercase labels, a thin maroon
## slider line with a music-note knob, and maroon buttons with black outlines
## and teal text. Keeping the pieces here means the pause screen cannot drift
## away from the settings screen it is modelled on.

const GothUI := preload("res://scripts/ui/gothic_ui.gd")

const ART_DIR := "res://Assets/UI/start_screen/"
const BG_COLOR := Color("#131a2c")
const MAROON := Color("#652545")
const MAROON_HOVER := Color("#7d2f58")
const TEAL := Color("#4fead1")
const SKULL_W := 179.0


# ------------------------------------------------------------------ palette

## Restyles a button with the Canva plate: maroon fill, black outline, teal
## text. Pass `shadow` for the soft drop shadow the pause mockup shows.
static func skin_button(b: Button, shadow := false) -> void:
	for state in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = MAROON_HOVER if state == "hover" else MAROON
		s.border_color = Color.BLACK
		s.set_border_width_all(3)
		s.set_corner_radius_all(8)
		s.anti_aliasing = false
		if shadow:
			s.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
			s.shadow_size = 5
			s.shadow_offset = Vector2(0.0, 3.0)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", TEAL)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", TEAL)


## A plain teal X with no plate, for closing a modal.
static func plain_close(size_px: float, callback: Callable) -> Button:
	var b := GothUI.make_button("", Vector2(size_px, size_px), 16)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var flat := StyleBoxFlat.new()
		flat.draw_center = false
		flat.set_border_width_all(0)
		b.add_theme_stylebox_override(state, flat)
	for c in b.get_children():
		if c is Panel:  # the bevel hairlines make_button adds
			c.queue_free()
	b.add_child(GothUI.ornament(GothUI.ORN_CROSS, TEAL, TEAL))
	b.tooltip_text = "Close"
	b.pressed.connect(callback)
	return b


# ------------------------------------------------------------------ composites

## The modal plate. `border_all` draws the hairline around the whole frame;
## the title screen's settings panel leaves it off so only the top edge shows.
static func modal_panel(host: Control, panel_size: Vector2,
		border_all := false) -> Panel:
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -panel_size.x * 0.5
	panel.offset_right = panel_size.x * 0.5
	panel.offset_top = -panel_size.y * 0.5
	panel.offset_bottom = panel_size.y * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = MAROON
	if border_all:
		style.set_border_width_all(2)
	else:
		style.border_width_top = 2
	style.anti_aliasing = false
	panel.add_theme_stylebox_override("panel", style)
	host.add_child(panel)
	return panel


## The skull banner straddling the panel's top edge. A patch of panel colour
## breaks the hairline behind it, so the artwork appears to sit on the frame.
static func skull_banner(panel: Control, width := SKULL_W) -> void:
	var patch := ColorRect.new()
	patch.color = BG_COLOR
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	patch.anchor_left = 0.5
	patch.anchor_right = 0.5
	patch.offset_left = -width * 0.5 - 20.0
	patch.offset_right = width * 0.5 + 20.0
	patch.offset_top = -1.0
	patch.offset_bottom = 4.0
	panel.add_child(patch)
	panel.add_child(centered_tex(ART_DIR + "skull.png", -30.0, width))


## A modal heading. Uses the Canva lettering PNG when it exists (that is where
## the serif pixel face lives) and falls back to the game font otherwise.
static func heading(panel: Control, art_path: String, fallback_text: String,
		art_height: float, top: float, fallback_size: int) -> void:
	var title := load_scaled(art_path, art_height)
	if title != null:
		var t := TextureRect.new()
		t.texture = title
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		var tw := float(title.get_width())
		t.anchor_left = 0.5
		t.anchor_right = 0.5
		t.offset_left = -tw * 0.5
		t.offset_right = tw * 0.5
		t.offset_top = top
		t.offset_bottom = top + float(title.get_height())
		panel.add_child(t)
		return
	var l := GothUI.label(fallback_text, fallback_size, TEAL)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.anchor_right = 1.0
	l.offset_top = top
	l.offset_bottom = top + art_height + 8.0
	panel.add_child(l)


## One settings row: a teal lowercase label, a thin maroon line and a
## music-note knob. `cy` is the row's vertical centre inside the panel;
## `dx` slides the whole row sideways to centre it in a wider panel.
static func slider_row(panel: Control, text: String, cy: float, value: float,
		on_change: Callable, dx := 0.0) -> HSlider:
	var label := GothUI.label(text, 20, TEAL)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.offset_left = 40.0 + dx
	label.offset_right = 234.0 + dx
	label.offset_top = cy - 16.0
	label.offset_bottom = cy + 16.0
	panel.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.offset_left = 261.0 + dx
	slider.offset_right = 630.0 + dx
	slider.offset_top = cy - 14.0
	slider.offset_bottom = cy + 14.0
	style_note_slider(slider)
	slider.value_changed.connect(on_change)
	panel.add_child(slider)
	return slider


## Thin maroon line with a music-note knob (note.png). If note.png is missing,
## falls back to the gothic slider so the row is still usable.
static func style_note_slider(s: HSlider) -> void:
	var knob := load_scaled(ART_DIR + "note.png", 26.0)
	if knob == null:
		GothUI.style_slider(s)
		return
	var line := StyleBoxFlat.new()
	line.bg_color = MAROON
	line.content_margin_top = 1.0
	line.content_margin_bottom = 1.0
	line.anti_aliasing = false
	s.add_theme_stylebox_override("slider", line)
	s.add_theme_stylebox_override("grabber_area", line)
	s.add_theme_stylebox_override("grabber_area_highlight", line)
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)
	s.add_theme_icon_override("grabber_disabled", knob)


# ------------------------------------------------------------------ textures

## An image centred horizontally, `top` pixels from the top of its parent.
## Trims transparent padding off a PNG (Canva exports often keep a big empty
## margin), so the width refers to the visible artwork only.
static func centered_tex(path: String, top: float, width: float) -> TextureRect:
	var tex := crop(load(path) as Texture2D)
	var t := TextureRect.new()
	t.texture = tex
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	var s := fit(tex, width)
	t.anchor_left = 0.5
	t.anchor_right = 0.5
	t.offset_left = -s.x * 0.5
	t.offset_right = s.x * 0.5
	t.offset_top = top
	t.offset_bottom = top + s.y
	return t


## Trims transparent padding off a PNG, returning an atlas when there is any.
static func crop(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return tex
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(used)
	return atlas


static func fit(tex: Texture2D, width: float) -> Vector2:
	return Vector2(width, width * tex.get_height() / tex.get_width())


## Loads a PNG, trims transparent padding and resizes it to `height` pixels.
## Returns null if the file does not exist.
static func load_scaled(path: String, height: float) -> ImageTexture:
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	var used := img.get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		img = img.get_region(used)
	var h := int(round(height))
	var w := int(round(float(img.get_width()) * h / float(img.get_height())))
	img.resize(maxi(w, 1), maxi(h, 1), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)
