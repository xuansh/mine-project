extends Node

## 存档读写（GDD 4.10.8 批次 1）。
##
## 职责单一：把 Game 的快照写进 user://save.cfg，启动时读回来。
## 不认识任何业务字段——字段清单由 Game.to_dict / apply_dict 决定。
##
## 写盘策略：金币与解锁会高频变化，所以标脏 + 1 秒节流；
## 退出与切后台时立即落盘，避免玩家白挖一趟。

const SAVE_PATH : String = "user://save.cfg"
const SECTION : String = "progress"
## 两次写盘之间的最小间隔（秒）
const WRITE_THROTTLE : float = 1.0

var _dirty : bool = false
var _elapsed : float = 0.0

## 关掉后既不节流写盘、也不在退出时落盘。
## 自检 / 调试脚本必须关掉它，否则测试数据会覆盖玩家存档
var autosave_enabled : bool = true

func _ready() -> void:
	load_game()

	Game.coins_changed.connect(_on_coins_changed)
	Game.stats_changed.connect(_on_stats_changed)
	Game.skills_changed.connect(_on_skills_changed)

func _process(delta : float) -> void:
	if not autosave_enabled or not _dirty:
		return
	_elapsed += delta
	if _elapsed >= WRITE_THROTTLE:
		save_game()

func _notification(what : int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if autosave_enabled and _dirty:
			save_game()

# ---------------------------------------------------------------- 对外

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## 立即写盘（调试 / 退出时用）
func save_game() -> bool:
	var config := ConfigFile.new()
	var snapshot := Game.to_dict()
	for key in snapshot:
		config.set_value(SECTION, String(key), snapshot[key])

	var err := config.save(SAVE_PATH)
	if err != OK:
		push_warning("[存档] 写入失败，错误码 %d：%s" % [err, SAVE_PATH])
		return false

	_dirty = false
	_elapsed = 0.0
	return true

## 读档。没有存档时返回 false，Game 保持初始值
func load_game() -> bool:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return false

	var snapshot := {}
	for key in config.get_section_keys(SECTION):
		snapshot[key] = config.get_value(SECTION, key)
	Game.apply_dict(snapshot)
	_dirty = false
	_elapsed = 0.0
	return true

## 删档（调试用，暂不暴露给玩家）
func erase_save() -> bool:
	_dirty = false
	if not has_save():
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH)) == OK

# ---------------------------------------------------------------- 内部

func _on_coins_changed(_total : int, _delta : int) -> void:
	_dirty = true

func _on_stats_changed() -> void:
	_dirty = true

func _on_skills_changed() -> void:
	_dirty = true
