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

const PIXEL_FONT := preload("res://Assets/UI/pixel_ui/font/pixel_ui_font.fnt")
const CENTER_WIPE := preload("res://scripts/battle/center_wipe.gdshader")
const ART_DIR := "res://Assets/UI/battle/"
const HP_DIR := "res://Assets/UI/Health_Bar/"

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
## How long the YOUR TURN splash stays on screen, fade-in and fade-out included.
const TURN_BANNER_SEC := 2.0
const TURN_FADE_IN := 0.3
const TURN_FADE_OUT := 0.45
## How long the rule takes to wipe outwards from its centre.
const TURN_RULE_WIPE := 0.55
const SPEED := 430.0
const BEAT_DOTS := 4
const WINDOW := 0.24
const PERFECT := 0.10
# Duel HP bars: a red pill fill, with the skull frame laid over the player side.
const BAR_W := 290.0
const BAR_H := 24.0
const BAR_X := 48.0
const BAR_Y := 86.0
const BAR_FRAME_W := 320.0
const ROW_NAMES := ["fight", "rest", "feint"]
const ROW_COLORS := [Color("#d42434"), Color("#f2eef7"), Color("#9a6cf0")]
const RED := Color("#d42434")
const TEAL := Color("#4fead1")
const CYAN := Color("#4fead1")
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
var _lead := LEAD
var _pattern: Array = []
var _judged: Array = []
var _notes: Array = []
var _dmg_dealt := 0
var _hits := 0
var _misses := 0
var _feints := 0
var _total_hits := 0
var _total_misses := 0
var _total_feints := 0
var _penalty := 1
var _feedback: Label
var _combo_label: Label
var _hit_line: ColorRect
var _hit_glow: ColorRect
var _enemy_name: Label
var _pbar_fill: TextureRect
var _ebar_fill: TextureRect
var _turn_layer: Control
var _turn_dim: ColorRect
var _turn_tween: Tween
var _turn_rule_mat: ShaderMaterial
var _hud: Node
var _music: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_cache: Dictionary = {}
var _player_portrait: Node2D
var _enemy_portrait: Node2D
var _beat_dots: Array[Control] = []
var _lane_glow: Array[ColorRect] = []
var _bob := 0.0
var _combo := 0
var _turn_last := -1
var _p_target := 1.0
var _p_show := 1.0
var _e_target := 1.0
var _e_show := 1.0
var _art_cache: Dictionary = {}
var _pip_tex: Array[Texture2D] = []
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


## Crops the transparent export margin off a Canva PNG and caches the result.
func _art(file_name: String, dir := ART_DIR) -> Texture2D:
	var key := dir + file_name
	if _art_cache.has(key):
		return _art_cache[key]
	var tex: Texture2D = load(key)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return tex
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return tex
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(used)
	_art_cache[key] = atlas
	return atlas


## The white serif letter inside a keycap export, with the thin red frame
## trimmed away (the frame is drawn in code so it stays crisp at HUD scale).
func _key_letter(file_name: String) -> Texture2D:
	var key := "key:" + file_name
	if _art_cache.has(key):
		return _art_cache[key]
	var tex: Texture2D = load(ART_DIR + file_name)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return tex
	var used := img.get_used_rect()
	var art := img.get_region(used)
	var inset := maxi(2, int(minf(art.get_width(), art.get_height()) * 0.06))
	var inner := art.get_region(Rect2i(inset, inset,
			art.get_width() - inset * 2, art.get_height() - inset * 2))
	var letter := inner.get_used_rect()
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(used.position + Vector2i(inset, inset) + letter.position,
			letter.size)
	_art_cache[key] = atlas
	return atlas


## turn_pip.png holds all four sparkles in one strip; slice them apart.
func _make_pips() -> void:
	if not _pip_tex.is_empty():
		return
	var tex: Texture2D = load(ART_DIR + "turn_pip.png")
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	var used := img.get_used_rect()
	var art := img.get_region(used)
	for i in BEAT_DOTS:
		var x0 := int(float(art.get_width()) * i / BEAT_DOTS)
		var x1 := int(float(art.get_width()) * (i + 1) / BEAT_DOTS)
		var part := art.get_region(Rect2i(x0, 0, x1 - x0, art.get_height()))
		var u := part.get_used_rect()
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(used.position + Vector2i(x0, 0) + u.position, u.size)
		_pip_tex.append(atlas)


func _note_tex(kind: int) -> Texture2D:
	match kind:
		ATTACK:
			return _art("note_fight.png")
		FEINT:
			return _art("note_feint.png")
		_:
			return _art("note_rest.png")


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
	_build_turn_overlay()


func _build_highway() -> void:
	var frame := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.06, 0.55)
	style.border_color = TEAL
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	frame.add_theme_stylebox_override("panel", style)
	frame.position = Vector2(TRACK_X - 10, TRACK_TOP - 10)
	frame.size = Vector2(TRACK_W + 20, JUDGE_Y + 94 - (TRACK_TOP - 10))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(frame)

	var lane_h := JUDGE_Y - TRACK_TOP
	for i in 3:
		var lane_x := TRACK_X + i * LANE_W
		var glow := ColorRect.new()
		glow.color = Color(ROW_COLORS[i], 0.0)
		glow.position = Vector2(lane_x, TRACK_TOP)
		glow.size = Vector2(LANE_W, lane_h)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(glow)
		_lane_glow.append(glow)

		if i > 0:
			var div := ColorRect.new()
			div.color = Color(TEAL, 0.55)
			div.position = Vector2(lane_x, TRACK_TOP)
			div.size = Vector2(1, lane_h)
			div.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_root.add_child(div)

		var name_lbl := _label(ROW_NAMES[i], 16, ROW_COLORS[i])
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.position = Vector2(LANE_CENTER[i] - 70, JUDGE_Y + 62)
		name_lbl.size = Vector2(140, 24)
		name_lbl.z_index = 5
		_root.add_child(name_lbl)

	# winged skull crest straddling the highway's top edge, sitting just above
	# the border and small enough to clear the turn pips
	var crest := _art("duel_crest.png")
	if crest != null:
		var cw := 230.0
		var ch := cw * crest.get_height() / crest.get_width()
		var c := TextureRect.new()
		c.texture = crest
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_SCALE
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.position = Vector2(576.0 - cw * 0.5, (TRACK_TOP - 10.0) - 5.0 - ch * 0.5)
		c.size = Vector2(cw, ch)
		_root.add_child(c)

	_hit_glow = ColorRect.new()
	_hit_glow.color = Color(TEAL, 0.13)
	_hit_glow.position = Vector2(TRACK_X, JUDGE_Y - 10)
	_hit_glow.size = Vector2(TRACK_W, 20)
	_hit_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hit_glow)

	_hit_line = ColorRect.new()
	_hit_line.color = TEAL
	_hit_line.position = Vector2(TRACK_X, JUDGE_Y - 1)
	_hit_line.size = Vector2(TRACK_W, 2)
	_hit_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hit_line)

	# turn pips: four sparkles from the uploaded strip
	_make_pips()
	var dot_w := 28.0
	var dot_h := 44.0
	var dot_gap := 24.0
	var total := float(BEAT_DOTS) * dot_w + float(BEAT_DOTS - 1) * dot_gap
	for i in _pip_tex.size():
		var d := TextureRect.new()
		d.texture = _pip_tex[i]
		d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		d.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		d.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.position = Vector2(576.0 - total * 0.5 + float(i) * (dot_w + dot_gap), 14.0)
		d.size = Vector2(dot_w, dot_h)
		d.pivot_offset = d.size * 0.5
		d.modulate = Color(1, 1, 1, 0.85)
		d.z_index = 5
		_root.add_child(d)
		_beat_dots.append(d)

	# judgement keys, one under each lane
	var keys := ["keycap_f.png", "keycap_g.png", "keycap_h.png"]
	for i in 3:
		var cap := Control.new()
		cap.position = Vector2(LANE_CENTER[i] - 31.0, JUDGE_Y + 8.0)
		cap.size = Vector2(62.0, 50.0)
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.z_index = 5
		var plate := Panel.new()
		plate.size = cap.size
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ps := StyleBoxFlat.new()
		ps.bg_color = Color("#131a2c")
		ps.border_color = RED
		ps.set_border_width_all(2)
		ps.anti_aliasing = false
		plate.add_theme_stylebox_override("panel", ps)
		cap.add_child(plate)
		var letter := TextureRect.new()
		letter.texture = _key_letter(keys[i])
		letter.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		letter.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		letter.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		letter.position = Vector2(16.0, 10.0)
		letter.size = Vector2(30.0, 30.0)
		cap.add_child(letter)
		_root.add_child(cap)


func _build_hud() -> void:
	_feedback = _label("", 32, TEAL)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.anchor_right = 1.0
	_feedback.offset_top = 404
	_feedback.offset_bottom = 456
	_feedback.z_index = 6
	_root.add_child(_feedback)

	var you := _label("YOU", 16, Color("#f2eef7"))
	you.offset_left = BAR_X
	you.offset_right = BAR_X + BAR_W
	you.offset_top = 42
	you.offset_bottom = 66
	_root.add_child(you)

	_enemy_name = _label("ENEMY", 16, RED)
	_enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_name.anchor_left = 1.0
	_enemy_name.anchor_right = 1.0
	_enemy_name.offset_left = -BAR_X - BAR_W
	_enemy_name.offset_right = -BAR_X
	_enemy_name.offset_top = 42
	_enemy_name.offset_bottom = 66
	_root.add_child(_enemy_name)

	_combo_label = _label("", 24, TEAL)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.offset_left = 800
	_combo_label.offset_right = 1130
	_combo_label.offset_top = 300
	_combo_label.offset_bottom = 340
	_combo_label.visible = false
	_combo_label.z_index = 6
	_root.add_child(_combo_label)


func _build_turn_overlay() -> void:
	_turn_dim = ColorRect.new()
	_turn_dim.color = Color(0.01, 0.01, 0.02, 0.0)
	_turn_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_turn_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_dim.z_index = 20
	_root.add_child(_turn_dim)

	_turn_layer = Control.new()
	_turn_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_turn_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_layer.modulate.a = 0.0
	_turn_layer.visible = false
	_turn_layer.z_index = 21
	_root.add_child(_turn_layer)

	var title := _art("your_turn_title.png")
	if title != null:
		var w := 520.0
		var h := w * title.get_height() / title.get_width()
		var t := TextureRect.new()
		t.texture = title
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.position = Vector2(576.0 - w * 0.5, 246.0)
		t.size = Vector2(w, h)
		_turn_layer.add_child(t)

	var rule := _art("turn_rule.png")
	if rule != null:
		var w := 620.0
		var h := w * rule.get_height() / rule.get_width()
		var r := TextureRect.new()
		r.texture = rule
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.position = Vector2(576.0 - w * 0.5, 326.0)
		r.size = Vector2(w, h)
		_turn_rule_mat = ShaderMaterial.new()
		_turn_rule_mat.shader = CENTER_WIPE
		_turn_rule_mat.set_shader_parameter("progress", 1.0)
		r.material = _turn_rule_mat
		_turn_layer.add_child(r)



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


func _build_enemy_bar() -> void:
	_ebar_fill = _duel_bar(true, false)


func _duel_bar(right_aligned: bool, with_frame: bool) -> TextureRect:
	var bar := Control.new()
	if right_aligned:
		bar.anchor_left = 1.0
		bar.anchor_right = 1.0
		bar.offset_left = -BAR_X - BAR_W
		bar.offset_right = -BAR_X
	else:
		bar.offset_left = BAR_X
		bar.offset_right = BAR_X + BAR_W
	bar.offset_top = BAR_Y
	bar.offset_bottom = BAR_Y + BAR_H
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)

	var track := Panel.new()
	track.size = Vector2(BAR_W, BAR_H)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color("#1a1018")
	ts.border_color = Color.BLACK
	ts.set_border_width_all(1)
	ts.set_corner_radius_all(int(BAR_H * 0.5))
	ts.anti_aliasing = false
	track.add_theme_stylebox_override("panel", ts)
	bar.add_child(track)

	var fill := TextureRect.new()
	fill.texture = _art("health_fill.png", HP_DIR)
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.position = Vector2.ZERO
	fill.size = Vector2(BAR_W, BAR_H)
	bar.add_child(fill)

	if with_frame:
		var frame := _art("health_frame.png", HP_DIR)
		if frame != null:
			var fw := BAR_FRAME_W
			var fh := fw * frame.get_height() / frame.get_width()
			var f := TextureRect.new()
			f.texture = frame
			f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			f.stretch_mode = TextureRect.STRETCH_SCALE
			f.mouse_filter = Control.MOUSE_FILTER_IGNORE
			f.position = Vector2((BAR_W - fw) * 0.5, (BAR_H - fh) * 0.5 - 7.0)
			f.size = Vector2(fw, fh)
			f.modulate = Color.WHITE
			bar.add_child(f)
	return fill


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
	_pbar_fill = _duel_bar(false, true)


func _refresh_player_bar(_cur: int = 0, _mx: int = 0) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_p_target = clampf(float(int(_player.get("health")))
			/ float(maxi(int(_player.get("max_health")), 1)), 0.0, 1.0)


func _refresh_enemy_bar() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	_e_target = clampf(float(int(_enemy.get("health")))
			/ float(maxi(int(_enemy.get("max_health")), 1)), 0.0, 1.0)


func _apply_fills(fill: TextureRect, frac: float) -> void:
	if fill == null:
		return
	var w := BAR_W * clampf(frac, 0.0, 1.0)
	fill.size.x = w
	fill.visible = w >= 2.0


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

		# Long notes get a body trailing above the head, added first so the
		# glyph draws on top of it.
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

		var art := TextureRect.new()
		art.name = "Glyph"
		art.texture = _note_tex(t)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.position = Vector2.ZERO
		art.size = n.size
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
	_misses = 0
	_feints = 0
	_clear_hold()
	_feedback.text = ""
	if p == P.PLAYER:
		# The splash gets a fixed two seconds, so give the player phase a
		# count-in long enough that the first note still lands after it.
		_lead = maxf(LEAD, ceilf(TURN_BANNER_SEC / _beat_sec + 0.4))
		_show_turn_banner()
	else:
		_lead = LEAD
		_hide_turn_banner()
	for i in _notes.size():
		var n: Control = _notes[i]
		n.scale = Vector2.ONE
		n.modulate = Color.WHITE
	_refresh_enemy_bar()


func _show_turn_banner() -> void:
	if _turn_layer == null:
		return
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	_turn_layer.visible = true
	_turn_layer.modulate.a = 0.0
	_turn_dim.color.a = 0.0
	if _turn_rule_mat != null:
		_turn_rule_mat.set_shader_parameter("progress", 0.0)
	# Fade in, wipe the rule out from its centre diamond, hold for the splash's
	# full duration, then clear before the first note reaches the judge line.
	var hold := maxf(0.1, TURN_BANNER_SEC - TURN_FADE_IN - TURN_FADE_OUT)
	_turn_tween = create_tween()
	_turn_tween.tween_property(_turn_layer, "modulate:a", 1.0, TURN_FADE_IN)
	_turn_tween.parallel().tween_property(_turn_dim, "color:a", 0.55, TURN_FADE_IN)
	if _turn_rule_mat != null:
		var wipe := _turn_tween.parallel().tween_property(_turn_rule_mat,
				"shader_parameter/progress", 1.0, TURN_RULE_WIPE)
		wipe.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_turn_tween.tween_interval(hold)
	_turn_tween.tween_property(_turn_layer, "modulate:a", 0.0, TURN_FADE_OUT)
	_turn_tween.parallel().tween_property(_turn_dim, "color:a", 0.0, TURN_FADE_OUT)
	if _turn_rule_mat != null:
		_turn_tween.parallel().tween_property(_turn_rule_mat,
				"shader_parameter/progress", 0.0, TURN_FADE_OUT)
	_turn_tween.tween_callback(func() -> void:
		if _turn_layer != null:
			_turn_layer.visible = false)


func _hide_turn_banner() -> void:
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	if _turn_layer != null:
		_turn_layer.visible = false
		_turn_layer.modulate.a = 0.0
	if _turn_dim != null:
		_turn_dim.color = Color(0.01, 0.01, 0.02, 0.0)


func _note_time(i: int) -> float:
	return (float(i) + _lead) * _beat_sec


func _phase_end() -> float:
	return (float(_pattern.size()) + _lead) * _beat_sec + 0.35


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
	_apply_fills(_pbar_fill, _p_show)
	_apply_fills(_ebar_fill, _e_show)

	# turn indicator: the active round's sparkle is red and breathes with the beat
	var turn_i := maxi(0, _round - 1) % BEAT_DOTS
	if turn_i != _turn_last:
		_turn_last = turn_i
		for i in _beat_dots.size():
			var d: Control = _beat_dots[i]
			var tw := create_tween()
			tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(d, "scale", Vector2(1.35, 1.35) if i == turn_i else Vector2.ONE, 0.22)
	for i in _beat_dots.size():
		if i == turn_i:
			var pulse := 0.65 + 0.35 * sin(_phase_time * TAU / _beat_sec)
			_beat_dots[i].modulate = Color(RED, pulse)
		else:
			_beat_dots[i].modulate = Color(1.0, 1.0, 1.0, 0.85)

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
			if tail_gap(_hold_note) > 0.12 and held < bar * 0.6:
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
	var best := -1
	var best_dt := 999.0
	for i in _pattern.size():
		if _judged[i] or int(_pattern[i]["type"]) != lane:
			continue
		var dt := absf(_phase_time - _note_time(i))
		if dt <= WINDOW and dt < best_dt:
			best = i
			best_dt = dt
	if best < 0:
		return

	_judged[best] = true
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
	_hide_turn_banner()
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
