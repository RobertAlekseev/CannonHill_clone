extends SceneTree
## Real scene + TCP integration: both input directions, five direct hits,
## client-visible damage, destruction/winner, and host restart replication.
var game: Node

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	var hosting: bool = game.mode == "host"
	if hosting:
		# Level bedrock keeps targets stable while five button-fired shots hit.
		game.sim.cells.fill(0)
		for y in range(80, 128):
			for x in 240: game.sim.cells[y * 240 + x] = 2
		for i in 2:
			game.sim.cannons[i].x = 80.0 + i * 36.0
			game.sim.cannons[i].y = 77.0
	game.angle = 5.0
	game.power = 55.0
	var start := Time.get_ticks_msec()
	var connected_at := -1
	var fired := 0
	var saw_damage := false
	var saw_victory := false
	var terminal_at := -1
	var reset_at := -1
	while Time.get_ticks_msec() - start < 20000:
		await process_frame
		var now := Time.get_ticks_msec()
		if game.peer and game.peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and connected_at == -1:
			connected_at = now
		if connected_at == -1: continue
		var elapsed := now - connected_at
		if hosting:
			if fired < 5 and elapsed >= 1000 + fired * 1000:
				game.fire_pending = true
				fired += 1
			if game.sim.round_over and terminal_at == -1:
				if game.sim.winner != 0 or game.sim.cannons[0].hp != 800 or game.sim.cannons[1].hp != 0:
					push_error("Unexpected authoritative health or winner")
					quit(1)
					return
				terminal_at = now
				print("HOST_VICTORY hp0=800 hp1=0 winner=0")
			if terminal_at != -1 and reset_at == -1 and now - terminal_at >= 1000:
				game.sim.reset()
				reset_at = now
				print("HOST_RESET")
			if reset_at != -1 and now - reset_at >= 1200:
				print("HOST_HEALTH_PASS")
				quit(0)
				return
		else:
			if fired == 0 and elapsed >= 500:
				game.fire_pending = true
				fired = 1
			if game.sim.cannons[0].hp == 800 and game.sim.cannons[1].hp == 800 and not saw_damage:
				saw_damage = true
				print("CLIENT_DAMAGE hp0=800 hp1=800")
			if game.sim.round_over and game.sim.winner == 0 and game.sim.cannons[1].hp == 0:
				saw_victory = true
			if saw_damage and saw_victory and not game.sim.round_over and game.sim.cannons[0].hp == 1000 and game.sim.cannons[1].hp == 1000:
				print("CLIENT_HEALTH_PASS damage=true victory=true restart=true")
				quit(0)
				return
	push_error("Health LAN test timed out")
	quit(1)
