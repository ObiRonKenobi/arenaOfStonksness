extends CharacterBody3D

signal health_changed(current: float, maximum: float)
signal ammo_changed
signal cash_changed(amount: int)
signal ult_changed(amount: float)
signal weapon_changed

const SPEED := 5.6
const HIP_FOV := 75.0
const ADS_FOV := 60.0
const ADS_FOV_LONG := 50.0
const HIP_GUN := Vector3(0.24, -0.2, -0.42)
const ADS_GUN := Vector3(0.0, -0.11, -0.5)
const RELOAD_GUN := Vector3(0.1, -0.42, -0.32)
const SHOTS := {
	"pipe_pistol": preload("res://assets/audio/shot_9mm.wav"),
	"street_smg": preload("res://assets/audio/gunshot.wav"),
	"pop_junk": preload("res://assets/audio/shot_22.wav"),
	"debt_shotgun": preload("res://assets/audio/shot_20g.wav"),
	"rent_rifle": preload("res://assets/audio/shot_556.wav"),
}
const RELOAD_SFX := preload("res://assets/audio/reload_ak.wav")
const SHOT_HEAVY := preload("res://assets/audio/shot_deagle.wav")
const SHOT_BLASTER := preload("res://assets/audio/sci_blaster.mp3")
const SHOT_SCI_GUN := preload("res://assets/audio/sci_gunshot.mp3")
const FLASH_GUN := preload("res://assets/fx/muzzle_gun.png")
const FLASH_LASER := preload("res://assets/fx/muzzle_laser.png")
const MOUSE_SENS := 0.0022
const GRAVITY := 20.0
const JUMP_SPEED := 6.2
const STEP_HEIGHT := 0.45
const BOARD_HOLD := 0.8

var health := 100.0
var max_health := 100.0
var cash := 999999
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
var _off_reload := 0.0
var _off_cd := 0.0
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
var _board_time := 0.0
var _board_target: Node = null
var _muzzle_flashes: Array[MeshInstance3D] = []
var _muzzle_guns: Array[Node3D] = []
var _muzzle_time := 0.0
var _nozzle := 0

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
			_finish_reload(0 if _akimbo() else -1)
	if _akimbo() and _off_reload > 0.0:
		_off_reload -= delta
		if _off_reload <= 0.0:
			_finish_reload(1)
	if _fire_cd > 0.0:
		_fire_cd -= delta
	if _off_cd > 0.0:
		_off_cd -= delta
	_tick_burst(delta)
	if _full_auto() and Input.is_action_pressed("shoot"):
		_fire_one(0)
	elif _uses_burst() and _burst_left <= 0:
		if Input.is_action_pressed("shoot") and not _side_reloading(0):
			_pull_trigger(0)
		elif _akimbo() and Input.is_action_pressed("aim") and not _side_reloading(1):
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
		var hip := Vector3(0.0, -0.14, -0.30) if _akimbo() else HIP_GUN
		var held := hip if _akimbo() else hip.lerp(ADS_GUN, _aim)
		var reloading := 0.0
		if _reload > 0.0 and not _akimbo():
			reloading = sin(clampf(1.0 - _reload / 1.15, 0.0, 1.0) * PI)
		_gun_mount.position = held.lerp(RELOAD_GUN, reloading)
		_gun_mount.rotation_degrees.x = lerpf(0.0, 35.0, reloading)
	camera.fov = lerpf(HIP_FOV, _ads_fov(), _aim)
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
	_tick_board(delta)
	_tick_muzzle(delta)
	_update_prompt()

func take_damage(amount: float) -> void:
	if _downed or _nap_invuln or not GameState.running:
		return
	var taken := amount
	if "tin_vest" in perks:
		taken *= 0.75
	if ult_active == "punk_f":
		taken *= 0.55
	health = maxf(0.0, health - taken)
	add_ult(taken * 0.22)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_down()

func heal(amount: float) -> void:
	if _downed:
		return
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)

func refill_carried_ammo() -> void:
	_store_slot()
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		var id := str(slot.get("id", ""))
		if id == "":
			continue
		var tier := int(slot.get("tier", 1))
		slot.mag = _capacity_for(id, tier)
		slot.offhand = slot.mag if id == "pipe_pistol" and tier >= 3 else 0
		slot.reserve = _reserve_for(id, tier) + int(Economy.weapon(id).mag) * int(slot.get("smith_ammo", 0))
		_slots[i] = slot
	_read_slot()
	ammo_changed.emit()

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
	_off_reload = 0.0
	_off_cd = 0.0
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
	else:
		var after := _mag_capacity()
		if weapon_id == "pipe_pistol":
			mag += maxi(0, after - before)
		else:
			mag = after
		if _akimbo():
			offhand_mag = after
		var scaled := _reserve_for(weapon_id, weapon_tier)
		if reserve < scaled:
			reserve = scaled
	_burst_left = 0
	weapon_changed.emit()
	_store_slot()
	if weapon_id == "pipe_pistol" and weapon_tier == 2:
		GameState.toast("Pipe Pistol v2. 3-round burst.")
	elif weapon_id == "pipe_pistol" and weapon_tier == 3:
		GameState.toast("Pipe Pistol v3. Two pistols, harder hits, bigger mags. Left and right mouse each fire one.")
	elif weapon_id == "rent_rifle" and weapon_tier == 2:
		GameState.toast("Rent Rifle v2. 3-round burst, larger mag.")
	elif weapon_id == "rent_rifle" and weapon_tier == 3:
		GameState.toast("Rent Rifle v3. Full auto.")
	elif weapon_id == "debt_shotgun" and weapon_tier == 2:
		GameState.toast("Debt Collector v2. Both barrels, same spread.")
	elif weapon_id == "debt_shotgun" and weapon_tier == 3:
		GameState.toast("Debt Collector v3. Twin lasers, larger mag.")
	else:
		GameState.toast("%s is now %s." % [Economy.weapon(weapon_id).name, Economy.tier_label(weapon_tier)])
	return true

func weapon_label() -> String:
	return "%s %s" % [Economy.weapon(weapon_id).name, Economy.tier_label(weapon_tier)]

func shot_damage() -> float:
	if weapon_id == "pop_junk" or weapon_id == "ledger_cannon":
		var wave := GameState.round_index
		return maxf(50.0, 220.0 - float(maxi(wave - 6, 0)) * 18.0) * _half_tier()
	var base: float = float(Economy.weapon(weapon_id).damage)
	if weapon_id == "debt_shotgun" and weapon_tier >= 3:
		base *= float(Economy.weapon(weapon_id).pellets)
	if weapon_id == "pipe_pistol":
		base *= Economy.tier_multiplier(weapon_tier)
		base *= 1.0 + 0.15 * float(smith_damage)
		if "mean_streak" in perks:
			base *= 1.25
		if weapon_tier >= 2:
			base *= 1.08
		if weapon_tier >= 3:
			base *= 1.4
		return base
	base *= _half_tier()
	base *= 1.0 + 0.15 * float(smith_damage)
	if "mean_streak" in perks:
		base *= 1.25
	return base

func _half_tier() -> float:
	if weapon_tier >= 3:
		return 2.5
	if weapon_tier >= 2:
		return 1.5
	return 1.0

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
		reserve = _reserve_for(id, tier) + extra
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
	var cap := _mag_capacity()
	mag = mini(int(slot.mag), cap)
	offhand_mag = mini(int(slot.get("offhand", 0)), cap) if _akimbo() else int(slot.get("offhand", 0))
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
	_off_reload = 0.0
	_off_cd = 0.0
	_fire_cd = 0.0
	_burst_left = 0
	ammo_changed.emit()
	weapon_changed.emit()

func _cycle_weapon() -> void:
	_switch_slot(1 - _slot)

func _uses_burst() -> bool:
	if weapon_id == "ledger_cannon":
		return true
	if weapon_id == "pop_junk" and weapon_tier == 2:
		return true
	if weapon_id == "pipe_pistol" and weapon_tier >= 2:
		return true
	return weapon_id == "rent_rifle" and weapon_tier == 2

func _full_auto() -> bool:
	if _uses_burst():
		return false
	if weapon_id == "pop_junk" and weapon_tier >= 3:
		return true
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
	return _capacity_for(weapon_id, weapon_tier)

func _capacity_for(id: String, tier: int) -> int:
	if id == "ledger_cannon":
		return 3
	if id == "debt_shotgun" and tier == 2:
		return 2
	var base := int(Economy.weapon(id).mag)
	if id == "pipe_pistol" and tier >= 3:
		return 33
	if id == "pipe_pistol" and tier >= 2:
		return 21
	if tier >= 3:
		return _snap_mag(id, int(round(float(base) * 2.5)))
	if tier >= 2:
		return _snap_mag(id, int(round(float(base) * 1.81)))
	return _snap_mag(id, base)

func _snap_mag(id: String, count: int) -> int:
	if id != "ledger_cannon":
		return maxi(1, count)
	return maxi(3, int(round(float(count) / 3.0)) * 3)

func _reserve_for(id: String, tier: int) -> int:
	if id == "ledger_cannon":
		return 30
	var stock := int(Economy.weapon(id).reserve)
	if id == "pipe_pistol" and tier >= 2:
		return 210
	if tier >= 2:
		var scaled := int(round(float(stock) * 2.69))
		if id == "ledger_cannon":
			scaled = maxi(3, int(round(float(scaled) / 3.0)) * 3)
		return scaled
	return stock

func _shells_per_shot() -> int:
	if weapon_id == "debt_shotgun" and weapon_tier >= 2:
		return 2
	return 1

func _chamber(side: int) -> int:
	return offhand_mag if side == 1 else mag

func _side_reloading(side: int) -> bool:
	if _akimbo() and side == 1:
		return _off_reload > 0.0
	return _reload > 0.0

func _cd_for(side: int) -> float:
	if _akimbo() and side == 1:
		return _off_cd
	return _fire_cd

func _set_cd(side: int, value: float) -> void:
	if _akimbo() and side == 1:
		_off_cd = value
	else:
		_fire_cd = value

func _pull_trigger(side: int) -> void:
	if _downed or _burst_left > 0:
		return
	if _side_reloading(side):
		return
	if _chamber(side) < _shells_per_shot():
		_start_reload(side if _akimbo() else -1)
		return
	if _cd_for(side) > 0.0:
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
		_set_cd(_burst_side, 0.42)

func _fire_one(side: int) -> bool:
	if _cd_for(side) > 0.0 or _side_reloading(side) or _downed:
		return false
	var shells := _shells_per_shot()
	if _chamber(side) < shells:
		_start_reload(side if _akimbo() else -1)
		return false
	if side == 1:
		offhand_mag -= shells
	else:
		mag -= shells
	ammo_changed.emit()
	if not _uses_burst():
		_set_cd(side, 1.0 / _shots_per_second())
	_play_gunshot(side)
	_pop_muzzle(side)
	_play_view_clip("fire", 0.0, side)
	var spec_shot := Economy.weapon(weapon_id)
	var kick := -0.04 if side == 0 else 0.04
	if weapon_id == "debt_shotgun" and weapon_tier >= 3:
		_shoot_ray(0.02, -0.03)
		_shoot_ray(0.02, 0.03)
	elif weapon_id == "debt_shotgun" and weapon_tier == 2:
		for bias in [-0.035, 0.035]:
			for _i in int(spec_shot.pellets):
				_shoot_ray(float(spec_shot.spread), bias)
	else:
		for _i in int(spec_shot.pellets):
			_shoot_ray(float(spec_shot.spread), kick if _akimbo() else 0.0)
	if _chamber(side) < shells:
		_start_reload(side if _akimbo() else -1)
	if weapon_id == "ledger_cannon":
		_nozzle = (_nozzle + 1) % 3
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
	var impact := origin + dir * 16.0
	for _hop in 16:
		if remain <= 0.05:
			break
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * remain)
		query.collision_mask = 3
		query.exclude = skip
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		impact = hit.position
		var body: Object = hit.collider
		var node := body as Node
		if node and node.is_in_group("enemies"):
			var dealt := shot_damage()
			if weapon_id == "pop_junk":
				dealt *= pow(0.85, float(pierced))
			node.call("take_damage", dealt, self, _hit_head(body, hit))
			pierced += 1
			var keep := weapon_id == "ledger_cannon" or (weapon_id == "pop_junk" and pierced < _laser_pierce())
			if not keep:
				break
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
			break
		if body is CollisionObject3D:
			skip.append((body as CollisionObject3D).get_rid())
		remain -= traveled + 0.08
		from = hit.position + dir * 0.08
	_spawn_tracer(dir, impact, hand_bias)

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

func _start_reload(side: int = -1) -> void:
	if reserve <= 0:
		return
	if not _akimbo():
		if _reload > 0.0 or mag >= _mag_capacity():
			return
		_reload = 1.15
		_burst_left = 0
		_reload_sfx.play()
		_play_view_clip("reload", 1.15)
		return
	var hands: Array[int] = []
	if side < 0:
		hands.append(0)
		hands.append(1)
	else:
		hands.append(side)
	var started := false
	for hand in hands:
		if _side_reloading(hand) or _chamber(hand) >= _mag_capacity():
			continue
		if hand == 1:
			_off_reload = 1.15
		else:
			_reload = 1.15
		if _burst_left > 0 and _burst_side == hand:
			_burst_left = 0
		_play_view_clip("reload", 1.15, hand)
		started = true
	if started:
		_reload_sfx.play()

func _finish_reload(side: int = -1) -> void:
	var cap := _mag_capacity()
	if not _akimbo() or side <= 0:
		var into_main := mini(maxi(cap - mag, 0), reserve)
		mag += into_main
		reserve -= into_main
	if _akimbo() and side == 1:
		var into_off := mini(maxi(cap - offhand_mag, 0), reserve)
		offhand_mag += into_off
		reserve -= into_off
	ammo_changed.emit()

func _interact() -> void:
	var hit := _look_hit(2.6)
	if hit != null and hit.is_in_group("stations"):
		hit.call("use", self)

func _tick_board(delta: float) -> void:
	var door := _nearby_window()
	if door == null or not Input.is_action_pressed("interact") or int(door.get("boards")) >= int(door.get("max_boards")):
		_board_time = 0.0
		_board_target = null
		return
	if door != _board_target:
		_board_target = door
		_board_time = 0.0
	_board_time += delta
	if _board_time >= BOARD_HOLD:
		_board_time = 0.0
		door.call("board", self)

func _nearby_window() -> Node:
	var best: Node = null
	var best_d := 2.1
	var facing := -global_transform.basis.z
	facing.y = 0.0
	if facing.length() < 0.01:
		return null
	facing = facing.normalized()
	for node in get_tree().get_nodes_in_group("barricades"):
		var body := node as Node3D
		if body == null:
			continue
		var flat := body.global_position - global_position
		flat.y = 0.0
		var dist := flat.length()
		if dist >= best_d or dist < 0.05:
			continue
		if facing.dot(flat / dist) < 0.2:
			continue
		best = body
		best_d = dist
	return best

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
	var door := _nearby_window()
	if door != null and door.has_method("prompt_for"):
		var text := str(door.call("prompt_for", self))
		if door == _board_target and _board_time > 0.0:
			text = "%s  %d%%" % [text, int((_board_time / BOARD_HOLD) * 100.0)]
		hud.call("set_prompt", text)
		return
	var hit := _look_hit(2.6)
	if hit != null and hit.has_method("prompt_for"):
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
		"cowboy":
			ult_time = 5.0
			GameState.toast("Market Crash")
		"punk_f":
			ult_time = 6.0
			GameState.toast("Cloud Cover")
		"worker":
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
	if ult_active == "worker":
		_nap_invuln = false
		_shove()
	ult_active = ""

func _shove() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(node.global_position) <= 4.5:
			node.call("knockback", global_position)

func market_crash_active() -> bool:
	return ult_active == "cowboy"

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
	_gunshot.stream = _shot_stream()
	_gunshot.volume_db = 1.5 if heavy else -4.0
	_gunshot.pitch_scale = randf_range(0.72, 0.8) if weapon_id == "ledger_cannon" else (randf_range(0.94, 1.0) if side == 0 else randf_range(1.02, 1.08))
	_gunshot.play()

func _shot_stream() -> AudioStream:
	if weapon_id == "ledger_cannon" or weapon_id == "pop_junk":
		return SHOT_BLASTER
	if weapon_tier >= 3:
		if weapon_id in ["street_smg", "rent_rifle"]:
			return SHOT_SCI_GUN
		return SHOT_BLASTER
	if weapon_id == "pipe_pistol" and weapon_tier >= 2:
		return SHOT_HEAVY
	return SHOTS.get(weapon_id, SHOTS["pipe_pistol"])

func _laser_muzzle() -> bool:
	return weapon_id == "pop_junk" or weapon_id == "ledger_cannon" or weapon_tier >= 3

func _flash_tex(laser: bool) -> Texture2D:
	return FLASH_LASER if laser else FLASH_GUN

func _muzzle_index(side: int) -> int:
	if _akimbo() and _muzzle_guns.size() > 1:
		return 0 if side == 1 else 1
	return 0

func _barrel_tip(side: int = 0) -> Vector3:
	var fallback := camera.to_global(Vector3(0.18, -0.08, -0.62))
	var tips := _live_muzzles(side)
	if tips.is_empty():
		return fallback
	if weapon_id == "ledger_cannon":
		return tips[_nozzle % tips.size()]
	return tips[0]

func _live_muzzles(side: int) -> PackedVector3Array:
	var tips := PackedVector3Array()
	if _muzzle_guns.is_empty():
		return tips
	var idx := _muzzle_index(side)
	if idx >= _muzzle_guns.size():
		idx = 0
	var rig := _muzzle_guns[idx]
	if rig == null or not is_instance_valid(rig):
		return tips
	for node in rig.find_children("*", "Skeleton3D", true, false):
		(node as Skeleton3D).force_update_all_bone_transforms()
	var held := rig.find_child("HeldGun", true, false) as Node3D
	var host: Node = held if held != null else rig
	var pts := _posed_points(host, held == null)
	if pts.is_empty():
		return tips
	var cluster := _far_cluster(pts)
	if weapon_id == "ledger_cannon":
		return _split_nozzles(cluster)
	tips.append(_cluster_center(cluster))
	return tips

func _posed_points(host: Node, stock_only: bool) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var meshes: Array[Node] = []
	if host is MeshInstance3D:
		meshes.append(host)
	meshes.append_array(host.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mesh_inst := node as MeshInstance3D
		if mesh_inst.mesh == null or not mesh_inst.visible or String(mesh_inst.name) == "MuzzleFlash":
			continue
		var n := String(mesh_inst.name).to_lower()
		if "arm" in n or "hand" in n:
			continue
		if stock_only and not ("glock" in n or "akm" in n):
			continue
		var skel: Skeleton3D = null
		if mesh_inst.skin != null and mesh_inst.skeleton != NodePath():
			skel = mesh_inst.get_node_or_null(mesh_inst.skeleton) as Skeleton3D
		if skel != null:
			pts.append_array(_skinned_points(mesh_inst, skel))
			continue
		for s in mesh_inst.mesh.get_surface_count():
			var verts := _surface_verts(mesh_inst.mesh, s)
			var step := maxi(1, int(verts.size() / 300.0))
			for i in range(0, verts.size(), step):
				pts.append(mesh_inst.global_transform * verts[i])
	return pts

func _far_cluster(pts: PackedVector3Array) -> PackedVector3Array:
	var cam := camera.global_position
	var best := 0.0
	for p in pts:
		best = maxf(best, cam.distance_squared_to(p))
	var limit := sqrt(best)
	var band := maxf(0.03, limit * 0.03)
	var cluster := PackedVector3Array()
	for p in pts:
		if cam.distance_to(p) >= limit - band:
			cluster.append(p)
	if cluster.is_empty():
		cluster.append(pts[0])
	return cluster

func _cluster_center(cluster: PackedVector3Array) -> Vector3:
	var acc := Vector3.ZERO
	for p in cluster:
		acc += p
	var center := acc / float(cluster.size())
	var away := center - camera.global_position
	if away.length_squared() > 0.0001:
		center += away.normalized() * 0.02
	return center

func _split_nozzles(cluster: PackedVector3Array) -> PackedVector3Array:
	var axis := camera.global_transform.basis.x
	var keyed: Array = []
	for p in cluster:
		keyed.append({"d": axis.dot(p), "p": p})
	keyed.sort_custom(func(a, b): return float(a.d) < float(b.d))
	var tips := PackedVector3Array()
	var n := keyed.size()
	if n < 3:
		var lone := _cluster_center(cluster)
		tips.append(lone)
		tips.append(lone)
		tips.append(lone)
		return tips
	var third := maxi(1, int(float(n) / 3.0))
	for bin in 3:
		var start := bin * third
		var stop := n if bin == 2 else mini(n, (bin + 1) * third)
		var acc := Vector3.ZERO
		var count := 0
		for i in range(start, stop):
			acc += keyed[i].p
			count += 1
		var center := acc / float(maxi(count, 1))
		var away := center - camera.global_position
		if away.length_squared() > 0.0001:
			center += away.normalized() * 0.02
		tips.append(center)
	return tips

func _skinned_points(mesh_inst: MeshInstance3D, skel: Skeleton3D) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var skin := mesh_inst.skin
	if skin == null or mesh_inst.mesh == null:
		return pts
	for s in mesh_inst.mesh.get_surface_count():
		var arrays: Array = mesh_inst.mesh.surface_get_arrays(s)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var step := maxi(1, int(verts.size() / 300.0))
		for i in range(0, verts.size(), step):
			var basis := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
			var origin := Vector3.ZERO
			for k in 4:
				var w := weights[i * 4 + k]
				if w < 0.001:
					continue
				var b := int(joints[i * 4 + k])
				if b < 0 or b >= skel.get_bone_count() or b >= skin.get_bind_count():
					continue
				var posed := skel.get_bone_global_pose(b) * skin.get_bind_pose(b)
				basis.x += posed.basis.x * w
				basis.y += posed.basis.y * w
				basis.z += posed.basis.z * w
				origin += posed.origin * w
			pts.append(skel.global_transform * (basis * verts[i] + origin))
	return pts

func _surface_verts(mesh: Mesh, surface: int) -> PackedVector3Array:
	var arrays: Array = mesh.surface_get_arrays(surface)
	if arrays.is_empty() or arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
		return PackedVector3Array()
	return arrays[Mesh.ARRAY_VERTEX]

func _register_muzzle(rig: Node3D) -> void:
	_muzzle_guns.append(rig)
	var flash := MeshInstance3D.new()
	flash.name = "MuzzleFlash"
	var span := 0.48
	if weapon_id == "debt_shotgun":
		span = 0.68
	elif weapon_id == "rent_rifle":
		span = 0.58
	elif weapon_id == "street_smg":
		span = 0.54
	elif weapon_id == "ledger_cannon":
		span = 0.72
	var quad := QuadMesh.new()
	quad.size = Vector2(span, span)
	flash.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _flash_tex(_laser_muzzle())
	mat.albedo_color = Color.WHITE
	flash.material_override = mat
	_gun_mount.add_child(flash)
	flash.top_level = true
	flash.visible = false
	var light := OmniLight3D.new()
	light.light_energy = 0.0
	light.omni_range = 1.6
	light.shadow_enabled = false
	light.light_color = Color(0.45, 0.35, 1.0) if _laser_muzzle() else Color(1.0, 0.65, 0.2)
	flash.add_child(light)
	_muzzle_flashes.append(flash)

func _pop_muzzle(side: int) -> void:
	if _muzzle_flashes.is_empty():
		return
	var idx := _muzzle_index(side)
	if idx >= _muzzle_flashes.size():
		idx = 0
	var flash := _muzzle_flashes[idx]
	if flash == null or not is_instance_valid(flash):
		return
	flash.global_position = _barrel_tip(side)
	flash.scale = Vector3.ONE * randf_range(0.9, 1.25)
	flash.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	flash.visible = true
	if flash.get_child_count() > 0:
		var light := flash.get_child(0) as OmniLight3D
		if light:
			light.light_energy = 2.6 if _laser_muzzle() else 1.9
	var gap := 0.07 if _uses_burst() else 1.0 / maxf(_shots_per_second(), 1.0)
	_muzzle_time = clampf(gap * 0.55, 0.03, 0.055)

func _tick_muzzle(delta: float) -> void:
	if _muzzle_time <= 0.0:
		return
	_muzzle_time -= delta
	if _muzzle_time > 0.0:
		return
	for flash in _muzzle_flashes:
		if flash == null or not is_instance_valid(flash):
			continue
		flash.visible = false
		if flash.get_child_count() > 0:
			var light := flash.get_child(0) as OmniLight3D
			if light:
				light.light_energy = 0.0

func _spawn_tracer(_dir: Vector3, impact: Vector3, hand_bias: float = 0.0) -> void:
	var side := 0
	if _akimbo():
		side = 1 if hand_bias > 0.0 else 0
	var start := _barrel_tip(side)
	var delta := impact - start
	var dist := delta.length()
	if dist < 0.25:
		return
	var laser := _laser_muzzle()
	var streak := MeshInstance3D.new()
	var box := BoxMesh.new()
	var thick := 0.022 if laser else 0.008
	if weapon_id == "debt_shotgun" and not laser:
		thick = 0.005
	box.size = Vector3(thick, thick, dist)
	streak.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.55, 0.45, 1.0, 0.95) if laser else Color(1.0, 0.62, 0.12, 0.9)
	streak.material_override = mat
	var host := get_tree().current_scene
	if host == null:
		host = self
	host.add_child(streak)
	streak.global_position = start + delta * 0.5
	if delta.length_squared() > 0.0001:
		streak.look_at(impact, camera.global_transform.basis.y)
	var life := 0.12 if laser else 0.07
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(streak.queue_free)

func _ads_fov() -> float:
	if weapon_id in ["debt_shotgun", "rent_rifle", "ledger_cannon"]:
		return ADS_FOV_LONG
	return ADS_FOV

func _arm_rig() -> Dictionary:
	if weapon_id in ["debt_shotgun", "rent_rifle", "ledger_cannon"] or (weapon_id == "street_smg" and weapon_tier >= 3):
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
	_muzzle_flashes.clear()
	_muzzle_guns.clear()
	_muzzle_time = 0.0
	_nozzle = 0
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
		_spawn_arm(rig_packed, arms, 0.14, false)
		_spawn_arm(rig_packed, arms, 0.14, true)
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
	if weapon_id == "ledger_cannon":
		_seat_held(rig, "res://assets/weapons/ledger_cannon.glb", Vector3(-1, 0, 0), Vector3(0, 1, 0), 1.15, "akm", 0.34, true, 0.7, false, false)
	elif weapon_id == "pop_junk":
		_seat_held(rig, "res://assets/weapons/ray_gun.glb", Vector3(0, 0, -1), Vector3(0, 1, 0), 0.52, "glock")
	elif weapon_id == "pipe_pistol" and weapon_tier >= 3:
		_seat_held(rig, "res://assets/weapons/pistol_v3.glb", Vector3(0, 0, -1), Vector3(0, 1, 0), 0.56, "glock")
	elif weapon_id == "pipe_pistol" and weapon_tier == 2:
		_seat_held(rig, "res://assets/weapons/pistol_v2.glb", Vector3(1, 0, 0), Vector3(0, 1, 0), 0.52, "glock")
	elif weapon_id == "street_smg" and weapon_tier >= 3:
		_seat_held(rig, "res://assets/weapons/smg_v3.glb", Vector3(1, 0, 0), Vector3(0, 1, 0), 0.95, "akm", 0.3, true, 0.25, false, true, 0.04)
	elif weapon_id == "street_smg" and weapon_tier == 2:
		_seat_held(rig, "res://assets/weapons/smg.glb", Vector3(1, 0, 0), Vector3(0, 1, 0), 0.55, "glock", 0.34, true, 0.0, true, false, -0.035, 0.03)
	elif weapon_id == "street_smg":
		_seat_held(rig, "res://assets/weapons/smg_v1.glb", Vector3(1, 0, 0), Vector3(0, 1, 0), 0.54, "glock", 0.28, true, 0.0, false, true, 0.0, 0.0, 0.08)
	elif weapon_id == "debt_shotgun" and weapon_tier >= 3:
		_seat_held(rig, "res://assets/weapons/shotgun_v3.glb", Vector3(1, 0, 0), Vector3(0, 1, 0), 1.25, "akm", 0.32, true, 0.0)
	elif weapon_id == "debt_shotgun" and weapon_tier == 2:
		_seat_held(rig, "res://assets/weapons/shotgun_v2.glb", Vector3(1, 0, 0), Vector3(0, 1, 0), 1.05, "akm", 0.3, true, 0.7)
	elif weapon_id == "debt_shotgun":
		_seat_held(rig, "res://assets/weapons/mossberg.glb", Vector3(1, 0, 0), Vector3(0, 1, 0), 1.35, "akm", 0.3, true, 0.0)
	elif weapon_id == "rent_rifle" and weapon_tier >= 3:
		_seat_held(rig, "res://assets/weapons/rifle_v3.glb", Vector3(1, 0, 0), Vector3(0, 1, 0), 1.15, "akm", 0.34, true, 0.7, false, false)
	elif weapon_id == "rent_rifle" and weapon_tier < 2:
		_seat_held(rig, "res://assets/weapons/rifle.glb", Vector3(0, 0, -1), Vector3(0, 1, 0), 1.15, "akm", 0.34, true, 0.25)
	if _akimbo():
		_collapse_support_hand(rig)
	pivot.position.x = _aim_nudge()
	_register_muzzle(rig)
	if weapon_id == "street_smg" and weapon_tier == 2:
		_point_barrel_at_crosshair(rig)
	var bucket := _offhand_anims if mirror else _view_anims
	for anim in rig.find_children("*", "AnimationPlayer", true, false):
		bucket.append(anim as AnimationPlayer)

func _point_barrel_at_crosshair(rig: Node3D) -> void:
	var gun := rig.find_child("HeldGun", true, false) as Node3D
	if gun == null or gun.get_child_count() == 0:
		return
	var model := gun.get_child(0) as Node3D
	var skeleton := gun.get_parent() as Skeleton3D
	if model == null or skeleton == null:
		return
	var hand := skeleton.find_bone("Hand.R.001")
	if hand < 0:
		return
	var pivot := (skeleton.global_transform * skeleton.get_bone_global_pose(hand)).origin
	var xf := model.global_transform
	var barrel := xf.basis.x.normalized()
	var muzzle := _barrel_tip(0)
	if muzzle.distance_squared_to(pivot) > 0.01 and barrel.dot(muzzle - pivot) < 0.0:
		barrel = -barrel
	var want := (camera.global_position - camera.global_transform.basis.z * 40.0 - pivot).normalized()
	if barrel.dot(want) > 0.9995:
		return
	var rot := Quaternion(barrel, want)
	var scale := xf.basis.get_scale()
	var spun := Basis(rot) * xf.basis.orthonormalized()
	var origin := pivot + rot * (xf.origin - pivot)
	model.global_transform = Transform3D(spun.scaled(scale), origin)

func _collapse_support_hand(rig: Node3D) -> void:
	for node in rig.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		if skeleton.find_bone("UpperArm.L") < 0:
			continue
		var modifier := preload("res://scripts/collapse_left_arm.gd").new() as SkeletonModifier3D
		skeleton.add_child(modifier)

func _aim_nudge() -> float:
	if weapon_id == "pipe_pistol" and weapon_tier >= 3:
		return 0.0
	if weapon_id == "pipe_pistol" and weapon_tier == 2:
		return -0.214
	if weapon_id == "pipe_pistol":
		return -0.211
	if weapon_id == "street_smg" and weapon_tier == 2:
		return -0.183
	if weapon_id == "street_smg" and weapon_tier < 2:
		return -0.214
	if weapon_id == "debt_shotgun" and weapon_tier == 2:
		return 0.048
	if weapon_id == "rent_rifle" and weapon_tier >= 3:
		return 0.1
	if weapon_id == "pop_junk":
		return -0.216
	if weapon_id == "ledger_cannon":
		return 0.034
	return 0.0

func _seat_held(rig: Node3D, path: String, model_fwd: Vector3, model_up: Vector3, world_length: float, hide_name: String, grip_t: float = 0.22, plant_hand: bool = false, nudge_support: float = 0.0, use_bolt: bool = false, auto_flip: bool = true, grip_lift: float = 0.0, side_shift: float = 0.0, barrel_slide: float = 0.0) -> void:
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
	for anim in rig.find_children("*", "AnimationPlayer", true, false):
		(anim as AnimationPlayer).stop()
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	var packed := load(path) as PackedScene
	if packed == null:
		return
	_attach_held(skeleton, packed, model_fwd, model_up, world_length, grip_t, plant_hand, nudge_support, use_bolt, auto_flip, grip_lift, side_shift, barrel_slide)

func _attach_held(skeleton: Skeleton3D, packed: PackedScene, model_fwd: Vector3, model_up: Vector3, world_length: float, grip_t: float = 0.22, plant_hand: bool = false, nudge_support: float = 0.0, use_bolt: bool = false, auto_flip: bool = true, grip_lift: float = 0.0, side_shift: float = 0.0, barrel_slide: float = 0.0) -> void:
	var bone := skeleton.find_bone("Root")
	if bone < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "HeldGun"
	attachment.bone_name = "Root"
	skeleton.add_child(attachment)
	var gun := packed.instantiate() as Node3D
	attachment.add_child(gun)
	gun.transform = Transform3D.IDENTITY
	var bone_xf := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var bone_basis := bone_xf.basis.orthonormalized()
	var world_fwd := -camera.global_transform.basis.z
	if use_bolt:
		var aim_bone := skeleton.find_bone("Barrel")
		if aim_bone < 0:
			aim_bone = skeleton.find_bone("Bolt")
		if aim_bone >= 0:
			var barrel_xf := skeleton.global_transform * skeleton.get_bone_global_pose(aim_bone)
			var along := barrel_xf.origin - bone_xf.origin
			if along.length() > 0.001:
				world_fwd = along.normalized()
	var local_fwd: Vector3 = (bone_basis.inverse() * world_fwd).normalized()
	var local_up: Vector3 = (bone_basis.inverse() * Vector3.UP).normalized()
	gun.quaternion = _map_axes(model_fwd.normalized(), model_up.normalized(), local_fwd, local_up)
	var box := _visual_aabb(gun)
	var current := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if current > 0.0001:
		gun.scale *= world_length / current
	box = _visual_aabb(gun)
	var half := absf(world_fwd.x) * box.size.x + absf(world_fwd.y) * box.size.y + absf(world_fwd.z) * box.size.z
	var rear: Vector3 = box.get_center() - world_fwd * (half * 0.5)
	var grip: Vector3 = _held_grip(gun, rear, world_fwd, world_length, grip_t)
	if auto_flip and grip.distance_squared_to(_aabb_support(box, world_fwd)) < grip.distance_squared_to(_aabb_support(box, -world_fwd)):
		gun.quaternion = _map_axes(-model_fwd.normalized(), model_up.normalized(), local_fwd, local_up)
		box = _visual_aabb(gun)
		half = absf(world_fwd.x) * box.size.x + absf(world_fwd.y) * box.size.y + absf(world_fwd.z) * box.size.z
		rear = box.get_center() - world_fwd * (half * 0.5)
	var plant := attachment.global_position
	if plant_hand:
		var hand_r := skeleton.find_bone("Hand.R.001")
		if hand_r >= 0:
			var right_pos: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(hand_r)).origin
			plant += world_fwd * world_fwd.dot(right_pos - plant)
	gun.global_position += plant - _held_grip(gun, rear, world_fwd, world_length, grip_t)
	if nudge_support > 0.0:
		var hand_l := skeleton.find_bone("Hand.L")
		if hand_l >= 0:
			var left_pos: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(hand_l)).origin
			var on_barrel: Vector3 = plant + world_fwd * world_fwd.dot(left_pos - plant)
			gun.global_position += (left_pos - on_barrel) * nudge_support
	if grip_lift != 0.0:
		gun.global_position -= camera.global_transform.basis.y * grip_lift
	if side_shift != 0.0:
		gun.global_position += camera.global_transform.basis.x * side_shift
	if barrel_slide != 0.0:
		gun.global_position += world_fwd * barrel_slide
	_color_viewmodel(gun)

func _aabb_support(box: AABB, dir: Vector3) -> Vector3:
	var point := box.position
	if dir.x > 0.0:
		point.x += box.size.x
	if dir.y > 0.0:
		point.y += box.size.y
	if dir.z > 0.0:
		point.z += box.size.z
	return point

func _held_grip(gun: Node3D, rear: Vector3, world_fwd: Vector3, world_length: float, grip_t: float) -> Vector3:
	for node in gun.find_children("*", "Skeleton3D", true, false):
		var candidate := node as Skeleton3D
		var grip := candidate.find_bone("Root")
		if grip >= 0:
			return (candidate.global_transform * candidate.get_bone_global_pose(grip)).origin
	return rear + world_fwd * world_length * grip_t

func _map_axes(from_fwd: Vector3, from_up: Vector3, to_fwd: Vector3, to_up: Vector3) -> Quaternion:
	return (_axis_basis(to_fwd, to_up) * _axis_basis(from_fwd, from_up).inverse()).get_rotation_quaternion()

func _axis_basis(fwd: Vector3, up: Vector3) -> Basis:
	var f := fwd.normalized()
	var r := up.normalized().cross(f)
	if r.length_squared() < 0.0001:
		r = Vector3.UP.cross(f)
	if r.length_squared() < 0.0001:
		r = Vector3.RIGHT.cross(f)
	r = r.normalized()
	var u := f.cross(r).normalized()
	return Basis(r, u, f)

func _visual_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var any := false
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.insert(0, node)
	for mesh_node in meshes:
		var mesh_inst := mesh_node as MeshInstance3D
		if mesh_inst.mesh == null or not mesh_inst.visible or String(mesh_inst.name) == "MuzzleFlash":
			continue
		var local := mesh_inst.get_aabb()
		var xf := mesh_inst.global_transform
		for i in 8:
			var corner := Vector3(
				local.position.x + local.size.x * float(i & 1),
				local.position.y + local.size.y * float((i >> 1) & 1),
				local.position.z + local.size.z * float((i >> 2) & 1)
			)
			var point := xf * corner
			if not any:
				box = AABB(point, Vector3.ZERO)
				any = true
			else:
				box = box.expand(point)
	return box

func _hold_idle() -> void:
	if _burst_left > 0:
		return
	if not _akimbo():
		if _reload > 0.0:
			return
		for anim in _all_view_anims():
			if anim.is_playing():
				continue
			var idle := _view_clip(anim, "idle")
			if idle != "":
				anim.play(idle)
		return
	if _reload <= 0.0:
		for anim in _offhand_anims:
			if anim.is_playing():
				continue
			var idle := _view_clip(anim, "idle")
			if idle != "":
				anim.play(idle)
	if _off_reload <= 0.0:
		for anim in _view_anims:
			if anim.is_playing():
				continue
			var idle := _view_clip(anim, "idle")
			if idle != "":
				anim.play(idle)

func _color_viewmodel(node: Node) -> void:
	if String(node.name) == "MuzzleFlash":
		return
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
