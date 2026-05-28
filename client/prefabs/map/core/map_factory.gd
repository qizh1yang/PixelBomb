# MapFactory.gd
# 统一地图场景实例化工厂 (Map Factory)
# 职责：根据 MapType 字符串返回对应的场景路径，并集中管理地图实例生命周期
# 通过 MapRegistry 动态查询，不写死任何 switch/map

class_name MapFactory

const DEFAULT_MAP_TYPE: String = "CLASSIC"

## 根据 MapType 字符串获取对应的场景路径
## 通过 MapRegistry 动态查询，非法 map_type 自动降级到 CLASSIC
static func get_map_scene_path(map_type: String) -> String:
	var t = map_type.to_upper().strip_edges()
	var registry = _get_registry()
	if registry:
		var path = registry.get_scene_path(t)
		if path != "":
			print("[MapFactory] Resolved scene path for '%s': %s" % [t, path])
			return path
	push_warning("[MapFactory] Unknown map_type: '%s', falling back to CLASSIC." % map_type)
	if registry:
		var fallback = registry.get_scene_path(DEFAULT_MAP_TYPE)
		if fallback != "":
			return fallback
	return "res://prefabs/map/map_classic/map_classic.tscn"

## 实例化并返回地图节点（不挂载到场景树，由调用方负责 add_child）
static func create_map(map_type: String) -> Node2D:
	var path = get_map_scene_path(map_type)
	if not ResourceLoader.exists(path):
		push_error("[MapFactory] Map scene not found: %s" % path)
		return null
	var packed: PackedScene = load(path)
	if not packed:
		push_error("[MapFactory] Failed to load map scene: %s" % path)
		return null
	var instance = packed.instantiate()
	if not instance is Node2D:
		push_error("[MapFactory] Map scene did not produce a Node2D: %s" % path)
		instance.queue_free()
		return null
	print("[MapFactory] Created map instance for '%s' from: %s" % [map_type, path])
	return instance as Node2D

## 安全卸载当前地图节点
static func unload_map(map_node: Node2D) -> void:
	if not is_instance_valid(map_node):
		return
	map_node.set_process(false)
	map_node.set_physics_process(false)
	for sig in map_node.get_signal_list():
		var connections = map_node.get_signal_connection_list(sig.name)
		for conn in connections:
			if map_node.is_connected(sig.name, conn.callable):
				map_node.disconnect(sig.name, conn.callable)
	map_node.queue_free()
	print("[MapFactory] Unloaded map: %s" % map_node.name)

## 获取所有可用的地图类型列表（从 MapRegistry 动态读取）
static func get_all_map_types() -> Array[String]:
	var registry = _get_registry()
	if registry:
		return registry.get_all_map_ids()
	return ["CLASSIC", "WINTER", "PROCEDURAL"]

## 获取人类可读的地图名称（从 MapRegistry 动态读取）
static func get_map_display_name(map_type: String) -> String:
	var registry = _get_registry()
	if registry:
		return registry.get_display_name(map_type)
	return "未知地图"

## 获取程序化地图默认参数
static func get_procedural_defaults(map_type: String) -> Dictionary:
	var registry = _get_registry()
	if registry:
		return registry.get_procedural_defaults(map_type)
	return {}

## 内部：获取 MapRegistry 单例
static func _get_registry():
	var registry = Engine.get_main_loop().root.get_node_or_null("/root/MapRegistry")
	return registry
