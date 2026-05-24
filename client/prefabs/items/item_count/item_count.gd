# 炸弹数量加成道具
# 提升玩家当前的炸弹放置上限，但受限于 Cap
# 创建时间：2026-05-08

extends "res://prefabs/items/ItemBase/item_base.gd"

# ── 导出变量 ──
@export var countIncrement: int = 1

# 执行效果逻辑
func _applyEffect(player: Node2D) -> void:
	if "currentMaxBombs" in player:
		var oldVal: int = player.currentMaxBombs
		var maxCap: int = player.maxBombsCap if "maxBombsCap" in player else 1
		
		player.currentMaxBombs = min(player.currentMaxBombs + countIncrement, maxCap)
		
		if player.currentMaxBombs > oldVal:
			print("[ITEM] Current max bombs increased to: ", player.currentMaxBombs)
		else:
			print("[ITEM] Already at bomb capacity limit!")
