class_name MineableData
extends Resource

## 总油量
@export var total_fuel : float

## 每秒消耗的油量 
@export var fuelConsumptionPerSecond : float

## 移动速度
@export var speed : float

## 攻击力：每次攻击对矿石造成的伤害
@export var attack : float

## 攻击间隔（秒）：挖矿时每隔这么久打一下矿石。0 或负数时用代码里的默认值 0.8
@export var attack_interval : float = 0.8

## 货舱容量（单位）。GDD 4.5：初始 20，技能树「扩容货舱」加 10
@export var cargo_max : int = 20

## 旋转速度
const rotate_speed : float = 0.02
