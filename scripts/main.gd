extends Node3D

func _ready() -> void:
	_ensure_inputs()
	GameState.reset()
	if "--audit" in OS.get_cmdline_user_args():
		_audit()
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
	var ok := false
	ok = GameState.running and GameState.round_index == 1 and barricades == 3 and stations == 13 and enemies > 0 and jumped and window_blocked and climbed and slots_ok and boarded and paid and int(player.get("cash")) >= 999999
	print("SMOKE_OK" if ok else "SMOKE_FAIL")
	get_tree().quit(0 if ok else 1)

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
