# 一次性护盾道具
# 抵挡一次致死伤害，护盾存在时角色有光圈
# 创建时间：2026-05-11

extends "res://prefabs/items/ItemBase/item_base.gd"

class_name ItemShield

# 执行护盾效果
func _applyEffect(player: Node2D) -> void:
	if player.has_method("apply_powerup"):
		player.apply_powerup(3) # 3 = SHIELD
	else:
		# 兼容旧逻辑
		if "currentShields" in player:
			player.currentShields = 1
