extends StaticBody3D

const PLANKS := preload("res://assets/textures/planks.png")

var boards := 4
var max_boards := 6
var sill_top := 1.05
var _outside := Vector3.ZERO

func _ready() -> void:
	add_to_group("barricades")
	collision_layer = 1
	collision_mask = 1
	_rebuild()

func spawn_position() -> Vector3:
	var spot := global_position + _outside
	spot.y = 0.05
	var side := Vector3(-_outside.z, 0.0, _outside.x)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	var best := spot
	var best_clear := -1.0
	for slot in [0, 1, -1, 2, -2, 3, -3, 4, -4]:
		var candidate := spot + side * float(slot) * 0.9
		var clear := 4.0
		for other in get_tree().get_nodes_in_group("enemies"):
			var body := other as Node3D
			if body == null:
				continue
			var flat := body.global_position - candidate
			flat.y = 0.0
			clear = minf(clear, flat.length())
		if clear > 0.85:
			return candidate
		if clear > best_clear:
			best_clear = clear
			best = candidate
	return best

func set_outside(offset: Vector3) -> void:
	_outside = offset

func board(player: Node) -> void:
	if boards >= max_boards:
		GameState.toast("This opening is fully boarded.")
		return
	var left := int(player.get("planks"))
	if left <= 0:
		GameState.toast("You need planks.")
		return
	player.set("planks", left - 1)
	boards += 1
	_rebuild()
	GameState.toast("Boarded. Planks left: %d" % int(player.get("planks")))

func chip(_amount: int = 1) -> void:
	if boards <= 0:
		return
	boards -= 1
	_rebuild()

func prompt_for(player: Node) -> String:
	if boards >= max_boards:
		return "Fully boarded"
	return "E  Board up  (%d planks)" % int(player.get("planks"))

func _rebuild() -> void:
	for child in get_children():
		child.free()
	collision_layer = 1 if boards > 0 else 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 0.21 * maxf(boards, 1), 0.16)
	shape.shape = box
	shape.position = Vector3(0, box.size.y * 0.5, 0)
	shape.disabled = boards <= 0
	add_child(shape)
	if boards <= 0:
		return
	for i in boards:
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(1.48, 0.18, 0.14)
		mesh.mesh = cube
		mesh.position = Vector3(0, 0.12 + float(i) * 0.21, 0)
		mesh.rotation_degrees = Vector3(0, 0, -2.5 if i % 2 == 0 else 2.0)
		mesh.material_override = _plank_material(i)
		add_child(mesh)

func _plank_material(row: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = PLANKS
	mat.uv1_scale = Vector3(1.0, 0.14, 1.0)
	mat.uv1_offset = Vector3(float(row) * 0.15, 0.04 + float(row) * 0.14, 0.0)
	return mat
