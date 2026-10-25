extends CharacterBody3D

signal died

const HIT_SFX := preload("res://assets/audio/body_hit.wav")
const MOAN_SFX := preload("res://assets/audio/horde_moan.wav")
const GRAVITY := 20.0
const STEP_HEIGHT := 0.45
const DEATH_TIME := 1.7
var archetype := "collector"
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
var _model: Node3D
var _anim: AnimationPlayer
var _clip := ""
var _lock := 0.0
var _death_t := 0.0
var _corpse_floor := 0.0
var _wander_phase := 0.0

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 3
	floor_snap_length = 0.45
	_wander_phase = randf() * TAU

func setup(kind: String, health: float, move_speed: float, door: Node3D) -> void:
	archetype = kind
	hp = health
	speed = move_speed
	_door = door
	match kind:
		"broker":
			attack = 7.0
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
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var slow := 1.0
	if player and player.has_method("market_crash_active") and player.call("market_crash_active"):
		slow = 0.45
	if player and str(player.get("ult_active")) == "dreads":
		slow = minf(slow, 0.7)
	_slow = slow
	if _door and (int(_door.get("boards")) <= 0) and (_climbing or global_position.z < -6.85):
		_climb_through_window(delta)
		return
	var target := global_position
	var attacking_door := false
	if _door and int(_door.get("boards")) > 0:
		target = _window_approach()
		var flat := global_position - target
		flat.y = 0.0
		attacking_door = flat.length() < 1.15
	elif player:
		var upstairs := player.global_position.y > global_position.y + 1.2
		if upstairs:
			target = _stair_target()
		else:
			target = player.global_position
		if not upstairs and global_position.distance_to(player.global_position) < 1.35:
			_hit_player(player)
	if not attacking_door:
		var dir := target - global_position
		dir.y = 0.0
		var climbing_stairs := _on_stair_climb()
		if dir.length() > 0.15:
			var dist := dir.length()
			if climbing_stairs:
				dir = dir.normalized()
			else:
				dir = _weave(dir.normalized(), delta, dist)
			if _yield_to_horde(dir, target):
				velocity.x = 0.0
				velocity.z = 0.0
			else:
				velocity.x = dir.x * speed * _slow
				velocity.z = dir.z * speed * _slow
			look_at(global_position + dir, Vector3.UP)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_hit_door()
	_sync_clip(velocity.length() > 0.2, attacking_door)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -1.0
	var step := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	if step.length() > 0.2:
		_step_up(step)

func _weave(dir: Vector3, delta: float, dist: float) -> Vector3:
	_wander_phase += delta * 1.35
	var fade := clampf(1.15 - float(GameState.round_index - 1) * 0.035, 0.12, 1.0)
	var reach := clampf(dist / 2.8, 0.25, 1.0)
	var sway := sin(_wander_phase) * 0.9 * fade * reach
	var side := Vector3(-dir.z, 0.0, dir.x)
	var lurch := lerpf(1.0, 0.72 + 0.28 * absf(sin(_wander_phase * 0.7)), fade)
	return (dir + side * sway).normalized() * lurch

func _yield_to_horde(dir: Vector3, target: Vector3) -> bool:
	if dir.length() < 0.01:
		return false
	var heading := Vector3(dir.x, 0.0, dir.z).normalized()
	var my_rank := global_position.distance_squared_to(target)
	for other in get_tree().get_nodes_in_group("enemies"):
		var body := other as CharacterBody3D
		if body == null or body == self or body._dead:
			continue
		var offset := body.global_position - global_position
		offset.y = 0.0
		var dist := offset.length()
		if dist > 0.78 or dist < 0.001:
			continue
		if offset.dot(heading) <= 0.0:
			continue
		if body.global_position.distance_squared_to(target) < my_rank:
			return true
	return false

func take_damage(amount: float, source: Node, headshot: bool = false) -> void:
	if _dead:
		return
	var bonus := 0
	if source and str(source.get("ult_active")) == "hobo":
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
		source.call("add_ult", 8.0)
	_die()

func knockback(from: Vector3) -> void:
	if _dead:
		return
	var push := global_position - from
	push.y = 0.0
	if push.length() < 0.1:
		push = Vector3.FORWARD
	global_position += push.normalized() * 3.2
	hp -= 18.0
	if hp <= 0.0:
		_drop_cash(30)
		_die()

func _window_approach() -> Vector3:
	var spot := _door.global_position
	spot.y = 0.0
	spot.z -= 0.95
	return spot

func _climb_through_window(delta: float) -> void:
	var mesh_node := $Mesh as Node3D
	var sill := float(_door.get("sill_top"))
	var wx := _door.global_position.x
	if not _climbing:
		_climbing = true
		_climb_phase = 0
		_climb_t = 0.0
	if _climb_phase == 0:
		var lip := Vector3(wx, 0.0, -7.95)
		var dir := lip - global_position
		dir.y = 0.0
		if dir.length() > 0.22:
			dir = dir.normalized()
			if _yield_to_horde(dir, lip):
				velocity.x = 0.0
				velocity.z = 0.0
			else:
				velocity.x = dir.x * speed * _slow
				velocity.z = dir.z * speed * _slow
			look_at(global_position + Vector3(0, 0, 1), Vector3.UP)
			if is_on_floor():
				velocity.y = -1.0
			else:
				velocity.y -= GRAVITY * delta
			move_and_slide()
			_sync_clip(true, false)
			return
		_climb_phase = 1
		_climb_t = 0.0
		_climb_from = global_position
		collision_layer = 0
		collision_mask = 0
		floor_snap_length = 0.0
		velocity = Vector3.ZERO
	_climb_t += delta
	var duration := 0.85
	var blend := clampf(_climb_t / duration, 0.0, 1.0)
	var outside := _climb_from
	var sill_point := Vector3(wx, sill + 0.55, -7.05)
	var inside := Vector3(wx, 0.05, -5.75)
	var pos := _arc(outside, sill_point, inside, blend)
	var ahead := _arc(outside, sill_point, inside, minf(blend + 0.08, 1.0)) - pos
	global_position = pos
	look_at(global_position + Vector3(0, 0, 1), Vector3.UP)
	if _model:
		var pitch := 0.0
		if ahead.length() > 0.05:
			pitch = atan2(-ahead.y, Vector2(ahead.x, ahead.z).length())
		_model.rotation = Vector3(clampf(pitch, -0.35, 0.15), PI, 0.0)
	_play("Jump")
	if blend < 1.0:
		return
	_climbing = false
	_climb_phase = 0
	collision_layer = 2
	collision_mask = 3
	floor_snap_length = 0.45
	velocity = Vector3.ZERO
	if _model:
		_model.rotation = Vector3(0.0, PI, 0.0)
	mesh_node.scale = Vector3.ONE
	mesh_node.rotation = Vector3.ZERO
	_sync_clip(true, false)

func _hit_door() -> void:
	if _cool > 0.0 or _door == null:
		return
	_cool = 0.7
	_door.call("chip", 1)

func _hit_player(player: Node) -> void:
	if _cool > 0.0:
		return
	_cool = 0.85
	player.call("take_damage", attack)
	_sync_clip(false, true)

func _drop_cash(amount: int) -> void:
	var pickup := preload("res://scenes/cash_pickup.tscn").instantiate()
	pickup.amount = amount
	var parent := get_parent()
	if parent:
		parent.add_child(pickup)
		pickup.global_position = global_position + Vector3(0, 0.4, 0)

func _process(_delta: float) -> void:
	if _anim == null or _clip == "":
		return
	var looping := "walk" in _clip.to_lower() or "idle" in _clip.to_lower()
	if looping and not _anim.is_playing():
		_anim.play(_clip)

func _stair_target() -> Vector3:
	var base := get_tree().get_first_node_in_group("stairs") as Node3D
	var top := get_tree().get_first_node_in_group("stair_top") as Node3D
	if global_position.y < 0.5 and base and global_position.distance_to(base.global_position) > 1.15:
		return base.global_position
	if top and global_position.y < 2.7:
		return top.global_position
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		return player.global_position
	return global_position

func _on_stair_climb() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or player.global_position.y <= global_position.y + 1.2:
		return false
	return global_position.y < 2.7

func _arc(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * u * u + b * 2.0 * u * t + c * t * t

func _step_up(dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var feet := global_position + Vector3(0, 0.15, 0)
	var ahead := dir.normalized() * 0.4
	var low := PhysicsRayQueryParameters3D.create(feet, feet + ahead)
	low.exclude = [self]
	low.collision_mask = 1
	if space.intersect_ray(low).is_empty():
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
	var players: Array = _model.find_children("*", "AnimationPlayer", true, false)
	if players.size() > 0:
		_anim = players[0] as AnimationPlayer
	if "--smoke" in OS.get_cmdline_user_args() and _anim:
		print("ANIMS ", archetype, _anim.get_animation_list())
	_play("Idle")

func _sync_clip(moving: bool, attacking: bool) -> void:
	if _lock > 0.0:
		return
	if _climbing and _climb_phase > 0:
		_play("Climb")
	elif attacking:
		_lock = 0.45
		_clip = ""
		_play("Hit")
	elif moving:
		_play("Walk")
	else:
		_play("Idle")

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
	var animation := _anim.get_animation(resolved)
	if animation:
		if "walk" in clip.to_lower() or "idle" in clip.to_lower() or "climb" in clip.to_lower():
			animation.loop_mode = Animation.LOOP_LINEAR
		else:
			animation.loop_mode = Animation.LOOP_NONE
	_anim.play(resolved)

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
		mesh_inst.set_surface_override_material(surface, flat)

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
