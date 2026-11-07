extends CharacterBody3D

signal died

const HIT_SFX := preload("res://assets/audio/body_hit.wav")
const MOAN_SFX := preload("res://assets/audio/horde_moan.wav")
const GRAVITY := 20.0
const STEP_HEIGHT := 0.45
const DEATH_TIME := 1.7
const SWING := 0.7
const IMPACT := 0.38
const REACH := 1.15
const TURN_RATE := 8.0
# Capsules touch at 0.7. Followers ease off inside GAP_FAR and stop at GAP_NEAR.
const GAP_NEAR := 0.72
const GAP_FAR := 1.05
# On the last straight stretch, each body holds its own side of the player instead of the same line.
const SURROUND := 6.5
const RING := 1.0
const RING_OUT := 1.75
const FLANK_RATE := 2.4
const MANTLE := "Mantle"
const MANTLE_TIME := 1.75
const SPINE_SHARE := {"Hips": 0.3, "Abdomen": 0.25, "Torso": 0.25, "Chest": 0.2}
const LIMB_END := {
	"UpperArm.L": "LowerArm.L", "LowerArm.L": "Wrist.L",
	"UpperArm.R": "LowerArm.R", "LowerArm.R": "Wrist.R",
	"UpperLeg.L": "LowerLeg.L", "LowerLeg.L": "Foot.L",
	"UpperLeg.R": "LowerLeg.R", "LowerLeg.R": "Foot.R",
}
# Window climb. at is root height as a share of the sill, then depth from the wall center (outside is negative).
# Aims are model space: +Z toward the room, +X the model's left. The right arm mirrors the left.
const MANTLE_KEYS := [
	{"t": 0.0},
	{"t": 0.15, "at": Vector2(0.0, -0.62), "spine": 0.3, "drop": 0.02,
		"arm": [Vector3(0.18, -0.55, 0.82), Vector3(0.05, -0.62, 0.78)],
		"leg_l": [Vector3(0.0, -0.99, 0.12), Vector3(0.0, -0.99, -0.1)],
		"leg_r": [Vector3(0.0, -0.88, 0.47), Vector3(0.0, -0.96, -0.28)]},
	{"t": 0.36, "at": Vector2(0.28, -0.56), "spine": 0.55, "drop": 0.0,
		"arm": [Vector3(0.1, -0.95, 0.3), Vector3(0.05, -0.95, 0.3)],
		"leg_l": [Vector3(0.02, -0.97, 0.22), Vector3(0.0, -0.93, -0.36)],
		"leg_r": [Vector3(-0.03, -0.32, 0.95), Vector3(0.0, -0.5, -0.87)]},
	{"t": 0.56, "at": Vector2(0.97, -0.05), "spine": 1.0, "drop": 0.4,
		"arm": [Vector3(0.35, -0.8, 0.45), Vector3(0.2, -0.85, 0.45)],
		"leg_l": [Vector3(0.05, -0.45, 0.89), Vector3(0.0, -0.72, -0.69)],
		"leg_r": [Vector3(0.0, -0.25, 0.97), Vector3(0.0, -0.83, -0.56)]},
	{"t": 0.74, "at": Vector2(0.62, 0.42), "spine": 0.65, "drop": 0.12,
		"arm": [Vector3(0.3, -0.6, 0.74), Vector3(0.15, -0.5, 0.85)],
		"leg_l": [Vector3(0.02, -0.85, -0.53), Vector3(0.0, -0.15, -0.99)],
		"leg_r": [Vector3(0.0, -0.9, 0.42), Vector3(0.0, -0.99, 0.08)]},
	{"t": 0.88, "at": Vector2(0.0, 0.95), "spine": 0.4, "drop": 0.2,
		"arm": [Vector3(0.35, -0.75, 0.55), Vector3(0.1, -0.6, 0.8)],
		"leg_l": [Vector3(0.03, -0.78, 0.62), Vector3(0.0, -0.85, -0.53)],
		"leg_r": [Vector3(0.0, -0.7, 0.71), Vector3(0.0, -0.92, -0.39)]},
	{"t": 1.0, "at": Vector2(0.05, 1.2)},
]
var archetype := "broker"
var _suit_name := "navy"
var hp := 40.0
var speed := 2.2
var attack := 8.0
var _door: Node3D
var _cool := 0.0
var _dead := false
var _slow := 1.0
var _climbing := false
var _climb_phase := 0
var _climb_t := 0.0
var _climb_from := Vector3.ZERO
var _lip_stuck := 0.0
var _model: Node3D
var _anim: AnimationPlayer
var _clip := ""
var _lock := 0.0
var _swing_t := -1.0
var _board_swing := false
var _death_t := 0.0
var _corpse_floor := 0.0
var _wander_phase := 0.0
var _steer_t := 0.0
var _steer_side := 1.0
var _steer_normal := Vector3.ZERO
var _side_bias := 1.0
var _flank := 0.0
var _flank_on := false
var _outer := false
var _pace := 1.0
var _walk_hold := 0.0
var _agent: NavigationAgent3D
var _chase_at := Vector3(9999, 9999, 9999)
var _chase_wait := 0.0

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 3
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	_wander_phase = randf() * TAU
	_side_bias = 1.0 if randi() % 2 == 0 else -1.0
	_agent = NavigationAgent3D.new()
	_agent.radius = 0.35
	_agent.height = 1.75
	_agent.path_desired_distance = 0.45
	_agent.target_desired_distance = 0.5
	add_child(_agent)

func setup(kind: String, health: float, move_speed: float, door: Node3D) -> void:
	archetype = kind
	hp = health
	speed = move_speed
	_door = door
	match kind:
		"broker":
			attack = 7.0
			_suit_name = _pick_suit()
		"king":
			attack = 16.0
	_wear_model()
	_voice(MOAN_SFX, -10.0)

func _physics_process(delta: float) -> void:
	if _dead:
		_death_t -= delta
		_settle_corpse()
		if _death_t <= 0.0:
			queue_free()
		return
	_cool = maxf(0.0, _cool - delta)
	_lock = maxf(0.0, _lock - delta)
	_steer_t = maxf(0.0, _steer_t - delta)
	_walk_hold = maxf(0.0, _walk_hold - delta)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var slow := 1.0
	if player and player.has_method("market_crash_active") and player.call("market_crash_active"):
		slow = 0.45
	if player and str(player.get("ult_active")) == "punk_f":
		slow = minf(slow, 0.7)
	_slow = slow
	if _door and (int(_door.get("boards")) <= 0) and (_climbing or _outside_window()):
		_climb_through_window(delta)
		return
	if _swing_t >= 0.0:
		var before := _swing_t
		_swing_t += delta
		if before < IMPACT and _swing_t >= IMPACT:
			if _board_swing:
				_land_board()
			else:
				_land_hit(player)
		var boarding := _board_swing
		if _swing_t >= SWING:
			_swing_t = -1.0
			_board_swing = false
		velocity.x = 0.0
		velocity.z = 0.0
		_sync_clip(false, not boarding)
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		else:
			velocity.y = -1.0
		move_and_slide()
		return
	var target := global_position
	var attacking_door := false
	if _door and int(_door.get("boards")) > 0:
		target = _window_approach()
		var flat := global_position - target
		flat.y = 0.0
		attacking_door = flat.length() < 1.15
	elif player:
		target = player.global_position
		_refresh_chase(player, delta)
		target = _agent.get_next_path_position()
	if not attacking_door:
		var dir := target - global_position
		dir.y = 0.0
		if player and not _door_fight():
			var slot := _surround_slot(player, delta)
			if _flank_on:
				dir = slot
		if _flank_on and dir.length() <= 0.22:
			velocity.x = 0.0
			velocity.z = 0.0
			_turn_toward(player.global_position - global_position, delta)
			if _in_strike(player):
				_begin_swing()
		elif dir.length() > 0.15:
			var dist := dir.length()
			if player and not _door_fight():
				dist = global_position.distance_to(player.global_position)
			if _on_final_leg() and not _flank_on:
				dir = _weave(dir.normalized(), delta, dist)
			else:
				dir = dir.normalized()
			if _steer_t > 0.0 and _steer_normal.length() > 0.1:
				dir = _slide_along(_steer_normal, dir)
			var pace_goal := _horde_pace(dir, target)
			# A body stepping off the line still has someone ahead. Let it move sideways.
			if _flank_on:
				pace_goal = maxf(pace_goal, 0.8)
			_ease_pace(pace_goal, delta)
			velocity.x = dir.x * speed * _slow * _pace
			velocity.z = dir.z * speed * _slow * _pace
			if _flank_on:
				_turn_toward(player.global_position - global_position, delta)
			else:
				_turn_toward(dir, delta)
			if player and not _door_fight() and _in_strike(player):
				_begin_swing()
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			if player and not _door_fight() and _in_strike(player):
				_begin_swing()
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_face_boards()
		_begin_swing(true)
	_sync_clip(Vector2(velocity.x, velocity.z).length() > 0.25, false)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -1.0
	var step := Vector3(velocity.x, 0.0, velocity.z)
	var before_pos := global_position
	move_and_slide()
	if step.length() > 0.2:
		_step_up(step)
		_note_bump(step, before_pos)

func _weave(dir: Vector3, delta: float, dist: float) -> Vector3:
	_wander_phase += delta * 1.35
	var fade := clampf(1.15 - float(GameState.round_index - 1) * 0.035, 0.12, 1.0)
	var reach := clampf(dist / 2.8, 0.25, 1.0)
	var sway := sin(_wander_phase) * 0.9 * fade * reach
	var side := Vector3(-dir.z, 0.0, dir.x)
	var lurch := lerpf(1.0, 0.72 + 0.28 * absf(sin(_wander_phase * 0.7)), fade)
	return (dir + side * sway).normalized() * lurch

func _surround_slot(player: Node3D, delta: float) -> Vector3:
	var from := global_position - player.global_position
	from.y = 0.0
	var dist := from.length()
	if dist > SURROUND or dist < 0.05:
		_flank_on = false
		_outer = false
		return Vector3.ZERO
	# A stair or a doorway still has corners. Stay on the path until the player is in the open.
	if not _flank_on and not _open_to(player):
		return Vector3.ZERO
	if not _flank_on:
		# Split the file once. The same offset every frame would walk them back into one line.
		var spread := 0.35 + 0.9 * float(int(get_instance_id()) % 97) / 96.0
		_flank = atan2(from.x, from.z) + _side_bias * spread
		_flank_on = true
	var closer := 0
	var push := 0.0
	for other in get_tree().get_nodes_in_group("enemies"):
		var body := other as CharacterBody3D
		if body == null or body == self or body._dead or body._climb_phase > 0:
			continue
		var there := body.global_position - player.global_position
		there.y = 0.0
		var other_dist := there.length()
		if other_dist > SURROUND or other_dist < 0.05:
			continue
		if other_dist < dist - 0.2:
			closer += 1
		var gap := wrapf(_flank - atan2(there.x, there.z), -PI, PI)
		if absf(gap) >= 0.7:
			continue
		var away := _side_bias if absf(gap) < 0.1 else signf(gap)
		push += away * (0.7 - absf(gap))
	# Once a body is in the ring, keep it there. Falling back to the outer ring empties the far side.
	if dist < RING + 0.5:
		_outer = false
	elif _outer:
		_outer = closer >= 5
	else:
		_outer = closer >= 7
	_flank = rotate_toward(_flank, wrapf(_flank + clampf(push, -1.0, 1.0), -PI, PI), FLANK_RATE * delta)
	var radius := RING_OUT if _outer else RING
	var slot := player.global_position + Vector3(sin(_flank), 0.0, cos(_flank)) * radius
	return slot - global_position

func _open_to(player: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.8, 0)
	var to := player.global_position + Vector3(0, 0.8, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [self, player]
	return space.intersect_ray(query).is_empty()

func _horde_pace(dir: Vector3, target: Vector3) -> float:
	# Followers ease off behind whoever is closer to the goal. A hard stop and go flickers the walk.
	if dir.length() < 0.01:
		return 1.0
	var heading := Vector3(dir.x, 0.0, dir.z).normalized()
	var my_rank := _rank_to(target)
	var pace := 1.0
	for other in get_tree().get_nodes_in_group("enemies"):
		var body := other as CharacterBody3D
		if body == null or body == self or body._dead:
			continue
		# A body already through the window is not a wall. Yielding to it freezes the queue.
		if body._climb_phase > 0 and body.collision_layer == 0 and body._door != null:
			var rel: Vector3 = body.global_position - (body._door as Node3D).global_position
			rel.y = 0.0
			if rel.dot(body._door_out()) <= 0.0:
				continue
		var offset := body.global_position - global_position
		offset.y = 0.0
		var dist := offset.length()
		if dist > GAP_FAR or dist < 0.001:
			continue
		if offset.dot(heading) < dist * 0.35:
			continue
		if body._rank_to(target) < my_rank:
			pace = minf(pace, smoothstep(GAP_NEAR, GAP_FAR, dist))
	return pace

func _ease_pace(goal: float, delta: float) -> void:
	var rate := 6.0 if goal < _pace else 3.0
	_pace = move_toward(_pace, goal, rate * delta)

func _aside_for(heading: Vector3, target: Vector3) -> Vector3:
	# A worse-ranked body planted in a closer enemy's line corks the window. Step off it.
	var my_rank := _rank_to(target)
	for other in get_tree().get_nodes_in_group("enemies"):
		var body := other as CharacterBody3D
		if body == null or body == self or body._dead or body.collision_layer == 0:
			continue
		var to_me := global_position - body.global_position
		to_me.y = 0.0
		var dist := to_me.length()
		if dist > GAP_NEAR or dist < 0.001:
			continue
		if body._rank_to(target) >= my_rank:
			continue
		var aim := target - body.global_position
		aim.y = 0.0
		if aim.length() < 0.05 or to_me.normalized().dot(aim.normalized()) < 0.5:
			continue
		var side := Vector3(-heading.z, 0.0, heading.x) * _side_bias
		return (heading + side).normalized()
	return Vector3.ZERO

func _turn_toward(dir: Vector3, delta: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	rotation.y = rotate_toward(rotation.y, atan2(-dir.x, -dir.z), TURN_RATE * delta)

func take_damage(amount: float, source: Node, headshot: bool = false) -> void:
	if _dead:
		return
	var bonus := 0
	if source and str(source.get("ult_active")) == "cowboy":
		bonus = 45 + GameState.round_index * 5
	var dealt := amount
	if headshot:
		if GameState.round_index <= 3:
			dealt = hp
		else:
			var mult := 2.15 - float(GameState.round_index - 4) * 0.035
			dealt = amount * maxf(1.35, mult)
		GameState.toast("Headshot")
	hp -= dealt
	_voice(HIT_SFX, -4.0)
	if hp > 0.0:
		return
	if source and source.has_method("add_cash"):
		var drop := 35 + GameState.round_index * 8 + bonus
		if headshot:
			drop += 40 + GameState.round_index * 10
		source.call("add_cash", 0)
		_drop_cash(drop)
		if _suit_name == "purple":
			_drop_supply("health" if randi() % 2 == 0 else "ammo")
		source.call("add_ult", 8.0)
	_die()

func knockback(from: Vector3) -> void:
	if _dead:
		return
	var push := global_position - from
	push.y = 0.0
	if push.length() < 0.1:
		push = Vector3.FORWARD
	move_and_collide(push.normalized() * 3.2)
	hp -= 18.0
	if hp <= 0.0:
		_drop_cash(30)
		_die()

func _door_out() -> Vector3:
	if _door and _door.has_method("outward"):
		return _door.call("outward")
	return Vector3.FORWARD

func _outside_window() -> bool:
	var rel := global_position - _door.global_position
	rel.y = 0.0
	return rel.dot(_door_out()) > -0.15

func _window_approach() -> Vector3:
	var spot := _door.global_position + _door_out() * 0.95
	spot.y = 0.0
	return spot

func _at_sill(gap: float) -> bool:
	if gap <= 0.45:
		return true
	var rel := global_position - _door.global_position
	rel.y = 0.0
	var out := _door_out()
	var depth := rel.dot(out)
	return depth <= 1.2 and (rel - out * depth).length() <= 0.55

func _lip_held(lip: Vector3) -> bool:
	for other in get_tree().get_nodes_in_group("enemies"):
		var body := other as CharacterBody3D
		if body == null or body == self or body._dead or body._door != _door:
			continue
		if body._climb_phase <= 0:
			continue
		var flat := body.global_position - lip
		flat.y = 0.0
		if flat.length() < 0.7:
			return true
	return false

func _separate_landing() -> void:
	for _step in 3:
		var push := Vector3.ZERO
		for other in get_tree().get_nodes_in_group("enemies"):
			var body := other as CharacterBody3D
			if body == null or body == self or body._dead or body.collision_layer == 0:
				continue
			var flat := global_position - body.global_position
			flat.y = 0.0
			var dist := flat.length()
			if dist >= 0.72:
				continue
			if dist < 0.001:
				flat = Vector3(_side_bias, 0.0, 0.0)
				dist = 1.0
			push += flat.normalized() * (0.72 - dist)
		if push.length() < 0.01:
			return
		global_position += push

func _climb_through_window(delta: float) -> void:
	var mesh_node := $Mesh as Node3D
	var sill := float(_door.get("sill_top"))
	var out := _door_out()
	if not _climbing:
		_climbing = true
		_climb_phase = 0
		_climb_t = 0.0
		_lip_stuck = 0.0
	if _climb_phase == 0:
		var lip := _window_approach()
		var flat := lip - global_position
		flat.y = 0.0
		var gap := flat.length()
		if _at_sill(gap) and _lip_held(lip):
			velocity.x = 0.0
			velocity.z = 0.0
			_turn_toward(-out, delta)
			if is_on_floor():
				velocity.y = -1.0
			else:
				velocity.y -= GRAVITY * delta
			move_and_slide()
			return
		if not _at_sill(gap):
			var dir := flat.normalized()
			var goal := _horde_pace(dir, lip)
			var aside := _aside_for(dir, lip)
			if aside != Vector3.ZERO:
				dir = aside
				goal = maxf(goal, 0.8)
			_ease_pace(goal, delta)
			velocity.x = dir.x * speed * _slow * _pace
			velocity.z = dir.z * speed * _slow * _pace
			_turn_toward(-out, delta)
			if is_on_floor():
				velocity.y = -1.0
			else:
				velocity.y -= GRAVITY * delta
			var before := global_position
			move_and_slide()
			if gap > 1.2:
				_sync_clip(Vector2(velocity.x, velocity.z).length() > 0.25, false)
			var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
			if _pace > 0.5 and gap <= 1.0 and moved < speed * _slow * delta * 0.35:
				_lip_stuck += delta
			else:
				_lip_stuck = 0.0
			if _lip_stuck < 0.4 or _lip_held(lip):
				return
		_lip_stuck = 0.0
		_climb_phase = 1
		_climb_t = 0.0
		_climb_from = global_position
		_clip = ""
		collision_layer = 0
		collision_mask = 0
		floor_snap_length = 0.0
		velocity = Vector3.ZERO
	_climb_t += delta
	_play(MANTLE)
	var blend := clampf(_climb_t / _climb_length(), 0.0, 1.0)
	global_position = _mantle_root(blend, out, sill)
	look_at(global_position - out, Vector3.UP)
	if blend < 1.0:
		return
	_climbing = false
	_climb_phase = 0
	_separate_landing()
	collision_layer = 2
	collision_mask = 3
	floor_snap_length = 0.45
	velocity = Vector3.ZERO
	if _model:
		_model.rotation = Vector3(0.0, PI, 0.0)
	mesh_node.scale = Vector3.ONE
	mesh_node.rotation = Vector3.ZERO
	_sync_clip(true, false)

func _note_bump(wanted: Vector3, before: Vector3) -> void:
	var moved := global_position - before
	moved.y = 0.0
	var expect := wanted.length() * get_physics_process_delta_time()
	if expect < 0.001 or moved.length() > expect * 0.45:
		return
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var normal := hit.get_normal()
		# The stair slope is a floor. Steering off it pins the horde at the bottom.
		if normal.y >= 0.5:
			continue
		var other: Object = hit.get_collider()
		if not (other is Node and (other as Node).is_in_group("enemies")):
			continue
		normal.y = 0.0
		if normal.length() < 0.2:
			continue
		normal = normal.normalized()
		# Keep one side per bump. Re-picking every frame flips a head-on body left and right.
		var fresh := _steer_t <= 0.0 or _steer_normal.dot(normal) < 0.5
		_steer_normal = normal
		if fresh:
			var lean := Vector3(-normal.z, 0.0, normal.x).dot(wanted.normalized())
			_steer_side = _side_bias if absf(lean) < 0.15 else signf(lean)
		_steer_t = 0.85
		return

func _slide_along(normal: Vector3, want: Vector3) -> Vector3:
	var along := Vector3(-normal.z, 0.0, normal.x) * _steer_side
	if along.length() < 0.01 or want.length() < 0.01:
		return want.normalized()
	along = along.normalized()
	if along.dot(want.normalized()) < -0.3:
		_steer_t = 0.0
		return want.normalized()
	return (along * 0.7 + want.normalized() * 0.3).normalized()

func _face_boards() -> void:
	if _door == null:
		return
	var aim := _door.global_position - global_position
	aim.y = 0.0
	if aim.length_squared() > 0.0001:
		_turn_toward(aim, get_physics_process_delta_time())

func _begin_swing(at_boards: bool = false) -> void:
	if _cool > 0.0 or _swing_t >= 0.0:
		return
	if _walk_hold > 0.0 and _is_loop(_clip):
		return
	_board_swing = at_boards
	_swing_t = 0.0
	_cool = SWING if at_boards else SWING + 0.45
	_sync_clip(false, true)
	_lock = SWING

func _land_board() -> void:
	if not _at_boards():
		return
	_cool = 1.5
	_door.call("chip", 1)

func _at_boards() -> bool:
	if _door == null or int(_door.get("boards")) <= 0:
		return false
	var flat := global_position - _window_approach()
	flat.y = 0.0
	return flat.length() < REACH

func _land_hit(player: Node3D) -> void:
	if player == null or not _in_strike(player):
		return
	player.call("take_damage", attack)

func _in_strike(player: Node3D) -> bool:
	var to := player.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > REACH or dist < 0.001:
		return false
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return false
	return forward.normalized().dot(to / dist) >= 0.55

func _drop_cash(amount: int) -> void:
	_spawn_pickup("cash", amount)

func _drop_supply(supply_kind: String) -> void:
	_spawn_pickup(supply_kind, 0)

func _spawn_pickup(supply_kind: String, cash_amount: int) -> void:
	var pickup := preload("res://scenes/cash_pickup.tscn").instantiate()
	pickup.kind = supply_kind
	pickup.amount = cash_amount
	var parent := get_parent()
	if parent:
		parent.add_child(pickup)
		var place := Vector3(0.0, 0.4, 0.0) if supply_kind == "cash" else Vector3(0.55, 0.4, 0.15)
		pickup.global_position = global_position + place

func _pick_suit() -> String:
	if randi() % 15 == 0:
		return "purple"
	return ["navy", "grey", "black"][randi() % 3]

func _process(_delta: float) -> void:
	if _anim == null or _clip == "":
		return
	if _is_loop(_clip) and not _anim.is_playing():
		_anim.play(_clip)
	var rate := 1.0
	if "walk" in _clip.to_lower():
		rate = clampf(Vector2(velocity.x, velocity.z).length() / maxf(speed, 0.1), 0.45, 1.0)
	_anim.speed_scale = rate

func _door_fight() -> bool:
	return _door != null and int(_door.get("boards")) > 0

func _refresh_chase(player: Node3D, delta: float) -> void:
	_chase_wait -= delta
	var moved := player.global_position.distance_to(_chase_at) >= 0.4
	if _chase_wait > 0.0 and not moved:
		return
	_chase_wait = 0.25
	_chase_at = player.global_position
	_agent.target_position = _chase_at

func _on_final_leg() -> bool:
	if _agent == null or _door_fight():
		return true
	if _agent.is_navigation_finished():
		return true
	var path := _agent.get_current_navigation_path()
	if path.is_empty():
		return false
	var idx := _agent.get_current_navigation_path_index()
	return path.size() - idx <= 1

func _rank_to(target: Vector3) -> float:
	var along := _path_left()
	if along >= 0.0:
		return along
	return global_position.distance_to(target)

func _path_left() -> float:
	if _agent == null:
		return -1.0
	var path := _agent.get_current_navigation_path()
	if path.is_empty():
		return -1.0
	var idx := clampi(_agent.get_current_navigation_path_index(), 0, path.size() - 1)
	var left := global_position.distance_to(path[idx])
	for i in range(idx, path.size() - 1):
		left += path[i].distance_to(path[i + 1])
	return left

func _climb_length() -> float:
	if _anim and _anim.has_animation(MANTLE):
		return MANTLE_TIME
	return 1.15

func _mantle_root(blend: float, out: Vector3, sill: float) -> Vector3:
	var spots: Array[Vector3] = []
	var times: Array[float] = []
	for key in MANTLE_KEYS:
		times.append(float(key.t))
		if key.has("at"):
			var at: Vector2 = key.at
			var spot := _door.global_position - out * at.y
			spot.y = at.x * sill
			spots.append(spot)
		else:
			spots.append(_climb_from)
	var i := 0
	while i < times.size() - 2 and blend > times[i + 1]:
		i += 1
	var w := clampf((blend - times[i]) / maxf(times[i + 1] - times[i], 0.001), 0.0, 1.0)
	var before := spots[maxi(i - 1, 0)]
	var after := spots[mini(i + 2, spots.size() - 1)]
	return spots[i].cubic_interpolate(spots[i + 1], before, after, w)

func _add_mantle() -> void:
	# The shipped Climb clip is a walk, so the window climb is posed from the skeleton here.
	# The library is shared per model, so this runs once per archetype.
	if _anim == null or _anim.has_animation(MANTLE) or not _anim.has_animation("Idle"):
		return
	if not _anim.has_animation_library(""):
		return
	var found := _model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	var skel := found[0] as Skeleton3D
	for bone in LIMB_END:
		if skel.find_bone(bone) < 0 or skel.find_bone(LIMB_END[bone]) < 0:
			return
	var count := skel.get_bone_count()
	var pos: Array[Vector3] = []
	var rot: Array[Quaternion] = []
	var scl: Array[Vector3] = []
	for i in count:
		var rest := skel.get_bone_rest(i)
		pos.append(rest.origin)
		rot.append(rest.basis.get_rotation_quaternion())
		scl.append(rest.basis.get_scale())
	var idle := _anim.get_animation("Idle")
	for t in idle.get_track_count():
		var bone := skel.find_bone(String(idle.track_get_path(t).get_concatenated_subnames()))
		if bone < 0:
			continue
		match idle.track_get_type(t):
			Animation.TYPE_POSITION_3D:
				pos[bone] = idle.position_track_interpolate(t, 0.0)
			Animation.TYPE_ROTATION_3D:
				rot[bone] = idle.rotation_track_interpolate(t, 0.0)
			Animation.TYPE_SCALE_3D:
				scl[bone] = idle.scale_track_interpolate(t, 0.0)
	var skel_path := String(_anim.get_node(_anim.root_node).get_path_to(skel))
	var clip := Animation.new()
	clip.length = MANTLE_TIME
	var rot_tracks: Array[int] = []
	var pos_tracks: Array[int] = []
	for i in count:
		var path := NodePath("%s:%s" % [skel_path, skel.get_bone_name(i)])
		var r := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(r, path)
		clip.track_set_interpolation_type(r, Animation.INTERPOLATION_CUBIC)
		rot_tracks.append(r)
		var p := clip.add_track(Animation.TYPE_POSITION_3D)
		clip.track_set_path(p, path)
		clip.track_set_interpolation_type(p, Animation.INTERPOLATION_CUBIC)
		pos_tracks.append(p)
	for key in MANTLE_KEYS:
		var posed := _mantle_pose(skel, pos, rot, scl, key)
		var time := float(key.t) * MANTLE_TIME
		for i in count:
			clip.position_track_insert_key(pos_tracks[i], time, posed[0][i])
			clip.rotation_track_insert_key(rot_tracks[i], time, posed[1][i])
	_anim.get_animation_library("").add_animation(MANTLE, clip)

func _mantle_pose(skel: Skeleton3D, base_pos: Array[Vector3], base_rot: Array[Quaternion], scl: Array[Vector3], key: Dictionary) -> Array:
	var pos := base_pos.duplicate()
	var rot := base_rot.duplicate()
	if not key.has("spine"):
		return [pos, rot]
	var base_glob := _bone_globals(skel, base_pos, base_rot, scl)
	var arm: Array = key.arm
	var leg_l: Array = key.leg_l
	var leg_r: Array = key.leg_r
	var aims := {
		"UpperArm.L": arm[0], "LowerArm.L": arm[1],
		"UpperArm.R": _mirror(arm[0]), "LowerArm.R": _mirror(arm[1]),
		"UpperLeg.L": leg_l[0], "LowerLeg.L": leg_l[1],
		"UpperLeg.R": leg_r[0], "LowerLeg.R": leg_r[1],
	}
	var spine := float(key.spine)
	var glob: Array[Transform3D] = []
	glob.resize(skel.get_bone_count())
	for i in skel.get_bone_count():
		var parent := skel.get_bone_parent(i)
		var parent_g := glob[parent] if parent >= 0 else Transform3D.IDENTITY
		var bone := skel.get_bone_name(i)
		var g := parent_g * Transform3D(Basis(rot[i]) * Basis.from_scale(scl[i]), pos[i])
		if bone == "Body":
			g.origin.y -= float(key.drop)
		elif SPINE_SHARE.has(bone):
			g.basis = Basis(Vector3.RIGHT, spine * float(SPINE_SHARE[bone])) * g.basis
		elif bone == "Neck" or bone == "Head":
			g.basis = Basis(Vector3.RIGHT, -spine * 0.2) * g.basis
		elif aims.has(bone):
			var end := skel.find_bone(LIMB_END[bone])
			var tip := base_glob[i].affine_inverse() * base_glob[end].origin
			var now := (g.basis * tip).normalized()
			g.basis = Basis(Quaternion(now, (aims[bone] as Vector3).normalized())) * g.basis
		elif bone.begins_with("Foot."):
			# The feet hang off the root in this rig, so they ride the end of the shin.
			var shin := skel.find_bone("LowerLeg" + bone.substr(4))
			if shin >= 0:
				g = glob[shin] * (base_glob[shin].affine_inverse() * base_glob[i])
		var local := parent_g.affine_inverse() * g
		pos[i] = local.origin
		rot[i] = local.basis.get_rotation_quaternion()
		glob[i] = parent_g * Transform3D(Basis(rot[i]) * Basis.from_scale(scl[i]), pos[i])
	return [pos, rot]

func _bone_globals(skel: Skeleton3D, pos: Array[Vector3], rot: Array[Quaternion], scl: Array[Vector3]) -> Array[Transform3D]:
	var glob: Array[Transform3D] = []
	glob.resize(skel.get_bone_count())
	for i in skel.get_bone_count():
		var local := Transform3D(Basis(rot[i]) * Basis.from_scale(scl[i]), pos[i])
		var parent := skel.get_bone_parent(i)
		glob[i] = glob[parent] * local if parent >= 0 else local
	return glob

func _mirror(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)

func _step_up(dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var feet := global_position + Vector3(0, 0.15, 0)
	var ahead := dir.normalized() * 0.4
	var low := PhysicsRayQueryParameters3D.create(feet, feet + ahead)
	low.exclude = [self]
	low.collision_mask = 1
	var hit_low := space.intersect_ray(low)
	if hit_low.is_empty():
		return
	if (hit_low.normal as Vector3).y >= 0.5:
		return
	var chest := global_position + Vector3(0, STEP_HEIGHT + 0.2, 0)
	var high := PhysicsRayQueryParameters3D.create(chest, chest + ahead)
	high.exclude = [self]
	high.collision_mask = 1
	if not space.intersect_ray(high).is_empty():
		return
	global_position.y += STEP_HEIGHT

func _die() -> void:
	if _dead:
		return
	_dead = true
	_death_t = DEATH_TIME
	_corpse_floor = _floor_under()
	collision_layer = 0
	collision_mask = 0
	_lock = 0.0
	_clip = ""
	_play("Death")
	died.emit()

func _floor_under() -> float:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.6, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -4.0, 0))
	query.collision_mask = 1
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return global_position.y
	return hit.position.y

func _settle_corpse() -> void:
	var blend := clampf(1.0 - _death_t / DEATH_TIME, 0.0, 1.0)
	var drop := smoothstep(0.2, 0.85, blend)
	var visual := _model if _model != null else $Mesh as Node3D
	if visual:
		visual.position.y = -0.74 * drop
	if global_position.y > _corpse_floor + 0.02:
		global_position.y = move_toward(global_position.y, _corpse_floor, 8.0 * get_physics_process_delta_time())

func _wear_model() -> void:
	var path := "res://assets/characters/%s.glb" % archetype
	if not ResourceLoader.exists(path):
		_paint()
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_paint()
		return
	_model = packed.instantiate()
	_model.rotation.y = PI
	add_child(_model)
	$Mesh.visible = false
	_ink(_model)
	_plant_feet(_model)
	var players: Array = _model.find_children("*", "AnimationPlayer", true, false)
	if players.size() > 0:
		_anim = players[0] as AnimationPlayer
		_add_mantle()
	if "--smoke" in OS.get_cmdline_user_args() and _anim:
		print("ANIMS ", archetype, _anim.get_animation_list())
	_play("Idle")

func _plant_feet(root: Node3D) -> void:
	var box := AABB()
	var started := false
	var inv := root.global_transform.affine_inverse()
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var local := mesh_node.mesh.get_aabb()
		var to_root := inv * mesh_node.global_transform
		for i in 8:
			var point: Vector3 = to_root * local.get_endpoint(i)
			if not started:
				box = AABB(point, Vector3.ZERO)
				started = true
			else:
				box = box.expand(point)
	if not started:
		return
	root.position.y -= box.position.y

func _sync_clip(moving: bool, attacking: bool) -> void:
	if _lock > 0.0:
		return
	if _climbing and _climb_phase > 0:
		_play(MANTLE)
	elif attacking:
		_lock = 0.45
		_clip = ""
		_play("Hit")
	else:
		var want := "Walk" if moving else "Idle"
		if _walk_hold > 0.0 and _is_loop(_clip) and want.to_lower() not in _clip.to_lower():
			return
		var before := _clip
		_play(want)
		if _clip != before:
			_walk_hold = 0.3

func _is_loop(clip: String) -> bool:
	var lower := clip.to_lower()
	return "walk" in lower or "idle" in lower

func _voice(stream: AudioStream, db: float) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = db
	player.pitch_scale = randf_range(0.92, 1.08)
	player.max_distance = 18.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _play(clip: String) -> void:
	if _anim == null:
		return
	var resolved := ""
	if _anim.has_animation(clip):
		resolved = clip
	else:
		for name in _anim.get_animation_list():
			if clip.to_lower() in String(name).to_lower():
				resolved = String(name)
				break
	if resolved == "" or (_clip == resolved and _anim.is_playing()):
		return
	_clip = resolved
	var looping := _is_loop(clip)
	var animation := _anim.get_animation(resolved)
	if animation:
		animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	_anim.play(resolved, 0.2 if looping or clip == MANTLE else 0.08)

func _squash(on: bool) -> void:
	if _model == null:
		return
	if on:
		_model.scale = Vector3(1.0, 0.62, 1.1)
		_model.rotation = Vector3(-0.55, PI, 0.0)
	else:
		_model.scale = Vector3.ONE
		_model.rotation = Vector3(0.0, PI, 0.0)

func _ink(node: Node) -> void:
	for child in node.get_children():
		_ink(child)
	if not node is MeshInstance3D:
		return
	var mesh_inst := node as MeshInstance3D
	if mesh_inst.mesh == null:
		return
	mesh_inst.material_override = null
	for surface in mesh_inst.mesh.get_surface_count():
		var flat := StandardMaterial3D.new()
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var source := mesh_inst.get_active_material(surface)
		if source is BaseMaterial3D:
			var base := source as BaseMaterial3D
			flat.albedo_color = base.albedo_color
			flat.albedo_texture = base.albedo_texture
			flat.vertex_color_use_as_albedo = base.vertex_color_use_as_albedo
			if _suit_name != "navy" and _is_suit(base):
				flat.albedo_texture = null
				flat.albedo_color = _suit_color()
		mesh_inst.set_surface_override_material(surface, flat)

func _is_suit(mat: BaseMaterial3D) -> bool:
	return "suit" in String(mat.resource_name).to_lower()

func _suit_color() -> Color:
	match _suit_name:
		"grey":
			return Color(0.46, 0.47, 0.5)
		"black":
			return Color(0.07, 0.07, 0.08)
		"purple":
			return Color(0.42, 0.16, 0.58)
	return Color(0.12, 0.16, 0.32)

func _paint() -> void:
	var color := Color(0.82, 0.68, 0.2)
	match archetype:
		"broker":
			color = Color(0.15, 0.28, 0.55)
		"king":
			color = Color(0.48, 0.18, 0.55)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	$Mesh.material_override = mat
