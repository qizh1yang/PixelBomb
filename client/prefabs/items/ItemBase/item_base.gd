# 道具基类
# 处理通用的碰撞检测与拾取逻辑
# 创建时间：2026-05-08
# 更新：2026-05-11 - 支持局内道具自动拾取并立即生效

extends Area2D

class_name ItemBase

# ── 信号 ──
signal itemPicked(player: Node2D)

# ── 导出变量 ──
@export var item_id: String = ""

func _ready() -> void:
	# 道具在 layer 8，检测 layer 1（玩家）
	collision_layer = 0
	collision_mask = 1  # 检测玩家 (layer 1)
	
	# 确保 monitoring 开启
	monitoring = true
	monitorable = false
	
	body_entered.connect(_onBodyEntered)
	print("[ITEM] %s ready at %s" % [name, global_position])
	
	# 自动调整缩放：确保图标在世界中显示为标准 16x16 像素
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		var tex_size = sprite.texture.get_size()
		if tex_size.x > 0:
			var target_size = 16.0
			sprite.scale = Vector2(target_size / tex_size.x, target_size / tex_size.y)
	
	# 启动上下浮动效果
	_startBobbing()

var _bob_tween: Tween = null

# 上下浮动效果
func _startBobbing() -> void:
	if not is_inside_tree(): return
	
	var sprite = get_node_or_null("Sprite2D")
	if not sprite: return
	
	if _bob_tween:
		_bob_tween.kill()
	
	var original_pos = sprite.position
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(sprite, "position", original_pos + Vector2(0, -2), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(sprite, "position", original_pos, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

var itemID: String = ""
var _pickup_applied: bool = false

# 碰撞回调，检测玩家进入并执行拾取
func _onBodyEntered(body: Node2D) -> void:
	if _pickup_applied:
		return
	if not body.is_in_group("Player"):
		return

	# 只有本地玩家触发拾取
	if "isLocal" in body and not body.isLocal:
		return

	print("[ITEM] Player touched item: %s, itemID: %s" % [name, itemID])
	_pickup_applied = true

	# 先本地应用效果，再发网络请求给服务器确认
	_applyEffect(body)
	itemPicked.emit(body)

	var gm = get_node_or_null("/root/GameMode")
	if gm and not gm.is_offline_mode:
		var net = get_node_or_null("/root/NetworkManager")
		if net:
			net.send_data({
				"type": "PICKUP",
				"id": itemID
			})
	else:
		# ── [NEW] 离线/新手教程模式：直接在本地播放拾取特效并销毁 ──
		_playPickupEffect()


# 虚函数，由子类实现具体效果
func _applyEffect(_player: Node2D) -> void:
	pass

# 拾取特效：缩放+淡出后销毁
func _playPickupEffect() -> void:
	# 禁用碰撞防止重复拾取
	set_deferred("monitoring", false)
	
	# 停止浮动动画
	if _bob_tween:
		_bob_tween.kill()
	
	# 如果不在树里（例如已被销毁），直接返回
	if not is_inside_tree():
		queue_free()
		return
	
	# 播放拾取音效
	if ResourceLoader.exists("res://assets/audio/sfx/Bonus2.wav"):
		var sfx := AudioStreamPlayer2D.new()
		sfx.stream = load("res://assets/audio/sfx/Bonus2.wav")
		sfx.bus = &"SFX"
		sfx.volume_db = -5.0
		get_parent().add_child(sfx)
		sfx.global_position = global_position
		sfx.play()
		sfx.finished.connect(sfx.queue_free)
	
	# 缩放+淡出动画
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.15)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.chain().tween_callback(queue_free)
