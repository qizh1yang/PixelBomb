# 炸弹闪光 Shader 控制脚本
# 驱动 Sprite2D 的 ShaderMaterial 实现引线闪烁效果
# 创建时间：2026-05-08

extends Node

class_name Flash

# ── 私有成员变量 ──
var spriteMaterial: ShaderMaterial
var flashTween: Tween

func _ready() -> void:
	var sprite: Sprite2D = get_parent() as Sprite2D
	# 复制材质，保证每个炸弹实例独立互不影响
	sprite.material = sprite.material.duplicate()
	spriteMaterial = sprite.material as ShaderMaterial
	spriteMaterial.set_shader_parameter("percent", 0.0)

# 触发一次闪光动画
func flash() -> void:
	if flashTween and flashTween.is_valid():
		flashTween.kill()

	spriteMaterial.set_shader_parameter("percent", 1.0)

	flashTween = create_tween()
	flashTween.tween_property(
		spriteMaterial,
		"shader_parameter/percent",
		0.0,
		0.15
	)
