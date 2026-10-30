extends SceneTree
## Native viewport validation. Run with --script res://tests/health_scene.gd
## -- --case=damage|victory --screenshot=C:/absolute/path.png
var game: Node

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var scenario := "damage"
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): scenario = arg.trim_prefix("--case=")
		elif arg.begins_with("--screenshot="): path = arg.trim_prefix("--screenshot=")
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	if scenario == "victory": game.sim.cannons[1].hp = 200
	var c: Dictionary = game.sim.cannons[1]
	game.sim.shots.append({"x": c.x + 5.5, "y": c.y, "vx": -90.0, "vy": -game.Sim.GRAVITY * game.Sim.DT, "age": 0.0})
	var fire_button: Button
	for child in game.get_children():
		if child is Button and child.text == "FEUER": fire_button = child
	if not fire_button:
		push_error("Missing fire button")
		quit(1)
		return
	for frame in 45:
		await process_frame
		if frame == 20: fire_button.pressed.emit()
	var expected_hp := 0 if scenario == "victory" else 800
	if game.sim.cannons[1].hp != expected_hp:
		push_error("Unexpected health in native scene")
		quit(1)
		return
	if (scenario == "damage" and game.sim.shots.is_empty()) or (scenario == "victory" and not game.sim.shots.is_empty()):
		push_error("Fire button did not respect round state")
		quit(1)
		return
	if scenario == "victory" and game.round_label.text.find("SPIELER 1 GEWINNT") == -1:
		push_error("Missing victory label")
		quit(1)
		return
	if not path.is_empty():
		await RenderingServer.frame_post_draw
		var error: int = root.get_texture().get_image().save_png(path)
		if error != OK:
			push_error("Screenshot save failed")
			quit(1)
			return
	print("HEALTH_SCENE_PASS case=%s hp1=%d over=%s winner=%d" % [scenario, game.sim.cannons[1].hp, game.sim.round_over, game.sim.winner])
	quit(0)
