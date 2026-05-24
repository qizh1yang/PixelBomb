# 移动速度加成道具
# 移动间隔缩短（速度提升至200）
# 创建时间：2026-05-08
# 更新：2026-05-11 - 使用局内道具速度常量

extends "res://prefabs/items/ItemBase/item_base.gd"

class_name ItemSpeed

# 执行移动速度加成效果
func _applyEffect(player: Node2D) -> void:
	if player.has_method("apply_powerup"):
		player.apply_powerup(2) # 2 = SPEED_UP
	else:
		# 兼容旧逻辑
		if "currentSpeed" in player:
			player.currentSpeed = 200.0
