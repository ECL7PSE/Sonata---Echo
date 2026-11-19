extends CanvasLayer
## Rhythm duel: the enemy shows a short response section, then the player plays
## it back on the beat. Attack notes must be hit, rests must be left alone, and
## feints must NOT be touched. Accuracy chips the enemy's HP; mistakes cost the
## player HP. The dungeon is paused while this overlay is open and resumes when
## either side drops.
##
## Registered as the `Battle` autoload. Headless runs (the test suites) never
## build the UI and never start a duel, so game logic tests stay deterministic.

signal finished

const SHEET := preload("res://Assets/UI/gothic_ui_sheet_alpha.png")
const PIXEL_FONT := preload("res://Assets/UI/pixel_ui/font/pixel_ui_font.fnt")
const LANE_SYMBOL := preload("res://scripts/ui/lane_symbol.gd")
const GothUI := preload("res://scripts/ui/gothic_ui.gd")
const R_SMALL_SKULL := Rect2(213, 1309, 28, 32)
const R_ORB_LIGHT := Rect2(245, 1283, 84, 87)
const R_ORB_DARK := Rect2(24, 1283, 85, 87)

const ATTACK := 0
const IDLE := 1
const FEINT := 2

# Vertical highway: three lanes, notes fall from the top to the judge line.
const TRACK_X := 366.0
const TRACK_W := 420.0
const LANE_W := 140.0
const TRACK_TOP := 112.0
const JUDGE_Y := 506.0
const NOTE_SIZE := 64.0
const LANE_CENTER := [436.0, 576.0, 716.0]
const LEAD := 3.0
const SPEED := 430.0
const BEAT_DOTS := 4
const WINDOW := 0.24
const PERFECT := 0.10
# Duel HP bars: a code-drawn segmented groove, same slot grid as the HUD.
const DUEL_BAR_W := 260.0
const DUEL_BAR_H := 48.0
const DUEL_X0 := 14.0
const DUEL_Y0 := 10.0
const DUEL_SLOT_W := 40.0
const DUEL_SLOT_H := 28.0
const DUEL_PITCH := 48.0
const ROW_NAMES := ["ATTACK", "REST", "FEINT"]
const ROW_COLORS := [Color("#ff5a5a"), Color("#c9c9d4"), Color("#b07bff")]
const CYAN := Color("#7cf6ff")
# Judgement SFX: one hit thud per lane, a perfect sparkle, and a dull miss.
const SFX_HIT := ["res://audio/sfx/hit_attack.wav", "res://audio/sfx/hit_rest.wav", "res://audio/sfx/hit_feint.wav"]
const SFX_PERFECT := "res://audio/sfx/perfect.wav"
const SFX_MISS := "res://audio/sfx/miss.wav"
const SFX_POOL := 4

enum P { OFF, DEMO, PLAYER, RESULT }

var _active := false
var _ending := false
var last_result: StringName = &""
var _root: Control
var _enemy: Node
var _player: Node2D
var _phase: int = P.OFF
var _phase_time := 0.0
var _round := 0
var _beat_sec := 0.5
var _pattern: Array = []
var _judged: Array = []
var _notes: Array = []
var _dmg_dealt := 0
var _hits := 0
## Hits landed in this section, for the Metronome echo's first-note window.
var _phase_hits := 0
var _misses := 0
var _feints := 0
var _total_hits := 0
var _total_misses := 0
var _total_feints := 0
var _penalty := 1
var _phase_label: Label
var _feedback: Label
var _combo_label: Label
var _hit_line: ColorRect
var _hit_glow: ColorRect
var _enemy_name: Label
var _ebar_fills: Array[ColorRect] = []
var _ebar_base_w := 0.0
var _pbar_fills: Array[ColorRect] = []
var _pbar_base_w := 0.0
var _hud: Node
var _music: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_cache: Dictionary = {}
var _player_portrait: Node2D
var _enemy_portrait: Node2D
var _beat_dots: Array[Panel] = []
var _lane_glow: Array[ColorRect] = []
var _bob := 0.0
var _combo := 0
var _turn_last := -1
var _p_target := 5.0
var _p_show := 5.0
var _e_target := 5.0
var _e_show := 5.0
# Active long note: which note/lane is being held and the damage its press awarded.
var _hold_note := -1
## Physical key that started the hold, so its release is detected even for the
## Space alias (a lane index alone cannot tell the keys apart).
var _hold_key := 0
var _hold_dmg := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	if DisplayServer.get_name() == "headless":
		return
	_build()


func is_active() -> bool:
	return _active


func start(enemy: Node, player: Node2D) -> void:
	if _active or _ending or enemy == null or player == null:
		return
	if DisplayServer.get_name() == "headless":
		return
	if not is_instance_valid(enemy) or not is_instance_valid(player):
		return
	var transition := get_node_or_null("/root/SceneTransition")
	if transition == null:
		push_error("Battle requires the SceneTransition autoload.")
		return
	if transition.is_transitioning():
		return

	_enemy = enemy
	_player = player
	_active = true
	last_result = &""

	var transitioned: bool = await transition.run_action(
			Callable(self, "_prepare_battle"), true)
	if not transitioned:
		_active = false
		_enemy = null
		_player = null
		return
	_begin_round()


func _prepare_battle() -> void:
	_round = 0
	_combo = 0
	_clear_hold()
	_total_hits = 0
	_total_misses = 0
	_total_feints = 0
	_refresh_combo()
	_beat_sec = 60.0 / _bpm_for(_enemy)
	_penalty = maxi(1, int(_enemy.damage_amount() / 2.0))
	_enemy_name.text = str(_enemy.get("species")).to_upper()
	_hud = get_tree().current_scene.get_node_or_null("HealthUI")
	if _hud != null:
		_hud.visible = false
	if _player.has_signal("health_changed"):
		_player.health_changed.connect(_refresh_player_bar)
	_refresh_player_bar()
	_start_music()
	_clear_duelists()
	_build_duelists()
	_root.visible = true
	_root.modulate.a = 1.0
	if _enemy.has_signal("died"):
		_enemy.died.connect(_on_enemy_died)
	if _player.has_signal("died"):
		_player.died.connect(_on_player_died)


func _bpm_for(enemy: Node) -> float:
	var sp := 90.0
	var d = enemy.get("data")
	if d is Dictionary:
		sp = float(d.get("speed", 90.0))
	return clampf(84.0 + sp * 0.36, 96.0, 150.0)


func _region(r: Rect2) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = SHEET
	t.region = r
	return t


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------- UI build

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	_init_sfx()
	_build_highway()
	_build_hud()
	_build_enemy_bar()
	_build_player_bar()


func _build_highway() -> void:
	var frame := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0d0a14")
	style.border_color = Color("#6f1420")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", style)
	frame.position = Vector2(TRACK_X - 12, TRACK_TOP - 12)
	frame.size = Vector2(TRACK_W + 24, JUDGE_Y - TRACK_TOP + 140)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(frame)

	# lane tint + press glow
	for i in 3:
		var lane_x := TRACK_X + i * LANE_W
		var tint := ColorRect.new()
		tint.color = Color(ROW_COLORS[i], 0.06)
		tint.position = Vector2(lane_x, TRACK_TOP)
		tint.size = Vector2(LANE_W, JUDGE_Y - TRACK_TOP)
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(tint)

		var glow := ColorRect.new()
		glow.color = Color(ROW_COLORS[i], 0.0)
		glow.position = tint.position
		glow.size = tint.size
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(glow)
		_lane_glow.append(glow)

		if i > 0:
			var div := ColorRect.new()
			div.color = Color("#2a2233")
			div.position = Vector2(lane_x, TRACK_TOP)
			div.size = Vector2(2, JUDGE_Y - TRACK_TOP)
			div.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_root.add_child(div)

		var name_lbl := _label(ROW_NAMES[i], 16, ROW_COLORS[i])
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.position = Vector2(LANE_CENTER[i] - 70, JUDGE_Y + 58)
		name_lbl.size = Vector2(140, 24)
		name_lbl.z_index = 5
		_root.add_child(name_lbl)

	_hit_glow = ColorRect.new()
	_hit_glow.color = Color(CYAN, 0.22)
	_hit_glow.position = Vector2(TRACK_X, JUDGE_Y - 14)
	_hit_glow.size = Vector2(TRACK_W, 28)
	_hit_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hit_glow)

	_hit_line = ColorRect.new()
	_hit_line.color = CYAN
	_hit_line.position = Vector2(TRACK_X, JUDGE_Y - 2)
	_hit_line.size = Vector2(TRACK_W, 4)
	_hit_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hit_line)

	# turn indicator: hollow rings, centered over the highway
	var dot_w := 18.0
	var dot_gap := 10.0
	var total := float(BEAT_DOTS) * dot_w + float(BEAT_DOTS - 1) * dot_gap
	for i in BEAT_DOTS:
		var d := GothUI.turn_dot(dot_w)
		d.position = Vector2(576.0 - total * 0.5 + float(i) * (dot_w + dot_gap), 30.0)
		d.modulate = Color(0.35, 0.35, 0.42)
		_root.add_child(d)
		_beat_dots.append(d)

	# judgement keys, one under each lane
	var keys := ["F", "G", "H"]
	for i in 3:
		var cap := GothUI.keycap(keys[i], 44.0)
		cap.position = Vector2(LANE_CENTER[i] - 22.0, JUDGE_Y + 8.0)
		cap.z_index = 5
		_root.add_child(cap)


func _build_hud() -> void:
	_phase_label = _label("", 16, Color("#c9b7d4"))
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.anchor_right = 1.0
	_phase_label.offset_top = 66
	_phase_label.offset_bottom = 98
	_phase_label.z_index = 5
	_root.add_child(_phase_label)

	_feedback = _label("", 32, CYAN)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.anchor_right = 1.0
	_feedback.offset_top = 404
	_feedback.offset_bottom = 456
	_feedback.z_index = 6
	_root.add_child(_feedback)

	var you := _label("YOU", 16, Color("#8fe7ff"))
	you.offset_left = 20
	you.offset_right = 280
	you.offset_top = 12
	you.offset_bottom = 38
	_root.add_child(you)

	_enemy_name = _label("DUEL", 16, Color("#ff8a8a"))
	_enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_name.anchor_left = 1.0
	_enemy_name.anchor_right = 1.0
	_enemy_name.offset_left = -280
	_enemy_name.offset_right = -20
	_enemy_name.offset_top = 12
	_enemy_name.offset_bottom = 38
	_root.add_child(_enemy_name)

	_combo_label = _label("", 24, CYAN)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.offset_left = 800
	_combo_label.offset_right = 1130
	_combo_label.offset_top = 300
	_combo_label.offset_bottom = 340
	_combo_label.visible = false
	_combo_label.z_index = 6
	_root.add_child(_combo_label)



func _clear_duelists() -> void:
	for p in [_player_portrait, _enemy_portrait]:
		if p != null and is_instance_valid(p):
			p.queue_free()
	_player_portrait = null
	_enemy_portrait = null


func _build_duelists() -> void:
	_player_portrait = _portrait_from(_player, false, 190.0)
	_enemy_portrait = _portrait_from(_enemy, true, 962.0)


func _portrait_from(actor: Node, face_left: bool, x: float) -> Node2D:
	if actor == null or not is_instance_valid(actor):
		return null
	var s: Node2D = null
	var ps = actor.get("icon")
	if ps is Sprite2D and ps.texture != null:
		var c := Sprite2D.new()
		c.texture = ps.texture
		c.hframes = ps.hframes
		c.vframes = ps.vframes
		c.frame = ps.frame
		c.flip_h = face_left
		c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		c.scale = Vector2.ONE * clampf(150.0 / _frame_height(ps), 0.5, 12.0)
		s = c
	else:
		var es = actor.get("sprite")
		if es is AnimatedSprite2D and es.sprite_frames != null and es.sprite_frames.get_animation_names().size() > 0:
			var anim: String = es.animation
			if not es.sprite_frames.has_animation(anim):
				anim = es.sprite_frames.get_animation_names()[0]
			var c2 := AnimatedSprite2D.new()
			c2.sprite_frames = es.sprite_frames
			c2.animation = anim
			c2.frame = es.frame
			c2.flip_h = face_left
			c2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var tex: Texture2D = es.sprite_frames.get_frame_texture(anim, es.frame)
			var fh := float(tex.get_height()) if tex != null else 32.0
			c2.scale = Vector2.ONE * clampf(150.0 / fh, 0.5, 12.0) * 1.8
			s = c2
	if s == null:
		return null
	s.position = Vector2(x, 430.0)
	_root.add_child(s)
	return s


func _frame_height(spr: Sprite2D) -> float:
	var h := float(spr.texture.get_height())
	if spr.vframes > 1:
		h /= float(spr.vframes)
	return maxf(h, 1.0)


func _lunge(which: Node2D, dirn: float) -> void:
	if which == null or not is_instance_valid(which):
		return
	var x := which.position.x
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(which, "position:x", x + dirn * 18.0, 0.07)
	tw.tween_property(which, "position:x", x, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _duel_bar_chrome() -> Panel:
	return GothUI.segmented_bar(DUEL_BAR_W, DUEL_BAR_H, 5, DUEL_X0, DUEL_Y0,
			DUEL_PITCH, DUEL_SLOT_W, DUEL_SLOT_H)


func _build_enemy_bar() -> void:
	var bar := Control.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -280
	bar.offset_right = -20
	bar.offset_top = 46
	bar.offset_bottom = 94
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)

	bar.add_child(_duel_bar_chrome())
	_ebar_base_w = DUEL_SLOT_W
	for f in GothUI.bar_fills(5, DUEL_X0, DUEL_Y0, DUEL_PITCH,
			DUEL_SLOT_W, DUEL_SLOT_H):
		bar.add_child(f)
		_ebar_fills.append(f)


func _start_music() -> void:
	_stop_music()
	var key := str(_enemy.get("species")).to_lower()
	var path := "res://audio/battle/%s.wav" % key
	if not FileAccess.file_exists(path):
		return
	var stream: AudioStreamWAV = AudioStreamWAV.load_from_file(path)
	if stream == null:
		return
	# Seamless loop: 16-bit mono, so frames = bytes / 2.
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.data.size() * 0.5)
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.bus = "Music"
	_music.volume_db = -7.0
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_music.play()
	if Audio.has_method("duck_music"):
		Audio.duck_music(true)


func _stop_music() -> void:
	if _music != null and is_instance_valid(_music):
		_music.stop()
		_music.queue_free()
		_music = null
	if Audio.has_method("duck_music"):
		Audio.duck_music(false)


func _init_sfx() -> void:
	if not _sfx.is_empty():
		return
	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.volume_db = -4.0
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx.append(p)


func _play_sfx(path: String) -> void:
	if _sfx.is_empty():
		return
	var stream := _sfx_cache.get(path) as AudioStreamWAV
	if stream == null:
		if not FileAccess.file_exists(path):
			return
		stream = AudioStreamWAV.load_from_file(path)
		if stream == null:
			return
		_sfx_cache[path] = stream
	for p in _sfx:
		if not p.playing:
			p.stream = stream
			p.play()
			return
	# All players busy: steal the first rather than drop the sound.
	_sfx[0].stream = stream
	_sfx[0].play()


func _build_player_bar() -> void:
	var bar := Control.new()
	bar.offset_left = 20
	bar.offset_right = 280
	bar.offset_top = 46
	bar.offset_bottom = 94
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)

	bar.add_child(_duel_bar_chrome())
	_pbar_base_w = DUEL_SLOT_W
	for f in GothUI.bar_fills(5, DUEL_X0, DUEL_Y0, DUEL_PITCH,
			DUEL_SLOT_W, DUEL_SLOT_H):
		bar.add_child(f)
		_pbar_fills.append(f)


func _refresh_player_bar(_cur: int = 0, _mx: int = 0) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_p_target = float(int(_player.get("health"))) / float(maxi(int(_player.get("max_health")), 1)) * 5.0


func _refresh_enemy_bar() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	_e_target = float(int(_enemy.get("health"))) / float(maxi(int(_enemy.get("max_health")), 1)) * 5.0


func _apply_fills(fills: Array[ColorRect], base_w: float, shown: float) -> void:
	for i in fills.size():
		var fill := clampf(shown - float(i), 0.0, 1.0)
		fills[i].visible = fill > 0.001
		fills[i].size.x = base_w * fill


# ---------------------------------------------------------------- rounds

func _begin_round() -> void:
	_round += 1
	_pattern = _make_pattern(_round)
	_build_notes()
	_enter_phase(P.DEMO)


func _make_pattern(r: int) -> Array:
	var n := mini(4 + r, 9)
	var arr: Array = []
	for i in n:
		var t := ATTACK
		var roll := randf()
		if roll < 0.22:
			t = IDLE
		elif roll < 0.40:
			t = FEINT
		arr.append({"beat": float(i), "type": t})
	var attacks := 0
	for note in arr:
		if int(note["type"]) == ATTACK:
			attacks += 1
	if attacks < 2:
		arr[0]["type"] = ATTACK
		if n > 1:
			arr[1]["type"] = ATTACK
	# Roughly every third ATTACK note becomes a long note. Never the last note, so
	# the tail always has a following beat to land against.
	var seen := 0
	for i in arr.size():
		if int(arr[i]["type"]) != ATTACK:
			continue
		seen += 1
		if seen % 3 == 1 and i < arr.size() - 1:
			arr[i]["hold"] = 1.0
	return arr


func _build_notes() -> void:
	_clear_notes()
	for i in _pattern.size():
		var t: int = int(_pattern[i]["type"])
		var n := Control.new()
		n.size = Vector2(NOTE_SIZE, NOTE_SIZE)
		n.pivot_offset = n.size * 0.5
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Long notes get a body trailing above the head, added first so the halo
		# and skull art draw on top of it.
		if _pattern[i].has("hold"):
			var hc: Color = ROW_COLORS[t]
			var body := ColorRect.new()
			body.name = "HoldBody"
			body.color = Color(hc.r, hc.g, hc.b, 0.45)
			body.mouse_filter = Control.MOUSE_FILTER_IGNORE
			n.add_child(body)
			var cap := ColorRect.new()
			cap.name = "HoldCap"
			cap.color = Color(hc.r, hc.g, hc.b, 0.95)
			cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			n.add_child(cap)

		var gc: Color = ROW_COLORS[t]
		var glow: Control = LANE_SYMBOL.new()
		glow.name = "Halo"
		glow.kind = 3
		glow.accent = gc
		glow.position = Vector2(-10, -10)
		glow.size = n.size + Vector2(20, 20)
		glow.modulate = Color(1, 1, 1, 0.86)
		n.add_child(glow)

		var art: Control = LANE_SYMBOL.new()
		art.name = "Glyph"
		art.kind = t
		art.accent = gc
		art.position = Vector2(5, 5)
		art.size = n.size - Vector2(10, 10)
		n.add_child(art)

		_root.add_child(n)
		_notes.append(n)


func _clear_notes() -> void:
	for n in _notes:
		if is_instance_valid(n):
			n.queue_free()
	_notes.clear()


func _enter_phase(p: int) -> void:
	_phase = p
	_phase_time = 0.0
	_judged.clear()
	for i in _pattern.size():
		_judged.append(false)
	_dmg_dealt = 0
	_hits = 0
	_phase_hits = 0
	_misses = 0
	_feints = 0
	_clear_hold()
	_feedback.text = ""
	_phase_label.text = "ENEMY'S TURN" if p == P.DEMO else ("YOUR TURN" if p == P.PLAYER else "")
	_phase_label.modulate.a = 0.0
	create_tween().tween_property(_phase_label, "modulate:a", 1.0, 0.25)
	for i in _notes.size():
		var n: Control = _notes[i]
		n.scale = Vector2.ONE
		n.modulate = Color(1.3, 0.9, 1.6) if int(_pattern[i]["type"]) == FEINT else Color.WHITE
	_refresh_enemy_bar()


func _note_time(i: int) -> float:
	return (float(i) + LEAD) * _beat_sec


func _phase_end() -> float:
	return (float(_pattern.size()) + LEAD) * _beat_sec + 0.35


func _process(delta: float) -> void:
	if not _active or _ending or _transition_running():
		return
	_phase_time += delta

	var bp := fmod(_phase_time, _beat_sec) / _beat_sec
	var ease_bp := pow(1.0 - bp, 2.0)
	_hit_line.modulate.a = 0.35 + 0.65 * ease_bp
	_hit_glow.modulate.a = 0.28 + 1.15 * ease_bp

	_bob += delta
	if _player_portrait != null and is_instance_valid(_player_portrait):
		_player_portrait.position.y = 430.0 + sin(_bob * 2.4) * 3.0
	if _enemy_portrait != null and is_instance_valid(_enemy_portrait):
		_enemy_portrait.position.y = 430.0 + sin(_bob * 2.1 + 1.3) * 3.0
	# bars glide toward their new value instead of snapping
	var k := 1.0 - exp(-delta * 9.0)
	_p_show = lerpf(_p_show, _p_target, k)
	_e_show = lerpf(_e_show, _e_target, k)
	_apply_fills(_pbar_fills, _pbar_base_w, _p_show)
	_apply_fills(_ebar_fills, _ebar_base_w, _e_show)

	# turn indicator: the active round's ring is amber and breathes with the beat
	var turn_i := maxi(0, _round - 1) % BEAT_DOTS
	if turn_i != _turn_last:
		_turn_last = turn_i
		for i in _beat_dots.size():
			var d: Panel = _beat_dots[i]
			var tw := create_tween()
			tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(d, "scale", Vector2(1.35, 1.35) if i == turn_i else Vector2.ONE, 0.22)
	for i in _beat_dots.size():
		if i == turn_i:
			var pulse := 0.65 + 0.35 * sin(_phase_time * TAU / _beat_sec)
			_beat_dots[i].modulate = Color("#ffd93b", pulse)
		else:
			_beat_dots[i].modulate = Color(0.35, 0.35, 0.42)

	match _phase:
		P.DEMO:
			for i in _pattern.size():
				if not _judged[i] and _phase_time >= _note_time(i):
					_judged[i] = true
					_burst(i, Color(1.6, 1.6, 1.6))
					_lunge(_enemy_portrait, -1.0)
			if _phase_time > _phase_end():
				_enter_phase(P.PLAYER)
		P.PLAYER:
			if _phase_time > _phase_end():
				_finish_player()
		P.RESULT:
			if _phase_time > 1.5:
				if is_instance_valid(_enemy) and int(_enemy.get("health")) > 0:
					_begin_round()
				else:
					_end()

	if _phase == P.PLAYER:
		_tick_hold()
	_update_notes()


func _update_notes() -> void:
	for i in _notes.size():
		var n: Control = _notes[i]
		if not is_instance_valid(n):
			continue
		if _phase == P.RESULT:
			n.visible = false
			continue
		var t: int = int(_pattern[i]["type"])
		if i == _hold_note:
			# Held: the head sticks to the judge line while the body drains.
			n.position = Vector2(LANE_CENTER[t] - NOTE_SIZE * 0.5, JUDGE_Y - NOTE_SIZE * 0.5)
			n.visible = true
		else:
			var y := JUDGE_Y - (_note_time(i) - _phase_time) * SPEED
			n.position = Vector2(LANE_CENTER[t] - NOTE_SIZE * 0.5, y - NOTE_SIZE * 0.5)
			n.visible = y > TRACK_TOP - 8.0 and y < JUDGE_Y + NOTE_SIZE
		var halo := n.get_node_or_null("Halo") as CanvasItem
		if halo != null:
			halo.modulate.a = 0.34 + 0.14 * sin((_note_time(i) - _phase_time) * TAU / _beat_sec)
		_layout_hold(i, n)


func _layout_hold(i: int, n: Control) -> void:
	# Re-glue the long-note body to the head every frame and match its visibility.
	var body := n.get_node_or_null("HoldBody") as ColorRect
	if body == null:
		return
	var h := float(_pattern[i]["hold"]) * _beat_sec * SPEED
	if i == _hold_note:
		# Drain the body as the tail approaches so the hold is visibly held.
		var tail_t: float = _note_time(i) + float(_pattern[i]["hold"]) * _beat_sec
		h = maxf(0.0, (tail_t - _phase_time) * SPEED)
	var x := NOTE_SIZE * 0.5 - 13.0
	# Never let the tail poke above the highway frame.
	var head_y: float = n.position.y + NOTE_SIZE * 0.5
	h = minf(h, maxf(0.0, head_y - TRACK_TOP))
	body.position = Vector2(x, NOTE_SIZE * 0.5 - h)
	body.size = Vector2(26.0, h)
	body.visible = n.visible
	var cap := n.get_node_or_null("HoldCap") as ColorRect
	if cap != null:
		cap.position = Vector2(x, NOTE_SIZE * 0.5 - h)
		cap.size = Vector2(26.0, 3.0)
		cap.visible = n.visible


func _input(event: InputEvent) -> void:
	if _transition_running():
		get_viewport().set_input_as_handled()
		return
	if not _active or _phase != P.PLAYER:
		return
	# Each lane has its own judgement key: F=attack, G=rest, H=feint. Space/Enter
	# (ui_accept) stays an alias for F so muscle memory still hits attack notes.
	if event is InputEventKey and not event.echo:
		var lane := -1
		match event.physical_keycode:
			KEY_F:
				lane = ATTACK
			KEY_G:
				lane = IDLE
			KEY_H:
				lane = FEINT
		if lane >= 0 and event.pressed:
			get_viewport().set_input_as_handled()
			_try_hit(lane, event.physical_keycode)
			return
		# Releasing the key that started the hold breaks it early.
		if not event.pressed and _hold_note >= 0 and _hold_key == event.physical_keycode:
			get_viewport().set_input_as_handled()
			var bar: float = float(_pattern[_hold_note]["hold"]) * _beat_sec
			var held: float = _phase_time - _note_time(_hold_note)
			# Sustained most of the bar (or let go right at the tail): done.
			# Hollow Note drops the required sustain to a third.
			var need := 0.25 if GameState.echo_on("hollow_note") else 0.6
			if tail_gap(_hold_note) > 0.12 and held < bar * need:
				_break_hold()
			return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_try_hit(ATTACK, event.physical_keycode)


## Seconds left before this note's tail passes.
func tail_gap(i: int) -> float:
	return _note_time(i) + float(_pattern[i]["hold"]) * _beat_sec - _phase_time


func _try_hit(lane: int, key: int = 0) -> void:
	# Only notes of the pressed lane that sit inside the timing window count.
	# Metronome widens the window for the first note of each section.
	var win := WINDOW
	if GameState.echo_on("metronome") and _phase_hits == 0:
		win *= 1.4
	var best := -1
	var best_dt := 999.0
	for i in _pattern.size():
		if _judged[i] or int(_pattern[i]["type"]) != lane:
			continue
		var dt := absf(_phase_time - _note_time(i))
		if dt <= win and dt < best_dt:
			best = i
			best_dt = dt
	if best < 0:
		return

	_judged[best] = true
	_phase_hits += 1
	if lane == ATTACK:
		var dmg := 1
		_hits += 1
		_total_hits += 1
		_combo += 1
		if best_dt <= PERFECT:
			dmg = 2
			_pop_feedback("PERFECT", CYAN)
			_play_sfx(SFX_PERFECT)
		else:
			_pop_feedback("GOOD", Color("#9fffc9"))
		_play_sfx(SFX_HIT[ATTACK])
		_dmg_dealt += dmg
		if _pattern[best].has("hold"):
			# Long note: stay glued while the tail passes. The head is not burst yet.
			_hold_note = best
			_hold_key = key
			_hold_dmg = dmg
		else:
			_burst(best, Color(0.5, 1.6, 0.7))
		_lunge(_player_portrait, 1.0)
	elif lane == IDLE:
		# Rest notes are real notes: tap G on the beat. They just deal no damage.
		_hits += 1
		_total_hits += 1
		_combo += 1
		if best_dt <= PERFECT:
			_pop_feedback("PERFECT", CYAN)
			_play_sfx(SFX_PERFECT)
		else:
			_pop_feedback("GOOD", Color("#9fffc9"))
		_play_sfx(SFX_HIT[IDLE])
		_burst(best, Color(0.5, 1.6, 0.7))
		_lunge(_player_portrait, 1.0)
	else:
		# Feint is a real note too: tap H on the beat, no damage dealt.
		_hits += 1
		_total_hits += 1
		_combo += 1
		if best_dt <= PERFECT:
			_pop_feedback("PERFECT", CYAN)
			_play_sfx(SFX_PERFECT)
		else:
			_pop_feedback("GOOD", Color("#cfc0ff"))
		_play_sfx(SFX_HIT[FEINT])
		_burst(best, Color(0.5, 1.6, 0.7))
		_lunge(_player_portrait, 1.0)
	_refresh_combo()


func _refresh_combo() -> void:
	if _combo_label == null:
		return
	_combo_label.visible = _combo >= 2
	_combo_label.text = "COMBO x%d" % _combo


func _clear_hold() -> void:
	_hold_note = -1
	_hold_key = 0
	_hold_dmg = 0


func _tick_hold() -> void:
	if _hold_note < 0:
		return
	var tail := _note_time(_hold_note) + float(_pattern[_hold_note]["hold"]) * _beat_sec
	if _phase_time >= tail:
		# Held cleanly through the tail: reward quietly, no extra damage.
		var i := _hold_note
		_pop_feedback("HOLD", CYAN)
		_burst(i, Color(0.5, 1.6, 0.7))
		_clear_hold()


func _break_hold() -> void:
	if _hold_note < 0:
		return
	# Released before the tail: undo the press's damage and count the drop.
	_combo = 0
	_hits = maxi(0, _hits - 1)
	_total_hits = maxi(0, _total_hits - 1)
	_misses += 1
	_total_misses += 1
	_dmg_dealt -= _hold_dmg
	_play_sfx(SFX_MISS)
	_pop_feedback("MISS", Color("#ff7b7b"))
	_refresh_combo()
	_clear_hold()


func _pop_feedback(text: String, color: Color) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", color)
	_feedback.pivot_offset = Vector2(576, 26)
	_feedback.scale = Vector2(1.25, 1.25)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_feedback, "scale", Vector2.ONE, 0.18)


func _flash_lane(t: int) -> void:
	var g: ColorRect = _lane_glow[t]
	g.color.a = 0.22
	var tw := create_tween()
	tw.tween_property(g, "color:a", 0.0, 0.22)


func _burst(i: int, color: Color) -> void:
	if i < 0 or i >= _notes.size() or not is_instance_valid(_notes[i]):
		return
	var n: Control = _notes[i]
	var t: int = int(_pattern[i]["type"])
	_flash_lane(t)
	n.modulate = color
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "scale", Vector2(1.75, 1.75), 0.12)
	tw.parallel().tween_property(n, "position:y", n.position.y - 14.0, 0.16)
	tw.parallel().tween_property(n, "modulate:a", 0.0, 0.16)
	tw.tween_callback(n.hide)


func _finish_player() -> void:
	for i in _pattern.size():
		if not _judged[i]:
			_judged[i] = true
			_misses += 1
			_total_misses += 1
			_take_player_hit()

	_phase = P.RESULT
	_phase_time = 0.0
	_phase_label.text = ""
	var finishing := false
	if _dmg_dealt > 0 and is_instance_valid(_enemy):
		# Would this round's damage drop the enemy? Only the killing blow earns a rank.
		finishing = int(_enemy.get("health")) - _dmg_dealt <= 0
		# The tree is paused, so the enemy's i-frame timer cannot tick down. Clear
		# it by hand or only the first round of a duel could ever deal damage.
		_enemy._end_invincibility()
		_enemy.take_damage(_dmg_dealt, _enemy.global_position + Vector2(0, -20))
	if not _active:
		return
	if finishing:
		var rank := _rank()
		_feedback.text = "RANK %s" % rank
		GameState.add_coins(_rank_bonus(rank))
	else:
		_feedback.text = "HITS %d   MISS %d   FEINT %d" % [_hits, _misses, _feints]
	_refresh_enemy_bar()
	if int(_player.get("health")) <= 0:
		_end(&"defeat")


func _rank() -> String:
	# Duel-wide accuracy, not just the last round.
	var acc := float(_total_hits) / float(maxi(1, _total_hits + _total_misses + _total_feints))
	if acc >= 0.95:
		return "S"
	if acc >= 0.85:
		return "A"
	if acc >= 0.70:
		return "B"
	if acc >= 0.50:
		return "C"
	return "D"


func _rank_bonus(rank: String) -> int:
	return int({"S": 6, "A": 4, "B": 2, "C": 1}.get(rank, 0))


func _take_player_hit() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("take_damage"):
		# Same pause problem as the enemy: the i-frame timer is frozen, so every
		# mistake after the first would be silently ignored.
		if _player.has_method("_end_invincibility"):
			_player._end_invincibility()
		_player.take_damage(_penalty, _enemy.global_position)


func _transition_running() -> bool:
	var transition := get_node_or_null("/root/SceneTransition")
	return transition != null and bool(transition.call("is_transitioning"))


# ---------------------------------------------------------------- teardown

func _on_enemy_died() -> void:
	_end(&"victory")


func _on_player_died() -> void:
	_end(&"defeat")


func _end(result: StringName = &"") -> void:
	if not _active or _ending:
		return
	if result == &"":
		if is_instance_valid(_enemy) and int(_enemy.get("health")) <= 0:
			result = &"victory"
		elif is_instance_valid(_player) and int(_player.get("health")) <= 0:
			result = &"defeat"
		else:
			result = &"aborted"
	last_result = result
	_active = false
	_ending = true

	var transition := get_node_or_null("/root/SceneTransition")
	if transition == null:
		push_error("Battle requires the SceneTransition autoload.")
		_finish_battle_at_black()
		get_tree().paused = false
		_ending = false
		return

	var transitioned: bool = await transition.run_action(
			Callable(self, "_finish_battle_at_black"), false)
	if not transitioned:
		push_error("Battle could not start its result transition.")
		_finish_battle_at_black()
		get_tree().paused = false
	_ending = false


func _finish_battle_at_black() -> void:
	_phase = P.OFF
	_root.visible = false
	if _enemy != null and is_instance_valid(_enemy) and _enemy.has_signal("died") \
			and _enemy.died.is_connected(_on_enemy_died):
		_enemy.died.disconnect(_on_enemy_died)
	if _player != null and is_instance_valid(_player) and _player.has_signal("died") \
			and _player.died.is_connected(_on_player_died):
		_player.died.disconnect(_on_player_died)
	if _player != null and is_instance_valid(_player) and _player.has_signal("health_changed") \
			and _player.health_changed.is_connected(_refresh_player_bar):
		_player.health_changed.disconnect(_refresh_player_bar)
	if _hud != null and is_instance_valid(_hud):
		_hud.visible = true
		_hud = null
	_stop_music()
	_clear_notes()
	Audio.play_dungeon_music()
	finished.emit()
