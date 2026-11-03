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
@export var land_dip := 0.45
@export var dip_spring := 160.0
@export var dip_damping := 14.0

@export_group("Camera")
@export var mouse_sensitivity := 0.0025
@export var min_pitch := -60.0
@export var max_pitch := 40.0

@export_group("Shot")
@export var shot_range := 80.0
@export var tracer_time := 0.06
@export var bullet_color := Color(0.3647, 0.9059, 0.6196, 1.0)
@export_range(0.005, 0.3, 0.005) var bullet_width := 0.035

var _bob := 0.0
var _bob_amount := 0.0
var _model_rest_y := 0.0
var _coyote := 0.0
var _buffer := 0.0
var _was_on_floor := true
var _dip := 0.0
var _dip_vel := 0.0

@onready var _model: Node3D = $Blob
@onready var _arm_aim: Node3D = %ArmAim
@onready var _camera_yaw: Node3D = $CameraYaw
@onready var _camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var _spring_arm: SpringArm3D = $CameraYaw/CameraPitch/SpringArm3D

@onready var _camera: Camera3D = %Camera3D
@onready var _muzzle: Marker3D = %Muzzle
@onready var _muzzle_flash: GPUParticles3D = %MuzzleFlash
@onready var _hit_spark: GPUParticles3D = %HitSpark
@onready var _tracer: MeshInstance3D = $Tracer

func _ready() -> void:
	_model_rest_y = _model.position.y
	_model.rotation.y = _face_yaw()
	_spring_arm.add_excluded_object(get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_shoot()
		return
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
		_dip = -land_dip * impact
		_dip_vel = 0.0
	_was_on_floor = is_on_floor()
	
	_model.rotation.y = lerp_angle(_model.rotation.y, _face_yaw(), 1.0 - exp(-turn_follow * delta))
	_arm_aim.rotation.x = -_camera_pitch.rotation.x
	_bob_body(delta, flat)

func _face_yaw() -> float:
	return _camera_yaw.rotation.y + PI

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

func _shoot() -> void:
	var aim := _camera_hit()
	var from := _muzzle.global_position
	var travel := aim - from
	if travel.length_squared() < 0.0001:
		return
	var direction := travel.normalized()
	var start := from + direction * 0.2
	var hit := _raycast(start, start + direction * shot_range)
	var end := start + direction * shot_range
	if not hit.is_empty():
		end = hit.position
	_play_burst(_muzzle_flash)
	_show_tracer(start, end)
	if hit.is_empty():
		return
	_hit_spark.global_position = hit.position
	_aim_along(_hit_spark, hit.normal)
	_play_burst(_hit_spark)
	_try_swap(hit.collider)

func _try_swap(collider: Object) -> void:
	var body: Node = collider as Node
	if body == null or not body.has_method("swap_with"):
		print("Hit ", body.name)
		return
	body.swap_with(self)
	velocity = Vector3.ZERO

func _camera_hit() -> Vector3:
	var from := _camera.global_position
	var to := from + _camera.global_basis * Vector3(0.0, 0.0, -shot_range)
	var hit := _raycast(from, to)
	if hit.is_empty():
		return to
	return hit.position

func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

func _aim_along(node: Node3D, direction: Vector3) -> void:
	var up := Vector3.RIGHT if absf(direction.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
	node.look_at(node.global_position + direction, up)

func _play_burst(particles: GPUParticles3D) -> void:
	var material := particles.process_material as ParticleProcessMaterial
	material.color = Color(1, 1, 1, 1)
	var ramp := material.color_ramp as GradientTexture1D
	var faded := bullet_color
	faded.a = 0.0
	var gradient := ramp.gradient
	gradient.colors = PackedColorArray([bullet_color, faded])
	ramp.gradient = gradient
	var surface := (particles.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	surface.emission_enabled = true
	surface.emission = Color(bullet_color.r, bullet_color.g, bullet_color.b, 1.0)
	surface.emission_energy_multiplier = 2.0
	particles.emitting = false
	particles.restart()
	particles.emitting = true

func _show_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	_tracer.visible = true
	_tracer.global_position = (from + to) * 0.5
	_aim_along(_tracer, to - from)
	var thickness := bullet_width / 0.035
	_tracer.scale = Vector3(thickness, thickness, length)
	var mat := _tracer.get_active_material(0) as StandardMaterial3D
	mat.albedo_color = bullet_color
	mat.emission = Color(bullet_color.r, bullet_color.g, bullet_color.b, 1.0)
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, tracer_time)
	tween.tween_callback(func() -> void:
		_tracer.visible = false)
