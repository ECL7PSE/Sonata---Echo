extends CanvasLayer
## In-run pause screen: resume, audio, fullscreen, quit to menu.
##
## Lives as an autoload so it works in any scene and keeps processing while the
## tree is paused. It refuses to open on the start screen (whose root is not a
## Node2D) and while a rhythm duel is running, because the duel owns the pause
## state then. Uses the same Canva modal skin as the title screen's settings
## page so the two menus read as one design.

signal closed

const GothUI := preload("res://scripts/ui/gothic_ui.gd")
const CanvaUI := preload("res://scripts/ui/canva_ui.gd")

const TITLE_ART := "res://Assets/UI/paused_title.png"
const PANEL_SIZE := Vector2(760.0, 480.0)
const BTN_H := 44.0
const BTN_FONT := 20
const FULL_MIN_W := 280.0

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

	var panel := CanvaUI.modal_panel(_root, PANEL_SIZE, true)

	# Skull with music notes, straddling the panel's top edge.
	CanvaUI.skull_banner(panel)

	# The mockup's serif lettering. Without the PNG the game font is used.
	CanvaUI.heading(panel, TITLE_ART, "Paused", 50.0, 40.0, 40)

	var x_button := CanvaUI.plain_close(64.0, close)
	x_button.anchor_left = 1.0
	x_button.anchor_right = 1.0
	x_button.offset_left = -82.0
	x_button.offset_right = -18.0
	x_button.offset_top = 24.0
	x_button.offset_bottom = 88.0
	panel.add_child(x_button)

	# Rows are centred as a block and sit a touch above the panel's midpoint,
	# matching the mockup.
	_music = CanvaUI.slider_row(panel, "music", 160.0, Settings.music,
			func(v: float) -> void: Settings.set_music(v), -15.0)
	_sfx = CanvaUI.slider_row(panel, "sound", 209.0, Settings.sfx,
			func(v: float) -> void: Settings.set_sfx(v), -15.0)

	_full = GothUI.make_button("", Vector2(280.0, BTN_H), BTN_FONT)
	CanvaUI.skin_button(_full, true)
	_centre(_full, 280.0, 258.0, BTN_H)
	_full.pressed.connect(_toggle_fullscreen)
	panel.add_child(_full)

	var resume := GothUI.make_button("resume", Vector2(210.0, BTN_H), BTN_FONT)
	CanvaUI.skin_button(resume, true)
	_centre(resume, 210.0, 318.0, BTN_H)
	resume.pressed.connect(close)
	panel.add_child(resume)

	var quit := GothUI.make_button("quit to menu", Vector2(220.0, BTN_H), BTN_FONT)
	CanvaUI.skin_button(quit, true)
	_centre(quit, 220.0, 378.0, BTN_H)
	quit.pressed.connect(_quit_to_menu)
	panel.add_child(quit)


## Centres a fixed-width control horizontally with a fixed height.
func _centre(c: Control, w: float, y: float, h: float) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.offset_left = -w * 0.5
	c.offset_right = w * 0.5
	c.offset_top = y
	c.offset_bottom = y + h


func _toggle_fullscreen() -> void:
	var want := not Settings.fullscreen
	var ok := Settings.set_fullscreen(want)
	_sync()
	# The button keeps toggling even if the OS refused the resize (the editor's
	# embedded game view cannot own its window); the tooltip explains the limit.
	_full.tooltip_text = "" if ok else \
		"Fullscreen is unavailable in the editor preview. Run the game in its own window."


func _sync() -> void:
	_music.set_value_no_signal(Settings.music)
	_sfx.set_value_no_signal(Settings.sfx)
	_set_full_label("fullscreen:on" if Settings.fullscreen else "fullscreen:off")


## Keeps the fullscreen button centred while letting it grow for its label.
func _set_full_label(text: String) -> void:
	_full.text = text
	var text_w := GothUI.FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			BTN_FONT).x
	var w := maxf(FULL_MIN_W, text_w + 56.0)
	_full.offset_left = -w * 0.5
	_full.offset_right = w * 0.5


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
