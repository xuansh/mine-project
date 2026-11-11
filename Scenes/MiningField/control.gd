extends Control

## Control.tscn 的根节点：负责在「矿区」「HUD」「升级树」「升级面板」之间协调。
## 矿区、HUD、升级树都放在同一个 SubViewport 里；HUD 是 layer=5 的 CanvasLayer，
## 升级树是 layer=10 的 CanvasLayer，两者都是 MineField 的兄弟节点。

@onready var _skill_tree : SkillTree = $SubViewportContainer/SubViewport/SkillTreeLayer/SkillTree
@onready var _hud : Hud = $SubViewportContainer/SubViewport/HudLayer/Hud
@onready var _upgrade_panel : UpgradePanel = $SubViewportContainer/SubViewport/Node3D/UpgradePanel

func _ready() -> void:
	_skill_tree.close_requested.connect(_on_skill_tree_close_requested)
	_skill_tree.visible = false
	_hud.action_requested.connect(_on_hud_action_requested)

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

## HUD 左下按钮列的动作分发
func _on_hud_action_requested(id : StringName) -> void:
	match id:
		&"skill_tree":
			_toggle_skill_tree()
		&"upgrade":
			_upgrade_panel.toggle_panel()
		_:
			pass
