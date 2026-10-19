extends SceneTree
## Renders two PNGs of the finished dungeon into screenshots/ so they can be
## dropped into the README:
##   screenshots/08-dungeon-overview.png  - the whole tile dungeon
##   screenshots/09-dungeon-gameplay.png  - the in-game view at the spawn point
##
## The overview camera is derived from the dungeon builder's own MAP_W / MAP_H
## rather than hardcoded, so growing the floor reframes the shot instead of
## quietly cropping it.
##
## Run it with:
##   godot --path . --script res://tools/capture_screenshots.gd

const OVERVIEW_PATH := "res://screenshots/08-dungeon-overview.png"
const GAMEPLAY_PATH := "res://screenshots/09-dungeon-gameplay.png"

var _frames := 0
var _player_camera: Camera2D = null
var _game: Node = null

func _initialize() -> void:
	_game = load("res://Main.tscn").instantiate()
	root.add_child(_game)
	_player_camera = _game.get_node("Player(CharacterBody2D)/Camera2D")


func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		8:
			_save(GAMEPLAY_PATH)
		32:
			# Swap the follow camera for one that frames the whole dungeon.
			if _player_camera != null:
				_player_camera.enabled = false
			var cam := Camera2D.new()
			cam.zoom = _fit_zoom()
			cam.position = _map_centre()
			cam.enabled = true
			_game.add_child(cam)
			cam.make_current()
			print("overview camera: zoom=%.3f at %s" % [cam.zoom.x, cam.position])
		48:
			_save(OVERVIEW_PATH)
		52:
			return true
	return false


## The dungeon in world pixels, read from the builder's own constants.
func _map_size() -> Vector2:
	var script: GDScript = load("res://dungeon_builder.gd")
	return Vector2(
		float(script.get("MAP_W")) * float(script.get("GRID")) * float(script.get("SCALE")),
		float(script.get("MAP_H")) * float(script.get("GRID")) * float(script.get("SCALE")))


func _map_centre() -> Vector2:
	return _map_size() / 2.0


## The largest zoom that still fits the whole map inside the window, with a small
## margin so the outer wall ring is not flush against the edge of the shot.
func _fit_zoom() -> Vector2:
	var view := Vector2(get_root().get_texture().get_size())
	var margin := 1.06
	return Vector2.ONE * minf(view.x / _map_size().x, view.y / _map_size().y) / margin


func _save(path: String) -> void:
	var img: Image = root.get_texture().get_image()
	var err := img.save_png(path)
	print("saved %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), err])