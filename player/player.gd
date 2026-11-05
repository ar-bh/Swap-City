class_name Player
extends CharacterBody3D

@export_group("Swap")
@export var swappable := true

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
@export var bullet_speed := 180.0
@export var tracer_time := 0.45
@export var bullet_color := Color(0.3647, 0.9059, 0.6196, 1.0)
@export_range(0.005, 0.3, 0.005) var bullet_width := 0.075

@export_group("Knockback")
@export var knockback_speed := 42.0
@export var knockback_up := 22.0
@export var ragdoll_time := 2.6

var _bob := 0.0
var _bob_amount := 0.0
var _model_rest_y := 0.0
var _coyote := 0.0
var _buffer := 0.0
var _was_on_floor := true
var _dip := 0.0
var _dip_vel := 0.0
var _ragdoll := false
var _watch := false
var _restarting := false
var _spin := Vector3.ZERO
var _ragdoll_left := 0.0
var _shot_flying := false
var _shot_from := Vector3.ZERO
var _shot_tip := Vector3.ZERO
var _shot_dir := Vector3.ZERO
var _shot_left := 0.0
var _first_person := false
var _view_blend := 0.0
var _spring_rest_pos := Vector3.ZERO
var _spring_rest_length := 5.5
var _hand_rest := Vector3.ZERO
var _pole_rest := Vector3.ZERO
var _left_hand_rest := Vector3.ZERO
var _gun_rest_basis := Basis.IDENTITY
var _gun_rest_scale := Vector3.ONE
var _camera_near_rest := 0.05
var _body_meshes: Array[GeometryInstance3D] = []

# First-person pose, in the same local space as the third-person rig.
const _FP_HAND := Vector3(-0.34, 0.12, 0.9)
const _FP_POLE := Vector3(-0.8, -0.2, 0.4)
const _FP_LEFT_HAND := Vector3(0.9, -1.0, -0.35)
const _FP_EYE := Vector3(0.0, 0.66, 0.0)
const _FP_GUN_SCALE := 0.8

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
@onready var _hand: Marker3D = %RightHandTarget
@onready var _left_hand: Marker3D = %LeftHandTarget
@onready var _gun_mount: Node3D = %GunMount
@onready var _arm_pole: Marker3D = %ArmAim/RightArmPole
@onready var _gun_model: Node3D = %GunMount/SpaceGun

func _ready() -> void:
	_model_rest_y = _model.position.y
	_model.rotation.y = _face_yaw()
	_spring_arm.add_excluded_object(get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The swap freezes the game, and these bursts have to keep playing through that.
	_muzzle_flash.process_mode = Node.PROCESS_MODE_ALWAYS
	_hit_spark.process_mode = Node.PROCESS_MODE_ALWAYS
	_spring_rest_pos = _spring_arm.position
	_spring_rest_length = _spring_arm.spring_length
	_hand_rest = _hand.position
	_pole_rest = _arm_pole.position
	_left_hand_rest = _left_hand.position
	_gun_rest_basis = _gun_mount.basis
	_gun_rest_scale = _gun_model.scale
	_camera_near_rest = _camera.near
	_collect_body_meshes(_model)

func _unhandled_input(event: InputEvent) -> void:
	if _ragdoll:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_SHIFT:
			_first_person = not _first_person
			return
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

func launch(direction: Vector3, hold_camera: bool = false) -> void:
	if _ragdoll:
		return
	_ragdoll = true
	_watch = hold_camera
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		flat = -global_basis.z
		flat.y = 0.0
	flat = flat.normalized()
	velocity = flat * knockback_speed + Vector3.UP * knockback_up
	_spin = Vector3(randf_range(-2.5, 2.5), randf_range(-2.0, 2.0), randf_range(-2.5, 2.5))
	_ragdoll_left = ragdoll_time
	_go_limp(flat)
	if not hold_camera:
		return
	var held := _camera.global_transform
	_camera.reparent(get_tree().current_scene)
	_camera.global_transform = held

func _go_limp(direction: Vector3) -> void:
	var legs := get_node_or_null("Blob/Skeleton/Legs") as Node
	if legs != null and legs.has_method("ragdoll"):
		legs.call("ragdoll", direction)
	var arms := get_node_or_null("Blob/Skeleton/Arms") as Node
	if arms != null and arms.has_method("ragdoll"):
		arms.call("ragdoll", direction)

func _physics_process(delta: float) -> void:
	if _shot_flying:
		_advance_shot(delta)
	if _ragdoll:
		_ragdoll_step(delta)
		return
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
	_update_view(delta)

func _face_yaw() -> float:
	return _camera_yaw.rotation.y + PI

func _update_view(delta: float) -> void:
	var target := 0.0
	if _first_person:
		target = 1.0
	_view_blend = lerpf(_view_blend, target, 1.0 - exp(-14.0 * delta))
	if not _first_person and _view_blend < 0.001:
		_view_blend = 0.0
	if _first_person and _view_blend > 0.999:
		_view_blend = 1.0
	var blend := _view_blend
	_spring_arm.position = _spring_rest_pos.lerp(Vector3.ZERO, blend)
	_spring_arm.spring_length = lerpf(_spring_rest_length, 0.0, blend)
	_camera.near = lerpf(_camera_near_rest, 0.02, blend)
	_hand.position = _hand_rest.lerp(_FP_HAND, blend)
	_arm_pole.position = _pole_rest.lerp(_FP_POLE, blend)
	_left_hand.position = _left_hand_rest.lerp(_FP_LEFT_HAND, blend)
	_gun_mount.basis = _gun_rest_basis.slerp(_fp_gun_basis(), blend)
	_gun_model.scale = _gun_rest_scale.lerp(_gun_rest_scale * _FP_GUN_SCALE, blend)
	var show_body := not _first_person and blend < 0.45
	for mesh in _body_meshes:
		mesh.visible = show_body

func _fp_gun_basis() -> Basis:
	var look_point := _FP_EYE + Vector3(0.0, 0.0, 8.0)
	var aim := (look_point - _FP_HAND).normalized()
	# The visible barrel is the model's -X. Point that down the crosshair.
	var local_barrel := -_gun_model.transform.basis.x.normalized()
	return Basis(Quaternion(local_barrel, aim))

func _collect_body_meshes(node: Node) -> void:
	if node.name == "Skeleton":
		return
	if node is GeometryInstance3D:
		_body_meshes.append(node)
	for child in node.get_children():
		_collect_body_meshes(child)

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
	_aim_muzzle_flash(direction)
	_play_burst(_muzzle_flash)
	_shot_from = start
	_shot_tip = start
	_shot_dir = direction
	_shot_left = shot_range
	_shot_flying = true
	var mat := _tracer.get_active_material(0) as StandardMaterial3D
	mat.albedo_color = bullet_color
	mat.emission_enabled = true
	mat.emission = Color(bullet_color.r, bullet_color.g, bullet_color.b, 1.0)
	mat.emission_energy_multiplier = 2.0
	_tracer.visible = true
	_draw_shot()

func _try_swap(collider: Object, _direction: Vector3) -> void:
	var body: Node = collider as Node
	if body == null or not swappable or not body.has_method("swap_with") or body.get("swappable") != true:
		_tracer.visible = false
		return
	body.swap_with(self)
	velocity = Vector3.ZERO
	if body.get("swapping") != true:
		_tracer.visible = false

func _ragdoll_step(delta: float) -> void:
	var falling := velocity.y
	velocity.y -= gravity * delta
	var axis := _spin.normalized() if _spin.length_squared() > 0.001 else Vector3.RIGHT
	_model.rotate(axis, _spin.length() * delta)
	move_and_slide()
	if is_on_floor() and falling < -2.0:
		velocity.y = -falling * 0.55
		velocity.x *= 0.72
		velocity.z *= 0.72
		_spin *= 0.6
	if _watch:
		var focus := global_position + Vector3.UP * 1.4
		var to_focus := focus - _camera.global_position
		if to_focus.length_squared() > 0.001:
			var up := Vector3.RIGHT if absf(to_focus.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
			_camera.look_at(focus, up)
		_ragdoll_left -= delta
		if _ragdoll_left <= 0.0:
			_restart_level()

func _restart_level() -> void:
	if _restarting:
		return
	_restarting = true
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.call_deferred("reload_current_scene")

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

func _aim_muzzle_flash(direction: Vector3) -> void:
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var side := up.cross(direction).normalized()
	var lifted := direction.cross(side).normalized()
	_muzzle_flash.global_position = _muzzle.global_position
	_muzzle_flash.global_basis = Basis(side, lifted, direction)

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

func _advance_shot(delta: float) -> void:
	var step := minf(bullet_speed * delta, _shot_left)
	var next := _shot_tip + _shot_dir * step
	var hit := _raycast(_shot_tip, next)
	if not hit.is_empty():
		_shot_tip = hit.position
		_draw_shot()
		_end_shot(hit)
		return
	_shot_tip = next
	_shot_left -= step
	_draw_shot()
	if _shot_left <= 0.0:
		_shot_flying = false
		_tracer.visible = false

func _end_shot(hit: Dictionary) -> void:
	_shot_flying = false
	_hit_spark.global_position = hit.position
	var normal: Vector3 = hit.normal
	_aim_along(_hit_spark, normal)
	_play_burst(_hit_spark)
	_try_swap(hit.collider, _shot_dir)

func _draw_shot() -> void:
	var travel := _shot_tip - _shot_from
	var length := travel.length()
	if length < 0.02:
		_tracer.scale = Vector3(bullet_width, 0.02, bullet_width)
		_tracer.global_position = _shot_from
		return
	var dir := travel / length
	var up := Vector3.RIGHT if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var side := dir.cross(up).normalized()
	_tracer.global_position = (_shot_from + _shot_tip) * 0.5
	_tracer.global_basis = Basis(side, dir, side.cross(dir).normalized())
	_tracer.scale = Vector3(bullet_width, length, bullet_width)
