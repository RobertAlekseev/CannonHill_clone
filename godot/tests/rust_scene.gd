extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	var start := Time.get_ticks_msec()
	var ready_announced := false
	var fired := false
	var saw_shots := false
	var saw_warning := false
	var saw_drop := false
	var announced := false
	var initial_round := -1
	var restarted := false
	var reconnecting := false
	var reconnect_sequence := -1
	while Time.get_ticks_msec() - start < 22000:
		await process_frame
		var client = game.rust_client
		if client.player >= 0 and not ready_announced:
			print("MIXED_READY player=%d" % client.player)
			ready_announced = true
		if client.state.is_empty() or client.players != 2: continue
		if initial_round < 0: initial_round = client.round_id
		if not fired:
			game.angle = 47.0
			game.power = 55.0
			game.fire_pending = true
			fired = true
		saw_shots = saw_shots or game.sim.shots.size() >= 2
		saw_warning = saw_warning or client.warning_x >= 0
		saw_drop = saw_drop or not game.sim.drop.is_empty()
		if not announced and saw_shots and saw_warning and saw_drop:
			assert(game.sim.cells == client.cells)
			assert(game.sim.tick == int(client.state.tick))
			assert(int(game.sim.cannons[game.player].angle) == 47)
			assert(game.values_label.text.begins_with("SPIELER %d" % (game.player + 1)))
			print("MIXED_PLAY_PASS player=%d revision=%d hash=%s" % [
				game.player, int(client.state.revision), client.cells.hex_encode().sha256_text()])
			announced = true
			if game.player == 0:
				for node in game.get_children():
					if node is Button and node.text == "Neustart": node.pressed.emit()
		if announced and client.round_id > initial_round and not restarted:
			assert(game.sim.cannons[0].hp == 1000 and game.sim.cannons[1].hp == 1000)
			assert(not game.sim.round_over)
			restarted = true
			reconnect_sequence = client.sequence
			client.socket.close()
			reconnecting = true
		if reconnecting and client.sequence > reconnect_sequence + 2:
			assert(client.round_id > initial_round)
			assert(game.sim.cells == client.cells)
			print("MIXED_SCENE_PASS player=%d restart=true reconnect=true" % game.player)
			quit()
			return
	push_error("Mixed scene test timed out")
	quit(1)
