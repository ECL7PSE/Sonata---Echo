extends CanvasLayer
## In-run pause screen: resume, audio, fullscreen, quit to menu.
##
## Lives as an autoload so it works in any scene and keeps processing while the
## tree is paused. It refuses to open on the start screen (whose root is not a
## Node2D) and while a rhythm duel is running, because the duel owns the pause
## state then. The frame is drawn by gothic_ui.gd, not sliced from the sheet.

signal closed

const GothUI := preload("res://scripts/ui/gothic_ui.gd")

var _root: Control
var _music: HSlider
var _sfx: HSlider
var _full: Button
var _open := false


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func is_open() -> bool:
	return _open


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = -240
	panel.offset_bottom = 240
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	GothUI.dress(panel, 10)
	_root.add_child(panel)

	panel.add_child(_heading("PAUSED", 30.0, 56.0))

	# ornament() comes back anchored full-rect, so the vertical anchors must be
	# reset to the top or the rule lands on the panel's bottom edge.
	var rule := GothUI.ornament(GothUI.ORN_DIVIDER, GothUI.BORDER, GothUI.CRIMSON)
	rule.anchor_right = 1.0
	rule.anchor_top = 0.0
	rule.anchor_bottom = 0.0
	rule.offset_left = 120
	rule.offset_right = -120
	rule.offset_top = 92
	rule.offset_bottom = 110
	panel.add_child(rule)

	var resume := GothUI.make_button("RESUME", Vector2(300.0, 44.0), 16)
	_centre(resume, 300.0, 122.0)
	resume.pressed.connect(close)
	panel.add_child(resume)

	panel.add_child(_row_label("MUSIC", 186.0))
	_music = _slider(192.0)
	_music.value_changed.connect(func(v: float) -> void: Settings.set_music(v))
	panel.add_child(_music)

	panel.add_child(_row_label("SOUND", 236.0))
	_sfx = _slider(242.0)
	_sfx.value_changed.connect(func(v: float) -> void: Settings.set_sfx(v))
	panel.add_child(_sfx)

	_full = GothUI.make_button("FULLSCREEN", Vector2(420.0, 44.0), 16)
	_centre(_full, 420.0, 290.0)
	_full.pressed.connect(_toggle_fullscreen)
	panel.add_child(_full)

	var quit := GothUI.make_button("QUIT TO MENU", Vector2(300.0, 44.0), 16)
	_centre(quit, 300.0, 346.0)
	quit.pressed.connect(_quit_to_menu)
	panel.add_child(quit)


func _heading(text: String, y: float, h: float) -> Label:
	var l := GothUI.label(text, 32, GothUI.CYAN)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.anchor_right = 1.0
	l.offset_top = y
	l.offset_bottom = y + h
	return l


func _row_label(text: String, y: float) -> Label:
	var l := GothUI.label(text, 16, GothUI.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.offset_left = 70
	l.offset_right = 250
	l.offset_top = y
	l.offset_bottom = y + 38
	return l


## Centres a fixed-width control horizontally with a fixed height.
func _centre(c: Control, w: float, y: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.offset_left = -w * 0.5
	c.offset_right = w * 0.5
	c.offset_top = y
	c.offset_bottom = y + 44.0


func _slider(y: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.offset_left = 270
	s.offset_right = 650
	s.offset_top = y + 6
	s.offset_bottom = y + 32
	GothUI.style_slider(s)
	return s


func _toggle_fullscreen() -> void:
	var ok := Settings.set_fullscreen(not Settings.fullscreen)
	_full.text = ("FULLSCREEN: ON" if Settings.fullscreen else "FULLSCREEN: OFF") if ok \
		else "FULLSCREEN NEEDS ITS OWN WINDOW"


func _sync() -> void:
	_music.set_value_no_signal(Settings.music)
	_sfx.set_value_no_signal(Settings.sfx)
	_full.text = "FULLSCREEN: ON" if Settings.fullscreen else "FULLSCREEN: OFF"


func open() -> void:
	if _open:
		return
	if not (get_tree().current_scene is Node2D):
		return
	var battle := get_node_or_null("/root/Battle")
	if battle != null and battle.is_active():
		return
	_open = true
	_sync()
	_root.visible = true
	get_tree().paused = true


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	get_tree().paused = false
	closed.emit()


func _quit_to_menu() -> void:
	_close_quiet()
	var transition: Node = get_node("/root/SceneTransition")
	await transition.call("change_scene", "res://scenes/start_screen.tscn")


func _close_quiet() -> void:
	_open = false
	_root.visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _open:
		close()
		get_viewport().set_input_as_handled()
	else:
		open()
		if _open:
			get_viewport().set_input_as_handled()
