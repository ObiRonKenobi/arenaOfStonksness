extends Node3D

func _ready() -> void:
	_ensure_inputs()
	GameState.reset()
	if "--gunfit" in OS.get_cmdline_user_args():
		add_child(load("res://tools/gun_fit.gd").new())
		return
	if "--audit" in OS.get_cmdline_user_args():
		_audit()
		return
	if "--boards" in OS.get_cmdline_user_args():
		_boards_shot()
		return
	if "--smoke" in OS.get_cmdline_user_args():
		_smoke()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _smoke() -> void:
	await get_tree().process_frame
	GameState.begin_match()
	await get_tree().process_frame
	for node in get_tree().get_nodes_in_group("barricades"):
		node.set("boards", 0)
		node.call("_rebuild")
	for _i in 40:
		await get_tree().physics_frame
	var barricades := get_tree().get_nodes_in_group("barricades").size()
	var stations := get_tree().get_nodes_in_group("stations").size()
	var enemies := get_tree().get_nodes_in_group("enemies").size()
	var player := get_tree().get_first_node_in_group("player")
	var pos := Vector3.ZERO
	if player:
		pos = player.global_position
	var slots_ok := false
	if player:
		player.call("give_weapon", "street_smg", 1, false)
		player.call("give_weapon", "debt_shotgun", 1, false)
		var held_new: bool = str(player.get("weapon_id")) == "debt_shotgun"
		player.call("_switch_slot", 0)
		var back_to_first: bool = str(player.get("weapon_id")) == "pipe_pistol"
		var kept_other: bool = player.call("owns_weapon", "debt_shotgun")
		var replaced: bool = not player.call("owns_weapon", "street_smg")
		var before := int(player.get("reserve"))
		player.call("refill_weapon", "pipe_pistol")
		var refilled: bool = int(player.get("reserve")) > before
		var ammo_price: int = Economy.ammo_cost("street_smg")
		slots_ok = held_new and back_to_first and kept_other and replaced and refilled and ammo_price == 675
		player.call("_switch_slot", 0)
	print("SMOKE slots=%s" % slots_ok)
	print("SMOKE pos=%s" % pos)
	print("SMOKE running=%s round=%d character=%s barricades=%d stations=%d enemies=%d damage=%s" % [
		GameState.running,
		GameState.round_index,
		GameState.character_id,
		barricades,
		stations,
		enemies,
		player.call("shot_damage") if player else "none",
	])
	var floor_y := 0.0
	if player:
		floor_y = (player as Node3D).global_position.y
	var jump_key := InputEventKey.new()
	jump_key.physical_keycode = KEY_SPACE
	jump_key.pressed = true
	Input.parse_input_event(jump_key)
	for _j in 8:
		await get_tree().physics_frame
	var jumped := false
	if player:
		jumped = (player as Node3D).global_position.y > floor_y + 0.25
	print("SMOKE jump_y=%s floor_y=%s" % [player.global_position.y if player else 0.0, floor_y])
	var body := player as CharacterBody3D
	body.global_position = Vector3(0, 0.2, -6.0)
	body.velocity = Vector3.ZERO
	var window_blocked := body.test_move(body.global_transform, Vector3(0, 0, -1.5))
	var climbed := false
	for _i in 160:
		await get_tree().physics_frame
		for enemy in get_tree().get_nodes_in_group("enemies"):
			var spot := (enemy as Node3D).global_position
			if spot.z > -6.45 and spot.y > -0.2 and spot.y < 1.15:
				climbed = true
	print("SMOKE jumped=%s window_blocked=%s climbed=%s" % [jumped, window_blocked, climbed])
	var boarded := false
	var paid := false
	if player:
		var start_cash := int(player.get("cash"))
		body.global_position = Vector3(0, 0.2, -6.0)
		body.look_at(Vector3(0, 0.2, -8.0), Vector3.UP)
		var hold := InputEventKey.new()
		hold.physical_keycode = KEY_E
		hold.pressed = true
		Input.parse_input_event(hold)
		Input.action_press("interact")
		for _k in 70:
			await get_tree().physics_frame
		Input.action_release("interact")
		var door: Node = null
		for node in get_tree().get_nodes_in_group("barricades"):
			if absf((node as Node3D).global_position.x) < 0.2:
				door = node
				break
		boarded = door != null and int(door.get("boards")) >= 1
		paid = int(player.get("cash")) >= start_cash + 10
	print("SMOKE boarded=%s paid=%s cash=%s" % [boarded, paid, player.get("cash") if player else 0])
	var base_ok := GameState.running and GameState.round_index == 1 and barricades == 3 and stations == 13 and enemies > 0 and jumped and window_blocked and climbed and slots_ok and boarded and paid and int(player.get("cash")) >= 999999
	_smoke_ai(false)
	var drop_gap := await _smoke_drop_gap()
	var drops_ok := drop_gap <= 0.02
	print("SMOKE drops=%s gap=%.3f" % [drops_ok, drop_gap])
	var sprint: Dictionary = await _smoke_sprint(body)
	print("SMOKE sprint=%s walked=%.2f sprinted=%.2f aim_cut=%s sprint_cut=%s" % [sprint.ok, sprint.walked, sprint.sprinted, sprint.aim_cut, sprint.sprint_cut])
	var stair: Dictionary = await _smoke_stairs(body)
	print("SMOKE stairs=%s same=%s through=%s y=%.2f x=%.2f safe=%s flank=%s" % [stair.ok, stair.same, stair.through, stair.y, stair.x, stair.safe, stair.flank])
	var queue: Dictionary = await _smoke_queue(body)
	print("SMOKE queue=%s inside=%s waiting=%s" % [queue.ok, queue.inside, queue.waiting])
	var view: Dictionary = await _smoke_view(body)
	print("SMOKE view=%s rifle=%s pistol=%s" % [view.ok, view.rifle, view.pistol])
	var down: Dictionary = await _smoke_down(body)
	print("SMOKE down=%s cam_dy=%.3f roll=%.1f over=%s" % [down.ok, down.dy, down.roll, down.over])
	var ok := base_ok and drops_ok and bool(sprint.ok) and bool(down.ok) and bool(stair.ok) and bool(view.ok) and bool(queue.ok)
	print("SMOKE_OK" if ok else "SMOKE_FAIL")
	get_tree().quit(0 if ok else 1)

func _smoke_ai(active: bool) -> void:
	var director := get_node_or_null("/root/RoundDirector")
	if director:
		director.set_process(active)
	for node in get_tree().get_nodes_in_group("enemies"):
		node.set_physics_process(active)

func _smoke_drop_gap() -> float:
	var pickup := preload("res://scenes/cash_pickup.tscn").instantiate()
	pickup.kind = "cash"
	add_child(pickup)
	pickup.global_position = Vector3(2.2, 1.2, -1.5)
	for _i in 60:
		await get_tree().physics_frame
	if not is_instance_valid(pickup):
		return 99.0
	var gap := _smoke_floor_gap(pickup.global_position)
	pickup.queue_free()
	return gap

func _smoke_floor_gap(at: Vector3) -> float:
	var from := at + Vector3(0.0, 0.35, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -4.0, 0.0))
	query.collision_mask = 1
	var skip: Array[RID] = []
	for node in get_tree().get_nodes_in_group("player"):
		if node is CollisionObject3D:
			skip.append((node as CollisionObject3D).get_rid())
	query.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 99.0
	return absf(at.y - (hit.position as Vector3).y)

func _smoke_sprint(body: CharacterBody3D) -> Dictionary:
	Input.action_release("sprint")
	Input.action_release("aim")
	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("shoot")
	for _i in 2:
		await get_tree().physics_frame
	body.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	body.velocity = Vector3.ZERO
	body.global_position = Vector3(-4.5, 0.4, 0.4)
	for _i in 20:
		await get_tree().physics_frame
	var spot := body.global_position
	Input.action_press("move_forward")
	body.global_position = spot
	body.velocity = Vector3.ZERO
	var frames := 36
	for _i in frames:
		await get_tree().physics_frame
	var walked := Vector2(body.global_position.x - spot.x, body.global_position.z - spot.z).length()
	body.global_position = spot
	body.velocity = Vector3.ZERO
	Input.action_press("sprint")
	for _i in frames:
		await get_tree().physics_frame
	var sprinted := Vector2(body.global_position.x - spot.x, body.global_position.z - spot.z).length()
	Input.action_press("aim")
	for _i in 10:
		await get_tree().physics_frame
	var aim_cut := float(body.get("_aim")) > 0.25 and float(body.get("_sprint")) < 0.4 and str(body.get("_focus")) == "aim"
	Input.action_release("aim")
	Input.action_release("sprint")
	for _i in 3:
		await get_tree().physics_frame
	Input.action_press("aim")
	for _i in 18:
		await get_tree().physics_frame
	var aimed := float(body.get("_aim")) > 0.6 and str(body.get("_focus")) == "aim"
	Input.action_press("sprint")
	for _i in 12:
		await get_tree().physics_frame
	var sprint_cut := aimed and float(body.get("_aim")) < 0.3 and str(body.get("_focus")) == "sprint"
	Input.action_release("sprint")
	Input.action_release("aim")
	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("shoot")
	var faster := sprinted > walked * 1.2 and sprinted > walked + 0.45
	return {
		"ok": faster and aim_cut and sprint_cut,
		"walked": walked,
		"sprinted": sprinted,
		"aim_cut": aim_cut,
		"sprint_cut": sprint_cut,
	}

func _smoke_stairs(body: CharacterBody3D) -> Dictionary:
	for node in get_tree().get_nodes_in_group("barricades"):
		node.set("boards", 0)
		node.call("_rebuild")
	var foe: CharacterBody3D = null
	for node in get_tree().get_nodes_in_group("enemies"):
		var candidate := node as CharacterBody3D
		if candidate != null and not bool(candidate.get("_dead")):
			foe = candidate
			break
	if foe == null:
		return {"ok": false, "same": false, "through": true, "y": 0.0, "x": 0.0, "safe": false, "flank": false}
	_smoke_ai(false)
	foe.set_physics_process(true)
	foe.set("_door", null)
	foe.set("_swing_t", -1.0)
	foe.set("_cool", 0.0)
	foe.set("_flank_on", true)
	foe.set("_climbing", false)
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "aim", "interact"]:
		Input.action_release(action)
	body.set_physics_process(false)
	body.global_position = Vector3(7.2, 3.2, 2.35)
	body.velocity = Vector3.ZERO
	foe.global_position = Vector3(7.2, 3.2, 1.4)
	foe.velocity = Vector3.ZERO
	foe.look_at(body.global_position, Vector3.UP)
	var same: bool = foe.call("_in_strike", body)
	foe.global_position = Vector3(7.2, 0.15, 2.45)
	foe.velocity = Vector3.ZERO
	foe.look_at(body.global_position, Vector3.UP)
	var through: bool = foe.call("_in_strike", body)
	var health := float(body.get("health"))
	var y0 := foe.global_position.y
	foe.set("_chase_wait", 0.0)
	for _i in 45:
		await get_tree().physics_frame
	var safe := absf(float(body.get("health")) - health) < 0.1 and foe.global_position.y < body.global_position.y - 1.4
	var flank_off := not bool(foe.get("_flank_on"))
	for _i in 255:
		await get_tree().physics_frame
	var climbed := foe.global_position.y > y0 + 0.45
	var on_stair := foe.global_position.x > 5.6
	foe.set_physics_process(false)
	body.set_physics_process(true)
	return {
		"ok": same and not through and climbed and on_stair and safe and flank_off,
		"same": same,
		"through": through,
		"y": foe.global_position.y,
		"x": foe.global_position.x,
		"safe": safe,
		"flank": flank_off,
	}

func _smoke_queue(body: CharacterBody3D) -> Dictionary:
	var door: Node3D = null
	for node in get_tree().get_nodes_in_group("barricades"):
		if absf((node as Node3D).global_position.x) < 0.2:
			door = node as Node3D
			break
	if door == null:
		return {"ok": false, "inside": 0, "waiting": 4}
	door.set("boards", 0)
	door.call("_rebuild")
	_smoke_ai(false)
	body.set_physics_process(false)
	body.global_position = Vector3(0.0, 0.2, -4.5)
	body.velocity = Vector3.ZERO
	var pack: Array[Node] = []
	var spots: Array[Vector3] = [
		Vector3(-0.9, 0.15, -8.7),
		Vector3(-0.3, 0.15, -8.5),
		Vector3(0.35, 0.15, -8.8),
		Vector3(0.95, 0.15, -8.6),
	]
	for spot in spots:
		var enemy := preload("res://scenes/enemy.tscn").instantiate()
		add_child(enemy)
		enemy.global_position = spot
		enemy.call("setup", "broker", 40.0, 2.2, door)
		pack.append(enemy)
	for _i in 420:
		await get_tree().physics_frame
	var inside := 0
	var waiting := 0
	for enemy in pack:
		if not is_instance_valid(enemy):
			continue
		var spot := (enemy as Node3D).global_position
		if spot.z > -6.7:
			inside += 1
		elif spot.z < -7.2:
			waiting += 1
		enemy.set_physics_process(false)
	body.set_physics_process(true)
	return {"ok": inside >= 2 and waiting < 4, "inside": inside, "waiting": waiting}

func _smoke_view(body: CharacterBody3D) -> Dictionary:
	var door: Node = null
	for node in get_tree().get_nodes_in_group("barricades"):
		if absf((node as Node3D).global_position.x) < 0.2:
			door = node
			break
	if door == null:
		return {"ok": false, "rifle": false, "pistol": false}
	door.set("boards", int(door.get("max_boards")))
	door.call("_rebuild")
	body.global_position = Vector3(0.0, 0.2, -6.5)
	body.velocity = Vector3.ZERO
	body.rotation = Vector3.ZERO
	body.get_node("Head").rotation = Vector3.ZERO
	var rifle := await _smoke_muzzle_clear(body, "rent_rifle")
	var pistol := await _smoke_muzzle_clear(body, "pipe_pistol")
	return {"ok": rifle and pistol, "rifle": rifle, "pistol": pistol}

func _smoke_muzzle_clear(body: CharacterBody3D, id: String) -> bool:
	body.call("give_weapon", id, 1, false)
	for _i in 3:
		await get_tree().process_frame
	var cam := body.get_node("Head/Camera3D") as Camera3D
	var tip: Vector3 = body.call("_barrel_tip", 0)
	var rel := tip - cam.global_position
	if rel.length() < 0.3:
		return false
	var query := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + rel.normalized() * 4.0)
	query.collision_mask = 1
	query.exclude = [body]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var hit_dist := cam.global_position.distance_to(hit.position)
	return hit_dist < rel.length() - 0.05 and hit_dist > rel.length() * 0.18 + 0.05

func _boards_shot() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	GameState.begin_match()
	await get_tree().process_frame
	for _i in 20:
		await get_tree().physics_frame
	var body := get_tree().get_first_node_in_group("player") as CharacterBody3D
	var door: Node = null
	for node in get_tree().get_nodes_in_group("barricades"):
		if absf((node as Node3D).global_position.x) < 0.2:
			door = node
			break
	door.set("boards", int(door.get("max_boards")))
	door.call("_rebuild")
	body.global_position = Vector3(0.0, 0.2, -6.5)
	body.velocity = Vector3.ZERO
	body.rotation = Vector3.ZERO
	body.get_node("Head").rotation = Vector3.ZERO
	var dir := OS.get_environment("TEMP").path_join("stonks_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	for id in ["rent_rifle", "pipe_pistol"]:
		body.call("give_weapon", id, 1, false)
		for _i in 8:
			await get_tree().process_frame
		var img := (body.get_node("Head/Camera3D") as Camera3D).get_viewport().get_texture().get_image()
		img.save_png(dir.path_join("board_%s.png" % id))
		print("BOARD_SHOT %s" % id)
	get_tree().quit()

func _smoke_down(body: CharacterBody3D) -> Dictionary:
	body.call("take_damage", 10000.0)
	for _i in 65:
		await get_tree().physics_frame
	var camera := body.get_node("Head/Camera3D") as Camera3D
	var dy := camera.global_position.y - body.global_position.y
	var roll := rad_to_deg(camera.rotation.z)
	var posed := absf(dy) <= 0.6 and absf(roll) > 45.0
	for _i in 150:
		await get_tree().physics_frame
	return {"ok": posed and GameState.over, "dy": dy, "roll": roll, "over": GameState.over}

func _audit() -> void:
	await get_tree().process_frame
	GameState.begin_match()
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	var camera := player.get_node("Head/Camera3D") as Camera3D
	var guns := [
		["pipe_pistol", 1], ["pipe_pistol", 2], ["pipe_pistol", 3],
		["street_smg", 1], ["street_smg", 2], ["street_smg", 3],
		["debt_shotgun", 1], ["debt_shotgun", 2], ["debt_shotgun", 3],
		["rent_rifle", 1], ["rent_rifle", 2], ["rent_rifle", 3],
		["pop_junk", 1], ["ledger_cannon", 1],
	]
	var muzzle_ok := true
	for row in guns:
		player.set("weapon_id", row[0])
		player.set("weapon_tier", row[1])
		player.call("_show_gun")
		await get_tree().process_frame
		await get_tree().process_frame
		var tip: Vector3 = player.call("_barrel_tip", 0)
		var local := camera.to_local(tip)
		var mag: int = player.call("_mag_capacity")
		var reserve: int = player.call("_reserve_for", row[0], row[1])
		var damage: float = player.call("shot_damage")
		print("AUDIT %s t%s tip=%s mag=%d reserve=%d dmg=%.1f" % [row[0], row[1], local, mag, reserve, damage])
		if local.z > -0.2:
			muzzle_ok = false
		if row[0] == "ledger_cannon":
			var tips: PackedVector3Array = player.call("_live_muzzles", 0)
			var spread := PackedStringArray()
			for p in tips:
				spread.append("%.3f" % camera.to_local(p).x)
			print("AUDIT nozzles %s" % [", ".join(spread)])
			if tips.size() < 3:
				muzzle_ok = false
	var suits := {"navy": 0, "grey": 0, "black": 0, "purple": 0}
	for _i in 60:
		var enemy := preload("res://scenes/enemy.tscn").instantiate()
		add_child(enemy)
		enemy.call("setup", "broker", 10.0, 1.0, null)
		suits[str(enemy.get("_suit_name"))] += 1
		enemy.queue_free()
	print("AUDIT suits %s" % suits)
	GameState.set_round(5)
	var director := get_node("/root/RoundDirector")
	director.set("_king_phase", false)
	var numbered_kings := 0
	for _i in 8:
		if str(director.call("_roll_archetype")) == "king":
			numbered_kings += 1
	director.set("_king_phase", true)
	var break_kings := 0
	for _i in 8:
		if str(director.call("_roll_archetype")) == "king":
			break_kings += 1
	var round_held := GameState.round_index == 5
	var king_stats: Dictionary = director.call("_stats_for", "king")
	var suit_stats: Dictionary = director.call("_stats_for", "broker")
	print("AUDIT numbered_kings=%d break_kings=%d round=%d king_hp=%.1f suit_hp=%.1f" % [numbered_kings, break_kings, GameState.round_index, king_stats.hp, suit_stats.hp])
	var cast_ok := CharacterDB.ids().size() == 4
	print("AUDIT cast %s" % [str(CharacterDB.ids())])
	var scale_ok := int(player.call("_capacity_for", "street_smg", 2)) == int(round(30.0 * 1.81))
	scale_ok = scale_ok and int(player.call("_capacity_for", "pipe_pistol", 2)) == 21
	scale_ok = scale_ok and int(player.call("_capacity_for", "pipe_pistol", 3)) == 33
	scale_ok = scale_ok and int(player.call("_capacity_for", "ledger_cannon", 1)) == 3
	scale_ok = scale_ok and int(player.call("_reserve_for", "ledger_cannon", 1)) == 30
	scale_ok = scale_ok and int(player.call("_capacity_for", "debt_shotgun", 2)) == 2
	var ok := muzzle_ok and numbered_kings == 0 and break_kings == 8 and round_held and float(king_stats.hp) < float(suit_stats.hp) and float(king_stats.speed) > float(suit_stats.speed) and scale_ok and int(suits.purple) >= 1 and cast_ok
	print("AUDIT_OK" if ok else "AUDIT_FAIL")
	get_tree().quit(0 if ok else 1)

func _ensure_inputs() -> void:
	_bind("move_forward", KEY_W)
	_bind("move_back", KEY_S)
	_bind("move_left", KEY_A)
	_bind("move_right", KEY_D)
	_bind("shoot", MOUSE_BUTTON_LEFT)
	_bind("aim", MOUSE_BUTTON_RIGHT)
	_bind("interact", KEY_E)
	_bind("reload", KEY_R)
	_bind("ult", KEY_Q)
	_bind("jump", KEY_SPACE)
	_bind("weapon_1", KEY_1)
	_bind("weapon_2", KEY_2)

func _bind(action: String, code: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if not InputMap.action_get_events(action).is_empty():
		return
	var event := InputEventKey.new()
	if code == MOUSE_BUTTON_LEFT or code == MOUSE_BUTTON_RIGHT:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = code as MouseButton
		InputMap.action_add_event(action, mouse)
		return
	event.physical_keycode = code as Key
	InputMap.action_add_event(action, event)
