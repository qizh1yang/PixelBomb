extends CanvasLayer

const CONFIG_PATH = "user://guide_settings.cfg"

func _ready() -> void:
	# 检查是否为首次进入
	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)
	
	if err == OK and config.get_value("guide", "is_shown", false):
		# 不是第一次进入，直接销毁，不显示引导
		queue_free()
		return
		
	# 第一次进入，保存记录
	config.set_value("guide", "is_shown", true)
	config.save(CONFIG_PATH)

	var texture_rect = $Panel/VBoxContainer/TextureRect
	
	# 如果没有在编辑器中设定图片，则尝试动态加载
	if texture_rect.texture == null:
		var img_path = _find_image_in_guide_res()
		if img_path != "":
			var tex = load(img_path)
			if tex:
				texture_rect.texture = tex
		else:
			print("[GuideUI] 未找到按键图片，请在 res://assets/guide/res 目录下放置图片。")

func _find_image_in_guide_res() -> String:
	var path = "res://assets/guide/res"
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var clean_name = file_name.replace(".import", "")
				if clean_name.ends_with(".png") or clean_name.ends_with(".jpg") or clean_name.ends_with(".webp"):
					return path + "/" + clean_name
			file_name = dir.get_next()
	return ""
