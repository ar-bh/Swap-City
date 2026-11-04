@tool
extends Node3D

@export_group("Tube Legs")
@export var thickness := -0.14

@export_group("Stepping")
@export var distance_threshold := 0.55
@export var step_time := 0.12
@export var step_height := 0.25
@export var constant_forward := 0.7
@export var knee_reach := 1.0

@export_group("Air Pose")
@export var foot_spring := 80.0
@export var foot_damping := 6.0
@export var air_kick := 1.5
@export var air_tuck := 0.35
@export var land_time := 0.06

var _body: CharacterBody3D
var _left_tween: Tween
var _right_tween: Tween
var _step_left := true
var _airborne := false
var _left_foot_vel := Vector3.ZERO
var _right_foot_vel := Vector3.ZERO
var _thickness_applied := 999.0
var _left_constant_pos := Vector3.ZERO
var _right_constant_pos := Vector3.ZERO
var _left_constant_rest := Vector3.ZERO
var _right_constant_rest := Vector3.ZERO
var _constant_lead := Vector3.ZERO
var _foot_height := 0.0
var _ragdoll := false
var _left_knee := Vector3.ZERO
var _right_knee := Vector3.ZERO
var _left_knee_vel := Vector3.ZERO
var _right_knee_vel := Vector3.ZERO
var _upper_len := 1.0
var _lower_len := 1.0
var _held_vel := Vector3.ZERO

@onready var skeleton: Skeleton3D = get_parent()
@onready var left_path: Path3D = $LeftPath
@onready var right_path: Path3D = $RightPath
@onready var left_tube: CSGPolygon3D = $LeftTube
@onready var right_tube: CSGPolygon3D = $RightTube
@onready var left_constant: Marker3D = %LeftConstant
@onready var right_constant: Marker3D = %RightConstant
@onready var left_foot_target: Marker3D = %LeftFootTarget
@onready var right_foot_target: Marker3D = %RightFootTarget
@onready var left_pole: Marker3D = $"../LeftPole"
@onready var right_pole: Marker3D = $"../RightPole"
@onready var left_shoe: Node3D = $"../LeftShoe/Mesh"
@onready var right_shoe: Node3D = $"../RightShoe/Mesh"

func _ready() -> void:
	_body = _find_body()
	_left_constant_rest = left_constant.position
	_right_constant_rest = right_constant.position
	if not skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		skeleton.skeleton_updated.connect(_on_skeleton_updated)
	
	if Engine.is_editor_hint() or _body == null:
		return
	
	_foot_height = left_constant.global_position.y - _body.global_position.y
	left_foot_target.top_level = true
	right_foot_target.top_level = true
	_left_constant_pos = left_constant.global_position
	_right_constant_pos = right_constant.global_position

func ragdoll(direction: Vector3) -> void:
	if _ragdoll or _body == null:
		return
	_ragdoll = true
	if _left_tween != null:
		_left_tween.kill()
	if _right_tween != null:
		_right_tween.kill()
	_upper_len = skeleton.get_bone_rest(skeleton.find_bone("LeftKnee")).origin.length()
	_lower_len = skeleton.get_bone_rest(skeleton.find_bone("LeftFoot")).origin.length()
	_left_knee = _bent_joint("LeftHip", left_foot_target.global_position, 0.45)
	_right_knee = _bent_joint("RightHip", right_foot_target.global_position, -0.45)
	var kick := _hit_impulse(direction)
	var left_hip := skeleton.to_global(_bone_pos("LeftHip"))
	var right_hip := skeleton.to_global(_bone_pos("RightHip"))
	_left_foot_vel = kick + _fling(left_foot_target.global_position)
	_right_foot_vel = kick + _fling(right_foot_target.global_position)
	_left_knee_vel = kick * 0.35 + _fold(left_hip, left_foot_target.global_position, 18.0)
	_right_knee_vel = kick * 0.35 + _fold(right_hip, right_foot_target.global_position, -18.0)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _ragdoll or _body == null:
		return
	_ragdoll_leg("LeftHip", true, delta)
	_ragdoll_leg("RightHip", false, delta)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _body == null or _ragdoll:
		return
	
	_place_constants(delta)
	var left_shift := left_constant.global_position - _left_constant_pos
	var right_shift := right_constant.global_position - _right_constant_pos
	_left_constant_pos = left_constant.global_position
	_right_constant_pos = right_constant.global_position
	_aim_knee(left_pole, "LeftHip", left_foot_target)
	_aim_knee(right_pole, "RightHip", right_foot_target)
	
	if not _body.is_on_floor():
		if not _airborne:
			_begin_flop()
		left_foot_target.global_position += left_shift
		right_foot_target.global_position += right_shift
		_left_foot_vel = _flop_foot(left_foot_target, _air_goal(left_constant), _left_foot_vel, delta)
		_right_foot_vel = _flop_foot(right_foot_target, _air_goal(right_constant), _right_foot_vel, delta)
		_airborne = true
		return
	if _airborne:
		_airborne = false
		_left_foot_vel = Vector3.ZERO
		_right_foot_vel = Vector3.ZERO
		_left_tween = _plant(left_foot_target, left_constant)
		_right_tween = _plant(right_foot_target, right_constant)
		return
	
	if _is_busy(_left_tween) or _is_busy(_right_tween):
		return
	
	var left_due := left_constant.global_position.distance_to(left_foot_target.global_position) > distance_threshold
	var right_due := right_constant.global_position.distance_to(right_foot_target.global_position) > distance_threshold
	
	if _step_left and left_due:
		_left_tween = _begin_step(left_foot_target, left_constant, "LeftHip")
		_step_left = false
	elif right_due:
		_right_tween = _begin_step(right_foot_target, right_constant, "RightHip")
		_step_left = true
	elif left_due:
		_left_tween = _begin_step(left_foot_target, left_constant, "LeftHip")
		_step_left = false

## Puts both feet straight under the body, e.g. after the body was moved by a swap.
func snap_feet() -> void:
	if _left_tween != null:
		_left_tween.kill()
	if _right_tween != null:
		_right_tween.kill()
	_place_constants(0.0)
	left_foot_target.global_position = left_constant.global_position
	right_foot_target.global_position = right_constant.global_position
	_left_constant_pos = left_constant.global_position
	_right_constant_pos = right_constant.global_position
	_left_foot_vel = Vector3.ZERO
	_right_foot_vel = Vector3.ZERO

func _on_skeleton_updated() -> void:
	_apply_thickness()
	_set_curve(left_path, "LeftHip", "LeftKnee", left_shoe)
	_set_curve(right_path, "RightHip", "RightKnee", right_shoe)

func _set_curve(path: Path3D, hip_name: String, knee_name: String, shoe: Node3D) -> void:
	var curve := path.curve
	if curve == null:
		return
	var hip := _bone_pos(hip_name) + Vector3(0.0, 0.4, 0.0)
	var knee := _bone_pos(knee_name)
	var foot := skeleton.to_local(shoe.global_position) + Vector3(0.0, 0.12, 0.0)
	var control := 2.0 * knee - 0.5 * (hip + foot)
	var steps := 12
	if curve.point_count != steps:
		curve.clear_points()
		for _i in steps:
			curve.add_point(Vector3.ZERO)
	for i in steps:
		var t := float(i) / float(steps - 1)
		var u := 1.0 - t
		curve.set_point_position(i, u * u * hip + 2.0 * u * t * control + t * t * foot)
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

func _find_body() -> CharacterBody3D:
	var node: Node = self
	while node != null:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null

func _is_busy(tween: Tween) -> bool:
	return tween != null and tween.is_running()

func _hit_impulse(direction: Vector3) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	return flat.normalized() * 22.0 + Vector3.UP * 9.0

func _fling(pos: Vector3) -> Vector3:
	var away := pos - _body.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	return away.normalized() * randf_range(8.0, 16.0) + Vector3(randf_range(-5.0, 5.0), randf_range(4.0, 12.0), randf_range(-5.0, 5.0))

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

func _ragdoll_leg(hip_name: String, is_left: bool, delta: float) -> void:
	var hip := skeleton.to_global(_bone_pos(hip_name))
	var knee := _left_knee
	var knee_vel := _left_knee_vel
	var foot := left_foot_target
	var foot_vel := _left_foot_vel
	var pole := left_pole
	if not is_left:
		knee = _right_knee
		knee_vel = _right_knee_vel
		foot = right_foot_target
		foot_vel = _right_foot_vel
		pole = right_pole
	knee_vel += Vector3.DOWN * 36.0 * delta
	foot_vel += Vector3.DOWN * 36.0 * delta
	knee_vel *= 1.0 - clampf(1.2 * delta, 0.0, 0.2)
	foot_vel *= 1.0 - clampf(1.2 * delta, 0.0, 0.2)
	knee += knee_vel * delta
	foot.global_position += foot_vel * delta
	knee = _constrain(knee, hip, _upper_len, knee_vel)
	knee_vel = _held_vel
	foot.global_position = _constrain(foot.global_position, knee, _lower_len, foot_vel)
	foot_vel = _held_vel
	var span := foot.global_position - hip
	var dist := span.length()
	var limit := (_upper_len + _lower_len) * 0.68
	if dist > limit and dist > 0.001:
		var outward := span / dist
		foot.global_position = hip + outward * limit
		if foot_vel.dot(outward) > 0.0:
			foot_vel -= outward * foot_vel.dot(outward)
	knee = _keep_bent(hip, knee, foot.global_position)
	pole.global_position = knee
	if is_left:
		_left_knee = knee
		_left_knee_vel = knee_vel
		_left_foot_vel = foot_vel
	else:
		_right_knee = knee
		_right_knee_vel = knee_vel
		_right_foot_vel = foot_vel

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

func _aim_knee(pole: Marker3D, hip_name: String, target: Marker3D) -> void:
	var hip := _bone_pos(hip_name)
	var foot := skeleton.to_local(target.global_position)
	var leg := foot - hip
	if leg.length_squared() < 0.0001:
		return
	var dir := leg.normalized()
	var front := Vector3(0.0, 0.0, 1.0)
	front -= dir * front.dot(dir)
	if front.length_squared() < 0.0001:
		return
	pole.position = hip.lerp(foot, 0.5) + front.normalized() * knee_reach

func _place_constants(delta: float) -> void:
	var target := Vector3.ZERO
	var move := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	if _body.is_on_floor() and move.length_squared() > 0.25:
		target = skeleton.global_basis.inverse() * move.normalized() * constant_forward
	_constant_lead = _constant_lead.lerp(target, 1.0 - exp(-8.0 * delta))
	left_constant.position = _left_constant_rest + _constant_lead
	right_constant.position = _right_constant_rest + _constant_lead
	left_constant.global_position.y = _body.global_position.y + _foot_height
	right_constant.global_position.y = _body.global_position.y + _foot_height

func _begin_step(target: Marker3D, constant: Marker3D, hip_name: String) -> Tween:
	var from := target.global_position
	var travel := from.distance_to(_step_aim(constant))
	var lift := minf(step_height * travel / distance_threshold, step_height * 1.25)
	var duration := clampf(travel / 6.0, step_time, 0.24)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(t: float) -> void:
		var pos := from.lerp(_step_aim(constant), t)
		var tuck := sin(t * PI)
		var hip := skeleton.to_global(_bone_pos(hip_name))
		pos = pos.lerp(Vector3(hip.x, pos.y, hip.z), tuck * 0.35)
		pos.y += tuck * lift
		target.global_position = pos
	, 0.0, 1.0, duration)
	return tween

func _step_aim(constant: Marker3D) -> Vector3:
	return constant.global_position + _move_dir() * distance_threshold

func _move_dir() -> Vector3:
	var dir := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	if dir.length_squared() < 0.04:
		return Vector3.ZERO
	return dir.normalized()

func _begin_flop() -> void:
	if _left_tween != null:
		_left_tween.kill()
	if _right_tween != null:
		_right_tween.kill()
	_left_foot_vel = Vector3.UP * air_kick
	_right_foot_vel = Vector3.UP * air_kick

func _air_goal(constant: Marker3D) -> Vector3:
	var rise := clampf((_body.velocity.y + 5.0) / 15.0, 0.0, 1.0)
	var up := lerpf(0.05, air_tuck, rise)
	return constant.global_position + Vector3.UP * up

func _flop_foot(target: Marker3D, goal: Vector3, vel: Vector3, delta: float) -> Vector3:
	vel += (goal - target.global_position) * foot_spring * delta
	vel *= exp(-foot_damping * delta)
	target.global_position += vel * delta
	return vel

func _plant(target: Marker3D, constant: Marker3D) -> Tween:
	var from := target.global_position
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_method(func(t: float) -> void:
		target.global_position = from.lerp(constant.global_position, t)
	, 0.0, 1.0, land_time)
	return tween
