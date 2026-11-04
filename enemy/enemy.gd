class_name Enemy
extends CharacterBody3D

@export_group("Aim")
@export var track_time := 1.5
@export var lock_time := 0.5
@export var aim_height := 1.6
@export var turn_follow := 14.0
@export var aim_thickness := 0.1
@export var aim_color := Color(1.0, 0.85, 0.15, 1.0)
@export var lock_color := Color(1.0, 0.12, 0.08, 1.0)

@export_group("Shot")
@export var bullet_speed := 14.0
@export var shot_range := 40.0
@export var bullet_color := Color(0.0, 0.0, 0.0, 1.0)
@export var gravity := 9.8 * 3.0

@export_group("Swap")
@export var swappable := true
## Frozen beat before the bodies start moving.
@export var swap_freeze := 0.2
## How long the two bodies take to trade places while the game is paused.
@export var swap_time := 0.5
## Frozen beat after they arrive, before the game resumes.
@export var swap_hold := 0.15
@export var swap_lift := 0.6
@export var swap_side := 1.2
@export var swap_fov_kick := 8.0
## Degrees per second the enemy turns while finding the player again after a swap.
@export var swap_turn_speed := 90.0

enum Phase { TRACK, LOCK, FIRE }

var _phase: Phase = Phase.TRACK
var _time := 0.0
var _locked_dir := Vector3(0.0, 0.0, 1.0)
var _range_left := 0.0
# The bullet flies on its own, so a swap mid-flight does not stop it.
var _flying := false
var _bullet_dir := Vector3(0.0, 0.0, 1.0)
var _player: Node3D
var _aim: MeshInstance3D
var _aim_mat: StandardMaterial3D
# A separate red line follows the bullet, so it stays even after a swap hands _aim back to tracking.
var _shot_line: MeshInstance3D
## True while the game is paused for this enemy's swap.
var swapping := false
# After a swap the enemy keeps its old facing and turns slowly until it faces the player again.
var _recovering := false

@onready var _blob: Node3D = %Blob
@onready var _arm_aim: Node3D = %ArmAim
@onready var _gun_mount: Node3D = %GunMount
@onready var _muzzle: Marker3D = %Muzzle
@onready var _bullet: MeshInstance3D = %Bullet

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_bullet.top_level = true
	_bullet.visible = false
	var bullet_mesh := _bullet.mesh as SphereMesh
	if bullet_mesh != null:
		bullet_mesh.radius = 0.12
		bullet_mesh.height = 0.24
	var bullet_mat := _bullet.get_active_material(0) as StandardMaterial3D
	if bullet_mat != null:
		bullet_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bullet_mat.albedo_color = bullet_color
		bullet_mat.emission_enabled = false
	_aim = _make_line("AimLine", aim_color)
	_aim_mat = (_aim.mesh as BoxMesh).material as StandardMaterial3D
	_shot_line = _make_line("ShotLine", lock_color)
	_shot_line.visible = false

func _make_line(line_name: String, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = line_name
	node.top_level = true
	var line := BoxMesh.new()
	line.size = Vector3(aim_thickness, aim_thickness, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	line.material = mat
	node.mesh = line
	add_child(node)
	return node

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	_find_player()
	if _flying:
		_fly(delta)
	match _phase:
		Phase.TRACK:
			_track(delta)
		Phase.LOCK:
			_lock(delta)

func _find_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D

func _track(delta: float) -> void:
	if _player != null:
		var target := _player.global_position + Vector3.UP * aim_height
		_aim_at(target, delta)
		var travel := target - _muzzle.global_position
		if _recovering:
			_locked_dir = _facing_dir()
		elif travel.length_squared() > 0.0001:
			_locked_dir = travel.normalized()
	_paint_aim(aim_color)
	_show_line(_aim, _muzzle.global_position, _locked_dir)
	if _recovering or not _sees_player():
		_time = 0.0
		return
	_time += delta
	if _time < track_time:
		return
	_time = 0.0
	_phase = Phase.LOCK

func _lock(delta: float) -> void:
	_paint_aim(lock_color)
	_show_line(_aim, _muzzle.global_position, _locked_dir)
	_time += delta
	if _time < lock_time:
		return
	_time = 0.0
	_bullet.visible = true
	_bullet.global_position = _muzzle.global_position + _locked_dir * 0.2
	_range_left = shot_range
	_bullet_dir = _locked_dir
	_flying = true
	_aim.visible = false
	_show_line(_shot_line, _bullet.global_position, _bullet_dir)
	_phase = Phase.FIRE

func _fly(delta: float) -> void:
	var step := bullet_speed * delta
	if step > _range_left:
		step = _range_left
	var from := _bullet.global_position
	var to := from + _bullet_dir * step
	var hit := _raycast(from, to)
	_range_left -= step
	if not hit.is_empty():
		_bullet.global_position = hit.position
		_end_shot(hit)
		return
	_bullet.global_position = to
	_show_line(_shot_line, _bullet.global_position, _bullet_dir)
	if _range_left <= 0.0:
		_end_shot({})

func _end_shot(hit: Dictionary) -> void:
	_bullet.visible = false
	_shot_line.visible = false
	_flying = false
	if _phase == Phase.FIRE:
		_time = 0.0
		_phase = Phase.TRACK
	if hit.is_empty():
		return
	var collider := hit.collider as Object
	if collider is Player or (collider is Node and (collider as Node).is_in_group("player")):
		get_tree().reload_current_scene()

func _aim_at(target: Vector3, delta: float) -> void:
	var flat := target - _blob.global_position
	flat.y = 0.0
	if flat.length_squared() > 0.0001:
		var face := atan2(flat.x, flat.z)
		if _recovering:
			_blob.rotation.y = rotate_toward(_blob.rotation.y, face, deg_to_rad(swap_turn_speed) * delta)
			if absf(angle_difference(_blob.rotation.y, face)) < deg_to_rad(3.0):
				_recovering = false
		else:
			_blob.rotation.y = lerp_angle(_blob.rotation.y, face, 1.0 - exp(-turn_follow * delta))
	var from := _arm_aim.global_position
	var offset := target - from
	var horizontal := Vector2(offset.x, offset.z).length()
	var pitch := atan2(offset.y, horizontal)
	if _recovering:
		_arm_aim.rotation.x = rotate_toward(_arm_aim.rotation.x, -pitch, deg_to_rad(swap_turn_speed) * delta)
	else:
		_arm_aim.rotation.x = lerp_angle(_arm_aim.rotation.x, -pitch, 1.0 - exp(-turn_follow * delta))

## The direction the gun currently points, from the body's yaw and the arm's pitch.
func _facing_dir() -> Vector3:
	var yaw := _blob.rotation.y
	var pitch := -_arm_aim.rotation.x
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))

func swap_with(visitor: Node3D) -> void:
	if swapping or not swappable:
		return
	swapping = true
	velocity = Vector3.ZERO
	_aim.visible = false
	_time = 0.0
	_phase = Phase.TRACK

	var yaw_node := visitor.get_node_or_null("CameraYaw") as Node3D
	var pitch_node := visitor.get_node_or_null("CameraYaw/CameraPitch") as Node3D
	var visitor_blob := visitor.get_node_or_null("Blob") as Node3D
	var visitor_arm := visitor.get_node_or_null("%ArmAim") as Node3D
	var camera := visitor.get_node_or_null("%Camera3D") as Camera3D
	# The player's shot ends on contact; only this enemy's bullet stays in the air.
	var tracer := visitor.get_node_or_null("Tracer") as Node3D
	if tracer != null:
		tracer.visible = false

	var my_start := global_position
	var visitor_start := visitor.global_position
	var my_face := _blob.rotation.y
	var my_pitch := _arm_aim.rotation.x
	var visitor_face := my_face
	var visitor_pitch := my_pitch
	var yaw_start := 0.0
	var pitch_start := 0.0
	if yaw_node != null and pitch_node != null:
		yaw_start = yaw_node.rotation.y
		pitch_start = pitch_node.rotation.x
		visitor_face = yaw_start + PI
		visitor_pitch = -pitch_start
	var base_fov := 75.0
	if camera != null:
		base_fov = camera.fov

	# Both bodies swing out to opposite sides so they pass around each other instead of through.
	var side := (visitor_start - my_start).cross(Vector3.UP)
	if side.length_squared() > 0.0001:
		side = side.normalized() * swap_side

	# Physics only catches up with the new positions after the game resumes, so the
	# two bodies ignore each other until then instead of shoving the player aside.
	var other := visitor as PhysicsBody3D
	if other != null:
		add_collision_exception_with(other)
		other.add_collision_exception_with(self)

	# Freeze the whole game; only this tween keeps running while it is paused.
	get_tree().paused = true
	var tween := get_tree().create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(swap_freeze)
	tween.tween_method(func(t: float) -> void:
		var bump := sin(t * PI)
		var lift := Vector3.UP * swap_lift * bump
		global_position = my_start.lerp(visitor_start, t) + lift + side * bump
		visitor.global_position = visitor_start.lerp(my_start, t) + lift - side * bump
		# The visitor ends up looking the way this enemy looked; the enemy keeps its own facing.
		if yaw_node != null and pitch_node != null:
			yaw_node.rotation.y = lerp_angle(yaw_start, my_face - PI, t)
			pitch_node.rotation.x = lerp_angle(pitch_start, -my_pitch, t)
		if visitor_blob != null:
			visitor_blob.rotation.y = lerp_angle(visitor_face, my_face, t)
		if visitor_arm != null:
			visitor_arm.rotation.x = lerp_angle(visitor_pitch, my_pitch, t)
		if camera != null:
			camera.fov = base_fov + swap_fov_kick * bump
	, 0.0, 1.0, swap_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(swap_hold)
	tween.tween_callback(func() -> void:
		global_position = visitor_start
		visitor.global_position = my_start
		if camera != null:
			camera.fov = base_fov
		_snap_feet(self)
		_snap_feet(visitor)
		swapping = false
		_recovering = true
		get_tree().paused = false
		if other != null:
			get_tree().create_timer(0.2, false, true).timeout.connect(func() -> void:
				remove_collision_exception_with(other)
				other.remove_collision_exception_with(self)))

func _snap_feet(body: Node) -> void:
	var legs := body.get_node_or_null("Blob/Skeleton/Legs")
	if legs != null and legs.has_method("snap_feet"):
		legs.call("snap_feet")

func _paint_aim(color: Color) -> void:
	_aim_mat.albedo_color = color

func _show_line(line: MeshInstance3D, from: Vector3, direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		line.visible = false
		return
	var dir := direction.normalized()
	var end := from + dir * shot_range
	var hit := _raycast(from, end, true)
	if not hit.is_empty():
		end = hit.position
	var length := from.distance_to(end)
	if length < 0.05:
		line.visible = false
		return
	line.visible = true
	line.global_position = (from + end) * 0.5
	_point_along(line, dir)
	line.scale = Vector3(1.0, 1.0, length)

func _point_along(node: Node3D, direction: Vector3) -> void:
	var up := Vector3.RIGHT if absf(direction.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
	node.look_at(node.global_position + direction, up)

func _raycast(from: Vector3, to: Vector3, through_player: bool = false) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var skip: Array[RID] = [get_rid()]
	if through_player and _player is CollisionObject3D:
		skip.append((_player as CollisionObject3D).get_rid())
	query.exclude = skip
	return get_world_3d().direct_space_state.intersect_ray(query)

func _sees_player() -> bool:
	if _player == null:
		return false
	var target := _player.global_position + Vector3.UP * aim_height
	var hit := _raycast(_muzzle.global_position, target, false)
	if hit.is_empty():
		return true
	var collider := hit.collider as Object
	return collider is Player or (collider is Node and (collider as Node).is_in_group("player"))
