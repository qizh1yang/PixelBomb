# 炸弹威力加成道具
# 提升玩家当前的爆炸半径，最高堆叠至8
# 创建时间：2026-05-08
# 更新：2026-05-11 - 使用局内道具常量上限

extends "res://prefabs/items/ItemBase/item_base.gd"

class_name ItemPower

# ── 导出变量 ──
@export var radiusIncrement: int = 1

# 执行爆炸半径加成效果
func _applyEffect(player: Node2D) -> void:
	if player.has_method("apply_powerup"):
		player.apply_powerup(1) # 1 = POWER_UP
	else:
		# 兼容旧逻辑
		if "currentRadius" in player:
			player.currentRadius += radiusIncrement
