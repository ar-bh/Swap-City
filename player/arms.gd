@tool
extends Node3D

@export var thickness := -0.14

var _thickness_applied := 999.0
var _ragdoll := false
var _left_elbow := Vector3.ZERO
var _right_elbow := Vector3.ZERO
var _left_elbow_vel := Vector3.ZERO
var _right_elbow_vel := Vector3.ZERO
var _left_hand_vel := Vector3.ZERO
var _right_hand_vel := Vector3.ZERO
var _upper_len := 0.7
var _lower_len := 0.7
var _held_vel := Vector3.ZERO

@onready var skeleton: Skeleton3D = get_parent()
@onready var left_path: Path3D = $LeftPath
@onready var right_path: Path3D = $RightPath
@onready var left_tube: CSGPolygon3D = $LeftTube
@onready var right_tube: CSGPolygon3D = $RightTube
@onready var right_target: Marker3D = %RightHandTarget
@onready var left_target: Marker3D = %LeftHandTarget
@onready var left_glove: Node3D = $"../LeftGlove/Mesh"
@onready var right_glove: Node3D = $"../RightGlove/Mesh"
@onready var left_pole: Marker3D = $"../LeftArmPole"
@onready var right_pole: Marker3D = $"../ArmAim/RightArmPole"

func _ready() -> void:
	if not skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		skeleton.skeleton_updated.connect(_on_skeleton_updated)

func ragdoll(direction: Vector3) -> void:
	if _ragdoll:
		return
	_ragdoll = true
	_upper_len = skeleton.get_bone_rest(skeleton.find_bone("LeftElbow")).origin.length()
	_lower_len = skeleton.get_bone_rest(skeleton.find_bone("LeftHand")).origin.length()
	left_target.top_level = true
	right_target.top_level = true
	_left_elbow = _bent_joint("LeftShoulder", left_target.global_position, 0.4)
	_right_elbow = _bent_joint("RightShoulder", right_target.global_position, -0.4)
	var kick := _hit_impulse(direction)
	var left_root := skeleton.to_global(_bone_pos("LeftShoulder"))
	var right_root := skeleton.to_global(_bone_pos("RightShoulder"))
	_left_hand_vel = kick * 0.8 + _fling(left_target.global_position) * 0.35
	_right_hand_vel = kick * 0.8 + _fling(right_target.global_position) * 0.35
	_left_elbow_vel = kick * 0.2 + _fold(left_root, left_target.global_position, 26.0)
	_right_elbow_vel = kick * 0.2 + _fold(right_root, right_target.global_position, -26.0)
	for bone_name in ["LeftShoulder", "LeftElbow", "RightShoulder", "RightElbow"]:
		skeleton.set_bone_pose_scale(skeleton.find_bone(bone_name), Vector3.ONE)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _ragdoll:
		return
	_ragdoll_arm(true, delta)
	_ragdoll_arm(false, delta)

func _process(_delta: float) -> void:
	if _ragdoll:
		return
	_straighten_arm("RightShoulder", "RightElbow", "RightHand", right_target)
	_stretch_arm("LeftShoulder", "LeftElbow", "LeftHand", left_target)

func _on_skeleton_updated() -> void:
	_keep_glove("LeftShoulder", left_glove)
	_keep_glove("RightShoulder", right_glove)
	_apply_thickness()
	_set_curve(left_path, _bone_pos("LeftShoulder"), _bone_pos("LeftElbow"), _bone_pos("LeftHand"))
	var right_elbow := _bone_pos("RightElbow")
	if not _ragdoll:
		# Bend the right arm where the left elbow sits, mirrored, so both arms sprout from the same spot on the body.
		right_elbow = _bone_pos("LeftElbow") * Vector3(-1.0, 1.0, 1.0)
	_set_curve(right_path, _bone_pos("RightShoulder"), right_elbow, _bone_pos("RightHand"))

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

func _hit_impulse(direction: Vector3) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	return flat.normalized() * 20.0 + Vector3.UP * 8.0

func _fling(pos: Vector3) -> Vector3:
	var away := pos - skeleton.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	return away.normalized() * randf_range(7.0, 15.0) + Vector3(randf_range(-4.0, 4.0), randf_range(3.0, 11.0), randf_range(-4.0, 4.0))

func _fold(root: Vector3, end: Vector3, speed: float) -> Vector3:
	var bend := (end - root).cross(Vector3.UP)
	if bend.length_squared() < 0.0001:
		bend = Vector3.RIGHT
	return bend.normalized() * speed

func _bent_joint(root_name: String, end: Vector3, side: float) -> Vector3:
	var root := skeleton.to_global(_bone_pos(root_name))
	var mid := root.lerp(end, 0.5)
	var bend := (end - root).cross(Vector3.UP)
	if bend.length_squared() < 0.0001:
		bend = Vector3.RIGHT
	return mid + bend.normalized() * side

func _ragdoll_arm(is_left: bool, delta: float) -> void:
	var root_name := "LeftShoulder"
	var root := Vector3.ZERO
	var elbow := _left_elbow
	var elbow_vel := _left_elbow_vel
	var hand := left_target
	var hand_vel := _left_hand_vel
	var pole := left_pole
	if not is_left:
		root_name = "RightShoulder"
		elbow = _right_elbow
		elbow_vel = _right_elbow_vel
		hand = right_target
		hand_vel = _right_hand_vel
		pole = right_pole
	root = skeleton.to_global(_bone_pos(root_name))
	elbow_vel += Vector3.DOWN * 36.0 * delta
	hand_vel += Vector3.DOWN * 36.0 * delta
	elbow_vel *= 1.0 - clampf(1.2 * delta, 0.0, 0.2)
	hand_vel *= 1.0 - clampf(1.2 * delta, 0.0, 0.2)
	elbow += elbow_vel * delta
	hand.global_position += hand_vel * delta
	elbow = _constrain(elbow, root, _upper_len, elbow_vel)
	elbow_vel = _held_vel
	hand.global_position = _constrain(hand.global_position, elbow, _lower_len, hand_vel)
	hand_vel = _held_vel
	var span := hand.global_position - root
	var dist := span.length()
	var limit := (_upper_len + _lower_len) * 0.68
	if dist > limit and dist > 0.001:
		var outward := span / dist
		hand.global_position = root + outward * limit
		if hand_vel.dot(outward) > 0.0:
			hand_vel -= outward * hand_vel.dot(outward)
	elbow = _keep_bent(root, elbow, hand.global_position)
	pole.global_position = elbow
	if is_left:
		_left_elbow = elbow
		_left_elbow_vel = elbow_vel
		_left_hand_vel = hand_vel
	else:
		_right_elbow = elbow
		_right_elbow_vel = elbow_vel
		_right_hand_vel = hand_vel

func _keep_bent(root: Vector3, mid: Vector3, end: Vector3) -> Vector3:
	var span := end - root
	var dist := span.length()
	if dist < 0.001:
		return mid
	var along := span / dist
	var x := (_upper_len * _upper_len - _lower_len * _lower_len + dist * dist) / (2.0 * dist)
	var height := sqrt(maxf(_upper_len * _upper_len - x * x, 0.0))
	var side := mid - root - along * (mid - root).dot(along)
	if side.length_squared() < 0.0001:
		side = along.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	return root + along * x + side.normalized() * height

func _constrain(point: Vector3, anchor: Vector3, length: float, vel: Vector3) -> Vector3:
	var offset := point - anchor
	var dist := offset.length()
	if dist <= length or dist < 0.001:
		_held_vel = vel
		return point
	var normal := offset / dist
	var outward := vel.dot(normal)
	if outward > 0.0:
		vel -= normal * outward
	_held_vel = vel
	return anchor + normal * length

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
