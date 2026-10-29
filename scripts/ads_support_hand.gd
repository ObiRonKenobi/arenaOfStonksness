extends SkeletonModifier3D

var aim_onto_barrel := false

var _base := Vector3.ZERO
var _written := Vector3.ZERO
var _holding := false

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var arm := skeleton.find_bone("UpperArm.L")
	if arm < 0:
		return
	var player := skeleton.get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var camera := player.get_node_or_null("Head/Camera3D") as Camera3D
	if camera == null:
		return
	var pose := skeleton.get_bone_pose(arm)
	if _holding and pose.origin.is_equal_approx(_written):
		pose.origin = _base
	else:
		_base = pose.origin
		_holding = false
	skeleton.set_bone_pose(arm, pose)
	var aim := 0.0
	if aim_onto_barrel:
		aim = clampf(float(player.get("_aim")), 0.0, 1.0)
	var world := Vector3.ZERO
	if aim > 0.001:
		var fist := _fist_center(skeleton)
		var target := _barrel_point(skeleton, camera)
		if fist.is_finite() and target.is_finite():
			world += (target - fist).limit_length(0.7) * aim
	if world.length_squared() < 0.0000004:
		_holding = false
		return
	pose.origin = _base + skeleton.global_transform.basis.inverse() * world
	_written = pose.origin
	_holding = true
	skeleton.set_bone_pose(arm, pose)

func _fist_center(skeleton: Skeleton3D) -> Vector3:
	var hand := skeleton.find_bone("Hand.L")
	if hand < 0:
		return Vector3(INF, INF, INF)
	var total := Vector3.ZERO
	var count := 0
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if mesh_inst.mesh == null or mesh_inst.skin == null or mesh_inst.name == "MuzzleFlash":
			continue
		var skin := mesh_inst.skin
		for surface in mesh_inst.mesh.get_surface_count():
			var arrays: Array = mesh_inst.mesh.surface_get_arrays(surface)
			if arrays.is_empty() or arrays[Mesh.ARRAY_BONES] == null:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var step := maxi(1, int(verts.size() / 80.0))
			for i in range(0, verts.size(), step):
				var best := -1
				var best_w := 0.0
				for k in 4:
					var w := weights[i * 4 + k]
					if w > best_w:
						best_w = w
						best = int(joints[i * 4 + k])
				if best != hand:
					continue
				var posed := skeleton.get_bone_global_pose(best) * skin.get_bind_pose(best)
				total += skeleton.global_transform * (posed * verts[i])
				count += 1
	if count == 0:
		return Vector3(INF, INF, INF)
	return total / float(count)

func _barrel_point(skeleton: Skeleton3D, camera: Camera3D) -> Vector3:
	var gun := skeleton.find_child("HeldGun", true, false) as Node3D
	if gun == null:
		return Vector3(INF, INF, INF)
	var box := AABB()
	var any := false
	for node in gun.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if mesh_inst.mesh == null or not mesh_inst.visible:
			continue
		var local := mesh_inst.get_aabb()
		var xf := mesh_inst.global_transform
		for i in 8:
			var corner := xf * Vector3(
				local.position.x + local.size.x * float(i & 1),
				local.position.y + local.size.y * float((i >> 1) & 1),
				local.position.z + local.size.z * float((i >> 2) & 1)
			)
			if not any:
				box = AABB(corner, Vector3.ZERO)
				any = true
			else:
				box = box.expand(corner)
	if not any:
		return Vector3(INF, INF, INF)
	var center := box.get_center()
	var forward := -camera.global_transform.basis.z
	var extent := maxf(absf((box.position - center).dot(forward)), absf((box.position + box.size - center).dot(forward)))
	return center + forward * maxf(0.0, extent - 0.16)
