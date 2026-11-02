@tool
extends Node3D

@export var outline_material: ShaderMaterial

func _ready() -> void:
	if outline_material == null:
		return
	_apply(self)

func _apply(node: Node) -> void:
	if node is GeometryInstance3D and not _is_marker_gizmo(node):
		node.material_overlay = outline_material
	for child in node.get_children():
		_apply(child)

func _is_marker_gizmo(node: Node) -> bool:
	return node.get_parent() is Marker3D
