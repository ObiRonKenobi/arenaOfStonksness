extends CharacterBody3D

signal died

const HIT_SFX := preload("res://assets/audio/body_hit.wav")
const MOAN_SFX := preload("res://assets/audio/horde_moan.wav")
const LINE_PATHS := [
	"res://assets/audio/just_business.mp3",
	"res://assets/audio/on_the_list.mp3",
	"res://assets/audio/dont_make_schedule.mp3",
	"res://assets/audio/couldve_been_email.mp3",
	"res://assets/audio/q3_optimization.mp3",
	"res://assets/audio/clear_memo.mp3",
	"res://assets/audio/feedback_noted.mp3",
	"res://assets/audio/relocation.mp3",
	"res://assets/audio/we_are_helping.mp3",
]
const KING_LINE_PATHS := [
	"res://assets/audio/my_father.mp3",
	"res://assets/audio/jewish_lawyer.mp3",
	"res://assets/audio/someone_handle.mp3",
	"res://assets/audio/paid_for.mp3",
	"res://assets/audio/life_valuation.mp3",
	"res://assets/audio/tax_bracket.mp3",
	"res://assets/audio/im_telling.mp3",
	"res://assets/audio/hate_stairs.mp3",
	"res://assets/audio/expensive_outfit.mp3",
]
const GRAVITY := 20.0
const STEP_HEIGHT := 0.45
const DEATH_TIME := 1.7
const SWING := 0.7
const IMPACT := 0.38
const REACH := 1.15
const STRIKE_HEIGHT := 1.4
const TURN_RATE := 8.0
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
var _stuck := 0.0
var _lane_flip := false
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
var _walk_hold := 0.0
var _agent: NavigationAgent3D
var _safe := Vector3.ZERO
var _goal := Vector3(9999.0, 9999.0, 9999.0)
var _goal_wait := 0.0
var _goal_force := true
var _hold_t := 0.0
var _slow_t := 0.0
var _wall_t := 0.0
var _did_repath := false
var wall_stuck_max := 0.0
var snaps := 0
var _stair_lane := -1
var _stair_up := false
var _stair_leg := 0
var _window_lane := -1
var _claim_wait := 0.0
var _at_lip := false
var _lane_let_go := false
var _land_at := Vector3.ZERO
var _no_progress := 0
var _progress_t := 0.0
var _progress_dist := 0.0
var _progress_moved := 0.0
var _progress_seen := false
var _detour_left := 0.0
var _detour_at := Vector3.ZERO
var _no_lane_t := 0.0
var _ahead_shape: SphereShape3D
var _chase_at := Vector3(9999, 9999, 9999)
var _chase_wait := 0.0
var _line_wait := 0.0
var _line_busy := false
var _line_recent: Array[int] = []
var _lines: Array[AudioStream] = []
var _line_voice: AudioStreamPlayer3D

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 19
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	_wander_phase = randf() * TAU
	_goal_wait = randf() * 0.3
	_ahead_shape = SphereShape3D.new()
	_ahead_shape.radius = 0.4
	_agent = NavigationAgent3D.new()
	_agent.radius = 0.34
	_agent.height = 1.8
	_agent.path_desired_distance = 0.2
	_agent.target_desired_distance = 0.35
	_agent.path_max_distance = 0.8
	_agent.avoidance_enabled = true
	_agent.neighbor_distance = 3.0
	_agent.max_neighbors = 8
	_agent.time_horizon_agents = 0.8
	_agent.max_speed = 2.4
	_agent.avoidance_priority = 0.5
	add_child(_agent)
	_agent.velocity_computed.connect(_on_safe_velocity)
	_line_wait = randf_range(1.5, 4.0)

func setup(kind: String, health: float, move_speed: float, door: Node3D) -> void:
	archetype = kind
	hp = health
	speed = move_speed
	_door = door
	if _agent:
		_agent.max_speed = move_speed * 1.1
	match kind:
		"broker":
			attack = 7.0
			_suit_name = _pick_suit()
		"king":
			attack = 16.0
	_load_lines(KING_LINE_PATHS if kind == "king" else LINE_PATHS)
	_wear_model()
	_voice(MOAN_SFX, -10.0)

func _on_safe_velocity(safe_velocity: Vector3) -> void:
	_safe = safe_velocity

func _physics_process(delta: float) -> void:
	if _dead:
		_death_t -= delta
		_settle_corpse()
		if _death_t <= 0.0:
			queue_free()
		return
	_tick_line(delta)
	_cool = maxf(0.0, _cool - delta)
	_lock = maxf(0.0, _lock - delta)
	_walk_hold = maxf(0.0, _walk_hold - delta)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var slow := 1.0
	if player and player.has_method("market_crash_active") and player.call("market_crash_active"):
		slow = 0.45
	if player and str(player.get("ult_active")) == "punk_f":
		slow = minf(slow, 0.7)
	_slow = slow
	if _climbing:
		_agent.avoidance_enabled = false
		_agent.velocity = Vector3.ZERO
		_climb_through_window(delta)
		return
	_agent.avoidance_enabled = true
	if _detour_left > 0.0:
		_detour_left = maxf(0.0, _detour_left - delta)
		if _detour_left <= 0.0:
			_goal_force = true
	if _swing_t >= 0.0:
		_swing_frame(player, delta)
		return
	var goal := _choose_goal(player)
	_push_goal(goal, delta)
	var at_lip := _act_at_lip(player)
	if _climbing:
		_agent.avoidance_enabled = false
		_agent.velocity = Vector3.ZERO
		_climb_through_window(delta)
		return
	var holding := _holding_player(player)
	if _hold_t > 0.0:
		_hold_t = maxf(0.0, _hold_t - delta)
	var want := Vector3.ZERO
	if not at_lip and not holding and _hold_t <= 0.0:
		want = _path_want(delta)
	if _door != null:
		_agent.avoidance_priority = 1.0 if _window_lane >= 0 else 0.1
	else:
		_agent.avoidance_priority = 1.0 if holding else 0.5
	_agent.velocity = want
	var applied := want
	if want.length() > 0.01 and _safe.length() > 0.01 and not _into_wall(_safe):
		applied = _safe
	velocity.x = applied.x
	velocity.z = applied.z
	var in_reach := player != null and _door == null and not _floor_apart(player) and _flat_to(player.global_position) <= REACH
	if at_lip:
		_turn_toward(-_door_out(), delta)
	elif in_reach:
		_turn_toward(player.global_position - global_position, delta)
		if _in_strike(player):
			_face_now(player)
			_begin_swing()
	elif Vector2(velocity.x, velocity.z).length() > 0.15:
		_turn_toward(Vector3(velocity.x, 0.0, velocity.z), delta)
	_sync_clip(Vector2(velocity.x, velocity.z).length() > 0.25, false)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -1.0
	var before := global_position
	move_and_slide()
	_shove_out()
	_after_move(want, before, delta)

func _swing_frame(player: Node3D, delta: float) -> void:
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
	_agent.avoidance_priority = 1.0
	_agent.velocity = Vector3.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	if _at_window_lip():
		_turn_toward(-_door_out(), delta)
	elif player:
		_turn_toward(player.global_position - global_position, delta)
	_sync_clip(false, not boarding)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -1.0
	move_and_slide()

func _choose_goal(player: Node3D) -> Vector3:
	if _detour_left > 0.0:
		return _detour_at
	if _door != null:
		return _window_goal()
	if player == null:
		return global_position
	var map := _map()
	if map == null:
		return player.global_position
	return _stair_goal(player, map)

func _stair_goal(player: Node3D, map: Node) -> Vector3:
	var need: bool = map.call("needs_stairs", global_position, player.global_position)
	var going_up := int(map.call("floor_level", player.global_position)) > int(map.call("floor_level", global_position))
	var on_ramp: bool = map.call("on_ramp", global_position)
	var split := _stair_up and player.global_position.x < 5.5
	var still_climbing := _stair_up and _stair_leg > 0 and _stair_leg <= 2 and not _past_stairs()
	if _stair_lane >= 0 and not on_ramp and not split and not still_climbing and (not need or going_up != _stair_up):
		_stair_lane = -1
		_stair_leg = 0
		_goal_force = true
	if need and _stair_lane < 0:
		_stair_lane = _pick_stair_lane(map)
		_stair_up = going_up
		_stair_leg = 1
		_goal_force = true
	if _stair_lane < 0:
		return _chase_goal(player)
	var entry: Vector3 = map.call("stair_entry", _stair_lane, _stair_up)
	var exit: Vector3 = map.call("stair_exit", _stair_lane, _stair_up)
	if _stair_leg <= 1:
		if _flat_to(entry) <= 0.5 or on_ramp:
			_stair_leg = 2
			_goal_force = true
		else:
			return entry
	if _stair_leg <= 2:
		if _flat_to(exit) <= 0.6 or (not split and _past_stairs()):
			if not split:
				_stair_lane = -1
				_stair_leg = 0
				_goal_force = true
				return _chase_goal(player)
			_stair_leg = 3
			_goal_force = true
		else:
			return exit
	if _stair_leg == 3:
		var through: Vector3 = map.call("stair_through", _stair_lane)
		if _flat_to(through) <= 0.6:
			_stair_leg = 4
			_goal_force = true
		else:
			return through
	var clear: Vector3 = map.call("stair_clear", _stair_lane)
	if _flat_to(clear) <= 0.6:
		_stair_lane = -1
		_stair_leg = 0
		_goal_force = true
		return _chase_goal(player)
	return clear

func _chase_goal(player: Node3D) -> Vector3:
	var flat := global_position - player.global_position
	flat.y = 0.0
	var dist := flat.length()
	if dist > 2.2 or dist < 0.2:
		return player.global_position
	var base := atan2(flat.x, flat.z)
	var spread := (float(int(get_instance_id()) % 5) - 2.0) * 0.35
	var angle := base + spread
	return player.global_position + Vector3(sin(angle), 0.0, cos(angle)) * 0.8

func _pick_stair_lane(map: Node) -> int:
	var counts: Array[int] = [0, 0, 0]
	for other in get_tree().get_nodes_in_group("enemies"):
		var body := other as Node
		if body == null or body == self:
			continue
		var lane := int(body.get("_stair_lane"))
		if lane >= 0 and lane < 3:
			counts[lane] += 1
	var best := 0
	var best_count: int = counts[0]
	var best_dist := absf(float(map.call("lane_x", 0)) - global_position.x)
	for i in 3:
		var dist := absf(float(map.call("lane_x", i)) - global_position.x)
		if counts[i] < best_count or (counts[i] == best_count and dist < best_dist):
			best = i
			best_count = counts[i]
			best_dist = dist
	return best

func _past_stairs() -> bool:
	if _stair_up:
		return global_position.y >= 3.0 and global_position.z <= -2.2
	return global_position.y <= 0.15 and global_position.z >= 2.2

func _window_goal() -> Vector3:
	var lane := int(_door.call("lane_of", self))
	if lane < 0:
		_claim_wait -= get_physics_process_delta_time()
		if _claim_wait <= 0.0:
			_claim_wait = 0.2
			lane = int(_door.call("claim_lane", self))
		if lane < 0:
			_at_lip = false
			_window_lane = -1
			return _nearer_wait()
		_goal_force = true
	_window_lane = lane
	var lip: Vector3 = _door.call("lip", lane)
	_at_lip = _flat_to(lip) <= 0.6
	return lip

func _nearer_wait() -> Vector3:
	var best: Vector3 = _door.call("wait_spot", 0)
	var best_d := _flat_to(best)
	var other: Vector3 = _door.call("wait_spot", 1)
	if _flat_to(other) < best_d:
		return other
	return best

func _act_at_lip(player: Node3D) -> bool:
	if _door == null or not _at_lip or _window_lane < 0:
		return false
	var boards := int(_door.get("boards"))
	if boards > 0:
		_begin_swing(true)
	elif _landing_clear(_window_lane, player):
		_begin_climb()
	elif player and _player_blocks_landing(_window_lane, player) and _flat_to(player.global_position) <= 1.6 and not _floor_apart(player):
		_begin_swing(false)
	return true

func _landing_clear(lane: int, _player: Node3D) -> bool:
	for other in get_tree().get_nodes_in_group("enemies"):
		var body := other as CharacterBody3D
		if body == null or body == self or body._dead:
			continue
		if body._climbing and body._window_lane == lane and body._door == _door:
			return false
	return true

func _player_blocks_landing(lane: int, player: Node3D) -> bool:
	var spot: Vector3 = _door.call("landing", lane)
	var flat := player.global_position - spot
	flat.y = 0.0
	return flat.length() <= 0.8

func _begin_climb() -> void:
	if _climbing or _door == null:
		return
	_climbing = true
	_climb_phase = 1
	_climb_t = 0.0
	_climb_from = global_position
	_land_at = _pick_land_at(_window_lane)
	_lane_let_go = false
	_clip = ""
	collision_layer = 0
	collision_mask = 0
	floor_snap_length = 0.0
	velocity = Vector3.ZERO
	_agent.avoidance_enabled = false
	_agent.velocity = Vector3.ZERO

func _holding_player(player: Node3D) -> bool:
	if player == null or _door != null:
		return false
	var map := _map()
	if map == null:
		return false
	if int(map.call("floor_level", player.global_position)) != int(map.call("floor_level", global_position)):
		return false
	return _flat_to(player.global_position) <= 0.72

func _path_want(delta: float) -> Vector3:
	var next := _agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return Vector3.ZERO
	return dir.normalized() * speed * _slow * _speed_lurch(delta)

func _speed_lurch(delta: float) -> float:
	_wander_phase += delta * 1.35
	var map := _map()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	# The north landing is where a crowd has to arrive as a wall. Shuffling loses that race.
	if map and player and bool(map.call("on_ramp", global_position)) and player.global_position.x > 5.5 and player.global_position.z < -2.2:
		return 1.0
	var fade := clampf(1.15 - float(GameState.round_index - 1) * 0.035, 0.12, 1.0)
	return lerpf(1.0, 0.72 + 0.28 * absf(sin(_wander_phase * 0.7)), fade)

func _push_goal(goal: Vector3, delta: float) -> void:
	_goal_wait -= delta
	var jumped := _goal_force or goal.distance_to(_goal) >= 0.5
	if not jumped and _goal_wait > 0.0:
		return
	_goal_force = false
	_goal_wait = 0.3
	_goal = goal
	var snapped := goal
	var rid := _agent.get_navigation_map()
	if rid.is_valid():
		var closest := NavigationServer3D.map_get_closest_point(rid, goal)
		if closest.distance_to(goal) <= 1.5:
			snapped = closest
	_agent.target_position = snapped

func _after_move(want: Vector3, before: Vector3, delta: float) -> void:
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	var wanted := Vector2(want.x, want.z).length() * delta
	var heading := Vector3(want.x, 0.0, want.z)
	var on_ramp := false
	var map := _map()
	if map:
		on_ramp = bool(map.call("on_ramp", global_position))
	if not on_ramp and wanted >= 0.5 * delta and moved < wanted * 0.25 and _body_ahead(heading):
		_slow_t += delta
	else:
		_slow_t = 0.0
	if _slow_t >= 0.5:
		_slow_t = 0.0
		_hold_t = 0.5
	if wanted >= 0.5 * delta and moved < wanted * 0.25 and not _body_ahead(heading):
		_wall_t += delta
		wall_stuck_max = maxf(wall_stuck_max, _wall_t)
	else:
		_wall_t = 0.0
	if _wall_t >= 0.3 and heading.length_squared() > 0.01:
		var side := Vector3(-heading.z, 0.0, heading.x).normalized()
		if _into_wall(side):
			side = -side
		global_position += side * 0.35
		_wall_t = 0.0
		_force_repath()
	if _door != null and _window_lane < 0 and not _queued_at_window():
		_no_lane_t += delta
	else:
		_no_lane_t = 0.0
	_progress_moved += moved
	if _detour_left > 0.0:
		return
	_progress_t += delta
	if _progress_t < 1.0:
		return
	_progress_t = 0.0
	var dist := _flat_to(_goal)
	var moving := heading.length() > 0.05
	var blocked := moving and _body_ahead(heading)
	var failed := false
	var gained := _progress_dist - dist
	if _progress_seen and moving and not blocked and gained < 0.3 and _progress_moved < 0.35:
		_no_progress += 1
		failed = true
	elif moving and (blocked or gained >= 0.3 or _progress_moved >= 0.35):
		_no_progress = 0
	_progress_moved = 0.0
	_progress_seen = true
	_progress_dist = dist
	if failed or _no_lane_t > 6.0:
		_react_to_stall(heading)

func _body_ahead(dir: Vector3) -> bool:
	if dir.length_squared() < 0.0001:
		return false
	var heading := dir.normalized()
	for i in get_slide_collision_count():
		var other: Object = get_slide_collision(i).get_collider()
		if other is Node:
			var node := other as Node
			if node.is_in_group("enemies") or node.is_in_group("player"):
				return true
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var to := player.global_position - global_position
		to.y = 0.0
		if to.length() <= 1.5 and to.length() > 0.001 and to.normalized().dot(heading) > 0.5:
			return true
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _ahead_shape
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, 0.7, 0.0) + heading * 0.9)
	query.collision_mask = 2
	query.exclude = [get_rid()]
	return not space.intersect_shape(query, 1).is_empty()

func _force_repath() -> void:
	var target := _agent.target_position
	_agent.target_position = target + Vector3(0.02, 0.0, 0.0)
	_agent.target_position = target

func _snap_to_nav() -> void:
	var rid := _agent.get_navigation_map()
	if rid.is_valid():
		var closest := NavigationServer3D.map_get_closest_point(rid, global_position)
		if absf(closest.y - global_position.y) <= 0.75:
			global_position = closest
	_agent.set_velocity_forced(Vector3.ZERO)
	snaps += 1
	_wall_t = 0.0
	_did_repath = false
	_force_repath()

func _shove_out() -> void:
	var space := get_world_3d().direct_space_state
	var shape := _ahead_shape
	var old := shape.radius
	shape.radius = 0.32
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, 0.7, 0.0))
	query.collision_mask = 17
	query.exclude = [get_rid()]
	var hits := space.intersect_shape(query, 1)
	shape.radius = old
	if hits.is_empty():
		return
	var other: Object = hits[0].collider
	if not other is Node3D:
		return
	var away := global_position - (other as Node3D).global_position
	away.y = 0.0
	if away.length() < 0.05 or away.length() > 2.0:
		return
	global_position += away.normalized() * 0.06

func _into_wall(vel: Vector3) -> bool:
	var flat := Vector3(vel.x, 0.0, vel.z)
	if flat.length_squared() < 0.0001:
		return false
	var dir := flat.normalized()
	var from := global_position + Vector3(0.0, 0.55, 0.0)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 0.36)
	query.collision_mask = 17
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	return (hit.normal as Vector3).y < 0.5

func _map() -> Node:
	return get_tree().get_first_node_in_group("map")

func _flat_to(point: Vector3) -> float:
	var flat := point - global_position
	flat.y = 0.0
	return flat.length()

func _window_side() -> Vector3:
	var out := _door_out()
	var side := Vector3(-out.z, 0.0, out.x)
	if side.length_squared() < 0.0001:
		return Vector3.RIGHT
	return side.normalized()

func _lane_shift(lane: int) -> float:
	return -0.37 if lane <= 0 else 0.37

func _at_window_lip() -> bool:
	return _at_lip and _door != null and _window_lane >= 0


func _floor_apart(player: Node3D) -> bool:
	return absf(player.global_position.y - global_position.y) > STRIKE_HEIGHT

func _turn_toward(dir: Vector3, delta: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	rotation.y = rotate_toward(rotation.y, atan2(-dir.x, -dir.z), TURN_RATE * delta)

func _face_now(player: Node3D) -> void:
	var dir := player.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	rotation.y = atan2(-dir.x, -dir.z)

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
		if source.has_method("note_kill"):
			source.call("note_kill", headshot)
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

func _climb_through_window(delta: float) -> void:
	var mesh_node := $Mesh as Node3D
	var out := _door_out()
	_climb_t += delta
	_play(MANTLE)
	var blend := clampf(_climb_t / _climb_length(), 0.0, 1.0)
	if blend >= 0.6 and not _lane_let_go:
		_lane_let_go = true
		_release_lane()
	global_position = _mantle_root(blend, out, float(_door.get("sill_top")))
	if blend > 0.85:
		var w := clampf((blend - 0.85) / 0.15, 0.0, 1.0)
		var blended := global_position.lerp(_land_at, w)
		blended.y = global_position.y
		global_position = blended
	if out.length_squared() > 0.0001:
		look_at(global_position - out, Vector3.UP)
	if blend < 1.0:
		return
	_climbing = false
	_climb_phase = 0
	_lane_let_go = false
	collision_layer = 2
	collision_mask = 19
	floor_snap_length = 0.45
	velocity = Vector3.ZERO
	_agent.avoidance_enabled = true
	_agent.set_velocity_forced(Vector3.ZERO)
	_release_lane()
	_door = null
	_window_lane = -1
	_at_lip = false
	_no_progress = 0
	_progress_seen = false
	_no_lane_t = 0.0
	_goal_force = true
	if _model:
		_model.rotation = Vector3(0.0, PI, 0.0)
	mesh_node.scale = Vector3.ONE
	mesh_node.rotation = Vector3.ZERO
	_sync_clip(true, false)

func _release_lane() -> void:
	if _door and is_instance_valid(_door) and _door.has_method("release_lane"):
		_door.call("release_lane", self)

func _pick_land_at(lane: int) -> Vector3:
	var spot: Vector3 = _door.call("landing", lane)
	var into := -_door_out()
	var side := _window_side()
	var options: Array[Vector3] = [
		spot,
		spot + into * 0.7,
		spot + side * 0.9,
		spot - side * 0.9,
	]
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return options[0]
	var best: Vector3 = options[0]
	var best_d := -1.0
	for option in options:
		var flat := player.global_position - option
		flat.y = 0.0
		var dist := flat.length()
		if dist >= 0.8:
			return option
		if dist > best_d:
			best = option
			best_d = dist
	return best

func _queued_at_window() -> bool:
	if _door == null:
		return false
	var lip_a: Vector3 = _door.call("lip", 0)
	var lip_b: Vector3 = _door.call("lip", 1)
	return minf(_flat_to(lip_a), _flat_to(lip_b)) <= 2.6

func _react_to_stall(heading: Vector3) -> void:
	if _door != null:
		if _queued_at_window() and int(_door.get("boards")) == 0:
			return
		if _no_progress >= 3 or _no_lane_t > 6.0:
			_switch_window()
			_no_progress = 0
			_progress_seen = false
			_no_lane_t = 0.0
		return
	var map := _map()
	if map and bool(map.call("on_ramp", global_position)):
		return
	if _no_progress >= 6:
		_snap_to_nav()
		_no_progress = 0
		_progress_seen = false
		return
	if _no_progress >= 2:
		_start_detour(heading)

func _start_detour(heading: Vector3) -> void:
	var rid := _agent.get_navigation_map()
	if not rid.is_valid():
		return
	var forward := Vector3(heading.x, 0.0, heading.z)
	if forward.length_squared() < 0.0001:
		forward = -global_transform.basis.z
		forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var map := _map()
	var here_level := int(map.call("floor_level", global_position)) if map else 0
	for _i in 6:
		var point := NavigationServer3D.map_get_random_point(rid, 1, false)
		if _detour_ok(point, forward, map, here_level):
			_detour_at = point
			_detour_left = 1.5
			_goal_force = true
			return
	var closest := NavigationServer3D.map_get_closest_point(rid, global_position - forward * 3.5)
	if _detour_ok(closest, forward, map, here_level):
		_detour_at = closest
		_detour_left = 1.5
		_goal_force = true

func _detour_ok(point: Vector3, forward: Vector3, map: Node, here_level: int) -> bool:
	if map and int(map.call("floor_level", point)) != here_level:
		return false
	if point.y < global_position.y - 0.6:
		return false
	var to := point - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 3.0 or dist > 4.0:
		return false
	return to.normalized().dot(forward) < 0.0

func _switch_window() -> void:
	_release_lane()
	var nearest: Node3D = null
	var nearest_d := 9999.0
	var open_door: Node3D = null
	var open_d := 9999.0
	for node in get_tree().get_nodes_in_group("barricades"):
		var door := node as Node3D
		if door == null or door == _door:
			continue
		var dist := _flat_to(door.global_position)
		if dist < nearest_d:
			nearest = door
			nearest_d = dist
		if int(door.get("boards")) == 0 and dist < open_d:
			open_door = door
			open_d = dist
	var pick := open_door if open_door != null else nearest
	if pick == null:
		return
	_door = pick
	_window_lane = -1
	_at_lip = false
	_goal_force = true

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
	if at_boards and _walk_hold > 0.0 and _is_loop(_clip):
		return
	_board_swing = at_boards
	_swing_t = 0.0
	_cool = SWING if at_boards else SWING + 0.15
	_sync_clip(false, true)
	_lock = SWING

func _land_board() -> void:
	if not _at_boards():
		return
	_cool = 1.5
	_door.call("chip", 1)

func _at_boards() -> bool:
	if _door == null or int(_door.get("boards")) <= 0 or _window_lane < 0:
		return false
	var lip: Vector3 = _door.call("lip", _window_lane)
	return _flat_to(lip) < 0.7

func _land_hit(player: Node3D) -> void:
	if player == null:
		return
	if _at_window_lip() and _flat_to(player.global_position) <= 1.6 and not _floor_apart(player):
		player.call("take_damage", attack)
		return
	if not _in_strike(player):
		return
	player.call("take_damage", attack)

func _in_strike(player: Node3D) -> bool:
	if _floor_apart(player):
		return false
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

func _climb_length() -> float:
	if _anim and _anim.has_animation(MANTLE):
		return MANTLE_TIME
	return 1.15

func _mantle_root(blend: float, out: Vector3, sill: float) -> Vector3:
	var shift := Vector3.ZERO
	if _window_lane >= 0:
		shift = _window_side() * _lane_shift(_window_lane)
	var spots: Array[Vector3] = []
	var times: Array[float] = []
	for key in MANTLE_KEYS:
		times.append(float(key.t))
		if key.has("at"):
			var at: Vector2 = key.at
			var spot := _door.global_position - out * at.y + shift
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

func _die() -> void:
	if _dead:
		return
	_dead = true
	_death_t = DEATH_TIME
	_release_lane()
	_stair_lane = -1
	_silence_line()
	_scream()
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

func _tick_line(delta: float) -> void:
	if _line_busy or _lines.is_empty():
		return
	_line_wait -= delta
	if _line_wait > 0.0:
		return
	_say(_pick_line())

func _pick_line() -> AudioStream:
	var choices: Array[int] = []
	for i in _lines.size():
		if _line_recent.size() >= 2 and i in _line_recent:
			continue
		if _line_recent.size() == 1 and i == _line_recent[0] and _lines.size() > 1:
			continue
		choices.append(i)
	if choices.is_empty():
		for i in _lines.size():
			choices.append(i)
	var pick: int = choices[randi() % choices.size()]
	_line_recent.append(pick)
	while _line_recent.size() > 2:
		_line_recent.pop_front()
	return _lines[pick]

func _say(stream: AudioStream) -> void:
	_line_busy = true
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = -0.25
	player.pitch_scale = 1.0
	_hear_from_body(player)
	player.unit_size = 6.0
	add_child(player)
	player.finished.connect(_line_finished.bind(player))
	_line_voice = player
	player.play()

const DEATH_PATHS := [
	"res://assets/audio/death_scream.mp3",
	"res://assets/audio/death_doom.mp3",
	"res://assets/audio/death_possessed.wav",
	"res://assets/audio/death_shocktrooper.wav",
]

func _scream() -> void:
	var stream := load(DEATH_PATHS[randi() % DEATH_PATHS.size()]) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = -2.5
	player.pitch_scale = 1.0
	_hear_from_body(player)
	var host := get_parent()
	if host == null:
		return
	host.add_child(player)
	player.global_position = global_position
	player.finished.connect(player.queue_free)
	player.play()

func _silence_line() -> void:
	_line_busy = false
	if _line_voice == null or not is_instance_valid(_line_voice):
		_line_voice = null
		return
	_line_voice.stop()
	_line_voice.queue_free()
	_line_voice = null

func _line_finished(player: AudioStreamPlayer3D) -> void:
	if player == _line_voice:
		_line_voice = null
		_line_busy = false
		_line_wait = randf_range(2.5, 6.0)
	if is_instance_valid(player):
		player.queue_free()

func _load_lines(paths: Array) -> void:
	_lines.clear()
	for path in paths:
		var stream := load(str(path)) as AudioStream
		if stream:
			_lines.append(stream)

func _voice(stream: AudioStream, db: float, pitch_lo: float = 0.92, pitch_hi: float = 1.08) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = db
	player.pitch_scale = randf_range(pitch_lo, pitch_hi)
	_hear_from_body(player)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _hear_from_body(player: AudioStreamPlayer3D) -> void:
	player.unit_size = 2.0
	player.max_distance = 24.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE

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
