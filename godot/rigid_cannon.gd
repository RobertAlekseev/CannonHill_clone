class_name RigidCannon
extends RefCounted
## P1 proposal: the cannon as one free 2D rigid body on the cell grid.
## Own impulse solver, deterministic and engine-neutral, so Unity and Unreal can
## port it line by line and the LAN host stays the only authority (see
## shared/physics-proposal-p1.md). Units: cells, seconds, y down, angle in rad
## (positive = clockwise on screen).
const GRAVITY := 39.24
const SUBSTEPS := 8
const MASS := 1.0
## Chassis 8 x 4 cells as a solid box.
const INERTIA := MASS * (8.0 * 8.0 + 4.0 * 4.0) / 12.0
const RESTITUTION := 0.05
const WHEEL_FRICTION_BRAKED := 0.9
const WHEEL_FRICTION_ROLLING := 0.03
const HULL_FRICTION := 0.6
const ANGULAR_DAMPING := 0.6
const ITERATIONS := 4
const SKIN := 0.1
const SLOP := 0.02
const CORRECTION := 0.3
## Contact points in body space: wheel bottoms (same support as spec v1) and
## chassis corners, which only touch the ground once the cannon tilts far.
const WHEELS: Array[Vector2] = [Vector2(-3, 3), Vector2(3, 3)]
const HULL: Array[Vector2] = [Vector2(-4, 1), Vector2(4, 1), Vector2(-4, -2), Vector2(4, -2), Vector2(0, -2)]
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var angle := 0.0
var spin := 0.0
var brake := true
var wheel_contacts := 0
var hull_contacts := 0

func _init(start: Vector2 = Vector2.ZERO) -> void:
	pos = start

func to_world(local: Vector2) -> Vector2:
	return pos + local.rotated(angle)

func point_velocity(point: Vector2) -> Vector2:
	var r := point - pos
	return vel + Vector2(-spin * r.y, spin * r.x)

func apply_impulse(point: Vector2, impulse: Vector2) -> void:
	vel += impulse / MASS
	spin += (point - pos).cross(impulse) / INERTIA

## Within 60 degrees of upright.
func upright() -> bool:
	return absf(wrapf(angle, -PI, PI)) < PI / 3.0

## On its side or roof.
func tipped() -> bool:
	return absf(wrapf(angle, -PI, PI)) > PI / 2.0

func step(world, dt: float) -> void:
	var h := dt / SUBSTEPS
	for substep in SUBSTEPS:
		vel.y += GRAVITY * h
		# Gather contacts first, then solve velocities iteratively, then move:
		# a resting body cancels gravity before it sinks, so it does not hop.
		var contacts: Array[Dictionary] = []
		wheel_contacts = 0
		hull_contacts = 0
		for local in WHEELS:
			if add_contact(world, local, WHEEL_FRICTION_BRAKED if brake else WHEEL_FRICTION_ROLLING, contacts):
				wheel_contacts += 1
		for local in HULL:
			if add_contact(world, local, HULL_FRICTION, contacts):
				hull_contacts += 1
		for iteration in ITERATIONS:
			for contact in contacts:
				solve_velocity(contact)
		pos += vel * h
		angle += spin * h
		spin *= 1.0 - ANGULAR_DAMPING * h
		# Soft push-out of the remaining penetration (Baumgarte style).
		for contact in contacts:
			var depth := penetration(world, to_world(contact.local), contact.n)
			pos += contact.n * maxf(depth - SLOP, 0.0) * CORRECTION / contacts.size()

static func solid_at(world, point: Vector2) -> bool:
	return world.solid(int(floor(point.x)), int(floor(point.y)))

## Surface normal from the solid cells around a point; up when undecided.
static func normal_at(world, point: Vector2) -> Vector2:
	var n := Vector2.ZERO
	var cx := int(floor(point.x))
	var cy := int(floor(point.y))
	for oy in range(-2, 3):
		for ox in range(-2, 3):
			if world.solid(cx + ox, cy + oy):
				n -= Vector2(cx + ox + 0.5, cy + oy + 0.5) - point
	return n.normalized() if n.length_squared() > 0.01 else Vector2.UP

static func penetration(world, point: Vector2, n: Vector2) -> float:
	var depth := 0.0
	while depth < 3.0 and solid_at(world, point + n * depth):
		depth += 0.05
	return depth

## A point touches the ground when it is inside or within SKIN above solid cells.
func add_contact(world, local: Vector2, friction: float, contacts: Array[Dictionary]) -> bool:
	var p := to_world(local)
	if not solid_at(world, p) and not solid_at(world, p + Vector2(0, SKIN)):
		return false
	contacts.append({"local": local, "n": normal_at(world, p), "friction": friction})
	return true

func solve_velocity(contact: Dictionary) -> void:
	var p := to_world(contact.local)
	var n: Vector2 = contact.n
	var r := p - pos
	var vn := point_velocity(p).dot(n)
	if vn >= 0.0:
		return
	var rn := r.cross(n)
	var j := -(1.0 + RESTITUTION) * vn / (1.0 / MASS + rn * rn / INERTIA)
	apply_impulse(p, n * j)
	var t := Vector2(-n.y, n.x)
	var rt := r.cross(t)
	var limit: float = contact.friction * j
	apply_impulse(p, t * clampf(-point_velocity(p).dot(t) / (1.0 / MASS + rt * rt / INERTIA), -limit, limit))

## Same fields for every engine; a later protocol version would send these
## per cannon instead of the v1 "tilt"/"vy" pair.
func snapshot() -> Dictionary:
	return {"x": pos.x, "y": pos.y, "vx": vel.x, "vy": vel.y, "angle": angle, "spin": spin, "brake": brake}

func apply_snapshot(state: Dictionary) -> void:
	pos = Vector2(float(state.x), float(state.y))
	vel = Vector2(float(state.vx), float(state.vy))
	angle = float(state.angle)
	spin = float(state.spin)
	brake = state.get("brake", true) == true
