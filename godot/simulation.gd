class_name SandSimulation
extends RefCounted
## Fixed 30 Hz, screen coordinates: x right / y down, one cell = 0.25 m.
const W := 240
const H := 128
const DT := 1.0 / 30.0
const GRAVITY := 39.24
var cells := PackedByteArray()
var cannons: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var tick := 0
var impacts := 0
var moved := 0

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
			"angle": 45.0, "power": 55.0, "cooldown": 0.0, "tilt": 0.0})
	shots.clear()
	tick = 0
	impacts = 0

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
	c.angle = clampf(angle, 5.0, 85.0)
	c.power = clampf(power, 15.0, 90.0)
	if fire and c.cooldown <= 0.0 and shots.size() < 32:
		var direction := Vector2(cos(deg_to_rad(c.angle)) * (1.0 if player == 0 else -1.0), -sin(deg_to_rad(c.angle)))
		var pos := Vector2(c.x, c.y - 1.0) + direction * 7.0
		shots.append({"x": pos.x, "y": pos.y, "vx": direction.x * c.power,
			"vy": direction.y * c.power, "age": 0.0})
		c.cooldown = 0.7

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
			if solid(int(floor(shot.x)), int(floor(shot.y))):
				crater(shot.x, shot.y)
				hit = true
				break
		if hit or shot.age > 12.0 or shot.x < 0.0 or shot.x >= W or shot.y >= H:
			shots.remove_at(i)

func snapshot() -> Dictionary:
	return {"type": "state", "version": 1, "tick": tick, "impacts": impacts,
		"cells": Marshalls.raw_to_base64(cells), "cannons": cannons, "shots": shots}

func apply_snapshot(state: Dictionary) -> bool:
	if state.get("version") != 1: return false
	var decoded := Marshalls.base64_to_raw(str(state.get("cells", "")))
	if decoded.size() != W * H or state.get("cannons", []).size() != 2: return false
	cells = decoded
	cannons.assign(state.cannons)
	shots.assign(state.shots)
	tick = int(state.tick)
	impacts = int(state.impacts)
	return true
