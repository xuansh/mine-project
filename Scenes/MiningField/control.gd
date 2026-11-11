extends Control

## Control.tscn 的根节点：负责在「矿区」「HUD」「升级树」「升级面板」之间协调。
## 布局（1920x1080 主场景）：SubViewportContainer 固定占右上 1547x802，
## 左侧空白栏和底部空白带留给 HUD（窗口级 CanvasLayer）。
## 升级树在 SubViewport 内的 layer=10 CanvasLayer，由这里统一开关。

@onready var _skill_tree_layer : CanvasLayer = $SubViewportContainer/SubViewport/SkillTreeLayer
@onready var _skill_tree : SkillTree = $SubViewportContainer/SubViewport/SkillTreeLayer/SkillTree
@onready var _hud : Hud = $HudLayer/Hud
@onready var _upgrade_panel : UpgradePanel = $SubViewportContainer/SubViewport/Node3D/UpgradePanel

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
		&"upgrade":
			_upgrade_panel.toggle_panel()
		_:
			pass
