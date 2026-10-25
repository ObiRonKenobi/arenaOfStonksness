extends CharacterBody3D

signal health_changed(current: float, maximum: float)
signal ammo_changed
signal cash_changed(amount: int)
signal ult_changed(amount: float)
signal weapon_changed

const SPEED := 5.6
const HIP_FOV := 75.0
const ADS_FOV := 60.0
const HIP_GUN := Vector3(0.24, -0.2, -0.42)
const ADS_GUN := Vector3(0.0, -0.11, -0.5)
const RELOAD_GUN := Vector3(0.1, -0.42, -0.32)
const SHOTS := {
	"pipe_pistol": preload("res://assets/audio/shot_9mm.wav"),
	"street_smg": preload("res://assets/audio/shot_9mm.wav"),
	"pop_junk": preload("res://assets/audio/shot_22.wav"),
	"debt_shotgun": preload("res://assets/audio/shot_20g.wav"),
	"rent_rifle": preload("res://assets/audio/shot_556.wav"),
}
const RELOAD_SFX := preload("res://assets/audio/reload_ak.wav")
const SHOT_HEAVY := preload("res://assets/audio/shot_deagle.wav")
const MOUSE_SENS := 0.0022
const GRAVITY := 20.0
const JUMP_SPEED := 6.2
const STEP_HEIGHT := 0.45

var health := 100.0
var max_health := 100.0
var cash := 500
var planks := 12
var weapon_id := "pipe_pistol"
var weapon_tier := 1
var smith_damage := 0
var smith_rate := 0
var smith_ammo := 0
var mag := 0
var offhand_mag := 0
var reserve := 0
var _slots: Array[Dictionary] = []
var _slot := 0
var perks: Array[String] = []
var ult := 0.0
var ult_active := ""
var ult_time := 0.0
var _nap_invuln := false
var _fire_cd := 0.0
var _reload := 0.0
var _bleed := 0.0
var _downed := false
var yaw := 0.0
var pitch := 0.0
var _gun_mount: Node3D
var _aim := 0.0
var _gunshot: AudioStreamPlayer
var _reload_sfx: AudioStreamPlayer
var _view_anims: Array[AnimationPlayer] = []
var _offhand_anims: Array[AnimationPlayer] = []
var _fire_clip := ""
var _reload_clip := ""
var _burst_left := 0
var _burst_side := 0
var _burst_gap := 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var mesh: MeshInstance3D = $Mesh

func _ready() -> void:
	add_to_group("player")
	collision_mask = 5
	floor_snap_length = 0.4
	_ensure_inputs()
	_build_viewmodel()
	_gunshot = AudioStreamPlayer.new()
	_gunshot.volume_db = -4.0
	add_child(_gunshot)
	_reload_sfx = AudioStreamPlayer.new()
	_reload_sfx.stream = RELOAD_SFX
	_reload_sfx.volume_db = -6.0
	add_child(_reload_sfx)
	weapon_changed.connect(_show_gun)
	_slots = [_empty_slot(), _empty_slot()]
	_load_weapon("pipe_pistol", 1, true)
	_store_slot()
	GameState.character_assigned.connect(_on_character)
	health_changed.emit(health, max_health)
	cash_changed.emit(cash)
	ult_changed.emit(ult)

func _unhandled_input(event: InputEvent) -> void:
	if not GameState.running or _downed:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * MOUSE_SENS
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENS, deg_to_rad(-80), deg_to_rad(80))
		rotation.y = yaw
		head.rotation.x = pitch
	elif event.is_action_pressed("shoot"):
		_pull_trigger(0)
	elif event.is_action_pressed("aim") and _akimbo():
		_pull_trigger(1)
	elif event.is_action_pressed("reload"):
		_start_reload()
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("ult"):
		_try_ult()
	elif event.is_action_pressed("weapon_1"):
		_switch_slot(0)
	elif event.is_action_pressed("weapon_2"):
		_switch_slot(1)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var wheel := (event as InputEventMouseButton).button_index
		if wheel == MOUSE_BUTTON_WHEEL_UP or wheel == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_weapon()

func _physics_process(delta: float) -> void:
	if not GameState.running:
		return
	if _downed:
		_bleed -= delta
		if _bleed <= 0.0:
			GameState.fail()
		return
	_tick_ult(delta)
	if _reload > 0.0:
		_reload -= delta
		if _reload <= 0.0:
			_finish_reload()
	if _fire_cd > 0.0:
		_fire_cd -= delta
	_tick_burst(delta)
	if _full_auto() and Input.is_action_pressed("shoot"):
		_fire_one(0)
	elif _uses_burst() and _burst_left <= 0 and _fire_cd <= 0.0:
		if Input.is_action_pressed("shoot"):
			_pull_trigger(0)
		elif _akimbo() and Input.is_action_pressed("aim"):
			_pull_trigger(1)
	_hold_idle()
	var wish := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		wish -= transform.basis.z
	if Input.is_action_pressed("move_back"):
		wish += transform.basis.z
	if Input.is_action_pressed("move_left"):
		wish -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		wish += transform.basis.x
	wish.y = 0.0
	if wish.length() > 0.01:
		wish = wish.normalized()
	var aiming := Input.is_action_pressed("aim") and _reload <= 0.0 and not _akimbo()
	_aim = move_toward(_aim, 1.0 if aiming else 0.0, delta * 7.0)
	if _gun_mount:
		var hip := Vector3(0.0, -0.18, -0.42) if _akimbo() else HIP_GUN
		var held := hip if _akimbo() else hip.lerp(ADS_GUN, _aim)
		var reloading := 0.0
		if _reload > 0.0:
			reloading = sin(clampf(1.0 - _reload / 1.15, 0.0, 1.0) * PI)
		_gun_mount.position = held.lerp(RELOAD_GUN, reloading)
		_gun_mount.rotation_degrees.x = lerpf(0.0, 35.0, reloading)
	camera.fov = lerpf(HIP_FOV, ADS_FOV, _aim)
	var speed := SPEED * (1.45 if ult_active == "punk" else 1.0) * lerpf(1.0, 0.72, _aim)
	velocity.x = wish.x * speed
	velocity.z = wish.z * speed
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_SPEED
		else:
			velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if wish.length() > 0.01:
		_step_up(wish)
	_update_prompt()

func take_damage(amount: float) -> void:
	if _downed or _nap_invuln or not GameState.running:
		return
	var taken := amount
	if "tin_vest" in perks:
		taken *= 0.75
	if ult_active == "dreads":
		taken *= 0.55
	health = maxf(0.0, health - taken)
	add_ult(taken * 0.22)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_down()

func add_cash(amount: int) -> void:
	cash = maxi(0, cash + amount)
	cash_changed.emit(cash)

func add_ult(amount: float) -> void:
	if ult_active != "":
		return
	ult = clampf(ult + amount, 0.0, 100.0)
	ult_changed.emit(ult)

func try_buy(cost: int) -> bool:
	if cash < cost:
		GameState.toast("Not enough cash.")
		return false
	add_cash(-cost)
	return true

func add_perk(id: String) -> bool:
	if id in perks:
		GameState.toast("Already owned.")
		return false
	if perks.size() >= Economy.MAX_PERKS:
		GameState.toast("Perk slots are full.")
		return false
	var price := int(Economy.PERKS[id].price)
	if not try_buy(price):
		return false
	perks.append(id)
	if id == "thick_skin":
		max_health = 150.0
		health = max_health
		health_changed.emit(health, max_health)
	GameState.toast("Bought %s." % Economy.PERKS[id].name)
	return true

func give_weapon(id: String, tier: int = 1, keep_smith: bool = false) -> void:
	var owned := _slot_of(id)
	if owned >= 0:
		refill_weapon(id)
		_switch_slot(owned)
		GameState.toast("Already carrying %s. Ammo refilled." % Economy.weapon(id).name)
		return
	_store_slot()
	var dest := _slot
	if str(_slots[0].id) == "":
		dest = 0
	elif str(_slots[1].id) == "":
		dest = 1
	var spec := Economy.weapon(id)
	var entry := _empty_slot()
	entry.id = id
	entry.tier = tier
	entry.mag = int(spec.mag)
	entry.offhand = 0
	entry.reserve = int(spec.reserve)
	if keep_smith and dest == _slot:
		entry.smith_damage = smith_damage
		entry.smith_rate = smith_rate
		entry.smith_ammo = smith_ammo
		entry.reserve += int(spec.mag) * smith_ammo
	_slots[dest] = entry
	_slot = dest
	_read_slot()
	_reload = 0.0
	_fire_cd = 0.0
	ammo_changed.emit()
	weapon_changed.emit()
	GameState.toast("Picked up %s." % spec.name)

func owns_weapon(id: String) -> bool:
	return _slot_of(id) >= 0

func refill_weapon(id: String) -> void:
	var index := _slot_of(id)
	if index < 0:
		return
	var amount := int(Economy.weapon(id).reserve)
	if index == _slot:
		reserve += amount
	else:
		_slots[index].reserve = int(_slots[index].reserve) + amount
	ammo_changed.emit()

func weapon_hud() -> String:
	var lines: PackedStringArray = []
	for i in 2:
		var id := str(_slots[i].id)
		var tier := int(_slots[i].tier)
		var mag_n := int(_slots[i].mag)
		var off_n := int(_slots[i].get("offhand", 0))
		var reserve_n := int(_slots[i].reserve)
		if i == _slot:
			id = weapon_id
			tier = weapon_tier
			mag_n = mag
			off_n = offhand_mag
			reserve_n = reserve
		if id == "":
			lines.append("%d  empty" % (i + 1))
		else:
			var mark := ">" if i == _slot else " "
			var ammo := "%d / %d" % [mag_n, reserve_n]
			if id == "pipe_pistol" and tier >= 3:
				ammo = "%d | %d / %d" % [mag_n, off_n, reserve_n]
			lines.append("%s %d  %s %s   %s" % [mark, i + 1, Economy.weapon(id).name, Economy.tier_label(tier), ammo])
	return "\n".join(lines)

func buy_smith(stat: String) -> bool:
	var level := _smith_level(stat)
	if level >= Economy.SMITH_MAX:
		GameState.toast("That mod is maxed.")
		return false
	if not try_buy(Economy.smith_cost(level + 1)):
		return false
	match stat:
		"damage":
			smith_damage += 1
		"rate":
			smith_rate += 1
		"ammo":
			smith_ammo += 1
			reserve += int(Economy.weapon(weapon_id).mag)
	ammo_changed.emit()
	GameState.toast("Street Smith: %s %d." % [stat, _smith_level(stat)])
	return true

func next_smith_stat() -> String:
	if smith_damage < Economy.SMITH_MAX:
		return "damage"
	if smith_rate < Economy.SMITH_MAX:
		return "rate"
	if smith_ammo < Economy.SMITH_MAX:
		return "ammo"
	return ""

func markup() -> bool:
	if weapon_tier >= 3:
		GameState.toast("%s is already v3." % Economy.weapon(weapon_id).name)
		return false
	var next_tier := weapon_tier + 1
	var cost := Economy.markup_cost(weapon_id, next_tier)
	if not try_buy(cost):
		return false
	var before := _mag_capacity()
	weapon_tier = next_tier
	if weapon_id == "pipe_pistol" and weapon_tier == 2:
		mag = 21
		reserve = 210
	elif weapon_id == "rent_rifle" and weapon_tier == 2:
		mag = 30
		reserve = 300
	else:
		var after := _mag_capacity()
		mag += maxi(0, after - before)
		if _akimbo():
			offhand_mag = after
	_burst_left = 0
	weapon_changed.emit()
	_store_slot()
	if weapon_id == "pipe_pistol" and weapon_tier == 2:
		GameState.toast("Pipe Pistol v2. 3-round burst.")
	elif weapon_id == "pipe_pistol" and weapon_tier == 3:
		GameState.toast("Pipe Pistol v3. Two pistols, harder hits, bigger mags. Left and right mouse each fire one.")
	elif weapon_id == "rent_rifle" and weapon_tier == 2:
		GameState.toast("Rent Rifle v2. 3-round burst, 30-round mag.")
	elif weapon_id == "rent_rifle" and weapon_tier == 3:
		GameState.toast("Rent Rifle v3. Full auto.")
	else:
		GameState.toast("%s is now %s." % [Economy.weapon(weapon_id).name, Economy.tier_label(weapon_tier)])
	return true

func weapon_label() -> String:
	return "%s %s" % [Economy.weapon(weapon_id).name, Economy.tier_label(weapon_tier)]

func shot_damage() -> float:
	if weapon_id == "pop_junk":
		var wave := GameState.round_index
		return maxf(50.0, 220.0 - float(maxi(wave - 6, 0)) * 18.0)
	var base: float = float(Economy.weapon(weapon_id).damage)
	base *= Economy.tier_multiplier(weapon_tier)
	base *= 1.0 + 0.15 * float(smith_damage)
	if "mean_streak" in perks:
		base *= 1.25
	if weapon_tier >= 2:
		base *= 1.08
	if weapon_id == "pipe_pistol" and weapon_tier >= 3:
		base *= 1.4
	return base

func _on_character(id: String) -> void:
	var color: Color = CharacterDB.info(id).get("color", Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mesh.material_override = mat
	_hide_body_from_own_camera()
	GameState.toast(CharacterDB.display_name(id))

func _load_weapon(id: String, tier: int, fill: bool) -> void:
	weapon_id = id
	weapon_tier = tier
	var spec := Economy.weapon(id)
	var extra := int(spec.mag) * smith_ammo
	if fill:
		mag = _mag_capacity()
		offhand_mag = _mag_capacity() if _akimbo() else 0
		reserve = int(spec.reserve) + extra
	ammo_changed.emit()
	weapon_changed.emit()

func _empty_slot() -> Dictionary:
	return {
		"id": "",
		"tier": 1,
		"mag": 0,
		"offhand": 0,
		"reserve": 0,
		"smith_damage": 0,
		"smith_rate": 0,
		"smith_ammo": 0,
	}

func _store_slot() -> void:
	if weapon_id == "":
		return
	_slots[_slot] = {
		"id": weapon_id,
		"tier": weapon_tier,
		"mag": mag,
		"offhand": offhand_mag,
		"reserve": reserve,
		"smith_damage": smith_damage,
		"smith_rate": smith_rate,
		"smith_ammo": smith_ammo,
	}

func _read_slot() -> void:
	var slot: Dictionary = _slots[_slot]
	weapon_id = str(slot.id)
	weapon_tier = int(slot.tier)
	mag = int(slot.mag)
	offhand_mag = int(slot.get("offhand", 0))
	reserve = int(slot.reserve)
	smith_damage = int(slot.smith_damage)
	smith_rate = int(slot.smith_rate)
	smith_ammo = int(slot.smith_ammo)

func _slot_of(id: String) -> int:
	for i in 2:
		var slot_id := weapon_id if i == _slot else str(_slots[i].id)
		if slot_id == id:
			return i
	return -1

func _switch_slot(index: int) -> void:
	if index == _slot or index < 0 or index > 1:
		return
	if str(_slots[index].id) == "":
		return
	_store_slot()
	_slot = index
	_read_slot()
	_reload = 0.0
	_fire_cd = 0.0
	_burst_left = 0
	ammo_changed.emit()
	weapon_changed.emit()

func _cycle_weapon() -> void:
	_switch_slot(1 - _slot)

func _uses_burst() -> bool:
	if weapon_id == "pipe_pistol" and weapon_tier >= 2:
		return true
	return weapon_id == "rent_rifle" and weapon_tier == 2

func _full_auto() -> bool:
	if _uses_burst():
		return false
	if weapon_id == "rent_rifle" and weapon_tier >= 3:
		return true
	return float(Economy.weapon(weapon_id).rate) >= 8.0

func _shots_per_second() -> float:
	var rate := float(Economy.weapon(weapon_id).rate)
	if weapon_id == "rent_rifle" and weapon_tier >= 3:
		rate = 10.0
	rate *= 1.0 + 0.12 * float(smith_rate)
	if "rapid_fire" in perks:
		rate *= 1.25
	if ult_active == "punk":
		rate *= 2.2
	return rate

func _akimbo() -> bool:
	return weapon_id == "pipe_pistol" and weapon_tier >= 3

func _mag_capacity() -> int:
	var base := int(Economy.weapon(weapon_id).mag)
	if weapon_id == "pipe_pistol" and weapon_tier >= 3:
		return base * 4
	if weapon_id == "pipe_pistol" and weapon_tier >= 2:
		return 21
	if weapon_id == "rent_rifle" and weapon_tier >= 2:
		return 30
	return base

func _pull_trigger(side: int) -> void:
	if _downed or _reload > 0.0 or _burst_left > 0 or _fire_cd > 0.0:
		return
	if _uses_burst():
		_burst_side = side
		_burst_left = 3
		_burst_gap = 0.0
		return
	_fire_one(side)

func _tick_burst(delta: float) -> void:
	if _burst_left <= 0:
		return
	_burst_gap -= delta
	if _burst_gap > 0.0:
		return
	if not _fire_one(_burst_side):
		_burst_left = 0
		return
	_burst_left -= 1
	if _burst_left > 0:
		_burst_gap = 0.07
	else:
		_fire_cd = 0.42

func _fire_one(side: int) -> bool:
	if _fire_cd > 0.0 or _reload > 0.0 or _downed:
		return false
	var pool := offhand_mag if side == 1 else mag
	if pool <= 0:
		if _reload <= 0.0 and reserve > 0 and mag <= 0 and (not _akimbo() or offhand_mag <= 0):
			_start_reload()
		return false
	if side == 1:
		offhand_mag -= 1
	else:
		mag -= 1
	ammo_changed.emit()
	if not _uses_burst():
		_fire_cd = 1.0 / _shots_per_second()
	_play_gunshot(side)
	_play_view_clip("fire", 0.0, side)
	var spec_shot := Economy.weapon(weapon_id)
	var kick := -0.04 if side == 0 else 0.04
	for _i in int(spec_shot.pellets):
		_shoot_ray(float(spec_shot.spread), kick if _akimbo() else 0.0)
	return true

func _shoot_ray(spread: float, hand_bias: float = 0.0) -> void:
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	dir += camera.global_transform.basis.x * hand_bias
	var aimed := spread * lerpf(1.0, 0.2, _aim)
	dir += camera.global_transform.basis.x * randf_range(-aimed, aimed)
	dir += camera.global_transform.basis.y * randf_range(-aimed, aimed)
	dir = dir.normalized()
	var space := get_world_3d().direct_space_state
	var from := origin
	var remain := 80.0
	var skip: Array[RID] = [get_rid()]
	var pierced := 0
	for _hop in 16:
		if remain <= 0.05:
			return
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * remain)
		query.collision_mask = 3
		query.exclude = skip
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return
		var body: Object = hit.collider
		var node := body as Node
		if node and node.is_in_group("enemies"):
			var dealt := shot_damage()
			if weapon_id == "pop_junk":
				dealt *= pow(0.85, float(pierced))
			node.call("take_damage", dealt, self, _hit_head(body, hit))
			pierced += 1
			if weapon_id != "pop_junk" or pierced >= _laser_pierce():
				return
			if body is CollisionObject3D:
				skip.append((body as CollisionObject3D).get_rid())
			var hopped := from.distance_to(hit.position)
			remain -= hopped + 0.08
			from = hit.position + dir * 0.08
			continue
		var traveled := from.distance_to(hit.position)
		var normal := hit.normal as Vector3
		var pass_through := node != null and node.is_in_group("stair_steps")
		var near_lip := dir.y < -0.15 and (traveled < 0.9 or (normal.y > 0.65 and traveled < 1.6))
		if not pass_through and near_lip:
			pass_through = true
		if not pass_through:
			return
		if body is CollisionObject3D:
			skip.append((body as CollisionObject3D).get_rid())
		remain -= traveled + 0.08
		from = hit.position + dir * 0.08

func _laser_pierce() -> int:
	var wave := GameState.round_index
	if wave <= 6:
		return 4
	if wave <= 10:
		return 3
	if wave <= 14:
		return 2
	return 1

func _hit_head(body: Object, hit: Dictionary) -> bool:
	if not body is CollisionObject3D or not hit.has("shape"):
		return false
	var col := body as CollisionObject3D
	var owner_id := col.shape_find_owner(int(hit.shape))
	if owner_id < 0:
		return false
	var owner := col.shape_owner_get_owner(owner_id)
	return owner is Node and str((owner as Node).name) == "Head"

func _start_reload() -> void:
	if _reload > 0.0 or reserve <= 0:
		return
	var cap := _mag_capacity()
	var hungry := mag < cap or (_akimbo() and offhand_mag < cap)
	if not hungry:
		return
	_reload = 1.15
	_burst_left = 0
	_reload_sfx.play()
	_play_view_clip("reload", 1.15)

func _finish_reload() -> void:
	var cap := _mag_capacity()
	var into_left := mini(maxi(cap - mag, 0), reserve)
	mag += into_left
	reserve -= into_left
	if _akimbo():
		var into_right := mini(maxi(cap - offhand_mag, 0), reserve)
		offhand_mag += into_right
		reserve -= into_right
	ammo_changed.emit()

func _interact() -> void:
	var hit := _look_hit(2.6)
	if hit == null:
		return
	if hit.is_in_group("barricades"):
		hit.call("board", self)
	elif hit.is_in_group("stations"):
		hit.call("use", self)

func _look_hit(distance: float) -> Node:
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * distance)
	query.collision_mask = 1
	query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var body: Object = hit.collider
	if body is Node:
		return body
	return null

func _update_prompt() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var hit := _look_hit(2.6)
	if hit == null:
		hud.call("set_prompt", "")
		return
	if hit.has_method("prompt_for"):
		hud.call("set_prompt", hit.call("prompt_for", self))
	else:
		hud.call("set_prompt", "")

func _try_ult() -> void:
	if ult < 100.0 or ult_active != "" or GameState.character_id == "":
		return
	ult = 0.0
	ult_changed.emit(ult)
	ult_active = GameState.character_id
	match ult_active:
		"punk":
			ult_time = 6.0
			GameState.toast("Feedback Loop")
		"hobo":
			ult_time = 5.0
			GameState.toast("Market Crash")
		"dreads":
			ult_time = 6.0
			GameState.toast("Cloud Cover")
		"lazy":
			ult_time = 2.6
			_nap_invuln = true
			health = minf(max_health, health + 20.0)
			health_changed.emit(health, max_health)
			GameState.toast("Power Nap")

func _tick_ult(delta: float) -> void:
	if ult_active == "":
		return
	ult_time -= delta
	if ult_active == "punk":
		health = maxf(1.0, health - 1.4 * delta)
		health_changed.emit(health, max_health)
	if ult_time > 0.0:
		return
	if ult_active == "lazy":
		_nap_invuln = false
		_shove()
	ult_active = ""

func _shove() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(node.global_position) <= 4.5:
			node.call("knockback", global_position)

func market_crash_active() -> bool:
	return ult_active == "hobo"

func _down() -> void:
	_downed = true
	_bleed = 3.0
	perks.clear()
	max_health = 100.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.toast("Down.")

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

func _smith_level(stat: String) -> int:
	match stat:
		"damage":
			return smith_damage
		"rate":
			return smith_rate
		"ammo":
			return smith_ammo
	return 0

func _play_gunshot(side: int) -> void:
	if _gunshot == null:
		return
	var heavy := weapon_id == "pipe_pistol" and weapon_tier >= 2
	_gunshot.stream = SHOT_HEAVY if heavy else SHOTS.get(weapon_id, SHOTS["pipe_pistol"])
	_gunshot.volume_db = 1.5 if heavy else -4.0
	_gunshot.pitch_scale = randf_range(0.94, 1.0) if side == 0 else randf_range(1.02, 1.08)
	_gunshot.play()

func _arm_rig() -> Dictionary:
	if weapon_id in ["street_smg", "debt_shotgun", "rent_rifle"]:
		return {"path": "res://assets/weapons/fps_rifle.glb", "scale": 0.08, "yaw": 90.0, "pos": Vector3(-0.35, -0.2, -0.43)}
	return {"path": "res://assets/weapons/fps_pistol.glb", "scale": 0.09, "yaw": 90.0, "pos": Vector3(-0.35, -0.23, -0.20)}

func _build_viewmodel() -> void:
	_gun_mount = Node3D.new()
	_gun_mount.name = "GunMount"
	camera.add_child(_gun_mount)
	_gun_mount.position = HIP_GUN

func _show_gun() -> void:
	if _gun_mount == null:
		return
	for child in _gun_mount.get_children():
		child.free()
	_view_anims.clear()
	_offhand_anims.clear()
	_fire_clip = ""
	_reload_clip = ""
	var arms: Dictionary = _arm_rig()
	var rig_packed := load(str(arms.path)) as PackedScene
	if rig_packed == null:
		push_error("Missing arm rig " + str(arms.path))
		return
	if _akimbo():
		_spawn_arm(rig_packed, arms, 0.18, false)
		_spawn_arm(rig_packed, arms, 0.18, true)
	else:
		_spawn_arm(rig_packed, arms, 0.0, false)
	_hold_idle()

func _spawn_arm(packed: PackedScene, arms: Dictionary, spread: float, mirror: bool) -> void:
	var pivot := Node3D.new()
	if mirror:
		pivot.scale.x = -1.0
	_gun_mount.add_child(pivot)
	var rig := packed.instantiate() as Node3D
	rig.scale = Vector3.ONE * float(arms.scale)
	rig.rotation_degrees.y = float(arms.yaw)
	var pos: Vector3 = arms.pos
	pos.x += spread
	rig.position = pos
	pivot.add_child(rig)
	_color_viewmodel(rig)
	if weapon_id == "pop_junk":
		_seat_held(rig, "res://assets/weapons/ray_gun.glb", Vector3(0.0, 0.0, -1.0), 2.96, 0.28, "glock")
	elif weapon_id == "pipe_pistol" and weapon_tier >= 2:
		_seat_held(rig, "res://assets/weapons/pistol_v2.glb", Vector3(1.0, 0.0, 0.0), 2.11, 0.36, "glock")
	elif weapon_id == "street_smg":
		_seat_held(rig, "res://assets/weapons/smg.glb", Vector3(1.0, 0.0, 0.0), 2.11, 0.48, "akm")
	elif weapon_id == "debt_shotgun":
		_seat_held(rig, "res://assets/weapons/mossberg.glb", Vector3(1.0, 0.0, 0.0), 6.03, 1.05, "akm")
	elif weapon_id == "rent_rifle" and weapon_tier < 2:
		_seat_held(rig, "res://assets/weapons/rifle.glb", Vector3(0.0, 0.0, 1.0), 4.76, 0.78, "akm")
	if _akimbo():
		_collapse_support_hand(rig)
	var bucket := _offhand_anims if mirror else _view_anims
	for anim in rig.find_children("*", "AnimationPlayer", true, false):
		bucket.append(anim as AnimationPlayer)

func _collapse_support_hand(rig: Node3D) -> void:
	for node in rig.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		if skeleton.find_bone("UpperArm.L") < 0:
			continue
		var modifier := preload("res://scripts/collapse_left_arm.gd").new() as SkeletonModifier3D
		skeleton.add_child(modifier)

func _seat_held(rig: Node3D, path: String, model_axis: Vector3, model_length: float, world_length: float, hide_name: String) -> void:
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		if hide_name != "" and hide_name in String(node.name).to_lower():
			(node as MeshInstance3D).visible = false
	var skeleton: Skeleton3D = null
	for node in rig.find_children("*", "Skeleton3D", true, false):
		var candidate := node as Skeleton3D
		if candidate.find_bone("Root") >= 0:
			skeleton = candidate
			break
	if skeleton == null:
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	_attach_pistol(skeleton, "Root", packed, model_axis, model_length, world_length)

func _attach_pistol(skeleton: Skeleton3D, bone_name: String, packed: PackedScene, model_axis: Vector3, model_length: float, world_length: float) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	var gun := packed.instantiate() as Node3D
	var bone_xf := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var aim := model_axis.normalized()
	var aim_bone := skeleton.find_bone("Barrel")
	if aim_bone < 0:
		aim_bone = skeleton.find_bone("Bolt")
	if aim_bone >= 0:
		var barrel_xf := skeleton.global_transform * skeleton.get_bone_global_pose(aim_bone)
		var local_aim: Vector3 = bone_xf.basis.inverse() * (barrel_xf.origin - bone_xf.origin)
		if local_aim.length() > 0.001:
			aim = local_aim.normalized()
	var bone_scale := bone_xf.basis.x.length()
	gun.scale = Vector3.ONE * (world_length / model_length / maxf(bone_scale, 0.001))
	if model_axis.normalized().dot(aim) < 0.999:
		gun.quaternion = Quaternion(model_axis.normalized(), aim)
	attachment.add_child(gun)
	_plant_grip(gun, attachment)
	_color_viewmodel(gun)

func _plant_grip(gun: Node3D, attachment: Node3D) -> void:
	var skeleton: Skeleton3D = null
	for node in gun.find_children("*", "Skeleton3D", true, false):
		var candidate := node as Skeleton3D
		if candidate.find_bone("Root") >= 0:
			skeleton = candidate
			break
	if skeleton == null:
		return
	var grip: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Root")).origin
	gun.global_position += attachment.global_position - grip

func _hold_idle() -> void:
	if _reload > 0.0 or _burst_left > 0:
		return
	for anim in _all_view_anims():
		if anim.is_playing():
			continue
		var idle := _view_clip(anim, "idle")
		if idle != "":
			anim.play(idle)

func _color_viewmodel(node: Node) -> void:
	for child in node.get_children():
		_color_viewmodel(child)
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
		mesh_inst.set_surface_override_material(surface, flat)

func _view_clip(anim: AnimationPlayer, kind: String) -> String:
	if anim == null:
		return ""
	var fire_hit := ""
	for name in anim.get_animation_list():
		var clip := String(name)
		if kind == "reload" and "Reload" in clip:
			return clip
		if kind == "idle" and "Idle" in clip:
			return clip
		if kind == "fire" and "FireWBullet" in clip:
			return clip
		if kind == "fire" and fire_hit == "" and "Shoot" in clip:
			fire_hit = clip
		if kind == "fire" and fire_hit == "" and "Fire" in clip and "WO" not in clip:
			fire_hit = clip
	return fire_hit

func _play_view_clip(kind: String, fit_seconds: float, side: int = -1) -> void:
	var players: Array[AnimationPlayer] = _view_anims
	if _akimbo() and side == 0:
		players = _offhand_anims
	elif _akimbo() and side == 1:
		players = _view_anims
	elif side < 0:
		players = _all_view_anims()
	if players.is_empty():
		return
	for anim in players:
		var clip := _view_clip(anim, kind)
		if clip == "":
			continue
		var animation := anim.get_animation(clip)
		if animation and fit_seconds > 0.05 and animation.length > 0.05:
			anim.speed_scale = animation.length / fit_seconds
		else:
			anim.speed_scale = 1.0
		anim.play(clip)

func _all_view_anims() -> Array[AnimationPlayer]:
	var players: Array[AnimationPlayer] = []
	players.append_array(_view_anims)
	players.append_array(_offhand_anims)
	return players

func _hide_body_from_own_camera() -> void:
	# The body sits around the first-person camera. Drawing it, especially the
	# inside-out ink shell, fills the whole view with black.
	mesh.visible = false

func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
	if code == MOUSE_BUTTON_LEFT or code == MOUSE_BUTTON_RIGHT:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = code as MouseButton
		InputMap.action_add_event(action, mouse)
		return
	var event := InputEventKey.new()
	event.physical_keycode = code as Key
	InputMap.action_add_event(action, event)
