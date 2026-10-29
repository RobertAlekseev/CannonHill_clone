extends SceneTree
const Sim = preload("res://simulation.gd")
const Assets = preload("res://shared_assets.gd")
var failures := 0

func check(condition: bool, description: String) -> void:
	if condition: print("PASS ", description)
	else:
		push_error("FAIL " + description)
		failures += 1

func sand_count(s) -> int:
	return s.cells.count(1)

func _initialize() -> void:
	var s = Sim.new()
	check(s.cells.size() == 30720, "fixed world dimensions")
	var count := sand_count(s)
	for i in 120: s.step()
	check(sand_count(s) == count, "sand is conserved while settling")
	check(s.cells.count(2) == Sim.W * 4, "bedrock does not move")
	var c: Dictionary = s.cannons[0]
	var initial_y: float = c.y
	for i in 120: s.step()
	check(absf(c.y - initial_y) < 0.1, "cannon stays supported at rest")
	s.crater(c.x, c.y + 8, 14)
	var destroyed := sand_count(s)
	for i in 90: s.step()
	check(c.y > initial_y + 2, "cannon falls when its support is removed")
	check(sand_count(s) == destroyed, "crater relaxation conserves remaining sand")
	s.reset()
	for i in 120: s.step()
	s.input_player(0, 45, 55, true)
	check(s.shots.size() == 1, "button press launches a projectile")
	s.input_player(0, 45, 55, true)
	check(s.shots.size() == 1, "host enforces fire cooldown")
	var initial: Dictionary = s.shots[0].duplicate()
	s.step()
	check(s.shots[0].x > initial.x and s.shots[0].y < initial.y, "initial ballistic flight")
	for i in 400: s.step()
	check(s.impacts > 0 and s.shots.is_empty(), "shot impacts terrain and is removed")
	check(s.events.filter(func(e): return e.type == "fire").size() == 1, "fire emits one local event")
	check(s.events.filter(func(e): return e.type == "impact").size() == s.impacts, "each impact emits one local event")
	s.reset()
	for i in 120: s.step()
	var preview: Dictionary = s.trajectory(1, 30, 70, 400)
	s.input_player(1, 30, 70, true)
	var flown := 0
	while not s.shots.is_empty() and flown < 400:
		s.step()
		flown += 1
	var landing: Vector2 = preview.points[-1]
	var impact: Dictionary = s.events[-1]
	check(preview.hit and landing.distance_to(Vector2(impact.x, impact.y)) < 0.5, "trajectory preview predicts the impact")
	check(not s.snapshot().has("events"), "local events stay out of the snapshot")
	var assets = Assets.new()
	check(assets.problems.is_empty() and assets.has("audio.fire") and assets.has("audio.impact"), "shared assets resolve with valid checksums")
	check(assets.audio("audio.impact") is AudioStreamWAV, "shared audio loads from outside the Godot project")
	var clone = Sim.new()
	check(clone.apply_snapshot(s.snapshot()) and clone.cells == s.cells and clone.tick == s.tick, "network snapshot roundtrip")
	check(not clone.apply_snapshot({"version": 99}), "incompatible protocol rejected")
	print("RESULT failures=", failures)
	quit(1 if failures else 0)
