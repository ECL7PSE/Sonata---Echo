extends Node
## Week 8: global platform tweaks. No gameplay changes.
## - F11 toggles fullscreen on PC builds (harmless on Web).
## - Autoload so it works in both StartScreen and Main scenes.

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_F11 or k.physical_keycode == KEY_F11):
			var mode: int = DisplayServer.window_get_mode()
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()
