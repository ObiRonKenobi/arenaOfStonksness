extends SceneTree

var _box := AABB()
var _any := false

func _initialize() -> void:
	call_deferred("_measure")

func _measure() -> void:
	for path in ["res://assets/weapons/fps_pistol.glb", "res://assets/weapons/fps_rifle.glb"]:
		var packed := load(path) as PackedScene
		if packed == null:
			print("MISSING ", path)
			continue
		var node := packed.instantiate()
		root.add_child(node)
		_box = AABB()
		_any = false
		_walk(node)
		print(path, " pos ", _box.position, " size ", _box.size)
		for skel in node.find_children("*", "Skeleton3D", true, false):
			var skeleton := skel as Skeleton3D
			print(" skeleton ", skeleton.name, " bones ", skeleton.get_bone_count())
			for bone_name in ["Root", "Hand.L", "Hand.R.001", "UpperArm.R.001"]:
				var idx := skeleton.find_bone(bone_name)
				if idx < 0:
					continue
				var origin := skeleton.global_transform * skeleton.get_bone_global_pose(idx).origin
				print("  ", bone_name, origin)
		node.free()
	quit()

func _walk(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		if mesh_inst.mesh:
			var local := mesh_inst.mesh.get_aabb()
			var xf := mesh_inst.global_transform
			for i in 8:
				var corner := Vector3(
					local.position.x + local.size.x * float(i & 1),
					local.position.y + local.size.y * float((i >> 1) & 1),
					local.position.z + local.size.z * float((i >> 2) & 1)
				)
				var point := xf * corner
				if not _any:
					_box = AABB(point, Vector3.ZERO)
					_any = true
				else:
					_box = _box.expand(point)
	for child in node.get_children():
		_walk(child)
