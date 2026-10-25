extends SkeletonModifier3D

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var arm := skeleton.find_bone("UpperArm.L")
	if arm < 0:
		return
	_squash(skeleton, arm)

func _squash(skeleton: Skeleton3D, bone: int) -> void:
	skeleton.set_bone_pose_scale(bone, Vector3(0.001, 0.001, 0.001))
	for child in skeleton.get_bone_children(bone):
		_squash(skeleton, child)
