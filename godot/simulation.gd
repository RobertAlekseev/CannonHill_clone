class_name SandSimulation
extends RefCounted
## Fixed 30 Hz, screen coordinates: x right / y down, one cell = 0.25 m.
const W := 240
const H := 128
const DT := 1.0 / 30.0
const GRAVITY := 39.24
const PROTOCOL_VERSION := 2
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
		cannons.append({"x": x, "y": float(surface_at(int(x))) - 3.0, "vy": 0.0,
			"angle": 45.0, "power": 55.0, "cooldown": 0.0, "tilt": 0.0,
			"hp": MAX_HP, "max_hp": MAX_HP, "hit_flash": 0.0})
	shots.clear()
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

func input_player(player: int, angle: float, power: float, fire: bool) -> void:
	if player < 0 or player >= 2 or not is_finite(angle) or not is_finite(power):
		return
	var c: Dictionary = cannons[player]
	if round_over or c.hp <= 0: return
	c.angle = clampf(angle, 5.0, 85.0)
	c.power = clampf(power, 15.0, 90.0)
	if fire and c.cooldown <= 0.0 and shots.size() < 32:
		var direction := Vector2(cos(deg_to_rad(c.angle)) * (1.0 if player == 0 else -1.0), -sin(deg_to_rad(c.angle)))
		var pos := Vector2(c.x, c.y - 1.0) + direction * 7.0
		shots.append({"x": pos.x, "y": pos.y, "vx": direction.x * c.power,
			"vy": direction.y * c.power, "age": 0.0})
		c.cooldown = 0.7

func cannon_at(pos: Vector2) -> int:
	for i in cannons.size():
		var c: Dictionary = cannons[i]
		if c.hp > 0 and pos.distance_squared_to(Vector2(c.x, c.y)) <= HULL_RADIUS * HULL_RADIUS:
			return i
	return -1

func explode(cx: float, cy: float, direct_player: int = -1) -> void:
	# Debug excavation calls crater() directly and deliberately causes no damage.
	if round_over: return
	crater(cx, cy)
	for i in cannons.size():
		var c: Dictionary = cannons[i]
		if c.hp <= 0: continue
		var distance := maxf(0.0, Vector2(cx, cy).distance_to(Vector2(c.x, c.y)) - HULL_RADIUS)
		var damage := SHOT_DAMAGE if i == direct_player else int(round(SHOT_DAMAGE * maxf(0.0, 1.0 - distance / BLAST_RADIUS)))
		if damage > 0:
			c.hp = maxi(0, int(c.hp) - damage)
			c.hit_flash = 0.25

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
		c.vy += GRAVITY * DT
		var target_y: float = minf(H - 7.0, c.y + c.vy * DT)
		# Two wheel probes: a supported wheel carries the simplified chassis.
		var left := H
		var right := H
		for y in range(maxi(0, int(c.y + 2)), H):
			if left == H and solid(int(c.x) - 3, y): left = y
			if right == H and solid(int(c.x) + 3, y): right = y
		var floor_y := float(mini(left, right)) - 3.0
		if target_y >= floor_y:
			target_y = floor_y
			c.vy = 0.0
		c.y = target_y
		c.tilt = clampf(atan2(float(right - left), 6.0), -0.5, 0.5)
	if round_over: return
	for i in range(shots.size() - 1, -1, -1):
		var shot: Dictionary = shots[i]
		shot.vy += GRAVITY * DT
		shot.age += DT
		var distance := Vector2(shot.vx, shot.vy).length() * DT
		var count := maxi(1, int(ceil(distance * 2.0)))
		var hit := false
		for substep in count:
			shot.x += shot.vx * DT / count
			shot.y += shot.vy * DT / count
			var target := cannon_at(Vector2(shot.x, shot.y))
			if target != -1:
				explode(shot.x, shot.y, target)
				hit = true
				break
			if solid(int(floor(shot.x)), int(floor(shot.y))):
				explode(shot.x, shot.y)
				hit = true
				break
		if hit or shot.age > 12.0 or shot.x < 0.0 or shot.x >= W or shot.y >= H:
			shots.remove_at(i)
	# Resolve after all shots of this tick, so simultaneous destruction is a draw.
	resolve_round()

func snapshot() -> Dictionary:
	return {"type": "state", "version": PROTOCOL_VERSION, "tick": tick, "impacts": impacts,
		"round_over": round_over, "winner": winner, "moved": moved,
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
		for key in ["x", "y", "vy", "angle", "power", "cooldown", "tilt", "hp", "max_hp", "hit_flash"]:
			if not numeric(c.get(key)): return false
		if c.hp < 0 or c.hp > MAX_HP or c.max_hp != MAX_HP: return false
	for shot in next_shots:
		if not shot is Dictionary: return false
		for key in ["x", "y", "vx", "vy", "age"]:
			if not numeric(shot.get(key)): return false
	for key in ["tick", "impacts", "moved"]:
		if not numeric(state.get(key)) or state[key] < 0: return false
	var decoded := Marshalls.base64_to_raw(str(state.get("cells", "")))
	if decoded.size() != W * H: return false
	cells = decoded
	cannons.assign(next_cannons.duplicate(true))
	shots.assign(next_shots.duplicate(true))
	tick = int(state.tick)
	impacts = int(state.impacts)
	moved = int(state.moved)
	round_over = state.round_over
	winner = int(state.winner)
	return true

func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
