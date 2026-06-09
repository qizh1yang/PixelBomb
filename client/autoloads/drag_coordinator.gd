# [AI MODIFY]
extends Node

# 战术背包拖拽事务协调器
# 职责：记录被拖拽的物品与源容器，通过 Target-first commit 事务机制确保跨容器传输 100% 稳定且不会丢失。

var dragged_item: Control = null
var source_container: Control = null

func begin_drag(item: Control, source: Control) -> void:
	dragged_item = item
	source_container = source

func end_drag() -> void:
	dragged_item = null
	source_container = null

func transfer(target_container: Control, grid_pos: Vector2i, is_special: bool = false) -> bool:
	if not is_instance_valid(dragged_item) or not is_instance_valid(target_container):
		return false
		
	# 1. 先检查 target_container.canPlaceItem()
	var can_place = false
	if target_container.has_method("canPlaceItem"):
		if target_container is LootGrid:
			can_place = target_container.canPlaceItem(dragged_item, grid_pos)
		else:
			can_place = target_container.canPlaceItem(dragged_item, grid_pos, is_special)

	if not can_place:
		return false

	# 2. 如果可放：执行放置事务 (Target-first commit)
	if is_special and target_container.has_method("placeItemInSpecial"):
		target_container.placeItemInSpecial(dragged_item, grid_pos)
	else:
		target_container.placeItem(dragged_item, grid_pos)

	# 跨容器放置成功后，如果目标是背包，则关闭背包引导提示
	if target_container.is_in_group("Backpack"):
		if TutorialManager:
			TutorialManager.hide_tutorial("chest_near")

	# 3. place 成功后：清理源容器中的数据与引用
	if is_instance_valid(source_container) and source_container.has_method("removeItem"):
		if source_container == target_container:
			# 为了防止 removeItem 将刚刚成功放置在同一容器新坐标的格子数据全部清空，
			# 我们临时备份新坐标格子的数据，调用 removeItem 清理老坐标，再将新坐标数据还原。
			# 这样既完美满足 Target-first commit，又避免了同容器移动导致的自我清除 Bug。
			var new_cells: Array[Vector2i] = []
			var new_special_cells: Array[Vector2i] = []
			
			if "gridData" in target_container:
				for r in range(target_container.gridData.size()):
					for c in range(target_container.gridData[r].size()):
						# [AI MODIFY]
						var cell = target_container.gridData[r][c]
						if cell is Array:
							if dragged_item in cell:
								new_cells.append(Vector2i(c, r))
						else:
							if cell == dragged_item:
								new_cells.append(Vector2i(c, r))
			if "specialGridData" in target_container:
				for r in range(target_container.specialGridData.size()):
					for c in range(target_container.specialGridData[r].size()):
						# [AI MODIFY]
						var cell = target_container.specialGridData[r][c]
						if cell is Array:
							if dragged_item in cell:
								new_special_cells.append(Vector2i(c, r))
						else:
							if cell == dragged_item:
								new_special_cells.append(Vector2i(c, r))
							
			# 清除全部引用（清除老格子）
			source_container.removeItem(dragged_item)
			
			# 还原新格子的引用
			# [AI MODIFY]
			if "gridData" in target_container:
				for cell in new_cells:
					var cell_val = target_container.gridData[cell.y][cell.x]
					if cell_val is Array:
						if not (dragged_item in cell_val):
							cell_val.append(dragged_item)
					else:
						target_container.gridData[cell.y][cell.x] = dragged_item
			if "specialGridData" in target_container:
				for cell in new_special_cells:
					var cell_val = target_container.specialGridData[cell.y][cell.x]
					if cell_val is Array:
						if not (dragged_item in cell_val):
							cell_val.append(dragged_item)
					else:
						target_container.specialGridData[cell.y][cell.x] = dragged_item
					
			# 重新设定最终属性
			dragged_item.gridPos = grid_pos
			
			# 保证其子节点关系正确
			var expected_parent = target_container.specialItemsContainer if is_special else target_container.itemsContainer
			if is_instance_valid(expected_parent) and dragged_item.get_parent() != expected_parent:
				if dragged_item.get_parent():
					dragged_item.get_parent().remove_child(dragged_item)
				expected_parent.add_child(dragged_item)
			
			dragged_item.position = Vector2(
				grid_pos.x * (target_container.CELL_SIZE + target_container.SPACING),
				grid_pos.y * (target_container.CELL_SIZE + target_container.SPACING)
			)
			
			# 重新计算属性增益与容量
			if target_container.has_method("updateBackpackStats"):
				target_container.updateBackpackStats()
			if target_container.has_method("updateCapacityDisplay"):
				target_container.updateCapacityDisplay()
		else:
			source_container.removeItem(dragged_item)
			
	# [AI MODIFY]
	if is_instance_valid(dragged_item):
		dragged_item.modulate.a = 1.0

	# 4. 最后 end_drag() 结束事务
	end_drag()
	return true
