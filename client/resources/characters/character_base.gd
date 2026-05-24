# 角色资源类 - 定义角色的基础属性与天花板
extends Resource
class_name CharacterResource

@export var character_id: String       # 唯一 ID (如 "player1", "fire")
@export var char_index: int = 0         # 对应原有 player1, player2 的索引
@export var display_name: String       # 显示名称
@export var description: String        # 角色描述
@export var icon: Texture2D           # 角色图标
@export var preview_scene: PackedScene # 预览场景 (用于角色选择界面)

# ── 基础属性 (出场时的默认值) ──
@export var base_speed: float = 100.0    # 基础移动速度
@export var base_bomb_cap: int = 1       # 基础炸弹数量
@export var base_radius: int = 1         # 基础爆炸范围
@export var base_shield_count: int = 0   # 基础护盾数量

# ── 属性天花板 (局内可提升到的最高数值) ──
@export var max_speed: float = 200.0      # 最高速度
@export var max_bomb_cap: int = 5        # 最多炸弹数
@export var max_radius: int = 8          # 最大爆炸范围
@export var max_shield_count: int = 3    # 最多护盾数

# ── 特殊能力 ──
@export var special_ability: String = ""  # 特殊能力 ID
@export var ability_description: String = "" # 能力描述
