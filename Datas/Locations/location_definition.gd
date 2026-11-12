class_name LocationDefinition
extends Resource

## 地球全景上的一个可进入地点（GDD 4.12）。
##
## 纯配置：位置（球面方向 × 半径）+ 名称 + 进入后切到哪个主区视图。
## 以后加「深井 / 熔炼站 / 废料场」只要再加一份 .tres，orbit_view 不用改。

## 唯一 id，对应 GDD 4.9 的地点编号（pit_01 / upgrade_terminal …）
@export var id : StringName = &""

## 地球上的标签主文案
@export var display_name : String = ""

## 标签副文案（编号 / 职能），可留空
@export var sub_label : String = ""

## 球面方向（会被归一化）。z 为正 = 朝向默认相机
@export var surface_dir : Vector3 = Vector3(0, 0, 1)

## 贴球面的半径，要和地球网格半径一致（约 0.5）
@export var surface_radius : float = 0.52

## 进入后切到的主区视图：&"mine" / &"upgrade"
@export var target_view : StringName = &"mine"
