extends SceneTree
const Sim = preload("res://simulation.gd")
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
	var clone = Sim.new()
	check(clone.apply_snapshot(s.snapshot()) and clone.cells == s.cells and clone.tick == s.tick, "network snapshot roundtrip")
	check(not clone.apply_snapshot({"version": 99}), "incompatible protocol rejected")
	print("RESULT failures=", failures)
	quit(1 if failures else 0)
