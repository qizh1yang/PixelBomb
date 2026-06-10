# 登录与注册场景逻辑
extends Control

# ── 场景节点（login.tscn）──
@onready var usernameInput: LineEdit = %UsernameInput
@onready var passwordInput: LineEdit = %PasswordInput
@onready var errorLabel: Label = %ErrorLabel
@onready var loginBtn: TextureButton = %LoginBtn
@onready var regBtn: Button = %RegBtn
@onready var guestBtn: Button = %GuestBtn
@onready var loadingOverlay: Control = %LoadingOverlay

const ACCOUNTS_FILE = "user://accounts.json"
var _local_accounts: Dictionary = {}
var _popup: Control = null

# ══════════════════════════════════════════════════════

func _ready() -> void:
	errorLabel.text = ""
	loadingOverlay.hide()
	_load_local_accounts()
	_autofill_last_account()

	# loginBtn.pressed 已在 login.tscn 中连接，此处不需要重复
	regBtn.pressed.connect(_on_register_btn_pressed)
	guestBtn.pressed.connect(_on_guest_btn_pressed)

	# 按钮样式：白色文字，hover 变橙色
	_style_text_btn(regBtn, Color("#B0B0C0"), Color("#F5A623"))
	_style_text_btn(guestBtn, Color("#B0B0C0"), Color("#F5A623"))

	var net = NetworkManager
	net.connected_to_server.connect(_on_connection_succeeded)
	net.connection_closed.connect(_on_connection_failed)
	net.message_received.connect(_on_message_received)
	net.kicked.connect(_on_kicked)

# ══════════════════════════════════════════════════════
#  按钮工具
# ══════════════════════════════════════════════════════

func _style_text_btn(btn: Button, normal_color: Color, hover_color: Color) -> void:
	btn.flat = true
	btn.add_theme_color_override("font_color", normal_color)
	btn.add_theme_color_override("font_hover_color", hover_color)
	btn.add_theme_color_override("font_pressed_color", hover_color.darkened(0.2))
	btn.add_theme_font_size_override("font_size", 14)

# ══════════════════════════════════════════════════════
#  本地账号
# ══════════════════════════════════════════════════════

func _load_local_accounts() -> void:
	if FileAccess.file_exists(ACCOUNTS_FILE):
		var f = FileAccess.open(ACCOUNTS_FILE, FileAccess.READ)
		var json = JSON.parse_string(f.get_as_text())
		if json is Dictionary: _local_accounts = json

func _save_local_account(uname: String, pwd: String) -> void:
	_local_accounts[uname] = pwd
	var f = FileAccess.open(ACCOUNTS_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(_local_accounts))

func _autofill_last_account() -> void:
	if not _local_accounts.is_empty():
		var last = _local_accounts.keys()[-1]
		usernameInput.text = last
		passwordInput.text = _local_accounts[last]

# ══════════════════════════════════════════════════════
#  登录
# ══════════════════════════════════════════════════════

func _on_login_pressed() -> void:
	var uname = usernameInput.text.strip_edges()
	var pwd = passwordInput.text.strip_edges()
	if uname == "" or pwd == "":
		_show_error("用户名和密码不能为空"); return

	_save_local_account(uname, pwd)
	_show_loading(true)
	NetworkManager.player_name = uname
	if not NetworkManager.is_connected_to_host:
		NetworkManager.connect_to_server()
		if not await _wait_for_connection(10.0): return
	NetworkManager.auth(uname, pwd)

# ══════════════════════════════════════════════════════
#  注册弹窗
# ══════════════════════════════════════════════════════

func _on_register_btn_pressed() -> void:
	_close_popup()
	_popup = _make_register_popup()
	add_child(_popup)

func _make_register_popup() -> Control:
	var ctrl = Control.new()
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)

	var mask = ColorRect.new()
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.color = Color(0, 0, 0, 0.5)
	ctrl.add_child(mask)
	mask.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _close_popup())

	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.size = Vector2(340, 320)
	ctrl.add_child(panel)

	var title = Label.new()
	title.text = "注册冒险者账号"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("#F5A623"))
	title.position = Vector2(20, 14)
	title.size = Vector2(300, 28)
	panel.add_child(title)

	var user_in = LineEdit.new()
	user_in.placeholder_text = "用户名（至少3个字符）"
	user_in.position = Vector2(20, 52)
	user_in.size = Vector2(300, 36)
	panel.add_child(user_in)

	var pass_in = LineEdit.new()
	pass_in.placeholder_text = "密码（至少6个字符）"
	pass_in.secret = true
	pass_in.position = Vector2(20, 96)
	pass_in.size = Vector2(300, 36)
	panel.add_child(pass_in)

	var conf_in = LineEdit.new()
	conf_in.placeholder_text = "确认密码"
	conf_in.secret = true
	conf_in.position = Vector2(20, 140)
	conf_in.size = Vector2(300, 36)
	panel.add_child(conf_in)

	var err_lbl = Label.new()
	err_lbl.position = Vector2(20, 184)
	err_lbl.size = Vector2(300, 20)
	err_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	err_lbl.add_theme_color_override("font_color", Color("#E83A3A"))
	panel.add_child(err_lbl)

	var submit = Button.new()
	submit.text = "注 册"
	submit.position = Vector2(20, 212)
	submit.size = Vector2(300, 36)
	panel.add_child(submit)

	var cancel = Button.new()
	cancel.text = "取 消"
	cancel.position = Vector2(20, 256)
	cancel.size = Vector2(300, 36)
	panel.add_child(cancel)

	submit.pressed.connect(func():
		var u = user_in.text.strip_edges()
		var p = pass_in.text
		var p2 = conf_in.text
		if u.length() < 3: err_lbl.text = "用户名至少需要3个字符"; return
		if p.length() < 6: err_lbl.text = "密码至少需要6个字符"; return
		if p != p2: err_lbl.text = "两次密码输入不一致"; return

		submit.disabled = true; submit.text = "注册中..."; err_lbl.text = ""
		if not NetworkManager.is_connected_to_host:
			NetworkManager.connect_to_server()
			if not await _wait_for_connection(10.0):
				err_lbl.text = "连接服务器超时"
				submit.disabled = false; submit.text = "注 册"
				return

		var state = {"done": false, "ok": false, "msg": ""}
		var on_msg = func(route, json):
			if route == "User.Register":
				state["done"] = true
				state["ok"] = (json.get("type") == "REGISTER_SUCCESS")
				if not state["ok"]: state["msg"] = json.get("message", "注册失败")

		NetworkManager.message_received.connect(on_msg)
		NetworkManager.request("User.Register", {"username": u, "password": p})
		var elapsed: float = 0.0
		while not state["done"] and elapsed < 8.0:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
		NetworkManager.message_received.disconnect(on_msg)

		if state["ok"]:
			_close_popup()
			usernameInput.text = u; passwordInput.text = p
			_show_error("注册成功，请点击登录")
			errorLabel.modulate = Color("#4ADE80")
		else:
			err_lbl.text = state["msg"] if state["msg"] != "" else "请求超时"
			submit.disabled = false; submit.text = "注 册"
	)

	cancel.pressed.connect(_close_popup)
	return ctrl

# ══════════════════════════════════════════════════════
#  游客弹窗
# ══════════════════════════════════════════════════════

func _on_guest_btn_pressed() -> void:
	_close_popup()
	_popup = _make_guest_popup()
	add_child(_popup)

func _make_guest_popup() -> Control:
	var ctrl = Control.new()
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)

	var mask = ColorRect.new()
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.color = Color(0, 0, 0, 0.5)
	ctrl.add_child(mask)
	mask.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _close_popup())

	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.size = Vector2(300, 180)
	ctrl.add_child(panel)

	var title = Label.new()
	title.text = "游客模式"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("#F5A623"))
	title.position = Vector2(20, 14)
	title.size = Vector2(260, 28)
	panel.add_child(title)

	var desc = Label.new()
	desc.text = "将以临时冒险者身份进入游戏。\n游客账号绑定当前设备，\n换设备后无法找回。"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_color_override("font_color", Color("#8B9DC3"))
	desc.position = Vector2(20, 46)
	desc.size = Vector2(260, 54)
	panel.add_child(desc)

	var confirm = Button.new()
	confirm.text = "游客进入"
	confirm.position = Vector2(20, 120)
	confirm.size = Vector2(124, 36)
	panel.add_child(confirm)

	var cancel = Button.new()
	cancel.text = "取消"
	cancel.position = Vector2(156, 120)
	cancel.size = Vector2(124, 36)
	panel.add_child(cancel)

	confirm.pressed.connect(func():
		_close_popup()
		_show_loading(true)
		if not NetworkManager.is_connected_to_host:
			NetworkManager.connect_to_server()
			if not await _wait_for_connection(10.0): return
		NetworkManager.guest_login()
	)
	cancel.pressed.connect(_close_popup)
	return ctrl

# ══════════════════════════════════════════════════════
#  通用
# ══════════════════════════════════════════════════════

func _close_popup() -> void:
	if _popup: _popup.queue_free()
	_popup = null

func _on_connection_succeeded() -> void: pass

func _on_connection_failed() -> void:
	_show_loading(false)
	_show_error("无法连接到事务所服务器")

func _on_message_received(route: String, json: Dictionary) -> void:
	match route:
		"User.Auth":
			_show_loading(false)
			if json.get("type") == "ERROR":
				_show_error(json.get("message", "登录失败"))
			else:
				UIManager.change_scene("lobby")
		"User.GuestLogin":
			_show_loading(false)
			if json.get("type") == "ERROR":
				_show_error(json.get("message", "游客登录失败"))
			else:
				UIManager.change_scene("lobby")

func _on_kicked(reason: String, message: String) -> void:
	_show_loading(false)
	_show_error(message)

func _show_error(msg: String) -> void:
	errorLabel.text = msg
	errorLabel.modulate = Color("#E83A3A")
	var t = create_tween()
	t.tween_property(errorLabel, "position:x", errorLabel.position.x + 5, 0.05)
	t.tween_property(errorLabel, "position:x", errorLabel.position.x - 5, 0.1)
	t.tween_property(errorLabel, "position:x", errorLabel.position.x, 0.05)

func _show_loading(active: bool) -> void:
	loadingOverlay.visible = active
	loginBtn.disabled = active

func _wait_for_connection(timeout: float) -> bool:
	if NetworkManager.is_connected_to_host: return true
	var timer = get_tree().create_timer(timeout)
	var ok = [false]; var to = [false]
	NetworkManager.connected_to_server.connect(func(): ok[0] = true, CONNECT_ONE_SHOT)
	timer.timeout.connect(func(): to[0] = true, CONNECT_ONE_SHOT)
	while not ok[0] and not to[0]:
		await get_tree().process_frame
	if to[0] and not ok[0]:
		NetworkManager.disconnect_from_server()
		_show_error("连接服务器超时 (10秒)")
		_show_loading(false)
		return false
	return true
