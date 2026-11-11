extends CanvasLayer

## 金币数字闪烁用色：变化瞬间染成工程黄，再淡回米白
const FLASH_COLOR : Color = Color("d9a227")

@onready var _value_label : Label = %ValueLabel

func _ready() -> void:
	Game.coins_changed.connect(_on_coins_changed)
	_value_label.text = _format(Game.coins)

func _on_coins_changed(total : int, delta : int) -> void:
	_value_label.text = _format(total)
	if delta > 0:
		_flash()

## 加钱时数字闪一下，让"挖到了"这件事有即时反馈
func _flash() -> void:
	_value_label.modulate = FLASH_COLOR
	var tween := create_tween()
	tween.tween_property(_value_label, "modulate", Color.WHITE, 0.35)

## 1234 -> 1,234
func _format(amount : int) -> String:
	var digits : String = str(absi(amount))
	var out : String = ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" + out) if amount < 0 else out
