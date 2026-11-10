extends Node

const FPS := 60.0

func _ready() -> void:
	_run()

func _run() -> void:
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--nav="):
			only = arg.substr("--nav=".length()).split(",")
	seed(7)
	var director := get_node_or_null("/root/RoundDirector")
	if director:
		director.set_process(false)
	GameState.begin_match()
	if director:
		director.set_process(false)
	await get_tree().process_frame
	var ready := false
	for _i in 180:
		await get_tree().physics_frame
		var maps := NavigationServer3D.get_maps()
		if maps.size() > 0 and NavigationServer3D.map_get_iteration_id(maps[0]) > 0:
			ready = true
			break
	if not ready:
		print("NAV map ok=false")
		print("NAV_FAIL")
		get_tree().quit(1)
		return
	var log := FileAccess.open("C:/Users/sudol/AppData/Local/Temp/stonks_nav_log.txt", FileAccess.WRITE)
	var names: Array[String] = [
		"window_pair", "window_boards", "reboard", "stair_up_crowd", "stair_corner",
		"stair_turn_top", "stair_down", "shop_mid", "shop_east", "ramp_block",
	]
	var all_ok := true
	for name in names:
		if only.size() > 0 and name not in only:
			continue
		_note(log, "NAV start %s" % name)
		var result: Dictionary = await _scenario(name)
		var ok: bool = result.ok
		all_ok = all_ok and ok
		_note(log, "NAV %s ok=%s %s t=%.1f" % [name, ok, result.metrics, result.t])
	_note(log, "NAV_OK" if all_ok else "NAV_FAIL")
	get_tree().quit(0 if all_ok else 1)

func _note(log: FileAccess, line: String) -> void:
	print(line)
	if log:
		log.store_line(line)
		log.flush()

func _scenario(name: String) -> Dictionary:
	_reset_world()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.set_physics_process(false)
	player.health = 100000.0
	player.max_health = 100000.0
	match name:
		"window_pair":
			return await _window_pair(player)
		"window_boards":
			return await _window_boards(player)
		"reboard":
			return await _reboard(player)
		"stair_up_crowd":
			return await _stair_up(player)
		"stair_corner":
			return await _stair_corner(player)
		"stair_turn_top":
			return await _stair_turn(player)
		"stair_down":
			return await _stair_down(player)
		"shop_mid":
			return await _shop(player, 0.0, [Vector3(-1.6, 0.15, 6.4), Vector3(1.6, 0.15, 6.4)])
		"shop_east":
			return await _shop(player, 6.0, [Vector3(4.4, 0.15, 6.4), Vector3(7.6, 0.15, 6.4)])
		"ramp_block":
			return await _ramp_block(player)
	return _fail("unknown", 0.0)

func _window_pair(player: CharacterBody3D) -> Dictionary:
	var door := _middle_window()
	_set_boards(door, 0)
	player.global_position = Vector3(0.0, 0.2, -6.3)
	var bodies: Array[Node] = []
	for x in [-1.8, -1.08, -0.36, 0.36, 1.08, 1.8]:
		bodies.append(_spawn(Vector3(x, 0.15, -9.2), 2.33, door))
	for x in [-1.2, -0.4, 0.4, 1.2]:
		bodies.append(_spawn(Vector3(x, 0.15, -10.4), 2.33, door))
	var track := _tracker()
	for _i in int(15.0 * FPS):
		await get_tree().physics_frame
		_sample(bodies, track)
	var inside := 0
	for body in bodies:
		if is_instance_valid(body) and (body as Node3D).global_position.z > -6.3:
			inside += 1
	var rules := _rules(track)
	var ok := rules and inside >= 6
	return {"ok": ok, "t": 15.0, "metrics": "inside=%d %s" % [inside, _metric(track)]}

func _window_boards(player: CharacterBody3D) -> Dictionary:
	var door := _middle_window()
	_set_boards(door, 6)
	player.global_position = Vector3(0.0, 0.2, 2.0)
	var bodies := _spawn_row([-0.9, -0.3, 0.3, 0.9], -8.6, 2.33, door)
	var max_swing := 0
	var lips: Array[bool] = [false, false]
	var cleared_at := -1.0
	var track := _tracker()
	var frames := int(35.0 * FPS)
	for i in frames:
		await get_tree().physics_frame
		_sample(bodies, track)
		var swinging := 0
		for body in bodies:
			if bool(body.get("_board_swing")) and float(body.get("_swing_t")) >= 0.0:
				swinging += 1
			for lane in 2:
				var lip: Vector3 = door.call("lip", lane)
				if _flat((body as Node3D).global_position, lip) <= 0.65 and int(door.get("boards")) > 0:
					lips[lane] = true
		max_swing = maxi(max_swing, swinging)
		if cleared_at < 0.0 and int(door.get("boards")) <= 0:
			cleared_at = float(i) / FPS
			break
	var inside := 0
	if cleared_at >= 0.0:
		for _i in int(10.0 * FPS):
			await get_tree().physics_frame
			_sample(bodies, track)
		for body in bodies:
			if (body as Node3D).global_position.z > -6.3:
				inside += 1
	var rules := _rules(track)
	var ok: bool = rules and max_swing <= 2 and lips[0] and lips[1] and cleared_at >= 0.0 and cleared_at <= 25.0 and inside == 4
	return {
		"ok": ok,
		"t": cleared_at,
		"metrics": "boards_t=%.1f swing=%d lips=%s,%s inside=%d %s" % [cleared_at, max_swing, lips[0], lips[1], inside, _metric(track)],
	}

func _reboard(player: CharacterBody3D) -> Dictionary:
	var door := _middle_window()
	_set_boards(door, 0)
	player.global_position = Vector3(0.0, 0.2, 0.0)
	var front := _spawn_row([-1.1, 1.1], -8.4, 2.33, door)
	var bodies: Array[Node] = []
	bodies.append_array(front)
	var track := _tracker()
	var landed: Array[Node] = []
	var frames := 0
	while frames < int(20.0 * FPS) and landed.size() < 2:
		await get_tree().physics_frame
		frames += 1
		_sample(bodies, track)
		for body in bodies:
			if body in landed:
				continue
			var at := (body as Node3D).global_position
			if at.z > -6.5 and not _is_climbing(body) and body.get("_door") == null:
				landed.append(body)
	_set_boards(door, 6)
	var rear := _spawn_row([-0.7, 0.7], -9.4, 2.33, door)
	bodies.append_array(rear)
	var swung := false
	var back := false
	var door_stuck := false
	for _i in int(6.0 * FPS):
		await get_tree().physics_frame
		_sample(bodies, track)
		if not swung:
			for body in bodies:
				if body in landed:
					continue
				if bool(body.get("_board_swing")) or float(body.get("_swing_t")) >= 0.0:
					swung = true
		for body in landed:
			if body.get("_door") != null:
				door_stuck = true
			if (body as Node3D).global_position.z < -6.2:
				back = true
	var near := 0
	var where := ""
	for body in bodies:
		var at := (body as Node3D).global_position
		where += " (%.1f,%.1f)" % [at.x, at.z]
		if body in landed and _flat(at, player.global_position) <= 1.5:
			near += 1
	var rules := _rules(track)
	var ok := rules and landed.size() >= 2 and swung and not back and not door_stuck and near == landed.size()
	return {
		"ok": ok,
		"t": float(frames) / FPS + 6.0,
		"metrics": "landed=%d near=%d swung=%s back=%s door=%s%s %s" % [landed.size(), near, swung, back, door_stuck, where, _metric(track)],
	}

func _stair_up(player: CharacterBody3D) -> Dictionary:
	player.global_position = Vector3(-6.0, 3.2, -4.0)
	var spots: Array[Vector3] = []
	for x in [2.6, 3.5, 4.4]:
		for z in [-3.0, -1.5, 0.0]:
			spots.append(Vector3(x, 0.15, z))
	spots.append(Vector3(4.95, 0.15, -1.5))
	spots.append(Vector3(4.7, 0.15, 0.0))
	spots.append(Vector3(4.95, 0.15, 1.6))
	var speeds: Array[float] = [1.73, 2.33, 3.3]
	var bodies: Array[Node] = []
	for i in spots.size():
		bodies.append(_spawn(spots[i], speeds[i % 3], null))
	var lanes := {}
	var spread := false
	var track := _tracker()
	var map := get_tree().get_first_node_in_group("map")
	for _i in int(30.0 * FPS):
		await get_tree().physics_frame
		_sample(bodies, track)
		var xs: Array[float] = []
		for body in bodies:
			var lane := int(body.get("_stair_lane"))
			if lane >= 0:
				lanes[lane] = true
			if bool(map.call("on_ramp", (body as Node3D).global_position)):
				xs.append((body as Node3D).global_position.x)
		if xs.size() >= 3:
			xs.sort()
			if xs[xs.size() - 1] - xs[0] >= 1.4:
				spread = true
	var arrived := 0
	for body in bodies:
		var at := (body as Node3D).global_position
		if at.y > 2.9 and _flat(at, player.global_position) <= 3.0:
			arrived += 1
	var rules := _rules(track)
	var ok := rules and arrived == 12 and lanes.size() == 3 and spread
	return {"ok": ok, "t": 30.0, "metrics": "up=%d lanes=%d spread=%s %s" % [arrived, lanes.size(), spread, _metric(track)]}

func _stair_corner(player: CharacterBody3D) -> Dictionary:
	player.global_position = Vector3(-6.0, 3.2, -4.0)
	var bodies: Array[Node] = []
	for spot in [Vector3(5.2, 0.15, 2.5), Vector3(4.95, 0.15, 1.8), Vector3(4.95, 0.15, -1.8), Vector3(4.4, 0.15, 3.2)]:
		bodies.append(_spawn(spot, 2.33, null))
	var track := _tracker()
	var seen := {}
	for _i in int(6.0 * FPS):
		await get_tree().physics_frame
		_sample(bodies, track)
		for body in bodies:
			var at := (body as Node3D).global_position
			if at.x >= 5.9 and at.y >= 0.5:
				seen[body.get_instance_id()] = true
	var rules := _rules(track)
	return {"ok": rules and seen.size() == 4, "t": 6.0, "metrics": "on=%d %s" % [seen.size(), _metric(track)]}

func _stair_turn(player: CharacterBody3D) -> Dictionary:
	player.global_position = Vector3(7.2, 3.2, 4.5)
	var bodies: Array[Node] = []
	var map := get_tree().get_first_node_in_group("map")
	for lane in 3:
		var x := float(map.call("lane_x", lane))
		bodies.append(_spawn(Vector3(x, 0.75, 1.4), 2.33, null))
		bodies.append(_spawn(Vector3(x, 1.35, 0.6), 2.33, null))
	var topped := {}
	var dropped := false
	var track := _tracker()
	for _i in int(20.0 * FPS):
		await get_tree().physics_frame
		_sample(bodies, track)
		for body in bodies:
			var y := (body as Node3D).global_position.y
			var id := body.get_instance_id()
			if y > 2.9:
				topped[id] = true
			elif bool(topped.get(id, false)) and y < 1.8:
				dropped = true
	var near := 0
	var far := 0.0
	for body in bodies:
		var dist := _flat((body as Node3D).global_position, player.global_position)
		far = maxf(far, dist)
		if dist <= 1.6:
			near += 1
	var rules := _rules(track)
	return {"ok": rules and near == 6 and not dropped, "t": 20.0, "metrics": "near=%d far=%.1f dropped=%s %s" % [near, far, dropped, _metric(track)]}

func _stair_down(player: CharacterBody3D) -> Dictionary:
	player.global_position = Vector3(2.0, 0.2, 4.0)
	var bodies: Array[Node] = []
	for x in [2.0, 2.7, 3.3, 4.0]:
		for z in [-4.0, -1.0]:
			bodies.append(_spawn(Vector3(x, 3.2, z), 2.33, null))
	var lanes := {}
	var track := _tracker()
	for _i in int(25.0 * FPS):
		await get_tree().physics_frame
		_sample(bodies, track)
		for body in bodies:
			if bool(body.get("_stair_up")):
				continue
			var lane := int(body.get("_stair_lane"))
			if lane >= 0:
				lanes[lane] = true
	var near := 0
	var far := 0.0
	var far_at := Vector3.ZERO
	for body in bodies:
		var at := (body as Node3D).global_position
		var dist := _flat(at, player.global_position)
		if dist >= far:
			far = dist
			far_at = at
		if dist <= 1.6:
			near += 1
	var rules := _rules(track)
	return {"ok": rules and near == 8 and lanes.size() >= 2, "t": 25.0, "metrics": "near=%d far=%.1f at=(%.1f,%.1f,%.1f) lanes=%d %s" % [near, far, far_at.x, far_at.y, far_at.z, lanes.size(), _metric(track)]}

func _shop(player: CharacterBody3D, gate_x: float, pressed: Array) -> Dictionary:
	var gate := _gate_at(gate_x)
	if gate and gate.has_method("set_open"):
		gate.call("set_open", true)
	player.global_position = Vector3(gate_x, 0.2, 9.8)
	var bodies: Array[Node] = []
	for spot in pressed:
		bodies.append(_spawn(spot, 2.33, null))
	var extras := [
		Vector3(0.0, 0.15, 0.0), Vector3(-2.0, 0.15, 2.0), Vector3(2.0, 0.15, 2.0),
		Vector3(-4.0, 0.15, -2.0), Vector3(3.0, 0.15, -3.0), Vector3(-1.0, 0.15, 4.0),
		Vector3(4.0, 0.15, 3.0), Vector3(1.0, 0.15, -4.0),
	]
	for spot in extras:
		bodies.append(_spawn(spot, 2.33, null))
	var track := _tracker()
	for _i in int(20.0 * FPS):
		await get_tree().physics_frame
		_sample(bodies, track)
	var inside := 0
	for body in bodies:
		if (body as Node3D).global_position.z > 7.4:
			inside += 1
	var rules := _rules(track)
	return {"ok": rules and inside == 10, "t": 20.0, "metrics": "inside=%d %s" % [inside, _metric(track)]}

func _ramp_block(player: CharacterBody3D) -> Dictionary:
	player.global_position = Vector3(7.2, 3.2, -3.2)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3(0.0, PI, 0.0)
	player.set_physics_process(true)
	var bodies: Array[Node] = []
	for i in 9:
		var x := 2.2 + float(i % 3) * 1.1
		var z := -1.0 + float(i / 3) * 1.4
		bodies.append(_spawn(Vector3(x, 0.15, z), 2.33, null))
	var track := _tracker()
	var heads := false
	var pushed := false
	var low := false
	for i in int(18.0 * FPS):
		await get_tree().physics_frame
		player.health = 100000.0
		_sample(bodies, track)
		if _standing_on_enemy(player):
			heads = true
		var on_ramp := 0
		var map := get_tree().get_first_node_in_group("map")
		for body in bodies:
			if bool(map.call("on_ramp", (body as Node3D).global_position)):
				on_ramp += 1
		if not pushed and (on_ramp >= 6 or i >= int(15.0 * FPS)):
			Input.action_press("move_forward")
			pushed = true
			for _k in int(3.0 * FPS):
				await get_tree().physics_frame
				player.health = 100000.0
				_sample(bodies, track)
				if _standing_on_enemy(player):
					heads = true
				if player.global_position.y < 2.3:
					low = true
			break
	Input.action_release("move_forward")
	player.set_physics_process(false)
	var rules := _rules(track)
	return {"ok": rules and pushed and not low and not heads, "t": 18.0, "metrics": "low=%s heads=%s %s" % [low, heads, _metric(track)]}

func _reset_world() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node):
			continue
		node.set_physics_process(false)
		var agent := node.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
		if agent:
			agent.avoidance_enabled = false
		node.queue_free()
	for node in get_tree().get_nodes_in_group("barricades"):
		_set_boards(node, 6)
	for node in get_tree().get_nodes_in_group("gates"):
		if node.has_method("set_open"):
			node.call("set_open", false)
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "aim", "interact"]:
		Input.action_release(action)

func _set_boards(door: Node, count: int) -> void:
	if door == null:
		return
	door.set("boards", count)
	door.call("_rebuild")
	if door.get("lane_owner") != null:
		door.set("lane_owner", [null, null])

func _middle_window() -> Node:
	for node in get_tree().get_nodes_in_group("barricades"):
		if absf((node as Node3D).global_position.x) < 0.2:
			return node
	return null

func _gate_at(x: float) -> Node:
	for node in get_tree().get_nodes_in_group("gates"):
		if absf((node as Node3D).global_position.x - x) < 0.4:
			return node
	return null

func _spawn_row(xs: Array, z: float, speed: float, door: Node) -> Array[Node]:
	var bodies: Array[Node] = []
	for x in xs:
		bodies.append(_spawn(Vector3(float(x), 0.15, z), speed, door))
	return bodies

func _spawn(at: Vector3, speed: float, door: Node) -> Node:
	var enemy := preload("res://scenes/enemy.tscn").instantiate()
	add_child(enemy)
	enemy.global_position = at
	enemy.call("setup", "broker", 40.0, speed, door)
	return enemy

func _tracker() -> Dictionary:
	return {"stuck": 0.0, "snaps": 0, "overlap": false, "fell": false, "y": {}}

func _sample(bodies: Array[Node], track: Dictionary) -> void:
	var now := float(Engine.get_physics_frames()) / FPS
	for body in bodies:
		if not is_instance_valid(body):
			continue
		track.stuck = maxf(float(track.stuck), float(body.get("wall_stuck_max")))
		track.snaps = maxi(int(track.snaps), int(body.get("snaps")))
		if not _is_climbing(body) and _in_wall(body as CharacterBody3D):
			if not bool(track.overlap):
				var at := (body as Node3D).global_position
				track.spot = "(%.1f,%.1f,%.1f)" % [at.x, at.y, at.z]
			track.overlap = true
		if _fell(body as Node3D, track, now):
			track.fell = true

func _rules(track: Dictionary) -> bool:
	return float(track.stuck) < 0.75 and int(track.snaps) == 0 and not bool(track.overlap) and not bool(track.fell)

func _metric(track: Dictionary) -> String:
	return "stuck=%.2f snaps=%d overlap=%s fell=%s spot=%s" % [track.stuck, track.snaps, track.overlap, track.fell, track.get("spot", "")]

func _is_climbing(body: Node) -> bool:
	return bool(body.get("_climbing")) and int(body.get("_climb_phase")) > 0

func _in_wall(body: CharacterBody3D) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, body.global_position + Vector3(0.0, 0.7, 0.0))
	query.collision_mask = 1
	query.exclude = [body.get_rid()]
	var hits := body.get_world_3d().direct_space_state.intersect_shape(query, 4)
	for hit in hits:
		var other: Object = hit.collider
		if other is Node and (other as Node).is_in_group("player"):
			continue
		return true
	return false

func _fell(body: Node3D, track: Dictionary, now: float) -> bool:
	var id := body.get_instance_id()
	var hist: Array = track.y.get(id, [])
	hist.append(Vector2(now, body.global_position.y))
	while hist.size() > 0 and now - (hist[0] as Vector2).x > 0.5:
		hist.remove_at(0)
	track.y[id] = hist
	if hist.is_empty() or _is_climbing(body) or _on_ramp_surface(body):
		return false
	var then: Vector2 = hist[0]
	return then.y > 2.2 and then.y - body.global_position.y > 0.5

func _on_ramp_surface(body: Node3D) -> bool:
	var z := body.global_position.z
	var ramp_y := 0.0
	if z <= -2.1:
		ramp_y = 3.125
	elif z < 2.1:
		ramp_y = (2.1 - z) / 4.2 * 3.125
	return body.global_position.x >= 5.5 and body.global_position.x <= 8.9 and absf(body.global_position.y - ramp_y) < 0.6

func _standing_on_enemy(player: CharacterBody3D) -> bool:
	for i in player.get_slide_collision_count():
		var hit := player.get_slide_collision(i)
		if hit.get_normal().y <= 0.5:
			continue
		var other: Object = hit.get_collider()
		if other is Node and (other as Node).is_in_group("enemies"):
			return true
	return false

func _flat(a: Vector3, b: Vector3) -> float:
	var flat := a - b
	flat.y = 0.0
	return flat.length()

func _fail(metrics: String, t: float) -> Dictionary:
	return {"ok": false, "t": t, "metrics": metrics}
