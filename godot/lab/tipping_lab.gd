extends Node2D
## P1 lab: rigid-body cannons on the regular sand world, offline only.
## The v1 support model runs alongside as a white outline for comparison.
## godot --path godot res://lab/tipping_lab.tscn
const Sim = preload("res://simulation.gd")
const Rigid = preload("res://rigid_cannon.gd")
## Recoil per unit of shot speed; 55 cells/s gives about 1.6 (rocks back).
const RECOIL := 0.03
var sim = Sim.new()
var bodies: Array = []
var player := 0
var angle := 45.0
var power := 55.0
var cooldown := [0.0, 0.0]
var accumulator := 0.0
var auto_smoke := false
var capture_path := ""
var capture_tick := 150
var ticks := 0
var image := Image.create(Sim.W, Sim.H, false, Image.FORMAT_RGBA8)
var texture: ImageTexture
var info: Label
var origin := Vector2(70, 120)
var cell_scale := 4.0

func _ready() -> void:
	texture = ImageTexture.create_from_image(image)
	var title := Label.new()
	title.text = "P1 LABOR  /  STARRKÖRPER-KANONE"
	title.position = Vector2(36, 20)
	title.add_theme_font_size_override("font_size", 27)
	title.modulate = Color("f4d59a")
	add_child(title)
	info = Label.new()
	info.position = Vector2(38, 64)
	info.modulate = Color("8ca9b9")
	add_child(info)
	var help := Label.new()
	help.text = "↑ ↓ Winkel   ← → Stärke   LEERTASTE Feuer   TAB Kanone   B Bremse   G Boden lösen   KLICK Krater   K Stoß   R Neustart   |   weiß: Modell v1"
	help.position = Vector2(38, 700)
	help.add_theme_font_size_override("font_size", 14)
	help.modulate = Color("8ca9b9")
	add_child(help)
	for arg in OS.get_cmdline_user_args():
		if arg == "--smoke": auto_smoke = true
		elif arg.begins_with("--capture="): capture_path = arg.trim_prefix("--capture=")
		elif arg.begins_with("--capture-at="): capture_tick = int(arg.trim_prefix("--capture-at="))
	reset()

func reset() -> void:
	sim.reset()
	bodies.clear()
	for c in sim.cannons:
		bodies.append(Rigid.new(Vector2(c.x, c.y - 0.5)))
	ticks = 0

## Barrel direction in body space, pointing inwards like spec v1.
static func aim(i: int, degrees: float) -> Vector2:
	return Vector2(cos(deg_to_rad(degrees)) * (1.0 if i == 0 else -1.0), -sin(deg_to_rad(degrees)))

func fire(i: int) -> void:
	if cooldown[i] > 0.0 or sim.shots.size() >= 32: return
	var body = bodies[i]
	# Aim is relative to the chassis, so a tilted cannon also tilts its shot.
	var dir: Vector2 = aim(i, angle if i == player else 45.0).rotated(body.angle)
	var shot_power: float = power if i == player else 55.0
	var muzzle: Vector2 = body.to_world(Vector2(0, -2)) + dir * 7.0
	sim.shots.append({"x": muzzle.x, "y": muzzle.y, "vx": dir.x * shot_power, "vy": dir.y * shot_power, "age": 0.0})
	body.apply_impulse(muzzle, -dir * shot_power * RECOIL)
	cooldown[i] = 0.7

func undermine(i: int) -> void:
	sim.crater(bodies[i].to_world(Vector2(5, 6)).x, bodies[i].pos.y + 7, 8)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell: Vector2 = (event.position - origin) / cell_scale
		sim.crater(cell.x, cell.y, 8)
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_SPACE: fire(player)
		KEY_TAB: player = 1 - player
		KEY_B: bodies[player].brake = not bodies[player].brake
		KEY_G: undermine(player)
		KEY_K: bodies[player].apply_impulse(bodies[player].to_world(Vector2(0, -6)), Vector2(-12.0 if player == 0 else 12.0, -2.0))
		KEY_R: reset()

func _process(delta: float) -> void:
	angle = clampf(angle + (float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN))) * delta * 40.0, 5, 85)
	power = clampf(power + (float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))) * delta * 30.0, 15, 90)
	accumulator += minf(delta, 0.15)
	while accumulator >= Sim.DT:
		accumulator -= Sim.DT
		ticks += 1
		sim.step()
		for i in 2:
			bodies[i].step(sim, Sim.DT)
			cooldown[i] = maxf(0.0, cooldown[i] - Sim.DT)
		if auto_smoke: smoke()
	var b0 = bodies[0]
	var b1 = bodies[1]
	info.text = "KANONE %d   WINKEL %02d°   STÄRKE %02d   |   L: Neigung %+.2f rad %s %s   R: Neigung %+.2f rad %s %s" % [player + 1, angle, power,
		b0.angle, "GEKIPPT" if b0.tipped() else "", "" if b0.brake else "ROLLT", b1.angle, "GEKIPPT" if b1.tipped() else "", "" if b1.brake else "ROLLT"]
	paint_terrain()
	queue_redraw()

## Scripted run for headless checks and screenshots: undermine the left cannon,
## fire both, shove the right one over.
func smoke() -> void:
	if ticks == 30: undermine(0)
	if ticks == 60:
		fire(0)
		fire(1)
	if ticks == 90: bodies[1].apply_impulse(bodies[1].to_world(Vector2(0, -6)), Vector2(12, -2))
	if ticks == capture_tick and not capture_path.is_empty(): capture.call_deferred()
	if ticks == 240:
		print("LAB_FINISHED left_angle=%.2f left_tipped=%s right_angle=%.2f right_tipped=%s impacts=%d" % [
			bodies[0].angle, bodies[0].tipped(), bodies[1].angle, bodies[1].tipped(), sim.impacts])
		get_tree().quit(0)

func paint_terrain() -> void:
	for y in Sim.H:
		for x in Sim.W:
			var cell: int = sim.cells[y * Sim.W + x]
			var color := Color(0.05 + y * 0.0003, 0.10 + y * 0.0003, 0.15 + y * 0.0003)
			if cell == 1:
				var grain := float((x * 17 + y * 31) % 11) / 110.0
				color = Color(0.72 + grain, 0.50 + grain, 0.27 + grain)
				if y > 0 and sim.cells[(y - 1) * Sim.W + x] == 0: color = Color("f4d59a")
			elif cell == 2: color = Color("344854")
			image.set_pixel(x, y, color)
	texture.update(image)

func to_screen(cell: Vector2) -> Vector2:
	return origin + cell * cell_scale

func _draw() -> void:
	draw_rect(Rect2(origin - Vector2(2, 2), Vector2(964, 516)), Color("43616c"))
	draw_texture_rect(texture, Rect2(origin, Vector2(960, 512)), false)
	for i in 2:
		# v1 reference: wheel probes and visual tilt only.
		var c: Dictionary = sim.cannons[i]
		var p := to_screen(Vector2(c.x, c.y))
		draw_line(p - Vector2(12, 0).rotated(c.tilt), p + Vector2(12, 0).rotated(c.tilt), Color(1, 1, 1, 0.35), 2, true)
		for wheel in [-1, 1]:
			draw_arc(p + Vector2(wheel * 12, 6).rotated(c.tilt), 6, 0, TAU, 16, Color(1, 1, 1, 0.35), 1.5, true)
		draw_rigid(i)
	for shot in sim.shots:
		draw_circle(to_screen(Vector2(shot.x, shot.y)), 3, Color("fff4d6"))

func draw_rigid(i: int) -> void:
	var body = bodies[i]
	var color := Color("78dac4") if i == 0 else Color("ef9c86")
	var corners := PackedVector2Array()
	for local in [Vector2(-4, -2), Vector2(4, -2), Vector2(4, 1), Vector2(-4, 1)]:
		corners.append(to_screen(body.to_world(local)))
	draw_colored_polygon(corners, color.darkened(0.25))
	corners.append(corners[0])
	draw_polyline(corners, color, 2, true)
	var dir: Vector2 = aim(i, angle if i == player else 45.0).rotated(body.angle)
	var pivot := to_screen(body.to_world(Vector2(0, -2)))
	draw_line(pivot, pivot + dir * 7.0 * cell_scale, color, 6, true)
	for wheel in [-3.0, 3.0]:
		var w := to_screen(body.to_world(Vector2(wheel, 1.5)))
		draw_circle(w, 1.5 * cell_scale, Color("15212b"))
		draw_arc(w, 1.5 * cell_scale - 1, 0, TAU, 20, color if body.brake else Color("f4d59a"), 2, true)
	draw_circle(to_screen(body.pos), 2, Color.WHITE)
	if player == i: draw_circle(to_screen(body.to_world(Vector2(0, -9))), 3, color)

func capture() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_path)
