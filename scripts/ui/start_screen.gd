extends CanvasLayer
## Title screen, built entirely in code.
##
## The gothic chrome (plates, frame, flourishes, cog) is drawn by gothic_ui.gd -
## nothing here is sliced from a sprite sheet, so the menu is crisp at any size.

const MAIN_SCENE := "res://scenes/Main.tscn"
const GothUI := preload("res://scripts/ui/gothic_ui.gd")

const MENU_W := 240.0
const MENU_H := 46.0
const MENU_SEP := 12
const BANNER_BG := Color("#171226")

const HELP_TEXT := "MOVE  WASD / Arrows      ATTACK  K / Space      FULLSCREEN  F11\n\nIN A DUEL\nF  ATTACK note      G  REST note      H  FEINT note\n\nPress the lane's key on the beat. Never press\non a feint - it is bait. Break its guard."

var _help: Control
var _settings: Control
var _buttons: Array[Button] = []
var _fullscreen_btn: Button


func _ready() -> void:
	for child in get_children():
		child.free()
	_build_menu()


func _build_menu() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bg := ColorRect.new()
	bg.color = GothUI.NAVY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var reveal: Array[Control] = []

	# A hairline frame around the whole screen. Cheap, and it makes the screen
	# read as an arranged composition rather than text floating in the dark.
	root.add_child(GothUI.inner_line(12.0, Color(0.44, 0.08, 0.14, 0.38), 2, 1))

	# The title sits on its own banner plate, so the words never have to fight
	# ornament for legibility.
	var banner := Panel.new()
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.anchor_top = 0.0
	banner.anchor_bottom = 0.0
	banner.offset_left = -240
	banner.offset_right = 240
	banner.offset_top = 72
	banner.offset_bottom = 196
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GothUI.dress(banner, 8, BANNER_BG)
	root.add_child(banner)
	reveal.append(banner)

	var title := GothUI.label("ECHO", 48, GothUI.CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.anchor_right = 1.0
	title.offset_top = 80
	title.offset_bottom = 144
	root.add_child(title)
	reveal.append(title)

	var subtitle := GothUI.label("LOST WORLDS", 24, GothUI.DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.anchor_right = 1.0
	subtitle.offset_top = 148
	subtitle.offset_bottom = 176
	root.add_child(subtitle)
	reveal.append(subtitle)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -MENU_W * 0.5
	box.offset_right = MENU_W * 0.5
	box.offset_top = 236
	box.offset_bottom = 572
	box.add_theme_constant_override("separation", MENU_SEP)
	root.add_child(box)

	_add_button(box, "CONTINUE", "continue", reveal)
	_add_button(box, "NEW GAME", "new", reveal)
	_add_button(box, "CONTROLS", "how", reveal)
	_add_button(box, "RESTART", "restart", reveal)
	_add_button(box, "EXIT", "exit", reveal)

	_add_gear(root, reveal)
	_build_help(root)
	_build_settings(root)
	_stagger(reveal)
	call_deferred("_focus_first")


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
	var b := GothUI.make_button(text, Vector2(MENU_W, MENU_H), 16)
	b.pressed.connect(_on_menu.bind(action))
	box.add_child(b)
	_buttons.append(b)
	reveal.append(b)


func _add_gear(root: Control, reveal: Array[Control]) -> void:
	var gear := GothUI.gear_button(46.0)
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
	get_tree().change_scene_to_file(MAIN_SCENE)


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
	var panel := _panel(_settings)

	var heading := GothUI.label("SETTINGS", 32, GothUI.CYAN)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.anchor_right = 1.0
	heading.offset_top = 36
	heading.offset_bottom = 88
	panel.add_child(heading)

	var rule := GothUI.ornament(GothUI.ORN_DIVIDER, GothUI.BORDER, GothUI.CRIMSON)
	rule.anchor_right = 1.0
	rule.anchor_top = 0.0
	rule.anchor_bottom = 0.0
	rule.offset_left = 120
	rule.offset_right = -120
	rule.offset_top = 92
	rule.offset_bottom = 110
	panel.add_child(rule)

	_add_slider_row(panel, "MUSIC", 128, "Music")
	_add_slider_row(panel, "SOUND", 180, "SFX")

	_fullscreen_btn = GothUI.make_button("FULLSCREEN", Vector2(420.0, 48.0), 16)
	_fullscreen_btn.anchor_left = 0.5
	_fullscreen_btn.anchor_right = 0.5
	_fullscreen_btn.offset_left = -210
	_fullscreen_btn.offset_right = 210
	_fullscreen_btn.offset_top = 240
	_fullscreen_btn.offset_bottom = 288
	_fullscreen_btn.pressed.connect(_toggle_fullscreen)
	panel.add_child(_fullscreen_btn)

	_add_close(panel, _close_settings)


func _add_slider_row(panel: Control, text: String, y: float, bus: String) -> void:
	var label := GothUI.label(text, 16, GothUI.TEXT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.offset_left = 70
	label.offset_right = 250
	label.offset_top = y
	label.offset_bottom = y + 38
	panel.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = _bus_linear(bus)
	slider.offset_left = 270
	slider.offset_right = 650
	slider.offset_top = y + 6
	slider.offset_bottom = y + 32
	GothUI.style_slider(slider)
	slider.value_changed.connect(_set_bus.bind(bus))
	panel.add_child(slider)


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
	if not ok:
		# Embedded game view: the OS window belongs to the editor, so it cannot
		# go fullscreen. Say so instead of leaving a dead button.
		_fullscreen_btn.text = "FULLSCREEN NEEDS ITS OWN WINDOW"


func _sync_settings() -> void:
	if _fullscreen_btn == null:
		return
	_fullscreen_btn.text = "FULLSCREEN: ON" if Settings.fullscreen else "FULLSCREEN: OFF"


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
