# 爆炸特效控制脚本
# 处理爆炸动画播放与碰撞伤害检测
# 创建时间：2026-05-08

extends Area2D

class_name ExplosionEffect

# ── 节点引用 ──
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	anim.animation_finished.connect(queue_free)
	body_entered.connect(_onBodyEntered)
	anim.play()

# 碰撞回调，对玩家造成伤害
func _onBodyEntered(body: Node2D) -> void:
	# 标注修改点：联机模式下，伤害判定完全由服务端权威广播，客户端本地不在此进行碰撞扣血判定
	var gm = get_node_or_null("/root/GameMode")
	if gm and not gm.is_offline_mode:
		# 问题4：客户端增加预测受击反馈
		if body.is_in_group("Player") and body.get("isLocal") == true:
			if body.has_method("play_predictive_hit_feedback"):
				body.play_predictive_hit_feedback()
		return

	if body.has_method("takeDamage"):
		body.takeDamage()

# 播放中心爆炸动画
func tocenter() -> void:
	if anim.sprite_frames.has_animation("center"):
		anim.play("center")

# 播放扩散方向爆炸动画
func toOther() -> void:
	if anim.sprite_frames.has_animation("up"):
		anim.play("up")
