extends Node2D
const Sim = preload("res://simulation.gd")
const Assets = preload("res://shared_assets.gd")
const PORT := 28741
var sim = Sim.new()
var server := TCPServer.new()
var peer: StreamPeerTCP
var incoming := ""
var outgoing := PackedByteArray()
var mode := "offline"
var player := 0
var status := "OFFLINE / Tab wechselt die Kanone"
var accumulator := 0.0
var send_clock := 0.0
var angle := 45.0
var power := 55.0
var fire_pending := false
var auto_smoke := false
var capture_path := ""
var capture_tick := 60
var smoke_ticks := 0
var image := Image.create(Sim.W, Sim.H, false, Image.FORMAT_RGBA8)
var texture: ImageTexture
var ip_field: LineEdit
var status_label: Label
var values_label: Label
var round_label: Label
var origin := Vector2(70, 240)
var cell_scale := 4.0
var assets = Assets.new()
var sounds := {}
var pixels := PackedByteArray()
var depth := PackedInt32Array()
var debris: Array[Dictionary] = []
var flashes: Array[Dictionary] = []
var shake := 0.0
var since_state := 0.0
var effect_counts := {"fire": 0, "impact": 0, "snow": 0, "heal": 0, "shield": 0, "split": 0}
## Highest event id already turned into effects (host and client alike).
var last_event := 0
var weapon := Sim.STONE
var weapon_pending := false
var smoke_weapon := Sim.STONE

func _ready() -> void:
	texture = ImageTexture.create_from_image(image)
	pixels.resize(Sim.W * Sim.H * 4)
	depth.resize(Sim.W)
	make_ui()
	for id in ["audio.fire", "audio.impact"]:
		var stream: AudioStream = assets.audio(id)
		if not stream: continue
		var player_node := AudioStreamPlayer.new()
		player_node.stream = stream
		player_node.max_polyphony = 4
		add_child(player_node)
		sounds[id] = player_node
	print("ASSETS root=%s loaded=%d problems=%s" % [assets.root, sounds.size(), assets.problems])
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host()
		elif arg.begins_with("--join="): join(arg.trim_prefix("--join="))
		elif arg == "--smoke": auto_smoke = true
		elif arg.begins_with("--capture="): capture_path = arg.trim_prefix("--capture=")
		elif arg.begins_with("--capture-at="): capture_tick = int(arg.trim_prefix("--capture-at="))
		elif arg.begins_with("--weapon="): smoke_weapon = clampi(int(arg.trim_prefix("--weapon=")), 0, Sim.SELECTABLE - 1)
	paint_terrain()

func make_ui() -> void:
	var title := Label.new()
	title.text = "CANNON HILL   /   SAND LABORATORY"
	title.position = Vector2(36, 20)
	title.add_theme_font_size_override("font_size", 27)
	title.modulate = Color("f4d59a")
	add_child(title)
	var subtitle := Label.new()
	subtitle.text = "GODOT  /  04     Echtzeit-Artillerie · Waffen · Lebenspunkte · Kippphysik · LAN für zwei"
	subtitle.position = Vector2(38, 58)
	subtitle.modulate = Color("8ca9b9")
	add_child(subtitle)
	button("Offline", 38, func(): disconnect_network(); sim.reset())
	button("LAN hosten", 150, host)
	ip_field = LineEdit.new()
	ip_field.position = Vector2(288, 99)
	ip_field.size = Vector2(185, 34)
	ip_field.text = "127.0.0.1"
	add_child(ip_field)
	button("Verbinden", 486, func(): join(ip_field.text.strip_edges()))
	button("Neustart", 624, func():
		if mode != "client": sim.reset())
	button("Boden lösen", 762, func():
		if mode != "client": sim.crater(sim.cannons[player].x, sim.cannons[player].y + 8, 12))
	button("FEUER", 900, func(): fire_pending = true)
	status_label = Label.new()
	status_label.position = Vector2(38, 144)
	status_label.modulate = Color("8cdfb0")
	add_child(status_label)
	values_label = Label.new()
	values_label.position = Vector2(38, 782)
	values_label.add_theme_font_size_override("font_size", 18)
	add_child(values_label)
	round_label = Label.new()
	round_label.position = Vector2(440, 183)
	round_label.size = Vector2(220, 44)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.add_theme_font_size_override("font_size", 16)
	round_label.modulate = Color("f4d59a")
	add_child(round_label)
	var help := Label.new()
	help.text = "↑ ↓ Winkel     ← → Stärke     LEERTASTE Feuer     1–7 / Q E Waffe     TAB Spieler (offline)     ESC verlässt IP-Feld"
	help.position = Vector2(38, 824)
	help.add_theme_font_size_override("font_size", 14)
	help.modulate = Color("8ca9b9")
	add_child(help)

func button(text: String, x: float, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.position = Vector2(x, 99)
	b.size = Vector2(125 if x != 38 else 100, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	add_child(b)

func disconnect_network() -> void:
	if peer: peer.disconnect_from_host()
	peer = null
	server.stop()
	incoming = ""
	outgoing.clear()
	mode = "offline"
	player = 0
	status = "OFFLINE / Tab wechselt die Kanone"

func host() -> void:
	disconnect_network()
	var error := server.listen(PORT)
	if error != OK:
		status = "Host fehlgeschlagen: " + error_string(error)
		return
	mode = "host"
	status = "HOST / TCP 28741 / warte auf Spieler 2"
	print("HOST_READY")

func join(address: String) -> void:
	disconnect_network()
	peer = StreamPeerTCP.new()
	var error := peer.connect_to_host(address, PORT)
	if error != OK:
		status = "Verbindung fehlgeschlagen: " + error_string(error)
		peer = null
		return
	mode = "client"
	player = 1
	status = "VERBINDE / " + address

func send(message: Dictionary) -> void:
	# Never queue unlimited stale snapshots behind a slow connection.
	if peer and outgoing.is_empty(): outgoing = (JSON.stringify(message) + "\n").to_utf8_buffer()

func network() -> void:
	if mode == "host" and server.is_connection_available():
		var candidate := server.take_connection()
		if peer: candidate.disconnect_from_host()
		else:
			peer = candidate
			peer.set_no_delay(true)
			status = "HOST / Spieler 2 verbunden"
			print("PEER_CONNECTED")
	if not peer: return
	peer.poll()
	var connection := peer.get_status()
	if connection == StreamPeerTCP.STATUS_ERROR or connection == StreamPeerTCP.STATUS_NONE:
		peer = null
		incoming = ""
		outgoing.clear()
		status = "VERBINDUNG GETRENNT / Offline oder erneut verbinden"
		if mode == "host": status = "HOST / Spieler getrennt / warte auf Spieler 2"
		return
	if connection != StreamPeerTCP.STATUS_CONNECTED: return
	if not outgoing.is_empty():
		var written := peer.put_partial_data(outgoing)
		if written[0] == OK: outgoing = outgoing.slice(written[1])
	var available := peer.get_available_bytes()
	if available > 0:
		var received := peer.get_data(available)
		if received[0] == OK: incoming += received[1].get_string_from_utf8()
	if incoming.length() > 262144:
		peer.disconnect_from_host()
		return
	while incoming.contains("\n"):
		var split := incoming.find("\n")
		var data = JSON.parse_string(incoming.left(split))
		incoming = incoming.substr(split + 1)
		if not data is Dictionary: continue
		if data.get("version") != Sim.PROTOCOL_VERSION:
			status = "ANDERE SPIELVERSION / Beide Spieler benötigen Godot v%d (Lebenspunkte + Kippphysik)" % Sim.PROTOCOL_VERSION
			peer.disconnect_from_host()
			peer = null
			incoming = ""
			outgoing.clear()
			return
		if mode == "host" and data.get("type") == "input":
			var wanted = data.get("weapon", -1)
			sim.input_player(1, float(data.get("angle", 45)), float(data.get("power", 55)), data.get("fire") == true,
				int(wanted) if (wanted is int or wanted is float) and is_finite(float(wanted)) else -1)
		elif mode == "client" and data.get("type") == "state":
			var first := last_event == 0
			if sim.apply_snapshot(data):
				# Joining mid-game or after a host restart: replay only the last
				# half second, older events would show stale explosions.
				var newest := 0
				for event in sim.events: newest = maxi(newest, event.id)
				if first or newest < last_event:
					last_event = 0
					for event in sim.events:
						if event.tick < sim.tick - 15: last_event = maxi(last_event, event.id)
				since_state = 0.0
				status = "LAN / Spieler 2 / Host-Tick %d" % sim.tick
				if sim.tick % 30 < 3: print("STATE_RECEIVED tick=%d impacts=%d hp0=%d hp1=%d over=%s winner=%d" % [sim.tick, sim.impacts, sim.cannons[0].hp, sim.cannons[1].hp, sim.round_over, sim.winner])

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE: fire_pending = true
		if event.keycode == KEY_ESCAPE: ip_field.release_focus()
		if ip_field.has_focus(): return
		if event.keycode >= KEY_1 and event.keycode < KEY_1 + Sim.SELECTABLE: select_weapon(event.keycode - KEY_1)
		if event.keycode == KEY_Q: select_weapon(posmod(weapon - 1, Sim.SELECTABLE))
		if event.keycode == KEY_E: select_weapon(posmod(weapon + 1, Sim.SELECTABLE))
		if event.keycode == KEY_TAB and mode == "offline":
			player = 1 - player
			angle = sim.cannons[player].angle
			power = sim.cannons[player].power
			weapon = sim.cannons[player].weapon

func select_weapon(index: int) -> void:
	weapon = index
	weapon_pending = true

func _process(delta: float) -> void:
	network()
	if not ip_field.has_focus():
		angle = clampf(angle + (float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN))) * delta * 40.0, 5, 85)
		power = clampf(power + (float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))) * delta * 30.0, 15, 90)
	accumulator += minf(delta, 0.15)
	while accumulator >= Sim.DT:
		accumulator -= Sim.DT
		if mode != "client":
			sim.input_player(player, angle, power, fire_pending, weapon)
			sim.step()
			fire_pending = false
		if auto_smoke:
			smoke_ticks += 1
			if smoke_ticks == 20: select_weapon(smoke_weapon)
			if smoke_ticks == 30: fire_pending = true
			if smoke_ticks == capture_tick and not capture_path.is_empty(): capture.call_deferred()
			if smoke_ticks == 200:
				print("EFFECTS fire=%d impact=%d snow=%d heal=%d shield=%d split=%d" % [effect_counts.fire, effect_counts.impact,
					effect_counts.snow, effect_counts.heal, effect_counts.shield, effect_counts.split])
				print("SMOKE_FINISHED tick=%d impacts=%d hp0=%d hp1=%d" % [sim.tick, sim.impacts, sim.cannons[0].hp, sim.cannons[1].hp])
				get_tree().quit(0)
	since_state += delta
	update_effects(delta)
	send_clock += delta
	if send_clock >= 0.1:
		send_clock = 0.0
		if mode == "host": send(sim.snapshot())
		elif mode == "client" and peer:
			if outgoing.is_empty():
				send({"type": "input", "version": Sim.PROTOCOL_VERSION, "angle": angle, "power": power, "fire": fire_pending, "weapon": weapon})
				fire_pending = false
				weapon_pending = false
	paint_terrain()
	status_label.text = status
	values_label.text = "SPIELER %d     WINKEL %02d°     STÄRKE %02d     |     %s     |     EINSCHLÄGE %d" % [player + 1, angle, power, weapon_text(), sim.impacts]
	if sim.round_over:
		round_label.text = ("UNENTSCHIEDEN" if sim.winner == -1 else "SPIELER %d GEWINNT" % (sim.winner + 1)) + "\nNeustart für nächste Runde"
	else:
		round_label.text = "%s\n%s" % [Sim.WEAPONS[weapon].name.to_upper(), weapon_hint(weapon)]
	queue_redraw()

func weapon_text() -> String:
	var ammo: int = sim.cannons[player].ammo[weapon]
	return "WAFFE %d %s (%s)" % [weapon + 1, Sim.WEAPONS[weapon].name.to_upper(), "∞" if ammo < 0 else str(ammo)]

func weapon_hint(index: int) -> String:
	var w: Dictionary = Sim.WEAPONS[index]
	if w.has("heal"): return "+%d LP" % w.heal
	if w.has("shield"): return "fängt %d Schaden ab" % w.shield
	if w.has("fill"): return "baut Sand auf"
	if w.has("fragments"): return "%d Splitter am Scheitel" % w.fragments
	if w.has("fuse"): return "prallt ab · Zünder %.1f s" % w.fuse
	return "%d max. Schaden" % w.damage

func update_effects(delta: float) -> void:
	for event in sim.events:
		if event.id <= last_event: continue
		last_event = event.id
		spawn_effect(event)
		if auto_smoke: print("EFFECT %s tick=%d" % [event.type, sim.tick])
	shake = maxf(0.0, shake - delta * 25.0)
	for i in range(debris.size() - 1, -1, -1):
		var d: Dictionary = debris[i]
		d.vel.y += Sim.GRAVITY * delta
		d.pos += d.vel * delta
		d.life -= delta
		if d.life <= 0.0 or (d.vel.y > 0.0 and sim.solid(int(d.pos.x), int(d.pos.y))):
			debris.remove_at(i)
	for i in range(flashes.size() - 1, -1, -1):
		flashes[i].life -= delta
		if flashes[i].life <= 0.0: flashes.remove_at(i)

func spawn_effect(event: Dictionary) -> void:
	effect_counts[event.type] += 1
	var pos := Vector2(event.x, event.y)
	var kind: int = int(event.get("kind", Sim.STONE))
	match event.type:
		"fire":
			flashes.append({"pos": pos, "life": 0.14, "max": 0.14, "radius": 3.0, "color": Color("fff4d6")})
			play("audio.fire")
		"heal", "shield":
			var color := Color("8cdfb0") if event.type == "heal" else Color("7fb8ff")
			flashes.append({"pos": pos, "life": 0.6, "max": 0.6, "radius": 9.0, "color": color})
		"split":
			flashes.append({"pos": pos, "life": 0.2, "max": 0.2, "radius": 5.0, "color": Color("fff4d6")})
			play("audio.fire")
		"snow":
			flashes.append({"pos": pos, "life": 0.3, "max": 0.3, "radius": 8.0, "color": Color("eef6ff")})
			for i in 24:
				debris.append({"pos": pos, "vel": Vector2.from_angle(randf_range(PI, TAU)) * randf_range(5.0, 20.0),
					"life": randf_range(0.4, 0.9), "color": Color("eef6ff")})
		_:
			var size: float = Sim.WEAPONS[kind].crater / 10.0
			shake = 7.0 * size
			flashes.append({"pos": pos, "life": 0.35, "max": 0.35, "radius": 11.0 * size, "color": Color("ffb36b")})
			for i in int(40 * size):
				var grain := randf() * 0.12
				debris.append({"pos": pos, "vel": Vector2.from_angle(randf_range(PI * 1.05, TAU * 0.98)) * randf_range(8.0, 38.0) * size,
					"life": randf_range(0.5, 1.3), "color": Color(0.72 + grain, 0.50 + grain, 0.27 + grain)})
			play("audio.impact")

func play(id: String) -> void:
	if sounds.has(id): sounds[id].play()

func paint_terrain() -> void:
	# depth[x]: solid cells above (x, y) in the current run; 0 marks a surface.
	depth.fill(-1)
	for y in Sim.H:
		var sky := Color(0.05 + y * 0.0003, 0.10 + y * 0.0003, 0.15 + y * 0.0003)
		for x in Sim.W:
			var index := y * Sim.W + x
			var cell: int = sim.cells[index]
			var color := sky
			if cell == 0:
				depth[x] = -1
			else:
				depth[x] += 1
				var grain := float((x * 17 + y * 31) % 11) / 110.0
				if cell == 2:
					color = Color(0.20 + grain * 0.3, 0.28 + grain * 0.3, 0.33 + grain * 0.3)
				elif depth[x] == 0:
					color = Color("f4d59a")
				else:
					var shade := minf(depth[x] / 45.0, 1.0) * 0.22
					color = Color(0.72 + grain - shade, 0.50 + grain - shade, 0.27 + grain - shade * 0.6)
			pixels[index * 4] = color.r8
			pixels[index * 4 + 1] = color.g8
			pixels[index * 4 + 2] = color.b8
			pixels[index * 4 + 3] = 255
	image.set_data(Sim.W, Sim.H, false, Image.FORMAT_RGBA8, pixels)
	texture.update(image)

func to_screen(cell: Vector2) -> Vector2:
	return origin + cell * cell_scale

func cannon_color(i: int) -> Color:
	return Color("78dac4") if i == 0 else Color("ef9c86")

func _draw() -> void:
	draw_health_card(0, Vector2(70, 178))
	draw_health_card(1, Vector2(680, 178))
	draw_style_box(panel_style(), Rect2(origin - Vector2(2, 2), Vector2(964, 516)))
	draw_set_transform(Vector2(randf_range(-shake, shake), randf_range(-shake, shake)))
	draw_texture_rect(texture, Rect2(origin, Vector2(960, 512)), false)
	# Short aiming aid from the local, not yet transmitted angle and power.
	var preview := PackedVector2Array()
	if Sim.WEAPONS[weapon].projectile: preview = sim.trajectory(player, angle, power, 22, weapon).points
	for k in range(2, preview.size(), 2):
		draw_circle(to_screen(preview[k]), 1.8, Color(cannon_color(player), 0.75 - 0.6 * k / preview.size()))
	for i in 2:
		var c: Dictionary = sim.cannons[i]
		var p := to_screen(Vector2(c.x, c.y))
		var color := cannon_color(i)
		if c.hp <= 0: color = Color("53616b")
		elif c.hit_flash > 0.0: color = Color("fff4d6")
		var dir: Vector2 = sim.barrel(i, angle if i == player else c.angle)
		var pivot := p + Vector2(0, -8).rotated(c.tilt)
		draw_line(pivot, pivot + dir * (14 if c.hp <= 0 else 28), color, 6, true)
		draw_line(p - Vector2(12, 0).rotated(c.tilt), p + Vector2(12, 0).rotated(c.tilt), color, 9, true)
		for wheel in [-1, 1]:
			var w := p + Vector2(wheel * 12, 6).rotated(c.tilt)
			draw_circle(w, 6, Color("15212b"))
			draw_arc(w, 5, 0, TAU, 20, color, 2, true)
		if c.shield > 0 and c.hp > 0:
			draw_arc(p + Vector2(0, -4), 26, 0, TAU, 40, Color("7fb8ff", 0.35 + 0.4 * c.shield / Sim.MAX_SHIELD), 2.5, true)
		if c.cooldown > 0.0 and c.hp > 0:
			draw_line(p + Vector2(-12, -20), p + Vector2(-12 + 24 * c.cooldown / 0.7, -20), Color(color, 0.7), 3)
		if c.hp <= 0:
			draw_line(p + Vector2(-8, -20), p + Vector2(8, -4), Color("ef9c86"), 2, true)
			draw_line(p + Vector2(8, -20), p + Vector2(-8, -4), Color("ef9c86"), 2, true)
		elif player == i:
			draw_circle(p - Vector2(0, 40), 3, color)
			if sim.tipped(i):
				draw_string(ThemeDB.fallback_font, p + Vector2(-60, -48), "GEKIPPT · richtet sich auf", HORIZONTAL_ALIGNMENT_CENTER, 120, 13, color)
			var meter := (power - 15.0) / 75.0
			draw_rect(Rect2(p + Vector2(-16, 18), Vector2(32, 4)), Color("15212b"))
			draw_rect(Rect2(p + Vector2(-16, 18), Vector2(32 * meter, 4)), color)
	# Clients get 10 Hz snapshots; draw shots on their ballistic path in between.
	var t := minf(since_state, 0.25) if mode == "client" else 0.0
	for shot in sim.shots:
		var vel := Vector2(shot.vx, shot.vy + Sim.GRAVITY * t)
		var p := to_screen(Vector2(shot.x + shot.vx * t, shot.y + shot.vy * t + 0.5 * Sim.GRAVITY * t * t))
		var kind: int = int(shot.get("kind", Sim.STONE))
		var shot_color: Color = [Color("fff4d6"), Color("8cdfb0"), Color("ff8a5c"), Color("e6b3ff"), Color("eef6ff"), Color.WHITE, Color.WHITE, Color("f4d59a")][kind]
		draw_line(p - vel.normalized() * (20 if kind == Sim.ROCKET else 12), p, Color(shot_color, 0.8), 3 if kind == Sim.ROCKET else 2, true)
		draw_circle(p, 2 if kind == Sim.SPLINTER else 3.5, shot_color)
	for d in debris:
		draw_rect(Rect2(to_screen(d.pos) - Vector2(1.5, 1.5), Vector2(3, 3)), Color(d.color, clampf(d.life * 2.0, 0.0, 1.0)))
	for f in flashes:
		var k: float = f.life / f.max
		draw_circle(to_screen(f.pos), f.radius * cell_scale * (1.2 - k * 0.6), Color(f.color, 0.45 * k))
	draw_set_transform(Vector2.ZERO)

func draw_health_card(index: int, pos: Vector2) -> void:
	var c: Dictionary = sim.cannons[index]
	var color := Color("78dac4") if index == 0 else Color("ef9c86")
	var label := "SPIELER %d" % (index + 1)
	if c.hp <= 0: label += " · ZERSTÖRT"
	draw_rect(Rect2(pos, Vector2(350, 50)), Color("101f2a"))
	draw_string(ThemeDB.fallback_font, pos + Vector2(10, 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
	var hp_text := "%d / %d LP" % [c.hp, c.max_hp]
	if c.shield > 0: hp_text = "◈ %d   " % c.shield + hp_text
	draw_string(ThemeDB.fallback_font, pos + Vector2(205, 20), hp_text, HORIZONTAL_ALIGNMENT_RIGHT, 135, 16, Color("e7edf1"))
	draw_rect(Rect2(pos + Vector2(10, 32), Vector2(330, 8)), Color("263945"))
	if c.hp > 0:
		draw_rect(Rect2(pos + Vector2(10, 32), Vector2(330.0 * c.hp / c.max_hp, 8)), color)

func panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("43616c")
	return s

func capture() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_path)
