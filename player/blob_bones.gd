@tool
extends Skeleton3D

func _ready() -> void:
	if find_bone("RightHip") != -1:
		return
	_build_side("Right", -1.0)
	_build_side("Left", 1.0)

func _build_side(side: String, sign: float) -> void:
	var hip := _add(side + "Hip", -1, Vector3(0.32 * sign, -0.79, 0.0))
	var knee := _add(side + "Knee", hip, Vector3(0.37 * sign, -0.68, 0.13))
	_add(side + "Foot", knee, Vector3(0.16 * sign, -0.98, -0.11))
	var shoulder := _add(side + "Shoulder", -1, Vector3(0.62 * sign, 0.26, 0.08))
	var elbow := _add(side + "Elbow", shoulder, Vector3(0.35 * sign, -0.26, 0.08))
	_add(side + "Hand", elbow, Vector3(0.06 * sign, -0.65, -0.02))

func _add(bone_name: String, parent: int, pos: Vector3) -> int:
	var index := add_bone(bone_name)
	if parent != -1:
		set_bone_parent(index, parent)
	set_bone_rest(index, Transform3D(Basis.IDENTITY, pos))
	set_bone_pose_position(index, pos)
	set_bone_pose_rotation(index, Quaternion.IDENTITY)
	set_bone_pose_scale(index, Vector3.ONE)
	return index
