extends CanvasLayer
## Title screen, built entirely in code.
##
## Uses the hand-made Canva artwork (corner flourish, skull, "Echo" title) from
## res://Assets/UI/start_screen/. Buttons, subtitle and overlays are still built
## in code through gothic_ui.gd.

const MAIN_SCENE := "res://scenes/Main.tscn"
const GothUI := preload("res://scripts/ui/gothic_ui.gd")
const CanvaUI := preload("res://scripts/ui/canva_ui.gd")

const ART_DIR := CanvaUI.ART_DIR

## On-screen width of each image in game pixels (1152x648 space). Height
## follows the image's own aspect ratio, so this works whatever size the PNGs
## were exported at. Taken from the Canva design (1920 wide) x 0.6.
const SKULL_W := CanvaUI.SKULL_W
const TITLE_W := 275.0
const CORNER_W := 80.0

# --- colours taken from the Canva design
const BG_COLOR := CanvaUI.BG_COLOR
const MAROON := CanvaUI.MAROON
const FRAME_COLOR := MAROON

const MENU_W := 222.0
const MENU_H := 54.0
const MENU_SEP := 10
const BUTTON_FONT_SIZE := 20

# Distance of the corner flourishes from the screen edges.
const CORNER_INSET := Vector2(118.0, 58.0)

const HELP_TEXT := "MOVE  WASD / Arrows      ATTACK  K / Space      FULLSCREEN  F11\n\nIN A DUEL\nF  left lane      G  middle lane      H  right lane\n\nWatch the enemy's section, then play it back:\npress each lane's key as its note crosses the line.\nEvery note lands and hurts the enemy. Build a combo."

var _help: Control
var _settings: Control
var _buttons: Array[Button] = []
var _fullscreen_btn: Button


func _ready() -> void:
	Audio.play_title_music()
	for child in get_children():
		child.free()
	_build_menu()


func _build_menu() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var reveal: Array[Control] = []

	# Maroon frame line around the screen (left/right 100, top 42, bottom 36).
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 100.0
	frame.offset_right = -100.0
	frame.offset_top = 42.0
	frame.offset_bottom = -36.0
	var frame_style := StyleBoxFlat.new()
	frame_style.draw_center = false
	frame_style.border_color = FRAME_COLOR
	frame_style.set_border_width_all(2)
	frame_style.anti_aliasing = false
	frame.add_theme_stylebox_override("panel", frame_style)
	root.add_child(frame)

	# Corner flourishes: one image, mirrored for the other three corners.
	var corner_tex := CanvaUI.crop(load(ART_DIR + "corner.png") as Texture2D)
	for c in [[0.0, 0.0], [1.0, 0.0], [0.0, 1.0], [1.0, 1.0]]:
		var corner := _corner(corner_tex, c[0], c[1])
		root.add_child(corner)
		reveal.append(corner)

	# Skull with music notes, sitting on the top edge of the frame.
	var skull := CanvaUI.centered_tex(ART_DIR + "skull.png", 5.0, SKULL_W)
	root.add_child(skull)
	reveal.append(skull)

	# "Echo" title image.
	var title := CanvaUI.centered_tex(ART_DIR + "title.png", 84.0, TITLE_W)
	root.add_child(title)
	reveal.append(title)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -MENU_W * 0.5
	box.offset_right = MENU_W * 0.5
	box.offset_top = 257
	box.offset_bottom = 570
	box.add_theme_constant_override("separation", MENU_SEP)
	root.add_child(box)

	_add_button(box, "continue", "continue", reveal)
	_add_button(box, "new game", "new", reveal)
	_add_button(box, "controls", "how", reveal)
	_add_button(box, "restart", "restart", reveal)
	_add_button(box, "exit", "exit", reveal)

	_add_gear(root, reveal)
	_build_help(root)
	_build_settings(root)
	_stagger(reveal)
	call_deferred("_focus_first")


## A corner flourish. (ax, ay) is 0 or 1 for left/right and top/bottom; the
## image is flipped to suit, so only the top-left artwork is needed.
func _corner(tex: Texture2D, ax: float, ay: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.flip_h = ax == 1.0
	t.flip_v = ay == 1.0
	var s := CanvaUI.fit(tex, CORNER_W)
	t.anchor_left = ax
	t.anchor_right = ax
	t.anchor_top = ay
	t.anchor_bottom = ay
	t.offset_left = CORNER_INSET.x if ax == 0.0 else -CORNER_INSET.x - s.x
	t.offset_right = t.offset_left + s.x
	t.offset_top = CORNER_INSET.y if ay == 0.0 else -CORNER_INSET.y - s.y
	t.offset_bottom = t.offset_top + s.y
	return t


## Fades the title block in, then the rows, for a calm entrance.
func _stagger(nodes: Array[Control]) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	var i := 0
	for n in nodes:
		n.modulate.a = 0.0
		tw.tween_property(n, "modulate:a", 1.0, 0.32).set_delay(0.04 + i * 0.055)
		i += 1


func _add_button(box: VBoxContainer, text: String, action: String,
		reveal: Array[Control]) -> void:
	var b := GothUI.make_button(text, Vector2(MENU_W, MENU_H), BUTTON_FONT_SIZE)
	CanvaUI.skin_button(b)
	b.pressed.connect(_on_menu.bind(action))
	box.add_child(b)
	_buttons.append(b)
	reveal.append(b)


func _add_gear(root: Control, reveal: Array[Control]) -> void:
	var gear := GothUI.gear_button(46.0)
	# Drop the maroon plate/outline so only the gear icon shows.
	for state in ["normal", "hover", "pressed", "disabled"]:
		var flat := StyleBoxFlat.new()
		flat.draw_center = false
		flat.set_border_width_all(0)
		gear.add_theme_stylebox_override(state, flat)
	for c in gear.get_children():
		if c is Panel:  # the bevel hairlines make_button adds
			c.queue_free()
	gear.anchor_left = 1.0
	gear.anchor_right = 1.0
	gear.offset_left = -66
	gear.offset_right = -20
	gear.offset_top = 20
	gear.offset_bottom = 66
	gear.pressed.connect(_on_menu.bind("settings"))
	root.add_child(gear)
	_buttons.append(gear)
	reveal.append(gear)


func _focus_first() -> void:
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _on_menu(action: String) -> void:
	match action:
		"continue":
			if SaveManager.has_run:
				SaveManager.load_save()
			_start_game()
		"new", "restart":
			SaveManager.clear_save()
			GameState.reset()
			_start_game()
		"how":
			_help.visible = true
			_settings.visible = false
		"settings":
			_settings.visible = true
			_help.visible = false
			_sync_settings()
			if _fullscreen_btn != null:
				_fullscreen_btn.grab_focus()
		"exit":
			get_tree().quit()


func _start_game() -> void:
	var transition: Node = get_node("/root/SceneTransition")
	await transition.call("change_scene", MAIN_SCENE,
			Callable(Audio, "play_dungeon_music"))


# ---------------------------------------------------------------- overlays

func _build_help(root: Control) -> void:
	_help = _overlay(root)
	var panel := _panel(_help)

	var heading := GothUI.label("CONTROLS", 32, GothUI.CYAN)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.anchor_right = 1.0
	heading.offset_top = 40
	heading.offset_bottom = 92
	panel.add_child(heading)

	var rule := GothUI.ornament(GothUI.ORN_DIVIDER, GothUI.BORDER, GothUI.CRIMSON)
	rule.anchor_right = 1.0
	rule.anchor_top = 0.0
	rule.anchor_bottom = 0.0
	rule.offset_left = 120
	rule.offset_right = -120
	rule.offset_top = 96
	rule.offset_bottom = 114
	panel.add_child(rule)

	var body := GothUI.label(HELP_TEXT, 16, GothUI.TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.anchor_right = 1.0
	body.offset_left = 60
	body.offset_right = -60
	body.offset_top = 124
	body.offset_bottom = 358
	panel.add_child(body)

	_add_close(panel, _close_help)


func _build_settings(root: Control) -> void:
	_settings = _overlay(root)
	var panel := CanvaUI.modal_panel(_settings, Vector2(760.0, 378.0))

	CanvaUI.skull_banner(panel)

	# "Settings" uses settings_title.png (the serif pixel lettering from the
	# design) and falls back to the game font if the file is not there.
	CanvaUI.heading(panel, ART_DIR + "settings_title.png", "Settings", 50.0,
			52.0, 36)

	CanvaUI.slider_row(panel, "music", 156.0, _bus_linear("Music"),
			_set_bus.bind("Music"))
	CanvaUI.slider_row(panel, "sound", 205.0, _bus_linear("SFX"),
			_set_bus.bind("SFX"))

	_fullscreen_btn = GothUI.make_button("full screen", Vector2(342.0, 49.0), 20)
	CanvaUI.skin_button(_fullscreen_btn)
	_fullscreen_btn.anchor_left = 0.5
	_fullscreen_btn.anchor_right = 0.5
	_fullscreen_btn.offset_left = -171.0
	_fullscreen_btn.offset_right = 171.0
	_fullscreen_btn.offset_top = 246.0
	_fullscreen_btn.offset_bottom = 295.0
	_fullscreen_btn.pressed.connect(_toggle_fullscreen)
	panel.add_child(_fullscreen_btn)

	var x_button := CanvaUI.plain_close(40.0, _close_settings)
	x_button.anchor_left = 1.0
	x_button.anchor_right = 1.0
	x_button.offset_left = -65.0
	x_button.offset_right = -25.0
	x_button.offset_top = 26.0
	x_button.offset_bottom = 66.0
	panel.add_child(x_button)


func _bus_linear(bus: String) -> float:
	return Settings.music if bus == "Music" else Settings.sfx


func _set_bus(value: float, bus: String) -> void:
	if bus == "Music":
		Settings.set_music(value)
	else:
		Settings.set_sfx(value)


func _toggle_fullscreen() -> void:
	var want := not Settings.fullscreen
	var ok := Settings.set_fullscreen(want)
	_sync_settings()
	# Toggle the label even if the OS refused the resize (the editor's embedded
	# game view cannot own its window); the tooltip explains the limit.
	_fullscreen_btn.tooltip_text = "" if ok else \
		"Fullscreen is unavailable in the editor preview. Run the game in its own window."


func _sync_settings() -> void:
	if _fullscreen_btn == null:
		return
	_fullscreen_btn.text = "full screen: on" if Settings.fullscreen else "full screen: off"


func _overlay(root: Control) -> Control:
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.visible = false
	root.add_child(page)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(dim)
	return page


func _panel(host: Control) -> Panel:
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = -189
	panel.offset_bottom = 189
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	GothUI.dress(panel, 10)
	host.add_child(panel)
	return panel


func _add_close(panel: Control, callback: Callable) -> void:
	var close := GothUI.close_button(40.0)
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.offset_left = -72
	close.offset_right = -32
	close.offset_top = 22
	close.offset_bottom = 62
	close.pressed.connect(callback)
	panel.add_child(close)


func _close_help() -> void:
	_help.visible = false
	_focus_first()


func _close_settings() -> void:
	_settings.visible = false
	_focus_first()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _settings != null and _settings.visible:
		_close_settings()
		get_viewport().set_input_as_handled()
	elif _help != null and _help.visible:
		_close_help()
		get_viewport().set_input_as_handled()
