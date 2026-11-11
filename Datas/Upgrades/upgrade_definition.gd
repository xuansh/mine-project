class_name UpgradeDefinition
extends Resource

## 升级分组名。同组的多条定义共享一个等级：钻头组同时包含伤害与攻速两条
@export var group : StringName = &""

## 对应机器数据里的字段名（预留，后续实体读取升级加成时用）
@export var stat_key : StringName = &""

## 卡片主标题（同组共用第一条的标题与描述）
@export var title : String = ""

## 卡片说明文字
@export var description : String = ""

## 初始值（等级 0）
@export var base_value : float = 0.0

## 封顶值。递增时取 min，递减（如攻击间隔）时取 max
@export var max_value : float = 0.0

## 每级变化量：正数往上加，负数往下减
@export var increment : float = 0.0

## 首次购买成本。成本曲线 cost(n) = base_cost × cost_growth^n，n 为已购次数
@export var base_cost : int = 0

## 成本增长系数，GDD 4.6 定为 1.55
@export var cost_growth : float = 1.55

## 数值显示保留的小数位
@export var decimals : int = 0

## 数值单位后缀，如 " 伤害"、" 秒"
@export var unit : String = ""
