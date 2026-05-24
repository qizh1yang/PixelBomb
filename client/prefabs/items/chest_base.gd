# 宝箱基类
# 处理开箱读条逻辑与品级颜色
# 创建时间：2026-05-08

extends Area2D

class_name ChestBase

# ── 枚举 ──
enum Tier { WHITE, BLUE, GOLD }

# ── 导出变量 ──
@export var tier: Tier = Tier.WHITE

# ── 私有成员变量 ──
var baseTime: Dictionary = {
	Tier.WHITE: 3.0,
	Tier.BLUE: 6.0,
	Tier.GOLD: 10.0
}
var currentOpenTime: float = 0.0
var isOpening: bool = false
var playerInside: Node2D = null

func _ready() -> void:
	collision_mask = 1
	body_entered.connect(_onBodyEntered)
	body_exited.connect(_onBodyExited)

	match tier:
		Tier.WHITE: $ColorRect.color = Color.WHITE
		Tier.BLUE: $ColorRect.color = Color.CORNFLOWER_BLUE
		Tier.GOLD: $ColorRect.color = Color.GOLD

# 玩家进入宝箱范围
func _onBodyEntered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		playerInside = body
		print("[CHEST] Player near. Hold to open...")

# 玩家离开宝箱范围
func _onBodyExited(body: Node2D) -> void:
	if body == playerInside:
		playerInside = null
		_resetOpening()

func _process(delta: float) -> void:
	if playerInside:
		isOpening = true
		currentOpenTime += delta
		var targetTime: float = baseTime[tier]
		if currentOpenTime >= targetTime:
			_onOpened()

# 重置开箱计时
func _resetOpening() -> void:
	isOpening = false
	currentOpenTime = 0.0

var chestID: String = ""

# 开箱完成回调
func _onOpened() -> void:
	print("[CHEST] Opening request for: ", chestID)
	var net = get_node_or_null("/root/NetworkManager")
	if net:
		net.request("Room.OpenChest", {"id": chestID})
	
	# 本地先行重置，等待服务端确认后消失
	_resetOpening()
	playerInside = null

func _spawnLoot() -> void:
	var loot_pool = [
		"res://prefabs/items/res/item_ammo_small.tres",
		"res://prefabs/items/res/item_ammo_long.tres",
		"res://prefabs/items/res/item_power_core.tres",
		"res://prefabs/items/res/item_epic_shield.tres",
		"res://prefabs/items/res/item_boots.tres"
	]
	
	var res_path = loot_pool[randi() % loot_pool.size()]
	var res = load(res_path)
	
	# 创建世界物品实体
	# 这里假设你有一个 world_item.tscn，如果没有我随后创建一个简单的
	var worldItemScene = load("res://prefabs/items/world_item.tscn")
	if worldItemScene:
		var item = worldItemScene.instantiate()
		item.item_resource = res
		item.global_position = global_position
		get_parent().add_child(item)
