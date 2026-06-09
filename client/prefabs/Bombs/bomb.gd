# 炸弹核心逻辑
# 处理引爆计时、爆炸扩散与爆炸音效
# 创建时间：2026-05-08

extends StaticBody2D

class_name Bomb

# ── 导出变量 ──
@export var explosionEffectScene: PackedScene
@export var explosionLength: int = 1
@export var limitUp: int = 1
@export var limitDown: int = 1
@export var limitLeft: int = 1
@export var limitRight: int = 1
@export var wallLayer: TileMapLayer
@export var fuseTime: float = 2.0
@export var explosionSound: AudioStream = preload("res://prefabs/Bombs/res/Explosion2.wav")

# ── 节点引用 ──
@onready var flashTimer: Timer = $FlashTimer
@onready var fuseTimer: Timer = $FuseTimer

func _ready() -> void:
	add_to_group("Bomb")
	flashTimer.timeout.connect(func(): $Sprite2D/Flash.flash())

	# 始终启动引信定时器作为兜底：在线模式由服务端权威引爆（is_exploded 防止重复触发）
	fuseTimer.timeout.connect(explode)
	fuseTimer.start()
	flashTimer.start()

var is_exploded: bool = false

# 执行爆炸主逻辑
func explode() -> void:
	if is_exploded: return
	is_exploded = true
	if is_instance_valid(flashTimer): flashTimer.stop()
	if is_instance_valid(fuseTimer): fuseTimer.stop()

	# 炸弹炸毁动画：渐隐 + 缩放消失
	_set_bomb_immune()
	var tween := create_tween()
	tween.tween_property($Sprite2D, "modulate:a", 0.0, 0.15)
	tween.parallel().tween_property($Sprite2D, "scale", Vector2(1.5, 1.5), 0.15)
	tween.tween_callback(_do_explode)

func _set_bomb_immune() -> void:
	# 爆炸瞬间碰撞体失效，防止玩家撞到正在炸毁的炸弹
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)

func _do_explode() -> void:
	var centerCell: Vector2i = wallLayer.local_to_map(wallLayer.to_local(global_position))
	spawnExplosionCenter(centerCell)

	var dirs = {
		Vector2i.UP: limitUp,
		Vector2i.DOWN: limitDown,
		Vector2i.LEFT: limitLeft,
		Vector2i.RIGHT: limitRight
	}

	for dir: Vector2i in dirs:
		var length = min(explosionLength, dirs[dir])
		for i: int in range(1, length + 1):
			var cell: Vector2i = centerCell + dir * i
			if not handleExplosionAt(cell, dir):
				break

	playExplosionSound()
	queue_free()

# 处理单个爆炸格的逻辑，返回是否继续扩散
func handleExplosionAt(cell: Vector2i, dir: Vector2i) -> bool:
	if wallLayer.is_indestructible(cell.x, cell.y):
		return false
	if wallLayer.is_destructible_wall(cell.x, cell.y):
		wallLayer.destroy_destructible_wall(cell.x, cell.y)
		spawnExplosionEffect(cell, dir)
		return false
	spawnExplosionEffect(cell, dir)
	return true

# 在指定格子生成带方向的爆炸特效
func spawnExplosionEffect(cell: Vector2i, dir: Vector2i) -> void:
	if not explosionEffectScene:
		return
	var eff: Node2D = explosionEffectScene.instantiate()
	get_parent().add_child(eff)
	eff.global_position = wallLayer.to_global(wallLayer.map_to_local(cell))

	var rot: int = 0
	if dir == Vector2i.RIGHT: rot = 90
	elif dir == Vector2i.DOWN: rot = 180
	elif dir == Vector2i.LEFT: rot = -90
	elif dir == Vector2i.UP: rot = 0

	eff.rotation_degrees = rot

	if eff.has_method("toOther"):
		eff.toOther()

# 在中心格子生成爆炸中心特效
func spawnExplosionCenter(cell: Vector2i) -> void:
	if not explosionEffectScene:
		return
	var eff: Node2D = explosionEffectScene.instantiate()
	get_parent().add_child(eff)
	eff.global_position = wallLayer.to_global(wallLayer.map_to_local(cell))

	if eff.has_method("tocenter"):
		eff.tocenter()

# 播放爆炸音效
func playExplosionSound() -> void:
	if not explosionSound: return

	var sfx: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	sfx.stream = explosionSound
	sfx.bus = &"SFX"
	get_parent().add_child(sfx)
	sfx.global_position = global_position
	sfx.play()
	sfx.finished.connect(sfx.queue_free)
