# 文件清理说明

## 🗑️ 可以删除的文件

以下文件已被新版本替代或不再需要，可以安全删除：

### 1. 旧部署脚本
- ❌ `deploy.sh` - 已被 `setup-ssl.sh` 替代（仅支持 HTTP）

### 2. 开发环境配置
- ❌ `docker-compose.yml` - 开发版本，生产环境使用 `docker-compose.prod.yml`
- ❌ `nginx/nginx.conf` - HTTP 配置，生产环境使用 `nginx/nginx-ssl.conf`

### 3. Windows 编译文件
- ❌ `Server/bomberman-server.exe` - Windows 二进制文件，Docker 中不需要

### 4. 冗余文档（export/ 目录）
- ❌ `export/BYPASS_SOLUTION.md` - 已合并到主文档
- ❌ `export/GODOT_EXPORT_GUIDE.md` - 已合并到主文档
- ❌ `export/HTTP_DEPLOYMENT_SOLUTION.md` - 已被 HTTPS 方案替代
- ❌ `export/README.md` - 内容已过时
- ❌ `export/SECURE_CONTEXT_FIX.md` - 已合并到主文档

### 5. 临时文档
- ❌ `Server/GO_PROXY_FIX.md` - 已合并到 `DEPLOYMENT_CHECKLIST.md`

## ✅ 保留的文件

以下文件是生产环境必需的：

### 核心配置
- ✅ `setup-ssl.sh` - 一键部署脚本
- ✅ `docker-compose.prod.yml` - 生产环境配置
- ✅ `nginx/nginx-ssl.conf` - HTTPS Nginx 配置

### 文档
- ✅ `README.md` - 主文档
- ✅ `HTTPS_DEPLOYMENT.md` - HTTPS 部署指南
- ✅ `DEPLOYMENT_CHECKLIST.md` - 部署检查清单
- ✅ `WEB_OPTIMIZATION.md` - 优化指南
- ✅ `DOCKER_COMPOSE_FIX.md` - 故障排除

### 游戏资源
- ✅ `Boob/` - 游戏资源（如需要）
- ✅ `Game_assets/` - 游戏资源（如需要）

## 🔧 清理命令

### 自动清理（推荐）

```bash
# 在项目根目录运行
cd /path/to/map

# 删除旧部署文件
rm -f deploy.sh
rm -f docker-compose.yml
rm -f nginx/nginx.conf

# 删除 Windows 二进制
rm -f Server/bomberman-server.exe

# 删除冗余文档
rm -f export/BYPASS_SOLUTION.md
rm -f export/GODOT_EXPORT_GUIDE.md
rm -f export/HTTP_DEPLOYMENT_SOLUTION.md
rm -f export/README.md
rm -f export/SECURE_CONTEXT_FIX.md
rm -f Server/GO_PROXY_FIX.md

echo "清理完成！"
```

### 手动清理

逐个删除上述文件，或使用文件管理器删除。

## 📦 清理后的项目结构

```
map/
├── Server/              # Go 后端
│   ├── main.go
│   ├── hub.go
│   ├── client.go
│   ├── go.mod
│   ├── go.sum
│   └── Dockerfile
├── Network/             # 网络管理
├── UI/                  # 用户界面
├── Players/             # 玩家
├── Main/                # 主场景
├── Scenes/              # 场景
├── export/web/          # Web 导出（仅保留 web 目录）
├── nginx/
│   └── nginx-ssl.conf   # 仅保留 SSL 配置
├── docker-compose.prod.yml  # 仅保留生产配置
├── setup-ssl.sh         # 部署脚本
├── README.md            # 主文档
├── HTTPS_DEPLOYMENT.md
├── DEPLOYMENT_CHECKLIST.md
├── WEB_OPTIMIZATION.md
└── DOCKER_COMPOSE_FIX.md
```

## ⚠️ 注意事项

1. **备份**：清理前建议先备份整个项目
2. **确认**：确保你不需要开发环境配置（`docker-compose.yml`）
3. **游戏资源**：`Boob/` 和 `Game_assets/` 根据实际使用情况决定是否保留

## ✅ 清理后的好处

- 🎯 **项目更清晰** - 只保留必要文件
- 📦 **体积更小** - 减少不必要的文件
- 🚀 **部署更快** - 上传文件更少
- 📚 **文档集中** - 避免信息分散
