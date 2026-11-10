class_name RustGameClient
extends RefCounted

const W := 240
const H := 128
const PROTOCOL := 1
var socket: WebSocketPeer
var address := ""
var status := ""
var player := -1
var round_id := -1
var terrain_revision := -1
var players := 0
var warning_x := -1.0
var sequence := 0
var reconnect_in := -1.0
var pending_cells := PackedByteArray()
var cells := PackedByteArray()
var state: Dictionary = {}
var reconnect_enabled := true

func connect_to(url: String) -> void:
	close()
	address = url
	reconnect_enabled = true
	open_socket()

func open_socket() -> void:
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 262144
	var error := socket.connect_to_url(address)
	status = "VERBINDE / Rust-Server"
	if error != OK:
		socket = null
		status = "Verbindung fehlgeschlagen / neuer Versuch"
		reconnect_in = 1.0

func close() -> void:
	reconnect_enabled = false
	if socket: socket.close()
	socket = null
	reconnect_in = -1.0
	player = -1
	round_id = -1
	terrain_revision = -1
	players = 0
	state.clear()
	pending_cells.clear()
	cells.clear()

func poll(delta: float) -> void:
	if reconnect_in >= 0.0:
		reconnect_in -= delta
		if reconnect_in <= 0.0:
			reconnect_in = -1.0
			open_socket()
	if not socket: return
	socket.poll()
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		var code := socket.get_close_code()
		socket = null
		player = -1
		players = 0
		round_id = -1
		terrain_revision = -1
		state.clear()
		pending_cells.clear()
		if code == 1008:
			status = "PARTIE VOLL / erneut verbinden, sobald ein Platz frei ist"
			reconnect_enabled = false
		elif reconnect_enabled:
			status = "VERBINDUNG GETRENNT / neuer Versuch"
			reconnect_in = 1.0
		return
	while socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		if not socket.was_string_packet():
			pending_cells = decode_terrain(packet)
			continue
		var data = JSON.parse_string(packet.get_string_from_utf8())
		if not data is Dictionary: continue
		if data.get("protocol") != PROTOCOL:
			close()
			status = "ANDERE SPIELVERSION / Rust-WebSocket v1 erforderlich"
			return
		if data.has("player"):
			if integer_between(data.player, 0, 1): player = int(data.player)
			continue
		if player < 0 or not valid_state(data): continue
		if int(data.revision) != terrain_revision and pending_cells.is_empty(): continue
		if not pending_cells.is_empty():
			cells = pending_cells
			pending_cells = PackedByteArray()
		if cells.size() != W * H: continue
		terrain_revision = int(data.revision)
		state = data
		round_id = int(data.round)
		players = int(data.players)
		warning_x = float(data.warning)
		sequence += 1
		status = "RUST-SERVER / Spieler %d" % (player + 1)
		if players < 2: status += " / warte auf zweiten Spieler"

func send_input(angle: float, power: float, fire: bool) -> bool:
	if players != 2: return false
	return send({"type": "input", "round": round_id, "angle": angle, "power": power, "fire": fire})

func restart() -> bool:
	if player != 0 or round_id < 0: return false
	return send({"type": "restart", "round": round_id})

func send(message: Dictionary) -> bool:
	if not socket or socket.get_ready_state() != WebSocketPeer.STATE_OPEN: return false
	if socket.get_current_outbound_buffered_amount() > 4096: return false
	return socket.send_text(JSON.stringify(message)) == OK

func apply_to(sim) -> void:
	if state.is_empty(): return
	if sim.cells != cells:
		sim.cells = cells.duplicate()
		sim.terrain_revision += 1
	for i in 2:
		var values: Array = state.cannons[i]
		var c: Dictionary = sim.cannons[i]
		c.hit_flash = 0.2 if values[4] < c.hp else 0.0
		c.x = float(values[0])
		c.y = float(values[1])
		c.angle = float(values[2])
		c.power = float(values[3])
		c.hp = int(values[4])
		c.shield = float(values[5])
		c.rapid = float(values[6])
		c.tilt = 0.0
	sim.shots.clear()
	for shot in state.shots:
		sim.shots.append({"x": float(shot[0]), "y": float(shot[1]), "vx": 0.0, "vy": 0.0, "age": 0.0})
	sim.drop = {}
	if state.drop is Array:
		sim.drop = {"kind": int(state.drop[0]), "x": float(state.drop[1]), "y": float(state.drop[2])}
	sim.tick = int(state.tick)
	sim.round_over = int(state.result) != -2
	sim.winner = int(state.result) if state.result >= 0 else -1
	sim.buff_notice = 0.0

static func numeric(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func integer_between(value: Variant, low: int, high: int) -> bool:
	return numeric(value) and value >= low and value <= high and int(value) == value

static func valid_state(data: Dictionary) -> bool:
	if not integer_between(data.get("round"), 0, 4294967295): return false
	if not integer_between(data.get("revision"), 0, 4294967295): return false
	if not integer_between(data.get("tick"), 0, 4294967295): return false
	if not integer_between(data.get("players"), 0, 2): return false
	if not integer_between(data.get("result"), -2, 1): return false
	if not data.get("cannons") is Array or data.cannons.size() != 2: return false
	for c in data.cannons:
		if not c is Array or c.size() != 7: return false
		for value in c:
			if not numeric(value): return false
		if not integer_between(c[4], 0, 1000) or c[5] < 0 or c[5] > 8 or c[6] < 0 or c[6] > 8: return false
	if not data.get("shots") is Array or data.shots.size() > 32: return false
	for shot in data.shots:
		if not shot is Array or shot.size() != 2 or not numeric(shot[0]) or not numeric(shot[1]): return false
	if data.get("drop") != null:
		var drop = data.drop
		if not drop is Array or drop.size() != 3: return false
		if not integer_between(drop[0], 0, 2) or not numeric(drop[1]) or not numeric(drop[2]): return false
	if not numeric(data.get("warning")): return false
	return true

static func decode_terrain(packet: PackedByteArray) -> PackedByteArray:
	if packet.size() == W * H + 1 and packet[0] == 0:
		var raw := packet.slice(1)
		for cell in raw:
			if cell > 2: return PackedByteArray()
		return raw
	if packet.size() < 3 or packet[0] != 1 or packet.size() % 2 != 1: return PackedByteArray()
	var decoded := PackedByteArray()
	decoded.resize(W * H)
	var offset := 0
	for i in range(1, packet.size(), 2):
		var count := int(packet[i])
		var cell := int(packet[i + 1])
		if count <= 0 or cell > 2 or offset + count > decoded.size(): return PackedByteArray()
		for x in count: decoded[offset + x] = cell
		offset += count
	return decoded if offset == W * H else PackedByteArray()
