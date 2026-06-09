# 玩家控制逻辑模块
# 处理移动、放置炸弹及属性天花板逻辑
# 创建时间：2026-05-08

extends CharacterBody2D

class_name PlayerController

# ── 导出变量 ──
@export var playerID: String = "1"
@export var tileSize: int = 16
@export var bodyRadius: float = 6.0
@export var bombScene: PackedScene

# ── 属性天花板（局内道具可提升的最大值） ──
@export var maxBombsCap: int = 2
@export var explosionRadiusCap: int = 1
@export var radiusUpCap: int = 0
@export var radiusDownCap: int = 0
@export var radiusLeftCap: int = 0
@export var radiusRightCap: int = 0
@export var speedCap: float = 95.0
@export var maxShieldsCap: int = 1

# ── 当前能力值（基础属性） ──
var currentMaxBombs: int = 1       # 初始炸弹数量：1
var currentRadius: int = 1         # 初始炸弹威力：1
var currentSpeed: float = 75.0      # 基础移动速度：75
var currentShields: int = 0        # 初始护盾数量：0
var _shieldHalo: Sprite2D = null  # 护盾光圈视觉节点

# ── 局内道具常量 ──
const POWERUP_MAX_BOMBS: int = 5
const POWERUP_MAX_RADIUS: int = 8
const POWERUP_SPEED: float = 200.0  # 移动间隔0.15秒对应的速度

# ── 史诗护盾状态 ──
@export var hasPersistentShield: bool = false
var isPersistentShieldReady: bool = true
var persistentShieldCooldown: float = 30.0
var persistentShieldTimer: float = 0.0

# ── 状态变量 ──
var activeBombs: int = 0
var isDead: bool = false
var currentDirection: String = "down"
var velocityInput: Vector2 = Vector2.ZERO
var isLocal: bool = true
var player_name: String = "Player"
var network_id: String = ""
var char_index: int = 0
var target_pos: Vector2 = Vector2.ZERO
var remote_state: String = "idle"
var remote_direction: String = "down"
var last_remote_tick: int = 0

# ── 伤害保护 ──
var isInvulnerable: bool = false
var invulnerableTimer: float = 0.0
const INVULNERABLE_DURATION: float = 0.5

# ── 节点引用 ──
@onready var animSprite: AnimatedSprite2D = $AnimatedSprite2D
var evacBar: ProgressBar

# ── 撤离状态 ──
var isEvacuating: bool = false
var evacTimer: float = 0.0
const EVAC_TIME: float = 2.0

func _ready() -> void:
	add_to_group("Player")
	# 核心修复：不能对非本地玩家设置 set_physics_process(false)，因为会阻止非本地玩家在 _physics_process 中运行位置插值同步(lerp)逻辑
	_setupEvacBar()
	_setupShieldHalo()

	# 战术物理加固：设置玩家之间物理碰撞例外，使其像幽灵般穿透，且不影响道具检测及与地图、炸弹的正常碰撞
	var players = get_tree().get_nodes_in_group("Player")
	for p in players:
		if p != self and p is PhysicsBody2D:
			add_collision_exception_with(p)
			p.add_collision_exception_with(self)

func _setupEvacBar() -> void:
	# 使用标准 ProgressBar，无需贴图即可显示
	evacBar = ProgressBar.new()
	add_child(evacBar)
	evacBar.hide()
	evacBar.max_value = EVAC_TIME
	evacBar.show_percentage = false # 隐藏百分比文字
	
	# 设置尺寸与位置（居中于玩家头顶）
	evacBar.custom_minimum_size = Vector2(32, 6)
	evacBar.size = evacBar.custom_minimum_size
	evacBar.position = Vector2(-16, -24)
	evacBar.z_index = 5
	
	# 设置样式 (亮绿色)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color.GREEN
	evacBar.add_theme_stylebox_override("fill", sb)
	
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	evacBar.add_theme_stylebox_override("background", bg)

# 创建护盾光圈视觉效果
func _setupShieldHalo() -> void:
	# 创建一个简单的圆形光圈图像
	var halo_size: int = 24
	var img: Image = Image.create(halo_size, halo_size, false, Image.FORMAT_RGBA8)
	var center := Vector2(halo_size / 2.0, halo_size / 2.0)
	var outer_radius: float = halo_size / 2.0
	var inner_radius: float = outer_radius - 3.0
	
	for x in range(halo_size):
		for y in range(halo_size):
			var dist: float = Vector2(x, y).distance_to(center)
			if dist >= inner_radius and dist <= outer_radius:
				var alpha: float = 1.0 - abs(dist - (inner_radius + outer_radius) / 2.0) / 1.5
				alpha = clampf(alpha, 0.0, 0.7)
				img.set_pixel(x, y, Color(0.5, 0.9, 1.0, alpha))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	
	_shieldHalo = Sprite2D.new()
	_shieldHalo.texture = ImageTexture.create_from_image(img)
	_shieldHalo.z_index = 10
	_shieldHalo.visible = false
	add_child(_shieldHalo)

func _physics_process(delta: float) -> void:
	if isDead: return
	_updateShieldCooldown(delta)
	_updateShieldHalo()
	_updateInvulnerability(delta)
	
	if isLocal:
		_handleMovement(delta)
		if isEvacuating:
			evacTimer += delta
			evacBar.value = evacTimer
			if evacTimer >= EVAC_TIME:
				_completeEvacuation()
	else:
		_handleRemoteMovement(delta)
		_syncRemoteState()

func _handleRemoteMovement(delta: float) -> void:
	var diff = global_position.distance_to(target_pos)
	if diff > 48.0:
		global_position = target_pos
	else:
		global_position = global_position.lerp(target_pos, delta * 12.0)

func _syncRemoteState() -> void:
	if isDead: return
	
	if remote_state == "dead":
		die()
		return
		
	if remote_state == "walk":
		if animSprite:
			animSprite.play("walk_" + remote_direction)
	else:
		if animSprite:
			animSprite.play("idle_" + remote_direction)

# 处理史诗护盾冷却计时
# 处理史诗护盾冷却计时
func _updateShieldCooldown(delta: float) -> void:
	if hasPersistentShield and not isPersistentShieldReady:
		persistentShieldTimer += delta
		if persistentShieldTimer >= persistentShieldCooldown:
			isPersistentShieldReady = true
			persistentShieldTimer = 0.0
			print("[SHIELD] Persistent shield REGENERATED!")

func _updateInvulnerability(delta: float) -> void:
	if isInvulnerable:
		invulnerableTimer -= delta
		# 闪烁效果
		if animSprite:
			animSprite.modulate.a = 0.5 if Engine.get_frames_drawn() % 10 < 5 else 1.0
		
		if invulnerableTimer <= 0:
			isInvulnerable = false
			if animSprite:
				animSprite.modulate.a = 1.0

# 处理移动输入与物理推进
func _handleMovement(_delta: float) -> void:
	if not isLocal: return
	
	# 获取移动输入
	velocityInput = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# 更新当前朝向（用于放炸弹后的推开逻辑）
	if velocityInput.length() > 0:
		if abs(velocityInput.x) > abs(velocityInput.y):
			currentDirection = "left" if velocityInput.x < 0 else "right"
		else:
			currentDirection = "up" if velocityInput.y < 0 else "down"
		
		# 播放动画
		if animSprite:
			animSprite.play("walk_" + currentDirection)
	else:
		if animSprite:
			animSprite.play("idle_" + currentDirection)
	
	# 核心过滤：只有本地玩家处理输入
	if not isLocal: return
	
	velocity = velocityInput * currentSpeed
	move_and_slide()
	
	# 放炸弹输入 (空格键)
	if Input.is_action_just_pressed("ui_accept"):
		placeBomb()
		
	# 撤离输入 (E 键)
	if Input.is_key_pressed(KEY_E):
		_tryEvacuate()
	else:
		if isEvacuating:
			_cancelEvacuate()

func _tryEvacuate() -> void:
	# 1. 速度检查
	if velocity.length() > 20.0:
		if isEvacuating: _cancelEvacuate()
		return
		
	# 2. 区域检查（优先支持动态撤离点，如果不存在则回退至地图正中心 3x3）
	var can_evac = false
	var gm = get_node_or_null("/root/GameMode")
	if gm and gm.wall_layer:
		var player_cell = gm.wall_layer.local_to_map(gm.wall_layer.to_local(global_position))
		
		var ext_cell = Vector2i(-999, -999)
		if "extraction_point" in gm.wall_layer:
			ext_cell = gm.wall_layer.extraction_point
			
		if ext_cell != Vector2i(-999, -999):
			# 校验是否站在撤离点 3x3 (即 Chebyshev 距离 <= 1 范围内)
			if abs(player_cell.x - ext_cell.x) <= 1 and abs(player_cell.y - ext_cell.y) <= 1:
				can_evac = true
		else:
			# 经典回退保底（地图中心 3x3 区域）
			var used_rect = gm.wall_layer.get_used_rect()
			var center = used_rect.position + (used_rect.size / 2)
			if abs(player_cell.x - center.x) <= 1 and abs(player_cell.y - center.y) <= 1:
				can_evac = true
				
	if can_evac:
		if not isEvacuating:
			isEvacuating = true
			evacTimer = 0.0
			evacBar.show()
			print("[PLAYER] 正在撤离...")
	else:
		if isEvacuating:
			_cancelEvacuate()


func _cancelEvacuate() -> void:
	isEvacuating = false
	evacTimer = 0.0
	evacBar.hide()

var isEvacuated: bool = false # 是否已成功撤离

func _completeEvacuation() -> void:
	isEvacuating = false
	isEvacuated = true
	evacBar.hide()
	hide() # 隐藏角色代表撤离成功
	
	if TutorialManager:
		TutorialManager.hide_tutorial("evac_zone")
	
	var net = get_node_or_null("/root/NetworkManager")
	if net:
		net.request("Room.Evacuate", {})
	
	print("[GAME] 撤离请求已发送！")
	
	# 如果是离线/测试模式，直接在本地触发结算信号
	var gm = get_node_or_null("/root/GameMode")
	if gm and gm.is_offline_mode:
		print("[GAME] 检测到离线模式，正在弹出本地结算面板...")
		await get_tree().create_timer(1.0).timeout
		gm.gameOverReceived.emit(true)

# 受到爆炸伤害，优先扣护盾，无护盾则死亡
func takeDamage() -> void:
	if isDead or isInvulnerable: return

	# 检查史诗护盾（持久护盾）
	if hasPersistentShield and isPersistentShieldReady:
		isPersistentShieldReady = false
		persistentShieldTimer = 0.0
		isInvulnerable = true
		invulnerableTimer = INVULNERABLE_DURATION
		print("[SHIELD] Persistent shield blocked damage!")
		return

	# 检查消耗性护盾
	if currentShields > 0:
		currentShields -= 1
		isInvulnerable = true
		invulnerableTimer = INVULNERABLE_DURATION
		print("[SHIELD] Consumable shield blocked damage!")
		return

	die()

# 执行死亡逻辑，播放死亡动画
func die() -> void:
	if isDead: return
	isDead = true
	print("[GAME] Player %s DIED!" % playerID)
	
	if animSprite:
		animSprite.play("dead")
	

	
	var gm = get_node_or_null("/root/GameMode")
	# 触发结算逻辑
	if isLocal and gm:
		# 延迟一秒弹出结算，让玩家看清死亡过程
		await get_tree().create_timer(1.0).timeout
		if gm.is_offline_mode:
			gm.gameOverReceived.emit(false)
		else:
			# 在联网模式下，死亡也是一种结算触发点（仅针对本地玩家）
			if gm.has_method("_finalizeMatchSettlement"):
				gm.call("_finalizeMatchSettlement", false)

# 检查是否满足放炸弹条件
func canSpawnBomb() -> bool:
	return activeBombs < currentMaxBombs and not isDead

# 放置炸弹并广播网络消息
func placeBomb() -> void:
	if not canSpawnBomb(): return

	var wlayer: TileMapLayer = get_tree().get_first_node_in_group("WallLayer")
	if wlayer == null: return

	var targetCell: Vector2i = wlayer.local_to_map(wlayer.to_local(global_position))

	if isLocal:
		doSpawnBomb(targetCell, currentRadius)
		_pushBackPlayer()

		var net = get_node_or_null("/root/NetworkManager")
		var gm = get_node_or_null("/root/GameMode")
		if net and gm and not gm.is_offline_mode:
			net.request("Room.PlaceBomb", {
				"x": targetCell.x,
				"y": targetCell.y
			})

# 获取四方向实际爆炸距离（受限于各方向的上限）
func get_actual_explosion_ranges() -> Dictionary:
	return {
		"up": mini(currentRadius, explosionRadiusCap + radiusUpCap),
		"down": mini(currentRadius, explosionRadiusCap + radiusDownCap),
		"left": mini(currentRadius, explosionRadiusCap + radiusLeftCap),
		"right": mini(currentRadius, explosionRadiusCap + radiusRightCap)
	}

# 实例化炸弹并挂载到场景
# cell：目标地图格坐标；radius：当前爆炸威力等级
func doSpawnBomb(cell: Vector2i, radius: int) -> void:
	if bombScene == null: return
	var wlayer: TileMapLayer = get_tree().get_first_node_in_group("WallLayer")
	if wlayer == null: return

	# 去重：检查该格子是否已存在炸弹，防止联机广播导致重复创建
	for existing in get_tree().get_nodes_in_group("Bomb"):
		if is_instance_valid(existing) and existing is Bomb:
			var existing_cell = wlayer.local_to_map(wlayer.to_local(existing.global_position))
			if existing_cell == cell:
				print("[BOMB] Duplicate bomb at %s prevented" % str(cell))
				return
	var bomb: Node = bombScene.instantiate()
	wlayer.get_parent().add_child(bomb)
	bomb.wallLayer = wlayer
	
	# 核心逻辑：炸弹的最终威力受限于当前威力和每个方向的上限
	# explosionRadiusCap 是全局基础上限（通常为 1 + 全局加成）
	bomb.explosionLength = radius
	
	var actual_ranges = get_actual_explosion_ranges()
	bomb.limitUp = actual_ranges["up"]
	bomb.limitDown = actual_ranges["down"]
	bomb.limitLeft = actual_ranges["left"]
	bomb.limitRight = actual_ranges["right"]
	
	bomb.global_position = wlayer.to_global(wlayer.map_to_local(cell))
	activeBombs += 1
	bomb.tree_exited.connect(func(): activeBombs -= 1)

# 放炸弹后将玩家微推离炸弹位置
func _pushBackPlayer() -> void:
	var backDir: Vector2 = Vector2.ZERO
	match currentDirection:
		"up": backDir = Vector2.DOWN
		"down": backDir = Vector2.UP
		"left": backDir = Vector2.RIGHT
		"right": backDir = Vector2.LEFT
	global_position += backDir * (tileSize * 0.5)

# 设置玩家显示名称
# newName：玩家名称
func setPlayerName(newName: String) -> void:
	player_name = newName

# 同步数值到服务器
func sync_stats_to_server() -> void:
	if not isLocal: return
	var net = get_node_or_null("/root/NetworkManager")
	var gm = get_node_or_null("/root/GameMode")
	if net and gm and not gm.is_offline_mode:
		net.request("Room.UpdateStats", {
			"bomb_cap": currentMaxBombs,
			"radius": currentRadius,
			"speed": currentSpeed,
			"shields": currentShields
		})

# ══════════════════════════════════════════════════════
#  局内道具系统 (受局外物品上限限制)
# ══════════════════════════════════════════════════════

# 应用局内增益道具
# type：道具类型（0=BOMB_UP, 1=POWER_UP, 2=SPEED_UP, 3=SHIELD）
# 返回：是否成功应用（即数值是否真正增加）
func apply_powerup(type: int) -> bool:
	match type:
		0: # BOMB_UP - 增加当前炸弹携带量（最高不超过 maxBombsCap）
			if currentMaxBombs >= maxBombsCap:
				print("[属性] 炸弹数量已达上限: %d，拾取但不增加" % maxBombsCap)
				return false
			currentMaxBombs = min(currentMaxBombs + 1, maxBombsCap)
			print("[属性] 炸弹携带 +1! 当前: %d / 上限: %d" % [currentMaxBombs, maxBombsCap])
			sync_stats_to_server()
			return true
		
		1: # POWER_UP - 增加当前爆炸威力（最高不超过所有方向中的最大上限）
			var max_cap = max(
				explosionRadiusCap + radiusUpCap,
				explosionRadiusCap + radiusDownCap,
				explosionRadiusCap + radiusLeftCap,
				explosionRadiusCap + radiusRightCap
			)
			
			if currentRadius >= max_cap:
				print("[属性] 爆炸威力已达全方向最高上限: %d，拾取但不增加" % max_cap)
				return false
			currentRadius += 1
			print("[属性] 爆炸威力提升! 当前等级: %d" % currentRadius)
			sync_stats_to_server()
			return true
		
		2: # SPEED_UP - 增加当前移动速度（最高不超过 speedCap）
			if currentSpeed >= speedCap:
				print("[属性] 移动速度已达上限: %.1f，拾取但不增加" % speedCap)
				return false
			currentSpeed = min(currentSpeed + 5.0, speedCap)
			print("[属性] 移动速度 +5! 当前: %.1f / 上限: %.1f" % [currentSpeed, speedCap])
			sync_stats_to_server()
			return true
		
		3: # SHIELD - 增加当前消耗性护盾（最高不超过 maxShieldsCap）
			if currentShields >= maxShieldsCap:
				print("[属性] 护盾数量已达上限: %d，拾取但不增加" % maxShieldsCap)
				return false
			currentShields = min(currentShields + 1, maxShieldsCap)
			print("[属性] 护盾 +1! 当前: %d / 上限: %d" % [currentShields, maxShieldsCap])
			sync_stats_to_server()
			return true
	
	return false

# 更新护盾光圈可见性
func _updateShieldHalo() -> void:
	if _shieldHalo:
		var should_show: bool = currentShields > 0 or (hasPersistentShield and isPersistentShieldReady)
		_shieldHalo.visible = should_show
		
		# 旋转光圈产生动态效果
		if should_show:
			_shieldHalo.rotation += 0.02

func apply_stats(stats: Dictionary) -> void:
	# Caps 仅当服务端明确发送时才覆盖（StartGame 时广播完整属性，UpdateStats 只广播 Current 值）
	if stats.has("bomb_cap"): maxBombsCap = int(stats.get("bomb_cap", 2))
	if stats.has("radius_cap"): explosionRadiusCap = int(stats.get("radius_cap", 1))
	if stats.has("speed_cap"): speedCap = float(stats.get("speed_cap", 95.0))
	if stats.has("shield_cap"): maxShieldsCap = int(stats.get("shield_cap", 1))
	if stats.has("has_persistent_shield"):
		hasPersistentShield = bool(stats.get("has_persistent_shield", false))
	
	# 如果是本地玩家，我们需要加上本地背包中已装备物品的属性上限加成
	if isLocal:
		var backpack_node = get_tree().get_first_node_in_group("Backpack")
		if is_instance_valid(backpack_node) and backpack_node.has_method("get_all_item_resources"):
			var items = backpack_node.get_all_item_resources()
			var bomb_boost = 0
			var radius_boost = 0
			var shield_boost = 0
			var speed_boost = 0.0
			var epic_shield = false
			var r_up = 0
			var r_down = 0
			var r_left = 0
			var r_right = 0
			for res in items:
				if res:
					bomb_boost += res.bomb_cap_boost
					radius_boost += res.radius_cap_boost
					shield_boost += res.shield_cap_boost
					speed_boost += res.speed_cap_boost
					r_up += res.radius_up_boost
					r_down += res.radius_down_boost
					r_left += res.radius_left_boost
					r_right += res.radius_right_boost
					if res.has_persistent_shield:
						epic_shield = true
			
			maxBombsCap += bomb_boost
			explosionRadiusCap += radius_boost
			radiusUpCap = r_up
			radiusDownCap = r_down
			radiusLeftCap = r_left
			radiusRightCap = r_right
			maxShieldsCap += shield_boost
			speedCap += speed_boost
			if epic_shield:
				hasPersistentShield = true
	
	# 如果广播中含有 current 字段，则优先使用服务端下发的局内权威当前属性值进行强对齐，实现多端完全同步
	if stats.has("bomb_current"):
		currentMaxBombs = int(stats.get("bomb_current", currentMaxBombs))
	else:
		currentMaxBombs = min(currentMaxBombs, maxBombsCap)
		
	if stats.has("radius_current"):
		currentRadius = int(stats.get("radius_current", currentRadius))
	else:
		currentRadius = min(currentRadius, explosionRadiusCap)
		
	if stats.has("speed_current"):
		currentSpeed = float(stats.get("speed_current", currentSpeed))
	else:
		currentSpeed = min(currentSpeed, speedCap)
		
	if stats.has("shield_current"):
		currentShields = int(stats.get("shield_current", currentShields))
	else:
		currentShields = min(currentShields, maxShieldsCap)
	
	# 更新护盾光圈可见性
	_updateShieldHalo()
	
	print("[STATS] Authoritative stats applied for player: ", playerID, " | Stats: ", stats)

func lose_shield() -> void:
	if currentShields > 0:
		currentShields -= 1
	elif hasPersistentShield and isPersistentShieldReady:
		isPersistentShieldReady = false
		persistentShieldTimer = 0.0
		
	isInvulnerable = true
	invulnerableTimer = INVULNERABLE_DURATION
	_updateShieldHalo()
	print("[SHIELD] Server authoritative: Shield broken for player: ", playerID)

func play_predictive_hit_feedback() -> void:
	# 屏幕震动
	var gm = get_node_or_null("/root/GameMode")
	if gm and gm.has_method("shake_camera"):
		gm.shake_camera(0.2, 5.0)
	
	# 受击闪红白效果
	if animSprite:
		var tween = create_tween()
		tween.tween_property(animSprite, "modulate", Color(5, 5, 5, 1), 0.05) # 闪白
		tween.tween_property(animSprite, "modulate", Color(1, 0, 0, 1), 0.05) # 闪红
		tween.tween_property(animSprite, "modulate", Color(1, 1, 1, 1), 0.1)  # 恢复
