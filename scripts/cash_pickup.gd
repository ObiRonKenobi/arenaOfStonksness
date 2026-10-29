extends Area3D

const PICKUP_SFX := preload("res://assets/audio/cash_pickup.wav")

var amount := 40
var kind := "cash"

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
		bill.position = Vector3(0.0, 0.03 + float(i) * 0.04, 0.0)
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
		body.call("heal", 45.0)
	elif kind == "ammo" and body.has_method("refill_weapon"):
		body.call("refill_weapon", str(body.get("weapon_id")))
	elif kind == "full":
		for player in get_tree().get_nodes_in_group("player"):
			if player.has_method("refill_carried_ammo"):
				player.call("refill_carried_ammo")
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
