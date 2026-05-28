# 程序化地图生成框架可视化与自动化综合测试套件
# 支持数字键 1-5 瞬时切五大高质量形状，支持 [R] 重滚种子、[S] 导出数据、[O] 调试遮罩开关
# 创建时间：2026-05-27

extends Node2D

@onready var procedural_map: ProceduralMap = $ProceduralMap
@onready var status_label: Label = $CanvasLayer/StatusLabel
@onready var camera: Camera2D = $Camera2D
var cam_speed: float = 400.0

# 仅保留 5 种高品质地图形状
const SHAPES: Array[String] = [
	"circle",
	"hexagon",
	"star",
	"ring",
	"cave"
]

var current_shape_idx: int = 0 # 默认展示 Circle

func _ready() -> void:
	if not procedural_map:
		push_error("[TEST] ProceduralMap node not found in scene tree!")
		return
		
	# 强行开启调试叠加层，方便第一视角审查
	procedural_map.show_debug_overlay = true
	
	# 配置默认小型尺寸并重画
	procedural_map.map_size = "small"
	procedural_map.shape_type = SHAPES[current_shape_idx]
	_regenerate_map()

# 根据当前设置重新生成新地图
func _regenerate_map(new_seed: int = -1) -> void:
	if not procedural_map: return
	
	var seed_val = new_seed if new_seed >= 0 else int(Time.get_unix_time_from_system())
	procedural_map.shape_type = SHAPES[current_shape_idx]
	procedural_map._generate_map(seed_val)
	
	_update_hud_display()

func _update_hud_display() -> void:
	if not status_label or not procedural_map: return
	
	var help_text = "Procedural Map Overhaul Interactive Debugger\n" + \
					"================================================\n" + \
					"Current Shape: %s (Key [1]-[5] to switch)\n" % SHAPES[current_shape_idx].capitalize() + \
					"Active Seed: %d\n" % procedural_map._map_seed + \
					"Grid Bounds: %dx%d (%s size)\n" % [procedural_map.map_data.size(), procedural_map.map_data[0].size(), procedural_map.map_size.capitalize()] + \
					"Spawnpoints: %d | Extraction Point Solved: %s\n" % [procedural_map.spawn_points.size(), "YES" if procedural_map.extraction_point != Vector2i(-1, -1) else "NO"] + \
					"Path Balance (Imbalance Score): %.1f%%\n" % [procedural_map.imbalance_score * 100.0] + \
					"================================================\n" + \
					"Interactive Controls:\n" + \
					"- [R] : Regenerate Random Map (New Seed)\n" + \
					"- [S] : Save Map Matrix to JSON & Export PNG Preview\n" + \
					"- [O] : Toggle BFS Reachability Topology Overlay\n" + \
					"- [M] : Toggle Map Size (Small -> Medium -> Large)\n" + \
					"- [Q/E] : Camera Zoom Out/In (Zoom: %.1fx)\n" % (camera.zoom.x if is_instance_valid(camera) else 1.2) + \
					"- [WASD/Arrows] : Pan Camera\n\n" + \
					"Key Shortcuts:\n" + \
					"  [1] Circle | [2] Hexagon | [3] Star | [4] Ring | [5] Cave"
					
	status_label.text = help_text

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key_str = OS.get_keycode_string(event.keycode)
		
		# 1-5 数字键快速切形状
		if key_str in ["1", "2", "3", "4", "5"]:
			current_shape_idx = key_str.to_int() - 1
			print("[TEST-CONTROL] Switching Shape to: ", SHAPES[current_shape_idx])
			_regenerate_map()
			
		elif key_str == "R":
			print("[TEST-CONTROL] Regenerating with new random seed...")
			_regenerate_map()
			
		elif key_str == "S":
			print("[TEST-CONTROL] Manually exporting JSON and PNG...")
			procedural_map.export_map_to_json("user://manual_procedural_map.json")
			procedural_map.export_map_to_png("user://manual_map_preview.png")
			_update_hud_display()
			
		elif key_str == "O":
			procedural_map.show_debug_overlay = not procedural_map.show_debug_overlay
			print("[TEST-CONTROL] Toggle debug overlay: ", procedural_map.show_debug_overlay)
			_regenerate_map(procedural_map._map_seed) # 保持原种子重绘
			
		elif key_str == "M":
			# 仅支持 Small, Medium, Large 尺寸切换
			match procedural_map.map_size:
				"small":
					procedural_map.map_size = "medium"
				"medium":
					procedural_map.map_size = "large"
				"large":
					procedural_map.map_size = "small"
			print("[TEST-CONTROL] Switching Map Size to: ", procedural_map.map_size)
			_regenerate_map()
			
		elif key_str == "Q":
			if is_instance_valid(camera):
				camera.zoom = (camera.zoom - Vector2(0.1, 0.1)).clamp(Vector2(0.2, 0.2), Vector2(4.0, 4.0))
				_update_hud_display()
				print("[TEST-CONTROL] Zoom Out: ", camera.zoom)
				
		elif key_str == "E":
			if is_instance_valid(camera):
				camera.zoom = (camera.zoom + Vector2(0.1, 0.1)).clamp(Vector2(0.2, 0.2), Vector2(4.0, 4.0))
				_update_hud_display()
				print("[TEST-CONTROL] Zoom In: ", camera.zoom)

func _process(delta: float) -> void:
	# 键盘 WASD / 方向键平移 Camera
	var cam_move = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		cam_move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		cam_move.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		cam_move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		cam_move.y += 1
		
	if cam_move != Vector2.ZERO and is_instance_valid(camera):
		camera.position += cam_move.normalized() * cam_speed * delta
