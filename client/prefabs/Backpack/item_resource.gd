extends Resource
class_name BackpackItemResource

## 异形物品资源定义
## 定义物品的形状、属性和视觉效果

@export var item_name: String = "Item"
@export var id: String = "item_id"
@export var icon: Texture2D

enum Category { ALL, BOMB, SPEED, RANGE, SPECIAL }
@export var category: Category = Category.ALL

## 物品形状：由相对于中心点的坐标数组组成
## 例如：1x1 = [Vector2i(0,0)]
## 例如：1x2 = [Vector2i(0,0), Vector2i(0,1)]
## 例如：L型 = [Vector2i(0,0), Vector2i(0,1), Vector2i(1,1)]
@export var shape: Array[Vector2i] = [Vector2i(0, 0)]

@export_group("Stats Boost")
@export var bomb_cap_boost: int = 0
@export var radius_cap_boost: int = 0
@export var radius_up_boost: int = 0
@export var radius_down_boost: int = 0
@export var radius_left_boost: int = 0
@export var radius_right_boost: int = 0
@export var speed_cap_boost: float = 0.0
@export var shield_cap_boost: int = 0
@export var has_persistent_shield: bool = false

@export_group("Visuals")
@export var theme_color: Color = Color.WHITE

enum Rarity { RARE, EPIC, DIAMOND }
@export var rarity: Rarity = Rarity.RARE

func get_rarity_color() -> Color:
	match rarity:
		Rarity.RARE: return Color.DODGER_BLUE    # 稀有 (Rare) - 蓝色
		Rarity.EPIC: return Color.MEDIUM_PURPLE  # 史诗 (Epic) - 紫色
		Rarity.DIAMOND: return Color.AQUA        # 钻石 (Diamond) - 青色/钻石色
	return Color.WHITE
