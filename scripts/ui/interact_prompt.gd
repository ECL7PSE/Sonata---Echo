extends RefCounted

const INTERACT_PROMPT_SCALE := 0.5


static func make(text: String, prompt_position: Vector2) -> Label:
	var prompt := Label.new()
	prompt.text = text
	prompt.add_theme_font_override("font",
			preload("res://Assets/UI/pixel_ui/font/pixel_ui_font.fnt"))
	prompt.add_theme_font_size_override("font_size", 20)
	prompt.add_theme_color_override("font_color", Color("#ffd166"))
	prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	prompt.add_theme_constant_override("shadow_offset_x", 2)
	prompt.add_theme_constant_override("shadow_offset_y", 2)
	prompt.position = prompt_position
	prompt.size = Vector2(160, 24)
	prompt.pivot_offset = prompt.size * 0.5
	prompt.scale = Vector2.ONE * INTERACT_PROMPT_SCALE
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.visible = false
	return prompt
