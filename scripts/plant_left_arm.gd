extends SkeletonModifier3D

var shift := Vector3(-0.040, 0.032, 0.0)
var roll := 0.0

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var camera := _camera()
	if camera == null:
		return
	var arm := skeleton.find_bone("UpperArm.L")
	if arm >= 0 and shift.length_squared() > 0.0:
		var pos := skeleton.get_bone_pose_position(arm)
		var parent := skeleton.get_bone_parent(arm)
		var parent_pose := Transform3D.IDENTITY
		if parent >= 0:
			parent_pose = skeleton.get_bone_global_pose(parent)
		var parent_world := skeleton.global_transform * parent_pose
		var local_shift: Vector3 = parent_world.basis.inverse() * (camera.global_transform.basis * shift)
		skeleton.set_bone_pose_position(arm, pos + local_shift)
	if absf(roll) < 0.1:
		return
	var hand := skeleton.find_bone("Hand.L")
	if hand < 0:
		return
	var hand_parent := skeleton.get_bone_parent(hand)
	var hand_parent_pose := Transform3D.IDENTITY
	if hand_parent >= 0:
		hand_parent_pose = skeleton.get_bone_global_pose(hand_parent)
	var hand_parent_world := skeleton.global_transform * hand_parent_pose
	var axis: Vector3 = hand_parent_world.basis.inverse() * (-camera.global_transform.basis.z)
	if axis.length_squared() < 0.0001:
		return
	var spun := Quaternion(axis.normalized(), deg_to_rad(roll)) * skeleton.get_bone_pose_rotation(hand)
	skeleton.set_bone_pose_rotation(hand, spun)

func _camera() -> Camera3D:
	var node: Node = self
	while node:
		if node is Camera3D:
			return node as Camera3D
		node = node.get_parent()
	return null
