extends Node

# 根据资源或 ID 创建角色
func create_character(char_res: CharacterResource) -> Node:
	if not char_res: return null
	
	# 动态加载对应场景
	var scene_path = "res://prefabs/Players/player%d/player%d.tscn" % [char_res.char_index + 1, char_res.char_index + 1]
	var scene = load(scene_path) as PackedScene
	if not scene: 
		push_error("Failed to load character scene: " + scene_path)
		return null
		
	var instance = scene.instantiate()
	
	# 应用基础属性
	if "currentSpeed" in instance: instance.currentSpeed = char_res.base_speed
	if "currentMaxBombs" in instance: instance.currentMaxBombs = char_res.base_bomb_cap
	if "currentRadius" in instance: instance.currentRadius = char_res.base_radius
	if "currentShields" in instance: instance.currentShields = char_res.base_shield_count
	
	# 应用天花板
	if "speedCap" in instance: instance.speedCap = char_res.max_speed
	if "maxBombsCap" in instance: instance.maxBombsCap = char_res.max_bomb_cap
	if "explosionRadiusCap" in instance: instance.explosionRadiusCap = char_res.max_radius
	if "maxShieldsCap" in instance: instance.maxShieldsCap = char_res.max_shield_count
	
	return instance
