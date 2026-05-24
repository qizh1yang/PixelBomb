@tool
extends Panel
class_name InventoryCell

enum State { NORMAL, HOVER, VALID_DROP, INVALID_DROP, SELECTED }

@onready var highlight = $Highlight

@export var is_special: bool = false:
	set(val):
		is_special = val
		_update_state()

var current_state: State = State.NORMAL:
	set(value):
		current_state = value
		_update_state()

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	_update_state()

func _on_mouse_entered():
	if current_state == State.NORMAL:
		current_state = State.HOVER

func _on_mouse_exited():
	if current_state == State.HOVER:
		current_state = State.NORMAL

func _update_state():
	if not is_inside_tree(): return
	
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	
	# AAA级立体阴影
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	
	# 基础背景色与边框色设置
	if is_special:
		style.bg_color = Color("#0c0e17") # 不透明超深底
		style.border_color = Color("#d4af37") # 金色实线
		style.set_border_width_all(2) # 2px 粗实线
	else:
		style.bg_color = Color("#1a1d2e") # 普通格不透明深色
		style.border_color = Color("#333852") # 深灰色边框
		style.set_border_width_all(1) # 1px
		
	match current_state:
		State.NORMAL:
			if highlight: highlight.visible = false
		State.HOVER:
			if highlight:
				highlight.visible = true
				highlight.modulate = Color(1, 1, 1, 0.08)
			if is_special:
				style.bg_color = Color("#121522")
				style.border_color = Color("#ffd700") # 明亮金色
			else:
				style.bg_color = Color("#22263a") # 轻微渐变亮色
				style.border_color = Color("#4a90e2") # 浅蓝色
				style.set_border_width_all(2) # hover 加粗为 2px
		State.VALID_DROP:
			if highlight:
				highlight.visible = true
				highlight.modulate = Color("#10b981") * Color(1, 1, 1, 0.25)
			style.bg_color = Color("#12251a") # 深林绿背景
			if is_special:
				style.border_color = Color("#d4af37")
			else:
				style.border_color = Color("#10b981") # 翠绿边框
			style.set_border_width_all(2)
		State.INVALID_DROP:
			if highlight: highlight.visible = false
		State.SELECTED:
			if highlight:
				highlight.visible = true
				highlight.modulate = Color(1, 1, 1, 0.2)
			style.bg_color = Color("#253045")
			style.border_color = Color("#0078d4")
			style.set_border_width_all(2)
			style.shadow_color = Color(0, 0.47, 0.83, 0.2)
			style.shadow_size = 4
			
	add_theme_stylebox_override("panel", style)
