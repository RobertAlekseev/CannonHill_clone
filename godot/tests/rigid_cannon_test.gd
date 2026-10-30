extends SceneTree
## P1 acceptance cases for lab/rigid_cannon.gd on static and sand terrain.
## godot --headless --path godot --script res://tests/rigid_cannon_test.gd
const Sim = preload("res://simulation.gd")
const Rigid = preload("res://rigid_cannon.gd")
var failures := 0

func check(condition: bool, description: String) -> void:
	if condition: print("PASS ", description)
	else:
		push_error("FAIL " + description)
		failures += 1

## Rock world whose surface height per column comes from a callable.
func world_from(surface: Callable):
	var s = Sim.new()
	s.cells.fill(0)
	for x in Sim.W:
		for y in range(clampi(int(surface.call(x)), 0, Sim.H), Sim.H):
			s.cells[y * Sim.W + x] = 2
	return s

func settle(world, body, seconds: float, sand := false) -> void:
	for i in int(seconds / Sim.DT):
		if sand: world.step()
		body.step(world, Sim.DT)

func body_on(world, x: float):
	return Rigid.new(Vector2(x, world.surface_at(int(x)) - 3.5))

func _initialize() -> void:
	# 1. Flat ground: stays upright, no drift, no jitter.
	var flat = world_from(func(_x): return 100)
	var c = body_on(flat, 120.0)
	settle(flat, c, 3.0)
	var rest: Vector2 = c.pos
	settle(flat, c, 2.0)
	check(absf(c.angle) < 0.02 and c.pos.distance_to(rest) < 0.05 and c.vel.length() < 0.2, "flat ground: upright and at rest")
	check(c.wheel_contacts == 2 and c.hull_contacts == 0, "flat ground: carried by both wheels only")

	# 2. Slope 1:3 (18 deg): braked cannon aligns with the slope and holds.
	var slope = world_from(func(x): return 60 + x / 3.0)
	c = body_on(slope, 120.0)
	settle(slope, c, 4.0)
	rest = c.pos
	settle(slope, c, 2.0)
	check(absf(c.angle - atan(1.0 / 3.0)) < 0.08, "slope: chassis follows an 18 degree slope")
	check(c.pos.distance_to(rest) < 0.3 and c.upright(), "slope: braked wheels hold without tipping")

	# 3. Same slope, brake released: rolls downhill (towards +x, y grows).
	c.brake = false
	var before: Vector2 = c.pos
	settle(slope, c, 1.5)
	check(c.pos.x > before.x + 3.0 and c.upright(), "slope: released brake rolls downhill upright")

	# 4. One-sided support loss: a narrow pit under the right wheel only. The
	# wheel drops in, the chassis leans on the edge and does not tip over.
	var pit = world_from(func(x): return 100 if x < 124 or x > 127 else 106)
	c = body_on(pit, 122.0)
	settle(pit, c, 3.0)
	check(c.angle > 0.3 and c.upright(), "one-sided loss: tilts towards the pit and stays upright")
	rest = c.pos
	settle(pit, c, 1.0)
	check(c.pos.distance_to(rest) < 0.1, "one-sided loss: comes to rest")
	# Wide pit with the centre of mass already above it: leans far into it.
	var wide = world_from(func(x): return 100 if x < 123 or x > 135 else 112)
	c = body_on(wide, 122.0)
	settle(wide, c, 3.0)
	check(c.angle > 0.7 and not c.tipped(), "one-sided loss: centre of mass over a wide pit leans into it")

	# 5. Ledge with the centre of mass beyond the edge: tips and falls off.
	var ledge = world_from(func(x): return 90 if x < 120 else 125)
	c = Rigid.new(Vector2(121.5, 86.5))
	settle(ledge, c, 4.0)
	check(c.tipped() or c.pos.y > 110.0, "ledge: centre of mass beyond the edge tips the cannon off")
	check(c.pos.y > 110.0, "ledge: cannon ends up on the lower level")

	# 6. Complete ground loss: free fall, then lands on the floor below.
	var hole = world_from(func(x): return 60 if x < 100 or x > 140 else 120)
	c = Rigid.new(Vector2(120, 56.5))
	settle(hole, c, 0.2)
	check(c.vel.y > 5.0 and c.wheel_contacts == 0, "ground loss: free fall without support")
	settle(hole, c, 3.0)
	check(c.wheel_contacts > 0 and c.pos.y > 110.0 and c.upright(), "ground loss: lands upright on the floor below")

	# 7. Drop from 20 cells: no bounce above the drop height, no tunnelling.
	c = Rigid.new(Vector2(120, 76.5))
	var landed := INF
	var highest := INF
	for i in 120:
		c.step(flat, Sim.DT)
		if c.wheel_contacts > 0 and landed == INF: landed = c.pos.y
		if landed != INF: highest = minf(highest, c.pos.y)
	check(landed - highest < 0.5 and c.pos.y < 100.0 and c.upright(), "drop: no bounce and no tunnelling")

	# 8. Recoil at the muzzle: a realistic shove rocks back, a huge one tips over.
	for case in [[1.5, false], [10.0, true]]:
		c = body_on(flat, 120.0)
		settle(flat, c, 1.0)
		c.apply_impulse(c.to_world(Vector2(5, -6)), Vector2(-case[0], 0))
		settle(flat, c, 4.0)
		check(c.tipped() == case[1], "recoil %.1f: %s" % [case[0], "tips over" if case[1] else "rocks back upright"])

	# 9. Real sand: cannon rests on settling sand, then sinks when undermined.
	var sand = Sim.new()
	c = body_on(sand, 40.0)
	settle(sand, c, 3.0, true)
	var top: float = c.pos.y
	check(c.upright() and c.wheel_contacts > 0, "sand: rests on the default terrain")
	var rest_angle: float = c.angle
	sand.crater(c.pos.x + 7, c.pos.y + 6, 7)
	settle(sand, c, 3.0, true)
	check(c.pos.y > top + 1.0 and c.angle > rest_angle + 0.1, "sand: one-sided undermining sinks and tilts towards the hole")

	# 10. Determinism and snapshot roundtrip: the host state reproduces exactly.
	var a = body_on(pit, 122.0)
	var b = Rigid.new()
	settle(pit, a, 0.5)
	b.apply_snapshot(a.snapshot())
	settle(pit, a, 1.0)
	settle(pit, b, 1.0)
	check(a.snapshot() == b.snapshot(), "snapshot roundtrip continues bit-identically")
	check(is_finite(a.pos.x) and is_finite(a.angle), "state stays finite")
	print("RESULT failures=", failures)
	quit(1 if failures else 0)
