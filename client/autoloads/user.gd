# user.gd - 身份认证会话单例
# 专职维护玩家登录凭证状态，为全局网络监视器与异常弹窗提供身份拦截判定
extends Node

# 当前登录成功的用户会话数据
var current_user: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## 判定玩家当前是否已通过服务器认证登录成功
func is_authenticated() -> bool:
	return not current_user.is_empty()

## 设置成功认证的用户个人数据
func set_authenticated_user(user_data: Dictionary) -> void:
	current_user = user_data
	print("[USER] Session authenticated successfully for user: ", current_user.get("name", "Unknown"))

## 注销或断开时清除会话凭据
func clear() -> void:
	if not current_user.is_empty():
		print("[USER] Session cleared.")
	current_user.clear()
