extends Control

## Control.tscn 的根节点：负责在「矿区」「HUD」「改装终端」之间协调。
## 窗口分三区（GDD 4.8.1）：左栏 373 / 右上主区 1547×802 / 底栏 278。
## 改装终端是主区的子场景，挂 SubViewport 内 CanvasLayer(layer=10)，
## 与矿区 3D 并存、靠可见性切换——不占全屏，也不另开窗口层。

@onready var _skill_tree_layer : CanvasLayer = $SubViewportContainer/SubViewport/SkillTreeLayer
@onready var _skill_tree : SkillTree = $SubViewportContainer/SubViewport/SkillTreeLayer/SkillTree

@export var _hud : Hud
func _ready() -> void:
	_skill_tree.close_requested.connect(_on_skill_tree_close_requested)
	_skill_tree_layer.visible = false
	_hud.action_requested.connect(_on_hud_action_requested)

func _unhandled_input(event : InputEvent) -> void:
	if event.is_action_pressed("Toggle-SkillTree"):
		get_viewport().set_input_as_handled()
		_toggle_skill_tree()
	elif event.is_action_pressed("ui_cancel") and _skill_tree_layer.visible:
		get_viewport().set_input_as_handled()
		_close_skill_tree()

func _toggle_skill_tree() -> void:
	if _skill_tree_layer.visible:
		_close_skill_tree()
	else:
		_skill_tree.open()
		_skill_tree_layer.visible = true

func _close_skill_tree() -> void:
	_skill_tree.close()
	_skill_tree_layer.visible = false

func _on_skill_tree_close_requested() -> void:
	_close_skill_tree()

## HUD 左下按钮列的动作分发
func _on_hud_action_requested(id : StringName) -> void:
	match id:
		&"skill_tree":
			_toggle_skill_tree()
		_:
			pass
