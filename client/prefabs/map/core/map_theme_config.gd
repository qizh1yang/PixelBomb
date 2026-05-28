# 地图主题美术样式配置文件
# 声明可为策划人员导出并配置的带权重样式的瓦片组合池
# 创建时间：2026-05-27

extends Resource

class_name MapThemeConfig

@export var theme_name: String = "SnowTheme"
@export var background_color: Color = Color("1e1e24")

# 地板瓦片池：格式 [{"source": int, "atlas": Vector2i, "weight": float}, ...]
@export var floor_tiles: Array[Dictionary] = [
	{ "source": 1, "atlas": Vector2i(1, 1), "weight": 70.0 },  # 主地板
	{ "source": 1, "atlas": Vector2i(0, 4), "weight": 20.0 },  # 斑驳地板
	{ "source": 1, "atlas": Vector2i(1, 4), "weight": 10.0 }   # 碎裂地板
]

# 硬墙瓦片池（不可破坏障碍）
@export var hard_wall_tiles: Array[Dictionary] = [
	{ "source": 1, "atlas": Vector2i(15, 9), "weight": 50.0 },
	{ "source": 1, "atlas": Vector2i(4, 13), "weight": 50.0 }
]

# 软墙瓦片池（可破坏障碍）
@export var soft_wall_tiles: Array[Dictionary] = [
	{ "source": 1, "atlas": Vector2i(4, 15), "weight": 40.0 },
	{ "source": 1, "atlas": Vector2i(5, 15), "weight": 40.0 },
	{ "source": 1, "atlas": Vector2i(0, 14), "weight": 20.0 }
]

# 边界外围大阻挡硬墙
@export var border_wall_tile: Dictionary = { "source": 0, "atlas": Vector2i(3, 2) }

# 撤离区/出口传送门瓦片
@export var extraction_tile: Dictionary = { "source": 1, "atlas": Vector2i(0, 14) }


# 根据配置权重抽取瓦片样式
func pick_tile(pool: Array[Dictionary], default_val: Dictionary) -> Dictionary:
	if pool.is_empty():
		return default_val
		
	var total_weight: float = 0.0
	for item in pool:
		total_weight += float(item.get("weight", 1.0))
		
	if total_weight <= 0.0:
		return pool[0]
		
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for item in pool:
		cumulative += float(item.get("weight", 1.0))
		if roll <= cumulative:
			return item
			
	return pool[0]
