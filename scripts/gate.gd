extends StaticBody3D

const DOOR_MODEL := preload("res://assets/props/door.glb")

var title := "Door"
var price := 0
var slide := 1.32
var _open := false
var _mesh: Node3D
var _shape: CollisionShape3D
var _nav_block: CollisionShape3D

func _ready() -> void:
	add_to_group("gates")
	collision_layer = 1
	collision_mask = 1
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.4, 0.06)
	_shape.shape = box
	# Recessed behind the interior brick so the pier covers the panel once it slides.
	_shape.position = Vector3(0, 1.2, 0.08)
	add_child(_shape)
	_mesh = DOOR_MODEL.instantiate() as Node3D
	add_child(_mesh)
	_fit_door(_mesh, box.size, _shape.position)
	# Physics seal. Left out of the nav bake, so opening a door never rebuilds the floor.
	_nav_block = CollisionShape3D.new()
	var block := BoxShape3D.new()
	block.size = Vector3(2.0, 2.4, 0.5)
	_nav_block.shape = block
	_nav_block.position = Vector3(0, 1.2, 0)
	add_child(_nav_block)

func prompt_for(_player: Node) -> String:
	if _open:
		return ""
	return "E  Open %s  $%d" % [title, price]

func set_open(open: bool) -> void:
	_open = open
	if _shape:
		_shape.disabled = open
	if _nav_block:
		_nav_block.disabled = open
	collision_layer = 0 if open else 1
	if _mesh:
		_mesh.visible = not open
		_mesh.position.x = slide if open else 0.0

func use(player: Node) -> void:
	if _open:
		return
	if not player.call("try_buy", price):
		return
	_open = true
	_shape.disabled = true
	_nav_block.disabled = true
	collision_layer = 0
	_play_unlock()
	var tween := create_tween()
	tween.tween_property(_mesh, "position:x", slide, 0.45)
	tween.finished.connect(func() -> void: _mesh.visible = false)
	GameState.toast("%s is open." % title)

func _play_unlock() -> void:
	var stream := load("res://assets/audio/door_unlock.mp3") as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = -4.0
	player.pitch_scale = 1.0
	player.unit_size = 3.0
	player.max_distance = 24.0
	player.position = _shape.position
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _fit_door(door: Node3D, size: Vector3, center: Vector3) -> void:
	var box := _door_bounds(door)
	if box.size.x < 0.001 or box.size.y < 0.001 or box.size.z < 0.001:
		door.position = center
		return
	door.scale = Vector3(size.x / box.size.x, size.y / box.size.y, size.z / box.size.z)
	var mid := box.get_center()
	door.position = center - Vector3(mid.x * door.scale.x, mid.y * door.scale.y, mid.z * door.scale.z)

func _door_bounds(root: Node3D) -> AABB:
	var box := AABB()
	var started := false
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node)
	for mesh_node in meshes:
		if mesh_node.mesh == null:
			continue
		var local := mesh_node.mesh.get_aabb()
		var to_root := root.global_transform.affine_inverse() * mesh_node.global_transform
		for i in 8:
			var point: Vector3 = to_root * local.get_endpoint(i)
			if not started:
				box = AABB(point, Vector3.ZERO)
				started = true
			else:
				box = box.expand(point)
	return box
