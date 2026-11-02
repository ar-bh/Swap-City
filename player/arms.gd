@tool
extends Node3D

@export var thickness := -0.14

var _thickness_applied := 999.0

@onready var skeleton: Skeleton3D = get_parent()
@onready var left_path: Path3D = $LeftPath
@onready var right_path: Path3D = $RightPath
@onready var left_tube: CSGPolygon3D = $LeftTube
@onready var right_tube: CSGPolygon3D = $RightTube
@onready var right_target: Marker3D = %RightHandTarget
@onready var left_target: Marker3D = %LeftHandTarget
@onready var left_glove: Node3D = $"../LeftGlove/Mesh"
@onready var right_glove: Node3D = $"../RightGlove/Mesh"

func _ready() -> void:
	if not skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		skeleton.skeleton_updated.connect(_on_skeleton_updated)

func _process(_delta: float) -> void:
	_straighten_arm("RightShoulder", "RightElbow", "RightHand", right_target)
	_stretch_arm("LeftShoulder", "LeftElbow", "LeftHand", left_target)

func _on_skeleton_updated() -> void:
	_keep_glove("LeftShoulder", left_glove)
	_keep_glove("RightShoulder", right_glove)
	_apply_thickness()
	_set_curve(left_path, _bone_pos("LeftShoulder"), _bone_pos("LeftElbow"), _bone_pos("LeftHand"))
	# Bend the right arm where the left elbow sits, mirrored, so both arms sprout from the same spot on the body.
	var sprout := _bone_pos("LeftElbow") * Vector3(-1.0, 1.0, 1.0)
	_set_curve(right_path, _bone_pos("RightShoulder"), sprout, _bone_pos("RightHand"))

func _set_curve(path: Path3D, shoulder: Vector3, elbow: Vector3, hand: Vector3) -> void:
	var curve := path.curve
	if curve == null:
		return
	var steps := 12
	if curve.point_count != steps:
		curve.clear_points()
		for _i in steps:
			curve.add_point(Vector3.ZERO)
	for i in steps:
		var t := float(i) / float(steps - 1)
		var point := shoulder.lerp(elbow, t * 2.0)
		if t >= 0.5:
			point = elbow.lerp(hand, (t - 0.5) * 2.0)
		curve.set_point_position(i, point)
		curve.set_point_in(i, Vector3.ZERO)
		curve.set_point_out(i, Vector3.ZERO)

func _apply_thickness() -> void:
	if is_equal_approx(_thickness_applied, thickness):
		return
	_thickness_applied = thickness
	var ring := PackedVector2Array()
	for i in 10:
		var angle := TAU * float(i) / 10.0
		ring.append(Vector2(cos(angle), sin(angle)) * thickness)
	left_tube.polygon = ring
	right_tube.polygon = ring

func _bone_pos(bone_name: String) -> Vector3:
	return skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin

func _stretch_arm(shoulder_name: String, elbow_name: String, hand_name: String, target: Node3D) -> void:
	var shoulder_i := skeleton.find_bone(shoulder_name)
	var elbow_i := skeleton.find_bone(elbow_name)
	var straight := skeleton.get_bone_rest(elbow_i).origin.length() + skeleton.get_bone_rest(skeleton.find_bone(hand_name)).origin.length()
	if straight <= 0.001:
		return
	var goal := skeleton.to_local(target.global_position)
	var s := maxf(_bone_pos(shoulder_name).distance_to(goal) / straight, 1.0)
	var scale := Vector3(s, s, s)
	if skeleton.get_bone_pose_scale(shoulder_i).is_equal_approx(scale) and skeleton.get_bone_pose_scale(elbow_i).is_equal_approx(Vector3.ONE):
		return
	skeleton.set_bone_pose_scale(shoulder_i, scale)
	skeleton.set_bone_pose_scale(elbow_i, Vector3.ONE)

# Scales the arm so its full length exactly reaches the target, keeping it straight.
func _straighten_arm(shoulder_name: String, elbow_name: String, hand_name: String, target: Node3D) -> void:
	var shoulder_i := skeleton.find_bone(shoulder_name)
	var elbow_i := skeleton.find_bone(elbow_name)
	var straight := skeleton.get_bone_rest(elbow_i).origin.length() + skeleton.get_bone_rest(skeleton.find_bone(hand_name)).origin.length()
	if straight <= 0.001:
		return
	var goal := skeleton.to_local(target.global_position)
	var s := _bone_pos(shoulder_name).distance_to(goal) / straight
	var scale := Vector3(s, s, s)
	if skeleton.get_bone_pose_scale(shoulder_i).is_equal_approx(scale) and skeleton.get_bone_pose_scale(elbow_i).is_equal_approx(Vector3.ONE):
		return
	skeleton.set_bone_pose_scale(shoulder_i, scale)
	skeleton.set_bone_pose_scale(elbow_i, Vector3.ONE)

func _keep_glove(shoulder_name: String, glove: Node3D) -> void:
	var s := skeleton.get_bone_pose_scale(skeleton.find_bone(shoulder_name)).x
	if s <= 0.001:
		return
	glove.scale = Vector3.ONE / s
