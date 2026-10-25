extends Area3D

const PICKUP_SFX := preload("res://assets/audio/cash_pickup.wav")

var amount := 40

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
	for i in 4:
		var bill := MeshInstance3D.new()
		var slab := BoxMesh.new()
		slab.size = Vector3(0.36, 0.035, 0.18)
		bill.mesh = slab
		bill.position = Vector3(0.0, 0.03 + float(i) * 0.04, 0.0)
		bill.rotation.y = deg_to_rad(-8.0 if i % 2 == 0 else 6.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.55, 0.28).lerp(Color(0.75, 0.82, 0.55), float(i) * 0.12)
		bill.material_override = mat
		add_child(bill)
	var mark := Label3D.new()
	mark.text = "$"
	mark.font_size = 48
	mark.position = Vector3(0.0, 0.22, 0.0)
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.modulate = Color(0.95, 0.9, 0.45)
	add_child(mark)

func _on_body(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("add_cash"):
		body.call("add_cash", amount)
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
