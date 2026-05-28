# 地图资源类 - 定义地图的元数据与场景
extends Resource
class_name MapResource

@export var map_id: String             # 唯一 ID (如 "CLASSIC", "WINTER", "PROCEDURAL")
@export var display_name: String       # 显示名称
@export var description: String        # 地图描述
@export var preview_texture: Texture2D # 预览图
@export var map_scene: PackedScene     # 地图场景 (包含 Map 根节点)

# ── 地图生成规则 ──
@export var width: int = 17           # 宽度
@export var height: int = 17          # 高度
@export var wall_density: float = 0.6 # 墙壁密度
@export var map_theme_color: Color = Color.WHITE

# ── 程序化地图默认参数（仅 PROCEDURAL 类型生效） ──
@export var is_procedural: bool = false
@export var default_shape: String = "circle"
@export var default_map_size: String = "small"

# ── 特殊属性 ──
@export var custom_rules: Dictionary = {}
