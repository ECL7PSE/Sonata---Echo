extends SceneTree
## One-shot probe: raw dimensions of every monster sheet.
## Run once to get the numbers, then set the frame grids in measure_sheets.gd.

const BASE := "res://Assets/Monsters_Creatures_Fantasy/"

const SHEETS := [
	"Rat/idle", "Rat/run", "Rat/attack_bite", "Rat/hurt", "Rat/rat-death",
	"Slime/idle", "Slime/walk", "Slime/attack", "Slime/hurt", "Slime/death",
	"Bat/fly", "Bat/attack", "Bat/hurt", "Bat/death",
	"Mushroom/Idle", "Mushroom/Run", "Mushroom/Attack",
			"Mushroom/Take Hit", "Mushroom/Death",
	"Flying eye/Flight", "Flying eye/Attack", "Flying eye/Take Hit",
			"Flying eye/Death",
	"Goblin/Idle", "Goblin/Run", "Goblin/Attack", "Goblin/Take Hit",
			"Goblin/Death",
	"Mimic/Idle_closed", "Mimic/opening", "Mimic/idle_open",
			"Mimic/transform", "Mimic/idle_transformed", "Mimic/walk",
			"Mimic/attack_1", "Mimic/hurt", "Mimic/death",
	"Skeleton/Idle", "Skeleton/Walk", "Skeleton/Attack",
			"Skeleton/Take Hit", "Skeleton/Death",
]


func _initialize() -> void:
	for s in SHEETS:
		var path: String = BASE + s + ".png"
		if not ResourceLoader.exists(path):
			print("%-28s MISSING" % s)
			continue
		var tex: Texture2D = load(path)
		var img: Image = tex.get_image()
		print("%-28s %4d x %4d" % [s, img.get_width(), img.get_height()])
	quit(0)