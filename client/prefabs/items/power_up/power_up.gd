# 局内道具（增益道具）
# 炸毁可破坏障碍物后有概率掉落，玩家经过自动拾取并立即生效
# 创建时间：2026-05-11

extends Area2D

class_name PowerUp

# ── 道具类型枚举 ──
enum Type {
	BOMB_UP,    # 炸弹+1：炸弹携带上限+1（最高5）
	POWER_UP,   # 威力+1：爆炸范围+1格（最高8）
	SPEED_UP,   # 速度UP：移动速度提升
	SHIELD      # 一次性护盾：抵挡一次致死伤害
}

# ── 道具类型配置 ──
const TYPE_CONFIG: Dictionary = {
	Type.BOMB_UP: {
		"name": "炸弹+1",
		"color": Color(1.0, 0.4, 0.2, 1.0),       # 橙红色
		"icon_char": "B",
		"max_stack": 5
	},
	Type.POWER_UP: {
		"name": "威力+1",
		"color": Color(1.0, 0.6, 0.0, 1.0),        # 火焰橙
		"icon_char": "P",
		"max_stack": 8
	},
	Type.SPEED_UP: {
		"name": "速度UP",
		"color": Color(0.2, 0.8, 1.0, 1.0),        # 天蓝色
		"icon_char": "S",
		"max_stack": 1
	},
	Type.SHIELD: {
		"name": "护盾",
		"color": Color(0.6, 0.9, 1.0, 1.0),        # 光盾白蓝
		"icon_char": "D",
		"max_stack": 1
	}
}

# ── 掉落权重（用于随机选择道具类型） ──
const DROP_WEIGHTS: Array = [
	# [Type, weight]
	[Type.BOMB_UP, 30],
	[Type.POWER_UP, 30],
	[Type.SPEED_UP, 20],
	[Type.SHIELD, 20],
]

# ── 导出变量 ──
@export var powerup_type: Type = Type.BOMB_UP

# ── 节点引用 ──
var _sprite: Sprite2D = null
var _label: Label = null
var _glow: PointLight2D = null
var _tween: Tween = null
var _is_picked: bool = false

func _ready() -> void:
	# 设置碰撞：道具检测玩家
	collision_layer = 0
	collision_mask = 1  # 玩家在 layer 1
	
	# 连接信号
	body_entered.connect(_on_body_entered)
	
	# 构建视觉元素
	_build_visuals()
	
	# 播放出现动画
	_play_spawn_animation()
	
	add_to_group("PowerUp")
	print("[POWERUP] %s spawned at %s" % [TYPE_CONFIG[powerup_type]["name"], global_position])

# 构建道具的视觉表现
func _build_visuals() -> void:
	var config: Dictionary = TYPE_CONFIG[powerup_type]
	
	# 底色圆形背景
	_sprite = Sprite2D.new()
	add_child(_sprite)
	
	# 创建一个 16x16 的纯色图标纹理
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var base_color: Color = config["color"]
	
	# 绘制圆形图标
	var center := Vector2(8, 8)
	for x in range(16):
		for y in range(16):
			var dist: float = Vector2(x, y).distance_to(center)
			if dist < 6.0:
				# 中心实心
				img.set_pixel(x, y, base_color)
			elif dist < 7.0:
				# 边缘渐变
				var alpha: float = 1.0 - (dist - 6.0)
				img.set_pixel(x, y, Color(base_color.r, base_color.g, base_color.b, alpha))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.z_index = 2
	
	# 添加图标文字标识
	_label = Label.new()
	add_child(_label)
	_label.text = config["icon_char"]
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size = Vector2(16, 16)
	_label.position = Vector2(-8, -8)
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 2)
	_label.z_index = 3
	
	# 碰撞形状
	var collision := CollisionShape2D.new()
	add_child(collision)
	var shape := CircleShape2D.new()
	shape.radius = 7.0
	collision.shape = shape

# 播放道具出现动画（从小变大 + 弹跳）
func _play_spawn_animation() -> void:
	scale = Vector2.ZERO
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	
	# 持续的上下浮动动画
	_tween.tween_callback(_start_float_animation)

# 上下浮动呼吸动画
func _start_float_animation() -> void:
	var float_tween := create_tween().set_loops()
	float_tween.tween_property(_sprite, "position:y", -2.0, 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tween.tween_property(_sprite, "position:y", 2.0, 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# 玩家碰到道具时触发
func _on_body_entered(body: Node2D) -> void:
	if _is_picked:
		return
	
	# 只检测玩家（CharacterBody2D + PlayerController）
	if not (body is CharacterBody2D):
		return
	
	if not body.has_method("apply_powerup"):
		return
	
	# 只有本地玩家可以拾取
	if "isLocal" in body and not body.isLocal:
		return
	
	_is_picked = true
	
	# 应用效果
	var success: bool = body.apply_powerup(powerup_type)
	
	if success:
		_play_pickup_effect()
		print("[POWERUP] %s picked up by %s" % [TYPE_CONFIG[powerup_type]["name"], body.name])
		
		# 发送网络消息通知其他客户端
		var net = get_node_or_null("/root/NetworkManager")
		if net:
			net.send_data({
				"type": "PICKUP",
				"x": int(global_position.x),
				"y": int(global_position.y)
			})
	else:
		# 如果无法应用（已达上限），允许重新拾取
		_is_picked = false

# 拾取特效：放大后消失
func _play_pickup_effect() -> void:
	# 停止所有动画
	if _tween and _tween.is_valid():
		_tween.kill()
	
	# 播放拾取音效
	var sfx := AudioStreamPlayer2D.new()
	sfx.stream = preload("res://assets/audio/sfx/Bonus2.wav")
	sfx.bus = &"SFX"
	sfx.volume_db = -5.0
	get_parent().add_child(sfx)
	sfx.global_position = global_position
	sfx.play()
	sfx.finished.connect(sfx.queue_free)
	
	# 拾取动画
	var pickup_tween := create_tween()
	pickup_tween.set_parallel(true)
	pickup_tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.15)
	pickup_tween.tween_property(self, "modulate:a", 0.0, 0.15)
	pickup_tween.chain().tween_callback(queue_free)

# ── 静态工具方法 ──

# 根据权重随机选择一个道具类型
static func random_type() -> Type:
	var total_weight: int = 0
	for entry in DROP_WEIGHTS:
		total_weight += entry[1]
	
	var roll: int = randi() % total_weight
	var cumulative: int = 0
	for entry in DROP_WEIGHTS:
		cumulative += entry[1]
		if roll < cumulative:
			return entry[0] as Type
	
	return Type.BOMB_UP  # fallback
