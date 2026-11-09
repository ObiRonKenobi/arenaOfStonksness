extends Area3D

const PICKUP_SFX := preload("res://assets/audio/cash_pickup.wav")
const GRAVITY := 20.0
const MAX_FALL := 20.0

var amount := 40
var kind := "cash"
var _floor_y := NAN
var _fall_speed := 0.0

func _ready() -> void:
	body_entered.connect(_on_body)
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.42, 0.28, 0.28)
	shape.shape = box
	shape.position.y = box.size.y * 0.5
	add_child(shape)
	var tint := Color(0.16, 0.55, 0.28)
	var mark_text := ""
	var mark_color := Color(0.95, 0.9, 0.45)
	if kind == "health":
		tint = Color(0.75, 0.18, 0.2)
	elif kind == "ammo":
		tint = Color(0.75, 0.48, 0.12)
		mark_text = "ammo"
		mark_color = Color(1.0, 0.86, 0.4)
	elif kind == "full":
		tint = Color(0.42, 0.16, 0.58)
		mark_text = "ammo"
		mark_color = Color(0.86, 0.62, 1.0)
	else:
		mark_text = "$"
	for i in 4:
		var bill := MeshInstance3D.new()
		var slab := BoxMesh.new()
		slab.size = Vector3(0.36, 0.035, 0.18)
		bill.mesh = slab
		bill.position = Vector3(0.0, slab.size.y * 0.5 + float(i) * 0.04, 0.0)
		bill.rotation.y = deg_to_rad(-8.0 if i % 2 == 0 else 6.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint.lerp(Color(0.9, 0.9, 0.8), float(i) * 0.12)
		bill.material_override = mat
		add_child(bill)
	if kind == "health":
		_add_cross()
		return
	var mark := Label3D.new()
	mark.text = mark_text
	mark.font_size = 32 if kind == "ammo" or kind == "full" else 48
	mark.position = Vector3(0.0, 0.28, 0.0)
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.modulate = mark_color
	mark.outline_size = 8
	mark.outline_modulate = Color(0.05, 0.04, 0.03)
	add_child(mark)

func _physics_process(delta: float) -> void:
	if is_nan(_floor_y):
		_floor_y = _find_floor()
	_fall_speed += GRAVITY * delta
	var y := global_position.y - _fall_speed * delta
	if y <= _floor_y:
		y = _floor_y
		set_physics_process(false)
	global_position.y = y

func _find_floor() -> float:
	var skip: Array[RID] = []
	for group in ["player", "barricades"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is CollisionObject3D:
				skip.append((node as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * MAX_FALL)
	query.collision_mask = 1
	query.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return global_position.y
	return (hit.position as Vector3).y

func _add_cross() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.12, 0.16)
	var upright := MeshInstance3D.new()
	var tall := BoxMesh.new()
	tall.size = Vector3(0.055, 0.22, 0.03)
	upright.mesh = tall
	upright.material_override = mat
	upright.position = Vector3(0.0, 0.3, 0.0)
	add_child(upright)
	var bar := MeshInstance3D.new()
	var wide := BoxMesh.new()
	wide.size = Vector3(0.18, 0.055, 0.03)
	bar.mesh = wide
	bar.material_override = mat
	bar.position = upright.position
	add_child(bar)

func _on_body(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if kind == "health" and body.has_method("heal"):
		if body.has_method("needs_health") and not body.call("needs_health"):
			return
		body.call("heal", 45.0)
		queue_free()
		return
	elif kind == "ammo" and body.has_method("refill_weapon"):
		var held := str(body.get("weapon_id"))
		if body.has_method("weapon_needs_ammo") and not body.call("weapon_needs_ammo", held):
			return
		body.call("refill_weapon", held)
		if body.has_method("note_ammo"):
			body.call("note_ammo")
		queue_free()
		return
	elif kind == "full":
		var anyone := false
		for player in get_tree().get_nodes_in_group("player"):
			if player.has_method("carried_needs_ammo") and player.call("carried_needs_ammo"):
				anyone = true
				break
		if not anyone:
			return
		for player in get_tree().get_nodes_in_group("player"):
			if player.has_method("refill_carried_ammo"):
				player.call("refill_carried_ammo")
		GameState.share_ammo()
		queue_free()
		return
	elif body.has_method("add_cash"):
		body.call("add_cash", amount)
	else:
		return
	var tone := AudioStreamPlayer3D.new()
	tone.stream = PICKUP_SFX
	tone.volume_db = -4.0
	var parent := get_parent()
	if parent:
		parent.add_child(tone)
		tone.global_position = global_position
		tone.finished.connect(tone.queue_free)
		tone.play()
	queue_free()
