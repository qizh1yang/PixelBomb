# Bomberman 多人在线游戏

基于 Godot 4.x 和 Go 的多人在线炸弹人游戏，支持 HTTPS 部署和 WebSocket 实时通信。

## 🎮 功能特性

- ✅ **多人在线对战** - 支持最多 4 人同时游戏
- ✅ **房间系统** - 创建/加入房间，准备状态管理
- ✅ **角色选择** - 3 种可选角色
- ✅ **实时同步** - WebSocket 实现低延迟通信
- ✅ **HTTPS 部署** - 支持安全连接和自签名证书
- ✅ **响应式 UI** - 适配 Web 和移动端
- ✅ **中文支持** - 完整的中文界面

## 📦 技术栈

### 前端
- **Godot 4.x** - 游戏引擎
- **GDScript** - 游戏逻辑
- **HTML5** - Web 导出

### 后端
- **Go 1.23** - 服务器语言
- **Gorilla WebSocket** - WebSocket 库
- **Hub 模式** - 房间管理架构

### 部署
- **Docker** - 容器化
- **Docker Compose** - 服务编排
- **Nginx** - Web 服务器和反向代理
- **OpenSSL** - SSL 证书生成

## 🚀 快速开始

### 前置要求

- Docker 20.10+
- Docker Compose 1.29+ 或 Docker Compose V2
- OpenSSL 1.0.2+

### 一键部署

```bash
# 1. 克隆项目
git clone <repository-url>
cd map

# 2. 运行部署脚本
chmod +x setup-ssl.sh
./setup-ssl.sh <你的服务器IP>

# 示例
./setup-ssl.sh 192.168.1.100
```

### 访问游戏

部署完成后，访问：`https://<你的服务器IP>`

**注意**：首次访问需要接受浏览器的自签名证书警告。

## 📁 项目结构

```
map/
├── Server/              # Go 后端服务器
│   ├── main.go         # 入口文件
│   ├── hub.go          # 房间管理
│   ├── client.go       # 客户端连接
│   └── Dockerfile      # Docker 镜像配置
├── Network/            # 网络管理
│   └── NetworkManager.gd  # WebSocket 客户端
├── UI/                 # 用户界面
│   ├── Lobby.tscn     # 大厅场景
│   └── Room.tscn      # 房间场景
├── Players/            # 玩家相关
├── Main/               # 主场景
├── export/web/         # Godot Web 导出文件
├── nginx/              # Nginx 配置
│   └── nginx-ssl.conf # HTTPS 配置
├── docker-compose.prod.yml  # 生产环境配置
├── setup-ssl.sh        # 一键部署脚本
└── README.md           # 本文件
```

## 🔧 开发指南

### 本地开发

#### 启动后端服务器

```bash
cd Server
go run .
```

#### 在 Godot 编辑器中运行

1. 打开 Godot 编辑器
2. 导入项目（`project.godot`）
3. 按 F5 运行

### 导出 Web 版本

1. Project → Export
2. 选择 "Web" 预设
3. 导出模式：**导出选中的资源（包括依赖项）**
4. 导出到：`export/web/index.html`

### 修改服务器配置

编辑 `Server/main.go`：

```go
const (
	serverPort = ":8080"  // WebSocket 端口
)
```

## 📚 详细文档

- [HTTPS 部署指南](HTTPS_DEPLOYMENT.md) - 完整的 HTTPS 部署说明
- [部署检查清单](DEPLOYMENT_CHECKLIST.md) - 部署前后的验证步骤
- [Web 优化指南](WEB_OPTIMIZATION.md) - 文件大小优化方法
- [Docker Compose 修复](DOCKER_COMPOSE_FIX.md) - 常见问题解决

## 🐛 故障排除

### 容器启动失败

```bash
# 查看日志
docker-compose -f docker-compose.prod.yml logs

# 检查端口占用
netstat -tulpn | grep -E ':(80|443|8080)'
```

### WebSocket 连接失败

```bash
# 检查服务器日志
docker logs bomberman-server

# 测试连接
docker exec bomberman-web wget -O- http://game-server:8080/ws
```

### 证书错误

```bash
# 重新生成证书
rm -rf ssl
./setup-ssl.sh <IP>
```

## 🔒 安全建议

### 开发/测试环境
- ✅ 使用自签名证书
- ✅ 接受浏览器警告

### 生产环境
- 🔐 使用域名 + Let's Encrypt 证书
- 🔐 配置防火墙规则
- 🔐 定期更新 Docker 镜像

## 📊 性能优化

### 文件大小
- **优化前**：165 MB
- **优化后**：38 MB
- **减少**：77%

### 加载时间（100 Mbps）
- **优化前**：~13 秒
- **优化后**：~3 秒

### 优化方法
1. 使用"导出选中的资源"
2. 压缩纹理（VRAM Compressed）
3. 裁剪字体文件
4. 启用 Gzip 压缩（级别 6）
5. 配置浏览器缓存（7 天）

## 🛠️ 维护命令

```bash
# 查看日志
docker-compose -f docker-compose.prod.yml logs -f

# 重启服务
docker-compose -f docker-compose.prod.yml restart

# 停止服务
docker-compose -f docker-compose.prod.yml down

# 更新并重新部署
docker-compose -f docker-compose.prod.yml up -d --build

# 清理旧镜像
docker system prune -a
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目采用 MIT 许可证。

## 🙏 致谢

- [Godot Engine](https://godotengine.org/) - 游戏引擎
- [Gorilla WebSocket](https://github.com/gorilla/websocket) - Go WebSocket 库
- [Nginx](https://nginx.org/) - Web 服务器

## 📞 联系方式

如有问题，请提交 Issue 或联系项目维护者。

---

**祝游戏愉快！** 🎮🎉
