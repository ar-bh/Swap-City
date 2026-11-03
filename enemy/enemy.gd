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

enum Phase { TRACK, LOCK, FIRE }

var _phase: Phase = Phase.TRACK
var _time := 0.0
var _locked_dir := Vector3(0.0, 0.0, 1.0)
var _range_left := 0.0
var _player: Node3D
var _aim: MeshInstance3D
var _aim_mat: StandardMaterial3D

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
	_aim = MeshInstance3D.new()
	_aim.name = "AimLine"
	_aim.top_level = true
	var line := BoxMesh.new()
	line.size = Vector3(aim_thickness, aim_thickness, 1.0)
	_aim_mat = StandardMaterial3D.new()
	_aim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_mat.albedo_color = aim_color
	line.material = _aim_mat
	_aim.mesh = line
	add_child(_aim)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	_find_player()
	match _phase:
		Phase.TRACK:
			_track(delta)
		Phase.LOCK:
			_lock(delta)
		Phase.FIRE:
			_fly(delta)

func _find_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D

func _track(delta: float) -> void:
	if _player != null:
		var target := _player.global_position + Vector3.UP * aim_height
		_aim_at(target, delta)
		var travel := target - _muzzle.global_position
		if travel.length_squared() > 0.0001:
			_locked_dir = travel.normalized()
	_paint_aim(aim_color)
	_show_aim(_muzzle.global_position, _locked_dir)
	_time += delta
	if _time < track_time:
		return
	_time = 0.0
	_phase = Phase.LOCK

func _lock(delta: float) -> void:
	_paint_aim(lock_color)
	_show_aim(_muzzle.global_position, _locked_dir)
	_time += delta
	if _time < lock_time:
		return
	_time = 0.0
	_bullet.visible = true
	_bullet.global_position = _muzzle.global_position + _locked_dir * 0.2
	_range_left = shot_range
	_show_aim(_bullet.global_position, _locked_dir)
	_phase = Phase.FIRE

func _fly(delta: float) -> void:
	var step := bullet_speed * delta
	if step > _range_left:
		step = _range_left
	var from := _bullet.global_position
	var to := from + _locked_dir * step
	var hit := _raycast(from, to)
	_range_left -= step
	if not hit.is_empty():
		_bullet.global_position = hit.position
		_aim.visible = false
		_end_shot(hit)
		return
	_bullet.global_position = to
	_show_aim(_bullet.global_position, _locked_dir)
	if _range_left <= 0.0:
		_aim.visible = false
		_end_shot({})

func _end_shot(hit: Dictionary) -> void:
	_bullet.visible = false
	_aim.visible = false
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
		_blob.rotation.y = lerp_angle(_blob.rotation.y, face, 1.0 - exp(-turn_follow * delta))
	var from := _arm_aim.global_position
	var offset := target - from
	var horizontal := Vector2(offset.x, offset.z).length()
	var pitch := atan2(offset.y, horizontal)
	_arm_aim.rotation.x = lerp_angle(_arm_aim.rotation.x, -pitch, 1.0 - exp(-turn_follow * delta))

func _paint_aim(color: Color) -> void:
	_aim_mat.albedo_color = color

func _show_aim(from: Vector3, direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		_aim.visible = false
		return
	var dir := direction.normalized()
	var end := from + dir * shot_range
	var hit := _raycast(from, end, true)
	if not hit.is_empty():
		end = hit.position
	var length := from.distance_to(end)
	if length < 0.05:
		_aim.visible = false
		return
	_aim.visible = true
	_aim.global_position = (from + end) * 0.5
	_point_along(_aim, dir)
	_aim.scale = Vector3(1.0, 1.0, length)

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
