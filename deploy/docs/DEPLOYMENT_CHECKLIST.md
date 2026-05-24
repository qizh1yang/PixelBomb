# 一键部署检查清单

## ✅ 部署前检查

### 1. 必需文件清单

```
map/
├── Server/
│   ├── Dockerfile          ✅ 包含 GOPROXY 配置
│   ├── go.mod
│   ├── go.sum
│   ├── main.go
│   ├── hub.go
│   └── client.go
├── export/web/             ✅ Godot 导出文件
│   ├── index.html
│   ├── index.js
│   ├── index.wasm
│   └── index.pck           ✅ 已优化（1.7MB）
├── nginx/
│   └── nginx-ssl.conf      ✅ WebSocket 代理配置正确
├── Network/
│   └── NetworkManager.gd   ✅ 支持 WSS
├── docker-compose.prod.yml ✅ 生产环境配置
└── setup-ssl.sh            ✅ 一键部署脚本
```

### 2. 配置一致性检查

#### ✅ Docker Compose 服务名
- **docker-compose.prod.yml**: `game-server`
- **nginx-ssl.conf**: `proxy_pass http://game-server:8080`
- **状态**: 一致 ✅

#### ✅ 容器名称
- **game-server 容器**: `bomberman-server`
- **web 容器**: `bomberman-web`

#### ✅ 网络配置
- **网络名**: `game-network`
- **驱动**: `bridge`

#### ✅ 端口映射
- **HTTP**: 80 → 80
- **HTTPS**: 443 → 443
- **WebSocket**: 8080 → 8080

### 3. Go 服务器配置

#### ✅ Dockerfile 优化
```dockerfile
ENV GOPROXY=https://goproxy.cn,direct
```
- 解决国内网络问题 ✅

#### ✅ 路由配置
```go
http.HandleFunc("/ws", ...)  // WebSocket 端点
```

### 4. Nginx 配置

#### ✅ SSL 证书路径
```nginx
ssl_certificate /etc/nginx/ssl/cert.pem;
ssl_certificate_key /etc/nginx/ssl/key.pem;
```

#### ✅ WebSocket 代理
```nginx
location /ws {
    proxy_pass http://game-server:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

#### ✅ 性能优化
- Gzip 压缩：级别 6 ✅
- 浏览器缓存：7 天 ✅
- COOP/COEP 头：已配置 ✅

### 5. 客户端配置

#### ✅ NetworkManager.gd
```gdscript
if protocol == "https:":
    server_url = "wss://" + str(host) + "/ws"
else:
    server_url = "ws://" + str(host) + "/ws"
```

## 🚀 一键部署步骤

### 方法 1：使用部署脚本（推荐）

```bash
# 1. 上传整个 map 目录到服务器
scp -r map/ user@server:/path/to/

# 2. SSH 登录服务器
ssh user@server

# 3. 进入项目目录
cd /path/to/map

# 4. 添加执行权限
chmod +x setup-ssl.sh

# 5. 运行部署脚本
./setup-ssl.sh <服务器IP>

# 示例
./setup-ssl.sh 47.110.34.178
```

### 方法 2：手动部署

```bash
# 1. 生成 SSL 证书
mkdir -p ssl
openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout ssl/key.pem \
    -out ssl/cert.pem \
    -subj "/C=CN/ST=State/L=City/O=Org/CN=<IP>"

# 2. 启动服务
docker-compose -f docker-compose.prod.yml up -d --build

# 3. 检查状态
docker-compose ps
```

## ✅ 部署后验证

### 1. 容器状态检查

```bash
# 检查容器是否运行
docker ps

# 预期输出：
# - bomberman-server (Up)
# - bomberman-web (Up)
```

### 2. 服务健康检查

```bash
# 检查 Go 服务器
docker logs bomberman-server --tail 10
# 预期：Bomberman Server started on :8080

# 检查 Nginx
docker logs bomberman-web --tail 10
# 预期：无错误信息
```

### 3. 网络连接测试

```bash
# 测试 HTTP → HTTPS 重定向
curl -I http://localhost
# 预期：301 Moved Permanently

# 测试 HTTPS
curl -I https://localhost -k
# 预期：200 OK

# 测试 WebSocket 代理
docker exec bomberman-web wget -O- http://game-server:8080/ws 2>&1
# 预期：连接成功（可能返回 400，但不是 404）
```

### 4. 浏览器访问测试

1. 访问 `https://<服务器IP>`
2. 接受自签名证书警告
3. 检查：
   - ✅ 页面加载成功
   - ✅ 游戏资源下载完成
   - ✅ 汉字显示正常
   - ✅ WebSocket 连接成功（查看浏览器 Console）

## 🔧 常见问题排查

### 问题 1：容器启动失败

```bash
# 查看详细日志
docker-compose -f docker-compose.prod.yml logs

# 常见原因：
# - 端口被占用：netstat -tulpn | grep -E ':(80|443|8080)'
# - 镜像拉取失败：检查 Docker 镜像源配置
# - 配置文件错误：检查 nginx-ssl.conf 语法
```

### 问题 2：WebSocket 连接失败

```bash
# 检查服务名解析
docker exec bomberman-web ping game-server

# 检查 Nginx 配置
docker exec bomberman-web cat /etc/nginx/nginx.conf | grep "proxy_pass"

# 应该显示：proxy_pass http://game-server:8080;
```

### 问题 3：SSL 证书错误

```bash
# 检查证书文件
ls -lh ssl/
# 应该有：cert.pem 和 key.pem

# 重新生成证书
rm -rf ssl
./setup-ssl.sh <IP>
```

## 📊 性能指标

### 文件大小优化

- **优化前**: 165 MB (index.pck: 136MB)
- **优化后**: 38 MB (index.pck: 1.7MB)
- **减少**: 77% ✅

### 加载时间估算

**10 Mbps 带宽**:
- 优化前：~2.2 分钟
- 优化后：~30 秒
- **提升**: 4.4x ✅

**100 Mbps 带宽**:
- 优化前：~13 秒
- 优化后：~3 秒
- **提升**: 4.3x ✅

## 🎯 部署成功标准

- [x] 所有容器正常运行
- [x] HTTP 自动重定向到 HTTPS
- [x] HTTPS 访问返回 200 OK
- [x] WebSocket 连接成功
- [x] 游戏资源加载完成
- [x] 汉字显示正常
- [x] 多人游戏功能正常

## 📝 维护命令

```bash
# 查看日志
docker-compose -f docker-compose.prod.yml logs -f

# 重启服务
docker-compose -f docker-compose.prod.yml restart

# 停止服务
docker-compose -f docker-compose.prod.yml down

# 更新代码后重新部署
docker-compose -f docker-compose.prod.yml up -d --build

# 清理旧镜像
docker system prune -a
```

## 🔒 安全建议

### 生产环境

1. **使用域名 + Let's Encrypt**
   - 避免自签名证书警告
   - 自动续期

2. **配置防火墙**
   ```bash
   # 只开放必要端口
   ufw allow 80/tcp
   ufw allow 443/tcp
   ufw enable
   ```

3. **定期更新**
   ```bash
   # 更新 Docker 镜像
   docker-compose pull
   docker-compose up -d
   ```

## ✅ 最终检查清单

部署前确认：
- [ ] 所有文件已上传到服务器
- [ ] setup-ssl.sh 有执行权限
- [ ] Docker 和 Docker Compose 已安装
- [ ] 防火墙已开放 80、443 端口
- [ ] 服务器 IP 地址正确

部署后确认：
- [ ] 容器全部运行（docker ps）
- [ ] HTTPS 访问正常
- [ ] WebSocket 连接成功
- [ ] 游戏功能正常
- [ ] 无错误日志

**全部完成 = 部署成功！** 🎉
