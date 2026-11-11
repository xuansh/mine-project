class_name Oredata
extends Resource

## 矿石显示名
@export var ore_name : String = ""

## 矿石耐久（血量）。挖掘机每次攻击扣掉 attack 点，扣到 0 即这一格挖完
@export var hp : float = 0.0

## 挖完这一格时掉落的数量
@export var drop : float = 0.0

## 每单位矿石卖出的金币。挖完一格的金币收益 = drop × value
@export var value : float = 1.0
