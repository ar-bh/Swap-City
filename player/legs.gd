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
@export var air_kick := 6.0
@export var air_tuck := 1.2
@export var air_trail := 0.8
@export var land_time := 0.06

var _body: CharacterBody3D
var _left_tween: Tween
var _right_tween: Tween
var _step_left := true
var _airborne := false
var _left_leads := true
var _left_foot_vel := Vector3.ZERO
var _right_foot_vel := Vector3.ZERO
var _thickness_applied := 999.0
var _left_constant_pos := Vector3.ZERO
var _right_constant_pos := Vector3.ZERO
var _left_constant_rest := Vector3.ZERO
var _right_constant_rest := Vector3.ZERO
var _constant_lead := Vector3.ZERO
var _foot_height := 0.0

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

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _body == null:
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
		_left_foot_vel = _flop_foot(left_foot_target, _air_goal(left_constant, _left_leads), _left_foot_vel, delta)
		_right_foot_vel = _flop_foot(right_foot_target, _air_goal(right_constant, not _left_leads), _right_foot_vel, delta)
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
	var ahead := (left_foot_target.global_position - right_foot_target.global_position).dot(_air_dir())
	if absf(ahead) < 0.05:
		_left_leads = _step_left
	else:
		_left_leads = ahead > 0.0
	_left_foot_vel = Vector3.DOWN * air_kick
	_right_foot_vel = Vector3.DOWN * air_kick

func _air_dir() -> Vector3:
	var dir := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	if dir.length_squared() < 0.04:
		dir = skeleton.global_basis.z
		dir.y = 0.0
	return dir.normalized()

func _air_goal(constant: Marker3D, lead: bool) -> Vector3:
	var rise := clampf((_body.velocity.y + 5.0) / 15.0, 0.0, 1.0)
	var up := lerpf(0.0, 0.1, rise)
	var fwd := lerpf(-0.15, -air_trail, rise)
	if lead:
		up = lerpf(0.1, air_tuck, rise)
		fwd = lerpf(0.2, 0.7, rise)
	return constant.global_position + Vector3.UP * up + _air_dir() * fwd

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
