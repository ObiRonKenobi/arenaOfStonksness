extends StaticBody3D

var title := "Door"
var price := 0
var slide := 1.5
var _open := false
var _mesh: MeshInstance3D
var _shape: CollisionShape3D

func _ready() -> void:
	add_to_group("gates")
	collision_layer = 1
	collision_mask = 1
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.32, 2.35, 0.12)
	_shape.shape = box
	_shape.position = Vector3(0, 1.175, 0)
	add_child(_shape)
	_mesh = MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = box.size
	_mesh.mesh = cube
	_mesh.position = _shape.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.22, 0.14)
	_mesh.material_override = mat
	add_child(_mesh)
	var label := Label3D.new()
	label.text = "%s\n$%d" % [title, price]
	label.font_size = 42
	label.position = Vector3(0, 0.55, -0.1)
	label.modulate = Color(1, 0.95, 0.8)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mesh.add_child(label)

func prompt_for(_player: Node) -> String:
	if _open:
		return ""
	return "E  Open %s  $%d" % [title, price]

func use(player: Node) -> void:
	if _open:
		return
	if not player.call("try_buy", price):
		return
	_open = true
	_shape.disabled = true
	collision_layer = 0
	var tween := create_tween()
	tween.tween_property(_mesh, "position:x", slide, 0.45)
	GameState.toast("%s is open." % title)
