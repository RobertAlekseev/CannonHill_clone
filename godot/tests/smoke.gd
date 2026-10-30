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
	rigid_body_checks()
	weapon_checks()
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

## v3: rigid-body cannons inside the real game simulation.
func rigid_body_checks() -> void:
	var s = Sim.new()
	for i in 90: s.step()
	var c: Dictionary = s.cannons[0]
	var rest := Vector2(c.x, c.y)
	var rest_tilt: float = c.tilt
	for i in 60: s.step()
	check(Vector2(c.x, c.y).distance_to(rest) < 0.1 and absf(c.tilt - rest_tilt) < 0.01, "rigid cannon rests on the start terrain")
	check(absf(rest_tilt) > 0.1, "rigid cannon follows the sloped start position")
	var level: Vector2 = s.barrel(0, 45.0)
	check(absf(level.angle() - (Sim.aim(0, 45.0).angle() + c.tilt)) < 0.001, "barrel aims relative to the tilted chassis")
	s.input_player(0, 45, 90, true)
	var peak := 0.0
	for i in 30:
		s.step()
		peak = maxf(peak, absf(c.tilt - rest_tilt))
	check(peak > 0.005 and not s.tipped(0), "recoil rocks the cannon without tipping it")
	s.cannons[1].tilt = PI
	s.cannons[1].cooldown = 0.0
	s.input_player(1, 45, 55, true)
	check(s.shots.filter(func(shot): return shot.vx < 0.0).is_empty(), "a tipped cannon cannot fire")
	for i in int(Sim.RIGHTING_TIME / Sim.DT) + 30: s.step()
	check(not s.tipped(1) and absf(s.cannons[1].tilt) < 0.6, "a tipped cannon rights itself after a while")
	s.reset()
	for i in 60: s.step()
	c = s.cannons[0]
	var before: Vector2 = Vector2(c.x, c.y)
	var tilt_before: float = c.tilt
	s.crater(c.x + 6, c.y + 6, 7)
	for i in 90: s.step()
	check(c.y > before.y + 1.0 and c.tilt > tilt_before + 0.1, "one-sided undermining tilts the cannon into the hole")
	var wire: Dictionary = JSON.parse_string(JSON.stringify(s.snapshot()))
	var replica = Sim.new()
	check(wire.version == Sim.PROTOCOL_VERSION and replica.apply_snapshot(wire) and is_equal_approx(replica.cannons[0].tilt, c.tilt) and replica.cannons[0].has("spin"), "snapshot carries rigid-body state")
	var broken := wire.duplicate(true)
	broken.cannons[0].erase("spin")
	check(not replica.apply_snapshot(broken), "snapshot without rigid-body fields is rejected")

## v4: weapons, ammo, helpers and the replicated event log.
func fire_with(s, player: int, kind: int, angle := 45.0, power := 55.0) -> void:
	s.cannons[player].cooldown = 0.0
	s.input_player(player, angle, power, true, kind)

func weapon_checks() -> void:
	var s = Sim.new()
	for i in 60: s.step()
	check(s.cannons[0].weapon == Sim.STONE and s.cannons[0].ammo[Sim.STONE] == -1, "stone is the default with unlimited ammo")
	fire_with(s, 0, Sim.ROCKET)
	fire_with(s, 0, Sim.ROCKET)
	fire_with(s, 0, Sim.ROCKET)
	check(s.shots.size() == 2 and s.cannons[0].ammo[Sim.ROCKET] == 0, "rockets are limited to two per round")
	s.input_player(0, 45, 55, false, 99)
	check(s.cannons[0].weapon == Sim.ROCKET, "invalid weapon index is ignored")
	# Rocket vs stone from the same cannon and aim: thrust makes it faster.
	var a = Sim.new()
	var b = Sim.new()
	fire_with(a, 0, Sim.ROCKET, 60, 50)
	fire_with(b, 0, Sim.STONE, 60, 50)
	for i in 12:
		a.step()
		b.step()
	check(Vector2(a.shots[0].vx, a.shots[0].vy).length() > Vector2(b.shots[0].vx, b.shots[0].vy).length() + 15.0, "rocket thrust accelerates the shot")
	var r = Sim.new()
	var preview: Dictionary = r.trajectory(1, 65, 35, 400, Sim.ROCKET)
	fire_with(r, 1, Sim.ROCKET, 65, 35)
	for i in 400:
		if r.shots.is_empty(): break
		r.step()
	var landing: Vector2 = preview.points[-1]
	var hits: Array = r.events.filter(func(e): return e.type == "impact")
	check(preview.hit and hits.size() == 1 and landing.distance_to(Vector2(hits[0].x, hits[0].y)) < 1.0, "rocket preview includes the thrust")
	# Grenade: bounces on the ground and only explodes when the fuse burns down.
	s = Sim.new()
	for i in 60: s.step()
	fire_with(s, 0, Sim.GRENADE, 50, 40)
	var touched := -1
	var exploded := -1
	for i in 150:
		s.step()
		if touched < 0 and not s.shots.is_empty() and s.events[-1].type == "fire" and s.shots[0].vy <= 0.0 and s.shots[0].age > 0.3: touched = i
		if exploded < 0 and s.impacts > 0: exploded = i
	check(touched >= 0 and exploded > touched, "grenade bounces before it explodes")
	check(absf(exploded * Sim.DT - Sim.WEAPONS[Sim.GRENADE].fuse) < 0.1, "grenade explodes after its fuse time")
	check(s.cannons[0].ammo[Sim.GRENADE] == 2, "grenade ammo is consumed")
	# Mega: splits at the apex into six splinters, each with its own crater.
	s = Sim.new()
	fire_with(s, 0, Sim.MEGA, 60, 60)
	var most := 0
	for i in 240:
		s.step()
		most = maxi(most, s.shots.size())
	check(most == 6 and s.events.filter(func(e): return e.type == "split").size() == 1, "mega splits into six splinters")
	check(s.impacts == 6, "every splinter explodes")
	# Snowball: adds sand, no damage.
	s = Sim.new()
	var sand: int = s.cells.count(1)
	fire_with(s, 0, Sim.SNOWBALL)
	for i in 150: s.step()
	check(s.cells.count(1) > sand + 50 and s.cannons[1].hp == Sim.MAX_HP and s.events[-1].type == "snow", "snowball builds sand without damage")
	# Medipack heals up to the maximum; shield absorbs before HP.
	s = Sim.new()
	s.cannons[0].hp = 500
	fire_with(s, 0, Sim.MEDIPACK)
	check(s.cannons[0].hp == 800 and s.shots.is_empty() and s.cannons[0].ammo[Sim.MEDIPACK] == 0, "medipack heals 300 without a projectile")
	fire_with(s, 0, Sim.MEDIPACK)
	check(s.cannons[0].hp == 800, "medipack cannot be used twice")
	fire_with(s, 1, Sim.SHIELD)
	s.explode(s.cannons[1].x, s.cannons[1].y, 1)
	check(s.cannons[1].hp == Sim.MAX_HP and s.cannons[1].shield == 200, "shield absorbs a direct hit")
	s.explode(s.cannons[1].x, s.cannons[1].y, 1)
	check(s.cannons[1].hp == Sim.MAX_HP and s.cannons[1].shield == 0, "shield absorbs the second hit as well")
	s.explode(s.cannons[1].x, s.cannons[1].y, 1)
	check(s.cannons[1].hp == 800 and s.cannons[1].shield == 0, "after the shield is gone HP takes damage")
	# Wire format: weapons, ammo, shield, shot kinds and a bounded event log.
	s = Sim.new()
	fire_with(s, 0, Sim.GRENADE)
	fire_with(s, 1, Sim.SHIELD)
	for i in 40: s.step()
	var wire: Dictionary = JSON.parse_string(JSON.stringify(s.snapshot()))
	var replica = Sim.new()
	check(replica.apply_snapshot(wire) and replica.cannons[0].ammo[Sim.GRENADE] == 2 and replica.cannons[1].shield == 400 and replica.shots[0].kind is int, "snapshot carries weapons, ammo, shields and shot kinds")
	check(replica.events.size() == 2 and replica.events[-1].id is int, "snapshot replays the event log with ids")
	for i in 40: s.emit({"type": "fire", "x": 0.0, "y": 0.0})
	check(s.snapshot().log.size() == Sim.EVENT_LOG, "event log in the snapshot is bounded")
	var broken := wire.duplicate(true)
	broken.cannons[0].weapon = 9
	check(not replica.apply_snapshot(broken), "snapshot with an unknown weapon is rejected")
	broken = wire.duplicate(true)
	broken.log[0].type = "evil"
	check(not replica.apply_snapshot(broken), "snapshot with an unknown event type is rejected")
