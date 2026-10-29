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
	test_health()
	print("RESULT failures=", failures)
	quit(1 if failures else 0)

func incoming_shot(s, player: int) -> Dictionary:
	var c: Dictionary = s.cannons[player]
	return {"x": c.x + 5.5, "y": c.y, "vx": -90.0, "vy": -Sim.GRAVITY * Sim.DT, "age": 0.0}

func test_health() -> void:
	var s = Sim.new()
	check(s.cannons[0].hp == 1000 and s.cannons[1].hp == 1000, "both cannons start with 1000 HP")
	s.shots.append(incoming_shot(s, 1))
	s.step()
	check(s.cannons[1].hp == 800 and s.shots.is_empty(), "swept projectile collision causes exactly 200 direct damage")
	check(s.cannons[0].hp == 1000 and s.impacts == 1, "direct hit does not double-apply splash or damage distant cannon")
	check(s.cannons[1].hit_flash > 0, "damage activates visible hit feedback")
	s.reset()
	s.cannons[0].x = 60.0
	s.cannons[0].y = 40.0
	s.explode(71, 40)
	check(s.cannons[0].hp == 900, "blast damage falls linearly with distance from hull")
	s.explode(78, 40)
	check(s.cannons[0].hp == 900, "blast radius boundary causes no damage")
	s.explode(60, 40)
	check(s.cannons[0].hp == 700, "own nearby explosions can cause self-damage")
	s.reset()
	var y: float = s.cannons[0].y
	s.crater(40, y + 8, 12)
	for i in 60: s.step()
	check(s.cannons[0].hp == 1000, "debug excavation and falling do not invent damage")
	s.reset()
	s.cannons[1].hp = 100
	s.shots.append(incoming_shot(s, 1))
	s.step()
	check(s.cannons[1].hp == 0 and s.round_over and s.winner == 0, "lethal hit clamps HP to zero and declares winner")
	s.input_player(0, 45, 55, true)
	s.input_player(1, 45, 55, true)
	check(s.shots.is_empty(), "neither player can fire after round ends")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(s.snapshot()))
	var clone = Sim.new()
	check(clone.apply_snapshot(snapshot) and clone.round_over and clone.winner == 0 and clone.cannons[1].hp == 0, "wire snapshot preserves health and terminal round state")
	clone.cannons[0].hp = 1
	check(s.cannons[0].hp == 1000, "replica state does not alias authoritative cannon dictionaries")
	var invalid := snapshot.duplicate(true)
	invalid.cannons[0].hp = -1
	var prior_hp: int = clone.cannons[0].hp
	check(not clone.apply_snapshot(invalid) and clone.cannons[0].hp == prior_hp, "invalid HP snapshot is rejected atomically")
	invalid = snapshot.duplicate(true)
	invalid.version = 1
	check(not clone.apply_snapshot(invalid), "legacy engine protocol cannot silently omit health")
	s.reset()
	s.cannons[0].hp = 200
	s.cannons[1].hp = 200
	s.shots.append(incoming_shot(s, 0))
	s.shots.append(incoming_shot(s, 1))
	s.step()
	check(s.round_over and s.winner == -1 and s.cannons[0].hp == 0 and s.cannons[1].hp == 0, "same-tick mutual destruction is a draw")
	s.reset()
	check(not s.round_over and s.winner == -1 and s.cannons[0].hp == 1000 and s.cannons[1].hp == 1000, "restart restores health and clears round result")
	s.input_player(0, 45, 55, true)
	check(s.shots.size() == 1, "new round permits firing again")
