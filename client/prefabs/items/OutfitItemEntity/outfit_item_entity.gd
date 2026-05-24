# 局外物品实体（物理掉落物）
# 玩家捡起后自动尝试放入背包
# 创建时间：2026-05-11

extends "res://prefabs/items/ItemBase/item_base.gd"

class_name OutfitItemEntity

# ── 成员变量 ──
var resource: BackpackItemResource

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	super._ready()
	if resource:
		_update_visuals()

# 初始化资源
func setup_resource(res: BackpackItemResource) -> void:
	resource = res
	if is_inside_tree():
		_update_visuals()

func _update_visuals() -> void:
	if not resource: return
	
	if resource.icon:
		sprite.texture = resource.icon
		# 动态计算缩放，确保物品在地图上显示为标准大小 (约 16x16 像素)
		var texSize = resource.icon.get_size()
		if texSize.x > 0 and texSize.y > 0:
			sprite.scale = Vector2(16.0 / texSize.x, 16.0 / texSize.y)
	else:
		# 如果没有图标，使用基础图标并染色
		sprite.texture = load("res://icon.svg")
		sprite.scale = Vector2(0.12, 0.12)
	
	sprite.modulate = resource.theme_color
	name = "OutfitItem_" + resource.item_name

# 重写拾取逻辑
func _applyEffect(player: Node2D) -> void:
	if not resource: return
	
	# 寻找背包
	var backpack = get_tree().get_first_node_in_group("Backpack")
	if backpack and backpack.has_method("tryAddItem"):
		var success = backpack.tryAddItem(resource)
		if success:
			print("[OUTFIT] Successfully added to backpack: %s" % resource.item_name)
		else:
			# 如果背包满了，可以考虑把物品弹开或者提示
			print("[OUTFIT] Backpack is full, cannot pick up: %s" % resource.item_name)
			# 这里我们可以选择不销毁实体，让玩家清理后再捡
			return 
	else:
		print("[OUTFIT] Error: Backpack not found")
