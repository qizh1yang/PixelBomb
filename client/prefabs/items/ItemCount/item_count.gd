# 炸弹数量加成道具
# 提升玩家当前的炸弹放置上限，最高堆叠至5
# 创建时间：2026-05-08
# 更新：2026-05-11 - 使用局内道具常量上限

extends "res://prefabs/items/ItemBase/item_base.gd"

class_name ItemCount

# ── 导出变量 ──
@export var countIncrement: int = 1

# 执行炸弹数量加成效果
func _applyEffect(player: Node2D) -> void:
	if player.has_method("apply_powerup"):
		player.apply_powerup(0) # 0 = BOMB_UP
	else:
		# 兼容旧逻辑
		if "currentMaxBombs" in player:
			player.currentMaxBombs += countIncrement
