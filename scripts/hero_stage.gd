extends Node3D

var _models: Array[Node3D] = []
var _index := 0
var _built := false

func _ready() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.05, 4.1)
	camera.fov = 30.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)

func setup() -> void:
	if _built:
		return
	_built = true
	for id in CharacterDB.HERO_IDS:
		var packed := CharacterDB.model_scene(id)
		if packed == null:
			continue
		var model := packed.instantiate() as Node3D
		model.name = id
		add_child(model)
		var tints: Array = []
		_ink(model, tints)
		model.set_meta("tints", tints)
		model.set_meta("foot", _foot_drop(model))
		_play_idle(model)
		_models.append(model)
	set_highlight(0)

func model_count() -> int:
	return _models.size()

func step(dir: int) -> void:
	set_highlight(_index + dir)

func current_id() -> String:
	if CharacterDB.HERO_IDS.is_empty():
		return ""
	return CharacterDB.HERO_IDS[posmod(_index, CharacterDB.HERO_IDS.size())]

func set_highlight(index: int) -> void:
	if CharacterDB.HERO_IDS.is_empty():
		return
	_index = posmod(index, CharacterDB.HERO_IDS.size())
	for i in _models.size():
		var model := _models[i]
		var selected := i == _index
		var x := (float(i) - 1.5) * 0.95
		model.position = Vector3(x, float(model.get_meta("foot")), 0.42 if selected else 0.0)
		model.rotation.y = 0.0
		_shade(model, 1.0 if selected else 0.34)

func set_active(on: bool) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

func _shade(model: Node3D, amount: float) -> void:
	for row in model.get_meta("tints"):
		var mat := row["mat"] as StandardMaterial3D
		var color: Color = row["color"]
		mat.albedo_color = Color(color.r * amount, color.g * amount, color.b * amount, color.a)

func _play_idle(model: Node) -> void:
	var players: Array = model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var anim := players[0] as AnimationPlayer
	var clip := ""
	if anim.has_animation("Idle"):
		clip = "Idle"
	else:
		for name in anim.get_animation_list():
			if "idle" in String(name).to_lower():
				clip = String(name)
				break
	if clip == "":
		return
	var animation := anim.get_animation(clip)
	if animation:
		animation.loop_mode = Animation.LOOP_LINEAR
	anim.play(clip)

func _foot_drop(root: Node3D) -> float:
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
		return 0.0
	return -box.position.y

func _ink(node: Node, bucket: Array) -> void:
	for child in node.get_children():
		_ink(child, bucket)
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
		bucket.append({"mat": flat, "color": flat.albedo_color})
