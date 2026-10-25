extends Node3D

func _ready() -> void:
	_ensure_inputs()
	GameState.reset()
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
	var ok := false
	ok = GameState.running and GameState.round_index == 1 and barricades == 3 and stations == 11 and enemies > 0 and jumped and window_blocked and climbed and slots_ok
	print("SMOKE_OK" if ok else "SMOKE_FAIL")
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
