class_name Player
extends CharacterBody3D

@export var speed := 8.0
@export var accel := 60.0
@export var air_accel := 30.0
@export var gravity := 9.8 * 3.0
@export var fall_gravity := 1.6
@export var jump := 15.0
@export var jump_cut := 0.5
@export var coyote_time := 0.1
@export var jump_buffer := 0.1
@export var turn_follow := 14.0
@export var bob_height := 0.12
@export var bob_rate := 10.0

@export_group("Jump Feel")
@export var jump_stretch := 0.1
@export var land_squash := 0.12
@export var air_stretch := 0.004
@export var squash_limit := 0.12
@export var squash_spring := 220.0
@export var squash_damping := 14.0
@export var land_dip := 0.45
@export var dip_spring := 160.0
@export var dip_damping := 14.0

@export_group("Camera")
@export var mouse_sensitivity := 0.0025
@export var min_pitch := -60.0
@export var max_pitch := 40.0

var _bob := 0.0
var _bob_amount := 0.0
var _model_rest_y := 0.0
var _coyote := 0.0
var _buffer := 0.0
var _was_on_floor := true
var _squash := 0.0
var _squash_vel := 0.0
var _dip := 0.0
var _dip_vel := 0.0
var _mesh_rest := {}

@onready var _model: Node3D = $Blob
@onready var _arm_aim: Node3D = %ArmAim
@onready var _camera_yaw: Node3D = $CameraYaw
@onready var _camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var _spring_arm: SpringArm3D = $CameraYaw/CameraPitch/SpringArm3D

func _ready() -> void:
	_model_rest_y = _model.position.y
	_model.rotation.y = _face_yaw()
	for child in _model.get_children():
		if child is MeshInstance3D:
			_mesh_rest[child] = child.transform
	_spring_arm.add_excluded_object(get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_camera_yaw.rotation.y -= motion.relative.x * mouse_sensitivity
		var pitch := _camera_pitch.rotation.x - motion.relative.y * mouse_sensitivity
		_camera_pitch.rotation.x = clampf(pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))

func _physics_process(delta: float) -> void:
	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote -= delta
	if Input.is_action_just_pressed("jump"):
		_buffer = jump_buffer
	else:
		_buffer -= delta
	
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump
		_buffer = 0.0
		_coyote = 0.0
		_squash = jump_stretch
		_squash_vel = 0.0
	elif not is_on_floor():
		var g := gravity
		if velocity.y < 0.0:
			g *= fall_gravity
		velocity.y -= g * delta
		if velocity.y > 0.0 and Input.is_action_just_released("jump"):
			velocity.y *= jump_cut
	
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var dir := _camera_yaw.global_basis * Vector3(input.x, 0.0, input.y)
	var rate := accel if is_on_floor() else air_accel
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(dir * speed, rate * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	var fall_speed := -velocity.y
	move_and_slide()
	
	if is_on_floor() and not _was_on_floor:
		var impact := clampf(fall_speed / 20.0, 0.35, 1.0)
		_squash = -land_squash * impact
		_squash_vel = 0.0
		_dip = -land_dip * impact
		_dip_vel = 0.0
	_was_on_floor = is_on_floor()
	
	_model.rotation.y = lerp_angle(_model.rotation.y, _face_yaw(), 1.0 - exp(-turn_follow * delta))
	_arm_aim.rotation.x = -_camera_pitch.rotation.x
	_squash_body(delta)
	_bob_body(delta, flat)

func _face_yaw() -> float:
	return _camera_yaw.rotation.y + PI

func _squash_body(delta: float) -> void:
	var target := 0.0
	if not is_on_floor():
		target = clampf(velocity.y * air_stretch, -squash_limit, squash_limit)
	_squash_vel += (squash_spring * (target - _squash) - squash_damping * _squash_vel) * delta
	_squash += _squash_vel * delta
	var sy := clampf(1.0 + _squash, 1.0 - squash_limit, 1.0 + squash_limit)
	var sx := 1.0 / sqrt(sy)
	var squash := Transform3D(Basis.from_scale(Vector3(sx, sy, sx)), Vector3(0.0, sy - 1.0, 0.0))
	for mesh in _mesh_rest:
		mesh.transform = squash * _mesh_rest[mesh]

func _bob_body(delta: float, move: Vector3) -> void:
	var moving := is_on_floor() and move.length_squared() > 0.25
	var target := 0.0
	if moving:
		var pace := move.length() / speed
		target = bob_height * clampf(pace, 0.35, 1.0)
		_bob += delta * bob_rate * clampf(pace, 0.35, 1.5)
	_bob_amount = lerpf(_bob_amount, target, 1.0 - exp(-8.0 * delta))
	_dip_vel += (-dip_spring * _dip - dip_damping * _dip_vel) * delta
	_dip += _dip_vel * delta
	_model.position.y = _model_rest_y + absf(sin(_bob)) * _bob_amount + _dip
