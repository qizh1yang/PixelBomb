extends CanvasLayer

@onready var panel = $PanelContainer
@onready var label = $PanelContainer/MarginContainer/VBoxContainer/Label
@onready var texture_rect = %TextureRect

var _text: String = ""
var _duration: float = 1.0
var _image_path: String = ""
var _y_offset: float = 0.0
var _active_tween: Tween = null

func setup(text: String, duration: float, image_path: String = "", y_offset: float = 0.0) -> void:
	_text = text
	_duration = duration
	_image_path = image_path
	_y_offset = y_offset

func _ready() -> void:
	if _text != "":
		label.text = _text
		
	if _image_path != "" and ResourceLoader.exists(_image_path):
		var tex = load(_image_path)
		if tex:
			texture_rect.texture = tex
			texture_rect.show()
		else:
			texture_rect.hide()
	else:
		texture_rect.hide()
		
	# 动态应用垂直偏移量，防止提示词位置发生重叠
	panel.offset_top += _y_offset
	panel.offset_bottom += _y_offset
		
	# 初始位置：屏幕左侧外
	panel.position.x = -800
	
	# 延迟一点执行动画以确保节点布局完成获取到正确的 size
	call_deferred("_play_anim")

func _play_anim() -> void:
	panel.position.x = -panel.size.x - 50
	
	_active_tween = create_tween()
	# 滑入
	_active_tween.tween_property(panel, "position:x", 20.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 如果时间为正数，则在展示对应时间后自动滑出
	if _duration > 0:
		_active_tween.tween_interval(_duration)
		_active_tween.tween_property(panel, "position:x", -panel.size.x - 50, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_active_tween.finished.connect(func(): queue_free())

func dismiss() -> void:
	if _active_tween:
		_active_tween.kill()
	
	var tween = create_tween()
	tween.tween_property(panel, "position:x", -panel.size.x - 50, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(func(): queue_free())
