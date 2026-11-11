class_name SkillTreeData
extends Resource

## 一整棵升级树的数据。节点之间的父子关系由 SkillNodeData.children 描述。

@export var root_id : StringName = &"root"
@export var nodes : Array[SkillNodeData] = []

func get_node_data(node_id : StringName) -> SkillNodeData:
	for node in nodes:
		if node != null and node.id == node_id:
			return node
	return null

## 某个节点的父节点。根节点返回 null
func get_parent_of(node_id : StringName) -> SkillNodeData:
	for node in nodes:
		if node != null and node.children.has(node_id):
			return node
	return null

func is_valid() -> bool:
	return get_node_data(root_id) != null
