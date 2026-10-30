class_name SandSimulation
extends RefCounted
## Fixed 30 Hz, screen coordinates: x right / y down, one cell = 0.25 m.
const W := 240
const H := 128
const DT := 1.0 / 30.0
const GRAVITY := 39.24
## v4: v3 (health, rigid-body cannons) plus weapons, ammo, shields and an
## event log (shared/network-protocol.md).
const PROTOCOL_VERSION := 4
enum { STONE, GRENADE, ROCKET, MEGA, SNOWBALL, MEDIPACK, SHIELD, SPLINTER }
## Own prototype balancing. crater/blast in cells, damage = direct hit maximum.
## ammo -1 = unlimited; projectile false = used instantly on the own cannon.
const WEAPONS: Array[Dictionary] = [
	{"name": "Stein", "ammo": -1, "cooldown": 0.7, "crater": 10.0, "damage": 200, "blast": 14.0, "projectile": true},
	{"name": "Granate", "ammo": 3, "cooldown": 1.0, "crater": 13.0, "damage": 260, "blast": 18.0, "projectile": true, "fuse": 2.5},
	{"name": "Rakete", "ammo": 2, "cooldown": 1.2, "crater": 15.0, "damage": 320, "blast": 18.0, "projectile": true, "thrust": 70.0, "burn": 0.6},
	{"name": "Mega", "ammo": 1, "cooldown": 1.5, "crater": 8.0, "damage": 150, "blast": 12.0, "projectile": true, "fragments": 6},
	{"name": "Schneeball", "ammo": 3, "cooldown": 1.0, "crater": 0.0, "damage": 0, "blast": 0.0, "projectile": true, "fill": 8.0},
	{"name": "Medipack", "ammo": 1, "cooldown": 1.0, "heal": 300, "projectile": false},
	{"name": "Schild", "ammo": 1, "cooldown": 1.0, "shield": 400, "projectile": false},
	{"name": "Splitter", "ammo": 0, "cooldown": 0.0, "crater": 6.0, "damage": 90, "blast": 9.0, "projectile": true},
]
## Weapons a player can select (Splitter only comes out of Mega).
const SELECTABLE := 7
const MAX_SHIELD := 400
const EVENT_LOG := 16
const Rigid = preload("res://rigid_cannon.gd")
## Recoil impulse per unit of shot speed; 55 cells/s rocks the cannon back.
const RECOIL := 0.03
## A cannon on its side or roof cannot fire and rights itself after this time.
const RIGHTING_TIME := 3.0
const MAX_HP := 1000
const SHOT_DAMAGE := 200
const BLAST_RADIUS := 14.0
const HULL_RADIUS := 4.0
var cells := PackedByteArray()
var cannons: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var tick := 0
var impacts := 0
var moved := 0
## Presentation events (fire, impact, snow, heal, shield) with increasing ids.
## The last EVENT_LOG travel in the snapshot as "log", so clients replay exactly.
var events: Array[Dictionary] = []
var next_event_id := 1
var round_over := false
var winner := -1

func _init() -> void:
	reset()

func reset() -> void:
	cells.resize(W * H)
	cells.fill(0)
	for x in W:
		var surface := int(81.0 + 10.0 * sin(x * 0.035) + 5.0 * sin(x * 0.081))
		for y in range(surface, H):
			cells[y * W + x] = 2 if y >= H - 4 else 1
	cannons = []
	for x in [40.0, 200.0]:
		cannons.append({"x": x, "y": float(surface_at(int(x))) - 3.0, "vx": 0.0, "vy": 0.0,
			"angle": 45.0, "power": 55.0, "cooldown": 0.0, "tilt": 0.0, "spin": 0.0,
			"tipped_time": 0.0, "hp": MAX_HP, "max_hp": MAX_HP, "hit_flash": 0.0,
			"weapon": STONE, "ammo": start_ammo(), "shield": 0})
	shots.clear()
	events.clear()
	tick = 0
	impacts = 0
	moved = 0
	round_over = false
	winner = -1

func solid(x: int, y: int) -> bool:
	return x >= 0 and x < W and y >= 0 and y < H and cells[y * W + x] != 0

func surface_at(x: int) -> int:
	for y in H:
		if solid(x, y):
			return y
	return H

static func start_ammo() -> Array:
	var ammo := []
	for i in SELECTABLE: ammo.append(WEAPONS[i].ammo)
	return ammo

func emit(event: Dictionary) -> void:
	event.id = next_event_id
	event.tick = tick
	next_event_id += 1
	events.append(event)
	if events.size() > 4 * EVENT_LOG: events = events.slice(-EVENT_LOG)

func input_player(player: int, angle: float, power: float, fire: bool, weapon: int = -1) -> void:
	if player < 0 or player >= 2 or not is_finite(angle) or not is_finite(power):
		return
	var c: Dictionary = cannons[player]
	if round_over or c.hp <= 0: return
	c.angle = clampf(angle, 5.0, 85.0)
	c.power = clampf(power, 15.0, 90.0)
	if weapon >= 0 and weapon < SELECTABLE: c.weapon = weapon
	if fire and c.cooldown <= 0.0 and not tipped(player) and int(c.ammo[c.weapon]) != 0:
		use_weapon(player)

func use_weapon(player: int) -> void:
	var c: Dictionary = cannons[player]
	var kind: int = c.weapon
	var weapon: Dictionary = WEAPONS[kind]
	if weapon.projectile and shots.size() >= 32: return
	if c.ammo[kind] > 0: c.ammo[kind] -= 1
	c.cooldown = weapon.cooldown
	var pos := Vector2(c.x, c.y)
	if weapon.has("heal"):
		c.hp = mini(MAX_HP, int(c.hp) + int(weapon.heal))
		emit({"type": "heal", "player": player, "x": pos.x, "y": pos.y, "kind": kind})
		return
	if weapon.has("shield"):
		c.shield = mini(MAX_SHIELD, int(c.shield) + int(weapon.shield))
		emit({"type": "shield", "player": player, "x": pos.x, "y": pos.y, "kind": kind})
		return
	var direction := barrel(player)
	pos = muzzle(player)
	shots.append({"x": pos.x, "y": pos.y, "vx": direction.x * c.power,
		"vy": direction.y * c.power, "age": 0.0, "kind": kind})
	var body := body_of(c)
	body.apply_impulse(pos, -direction * c.power * RECOIL)
	store(body, c)
	emit({"type": "fire", "player": player, "x": pos.x, "y": pos.y, "kind": kind})

## Barrel direction relative to the chassis (5..85 degrees, pointing inwards).
static func aim(player: int, angle: float) -> Vector2:
	return Vector2(cos(deg_to_rad(angle)) * (1.0 if player == 0 else -1.0), -sin(deg_to_rad(angle)))

## World direction of the barrel: the aim turns with the tilted chassis.
func barrel(player: int, angle: float = NAN) -> Vector2:
	var c: Dictionary = cannons[player]
	return aim(player, c.angle if is_nan(angle) else angle).rotated(c.tilt)

## Barrel pivot two cells above the body centre, muzzle seven cells further.
func muzzle(player: int, angle: float = NAN) -> Vector2:
	var c: Dictionary = cannons[player]
	return Vector2(c.x, c.y) + Vector2(0, -2).rotated(c.tilt) + barrel(player, angle) * 7.0

func tipped(player: int) -> bool:
	return absf(wrapf(float(cannons[player].tilt), -PI, PI)) > PI / 2.0

## The dictionary is the wire format; the solver works on a RigidCannon copy.
static func body_of(c: Dictionary) -> RigidCannon:
	var body := Rigid.new(Vector2(c.x, c.y))
	body.vel = Vector2(c.vx, c.vy)
	body.angle = c.tilt
	body.spin = c.spin
	return body

static func store(body: RigidCannon, c: Dictionary) -> void:
	c.x = clampf(body.pos.x, 4.0, W - 4.0)
	c.y = minf(body.pos.y, H - 7.0)
	c.vx = body.vel.x if c.x == body.pos.x else 0.0
	c.vy = body.vel.y
	c.tilt = wrapf(body.angle, -PI, PI)
	c.spin = body.spin

## Same integration as step() without changing the world. Returns one point per
## tick; when the flight ends in the ground, the last point is the hit position.
func march(pos: Vector2, vel: Vector2, max_ticks: int, kind: int = STONE) -> Dictionary:
	var points := PackedVector2Array([pos])
	for t in max_ticks:
		vel = accelerate(vel, t * DT, kind)
		var count := maxi(1, int(ceil(vel.length() * DT * 2.0)))
		for substep in count:
			pos += vel * DT / count
			if cannon_at(pos) != -1 or solid(int(floor(pos.x)), int(floor(pos.y))):
				points.append(pos)
				return {"points": points, "hit": true}
		points.append(pos)
		if pos.x < 0.0 or pos.x >= W or pos.y >= H:
			break
	return {"points": points, "hit": false}

func trajectory(player: int, angle: float, power: float, max_ticks: int = 90, kind: int = STONE) -> Dictionary:
	var clamped := clampf(angle, 5.0, 85.0)
	return march(muzzle(player, clamped), barrel(player, clamped) * clampf(power, 15.0, 90.0), max_ticks, kind)

## Gravity plus rocket thrust along the flight direction while the motor burns.
static func accelerate(vel: Vector2, age: float, kind: int) -> Vector2:
	vel.y += GRAVITY * DT
	var weapon: Dictionary = WEAPONS[kind]
	if weapon.has("thrust") and age < weapon.burn and vel.length_squared() > 0.01:
		vel += vel.normalized() * weapon.thrust * DT
	return vel

func cannon_at(pos: Vector2, radius: float = HULL_RADIUS) -> int:
	for i in cannons.size():
		var c: Dictionary = cannons[i]
		if c.hp > 0 and pos.distance_squared_to(Vector2(c.x, c.y)) <= radius * radius:
			return i
	return -1

func explode(cx: float, cy: float, direct_player: int = -1, kind: int = STONE) -> void:
	# Debug excavation calls crater() directly and deliberately causes no damage.
	if round_over: return
	var weapon: Dictionary = WEAPONS[kind]
	if weapon.has("fill"):
		emit({"type": "snow", "x": cx, "y": cy, "kind": kind})
		fill(cx, cy, weapon.fill)
		return
	emit({"type": "impact", "x": cx, "y": cy, "kind": kind})
	crater(cx, cy, weapon.crater)
	for i in cannons.size():
		var c: Dictionary = cannons[i]
		if c.hp <= 0: continue
		var distance := maxf(0.0, Vector2(cx, cy).distance_to(Vector2(c.x, c.y)) - HULL_RADIUS)
		var damage: int = weapon.damage if i == direct_player else int(round(weapon.damage * maxf(0.0, 1.0 - distance / weapon.blast)))
		# The shield absorbs damage first.
		var absorbed := mini(damage, int(c.shield))
		c.shield = int(c.shield) - absorbed
		damage -= absorbed
		if damage > 0:
			c.hp = maxi(0, int(c.hp) - damage)
			c.hit_flash = 0.25

## Snowball: packs sand into the air cells of a disc (never inside a cannon).
func fill(cx: float, cy: float, radius: float) -> void:
	for y in range(maxi(0, int(cy - radius)), mini(H - 4, int(cy + radius) + 1)):
		for x in range(maxi(0, int(cx - radius)), mini(W, int(cx + radius) + 1)):
			if cells[y * W + x] == 0 and Vector2(x - cx, y - cy).length_squared() < radius * radius and cannon_at(Vector2(x + 0.5, y + 0.5), 5.0) == -1:
				cells[y * W + x] = 1
	impacts += 1

## Grenade: back to the last free point, reflect on the local surface normal
## and lose most of the energy, so it soon rests until the fuse fires.
func bounce(shot: Dictionary, previous: Vector2) -> void:
	shot.x = previous.x
	shot.y = previous.y
	var n := RigidCannon.normal_at(self, previous)
	var vel := Vector2(shot.vx, shot.vy)
	vel = (vel - 2.0 * vel.dot(n) * n) * 0.45
	if vel.length() < 3.0: vel = Vector2.ZERO
	shot.vx = vel.x
	shot.vy = vel.y

func resolve_round() -> void:
	if round_over: return
	var alive: Array[int] = []
	for i in cannons.size():
		if cannons[i].hp > 0: alive.append(i)
	if alive.size() < 2:
		round_over = true
		winner = alive[0] if alive.size() == 1 else -1
		shots.clear()

func crater(cx: float, cy: float, radius: float = 10.0) -> void:
	for y in range(maxi(0, int(cy - radius)), mini(H, int(cy + radius) + 1)):
		for x in range(maxi(0, int(cx - radius)), mini(W, int(cx + radius) + 1)):
			if cells[y * W + x] == 1 and Vector2(x - cx, y - cy).length_squared() < radius * radius:
				cells[y * W + x] = 0
	impacts += 1

func step() -> void:
	tick += 1
	moved = 0
	# Bottom to top: a grain moves at most one cell per step. Alternating scan
	# directions avoid a permanent left/right preference. Rock never moves.
	for y in range(H - 2, -1, -1):
		for scan in W:
			var x: int = scan if tick % 2 == 0 else W - 1 - scan
			var index: int = y * W + x
			if cells[index] != 1:
				continue
			var target: int = index + W
			if cells[target] != 0:
				var side := 1 if (tick + x + y) % 2 == 0 else -1
				if x + side >= 0 and x + side < W and cells[target + side] == 0:
					target += side
				elif x - side >= 0 and x - side < W and cells[target - side] == 0:
					target -= side
				else:
					continue
			cells[index] = 0
			cells[target] = 1
			moved += 1
	for c in cannons:
		c.hit_flash = maxf(0.0, c.hit_flash - DT)
		c.cooldown = maxf(0.0, c.cooldown - DT)
		var body := body_of(c)
		body.step(self, DT)
		store(body, c)
		# Lying on its side or roof: after a while the crew rights the cannon.
		c.tipped_time = c.tipped_time + DT if absf(c.tilt) > PI / 2.0 else 0.0
		if c.tipped_time >= RIGHTING_TIME and c.hp > 0:
			c.tilt = 0.0
			c.spin = 0.0
			c.vx = 0.0
			c.y = minf(c.y, float(surface_at(int(c.x))) - 3.0)
			c.tipped_time = 0.0
	if round_over: return
	var spawned: Array[Dictionary] = []
	for i in range(shots.size() - 1, -1, -1):
		var shot: Dictionary = shots[i]
		if not shot.has("kind"): shot.kind = STONE
		var kind: int = shot.kind
		var weapon: Dictionary = WEAPONS[kind]
		var vel := accelerate(Vector2(shot.vx, shot.vy), shot.age, kind)
		var rising: bool = shot.vy < 0.0
		shot.vx = vel.x
		shot.vy = vel.y
		shot.age += DT
		# Mega splits at the top of its arc into a fan of splinters.
		if weapon.has("fragments") and rising and shot.vy >= 0.0:
			for f in weapon.fragments:
				var spread: float = (f - (weapon.fragments - 1) / 2.0) * 9.0
				spawned.append({"x": shot.x, "y": shot.y, "vx": shot.vx + spread, "vy": shot.vy - 4.0 + absf(spread) * 0.3, "age": 0.0, "kind": SPLINTER})
			emit({"type": "split", "x": shot.x, "y": shot.y, "kind": kind})
			shots.remove_at(i)
			continue
		var distance := Vector2(shot.vx, shot.vy).length() * DT
		var count := maxi(1, int(ceil(distance * 2.0)))
		var hit := false
		for substep in count:
			var previous := Vector2(shot.x, shot.y)
			shot.x += shot.vx * DT / count
			shot.y += shot.vy * DT / count
			var target := cannon_at(Vector2(shot.x, shot.y))
			if target != -1:
				explode(shot.x, shot.y, target, kind)
				hit = true
				break
			if solid(int(floor(shot.x)), int(floor(shot.y))):
				if weapon.has("fuse"):
					bounce(shot, previous)
					break
				explode(shot.x, shot.y, -1, kind)
				hit = true
				break
		if not hit and weapon.has("fuse") and shot.age >= weapon.fuse:
			explode(shot.x, shot.y, -1, kind)
			hit = true
		if hit or shot.age > 12.0 or shot.x < 0.0 or shot.x >= W or shot.y >= H:
			shots.remove_at(i)
	for shot in spawned:
		if shots.size() < 32: shots.append(shot)
	# Resolve after all shots of this tick, so simultaneous destruction is a draw.
	resolve_round()

func snapshot() -> Dictionary:
	return {"type": "state", "version": PROTOCOL_VERSION, "tick": tick, "impacts": impacts,
		"round_over": round_over, "winner": winner, "moved": moved, "log": events.slice(-EVENT_LOG),
		"cells": Marshalls.raw_to_base64(cells), "cannons": cannons, "shots": shots}

func apply_snapshot(state: Dictionary) -> bool:
	if state.get("version") != PROTOCOL_VERSION: return false
	var next_cannons = state.get("cannons")
	var next_shots = state.get("shots")
	if not next_cannons is Array or next_cannons.size() != 2: return false
	if not next_shots is Array or next_shots.size() > 32: return false
	if not state.get("round_over") is bool or not numeric(state.get("winner")): return false
	if state.winner != int(state.winner) or int(state.winner) < -1 or int(state.winner) > 1: return false
	for c in next_cannons:
		if not c is Dictionary: return false
		for key in ["x", "y", "vx", "vy", "angle", "power", "cooldown", "tilt", "spin", "tipped_time", "hp", "max_hp", "hit_flash", "weapon", "shield"]:
			if not numeric(c.get(key)): return false
		if c.hp < 0 or c.hp > MAX_HP or c.max_hp != MAX_HP: return false
		if int(c.weapon) < 0 or int(c.weapon) >= SELECTABLE or c.shield < 0 or c.shield > MAX_SHIELD: return false
		var ammo = c.get("ammo")
		if not ammo is Array or ammo.size() != SELECTABLE: return false
		for count in ammo:
			if not numeric(count) or count < -1: return false
	for shot in next_shots:
		if not shot is Dictionary: return false
		for key in ["x", "y", "vx", "vy", "age", "kind"]:
			if not numeric(shot.get(key)): return false
		if int(shot.kind) < 0 or int(shot.kind) >= WEAPONS.size(): return false
	var event_log = state.get("log")
	if not event_log is Array or event_log.size() > EVENT_LOG: return false
	for event in event_log:
		if not event is Dictionary or not numeric(event.get("id")) or not numeric(event.get("tick")) or not numeric(event.get("x")) or not numeric(event.get("y")): return false
		if not event.get("type") in ["fire", "impact", "snow", "heal", "shield", "split"]: return false
	for key in ["tick", "impacts", "moved"]:
		if not numeric(state.get(key)) or state[key] < 0: return false
	var decoded := Marshalls.base64_to_raw(str(state.get("cells", "")))
	if decoded.size() != W * H: return false
	cells = decoded
	cannons.assign(next_cannons.duplicate(true))
	shots.assign(next_shots.duplicate(true))
	# JSON numbers arrive as floats; indices must be ints again.
	for c in cannons:
		c.weapon = int(c.weapon)
		c.shield = int(c.shield)
		c.ammo = c.ammo.map(func(n): return int(n))
	for shot in shots: shot.kind = int(shot.kind)
	events.assign(event_log.duplicate(true))
	for event in events:
		event.id = int(event.id)
		event.tick = int(event.tick)
	tick = int(state.tick)
	impacts = int(state.impacts)
	moved = int(state.moved)
	round_over = state.round_over
	winner = int(state.winner)
	return true

func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
