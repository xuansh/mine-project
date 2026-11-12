@tool
extends EditorPlugin

## 把「技能树」注册成编辑器顶部的一个主屏标签。
##
## 入口：编辑器上方主屏标签（2D / 3D / Script 旁边）→「技能树」
## 代码主体在 editor_main.gd，这里只负责挂载与显隐。

const EditorMain := preload("res://addons/skill_tree_editor/editor_main.gd")

var _main : Control

func _enter_tree() -> void:
	_main = EditorMain.new()
	_main.name = "SkillTreeEditor"
	EditorInterface.get_editor_main_screen().add_child(_main)
	_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_make_visible(false)

func _exit_tree() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	_main = null

func _has_main_screen() -> bool:
	return true

func _make_visible(visible : bool) -> void:
	if is_instance_valid(_main):
		_main.visible = visible

func _get_plugin_name() -> String:
	return "技能树"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Node", "EditorIcons")
