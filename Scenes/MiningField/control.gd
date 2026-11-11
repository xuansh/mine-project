extends Control

## Control.tscn 的根节点：负责在「矿区」和「升级树」之间切换。
## 两块内容都放在同一个 SubViewport 里，升级树是 MineField 的兄弟节点。

@onready var _skill_tree : SkillTree = $SubViewportContainer/SubViewport/SkillTreeLayer/SkillTree

func _ready() -> void:
	_skill_tree.close_requested.connect(_on_skill_tree_close_requested)
	_skill_tree.visible = false

func _unhandled_input(event : InputEvent) -> void:
	if event.is_action_pressed("Toggle-SkillTree"):
		get_viewport().set_input_as_handled()
		_toggle_skill_tree()
	elif event.is_action_pressed("ui_cancel") and _skill_tree.visible:
		get_viewport().set_input_as_handled()
		_close_skill_tree()

func _toggle_skill_tree() -> void:
	if _skill_tree.visible:
		_close_skill_tree()
	else:
		_skill_tree.open()

func _close_skill_tree() -> void:
	_skill_tree.close()

func _on_skill_tree_close_requested() -> void:
	_close_skill_tree()
