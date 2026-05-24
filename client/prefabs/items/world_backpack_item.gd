extends "res://prefabs/items/ItemBase/item_base.gd"

## 世界中的异形物品实体
## 拾取后会打开背包并进入放置模式

@export var item_resource: BackpackItemResource

@onready var sprite = $Sprite2D

func _ready():
	super._ready()
	if item_resource and sprite:
		sprite.texture = item_resource.icon
		sprite.modulate = item_resource.theme_color

func _applyEffect(player: Node2D):
	# 找到玩家的背包 UI
	var hud = GameMode.hud
	if not hud: return
	
	var backpack = hud.get_node_or_null("Backpack")
	if not backpack:
		# 如果 HUD 里没有，去场景找 (适配不同架构)
		backpack = player.get_node_or_null("Backpack")
	
	if backpack:
		backpack.show()
		backpack.move_to_front()
		
		# 创建一个 BackpackItem UI 实例
		var itemUIScene = load("res://prefabs/Backpack/sub/backpack_item.tscn")
		var itemUI = itemUIScene.instantiate()
		itemUI.setup(item_resource)
		
		# 强制进入拖拽状态？
		# 在 Godot 中很难直接从代码启动 Drag & Drop
		# 所以我们先把它放到背包的一个临时区域，或者直接附加到鼠标上
		_attach_to_cursor(itemUI, backpack)

func _attach_to_cursor(itemUI: Control, backpack: Control):
	# 简单处理：将物品添加到背包的 Items 容器，但标记为待放置
	# 这里我们可以直接把它放在背包外面，提示玩家点击放置
	var items_container = backpack.get_node("%Items")
	items_container.add_child(itemUI)
	
	# 让物品跟随鼠标，直到玩家点击
	# 为了简化 Demo，我们直接把物品放在背包的第一个空格，如果放不下就消失
	var placed = false
	for r in range(backpack.ROWS):
		for c in range(backpack.COLS):
			if backpack._isSpaceAvailable(Vector2i(c, r), itemUI.resource.shape):
				backpack.placeItem(itemUI, Vector2i(c, r))
				placed = true
				break
		if placed: break
	
	if not placed:
		itemUI.queue_free()
		print("[BACKPACK] No space for picked item!")
