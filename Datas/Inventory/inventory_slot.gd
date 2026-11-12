class_name InventorySlot
extends RefCounted

## 底栏槽位的纯展示数据（GDD 4.11）。
##
## 底栏 UI 只认识这个结构，不认识挖掘机 / 物品 / 任务道具——
## 场景切换时换的是 slots 数组，底栏代码一行不改。

enum State {
	READY,   ## 在库，可以选中 / 派遣
	ACTIVE,  ## 已派出 / 使用中，只可观看不可再派遣
	LOCKED,  ## 暂不可用（预留：未解锁的物品槽）
}

## 槽位主标题（物品 / 机器名）
var title : String = ""

## 副标题（数值摘要等静态事实）
var subtitle : String = ""

## 状态行文案（「在库 · 点击选中」「出勤中」…）
var status_text : String = ""

var state : State = State.READY

## 背后的业务对象（ExcavatorUnit / 以后的物品实例）。
## 底栏不读它，只在 slot_activated 里原样递回给数据源
var payload : Variant = null
