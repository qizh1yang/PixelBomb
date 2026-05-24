# Docker Compose 错误修复指南

## 错误信息
```
KeyError: 'ContainerConfig'
```

## 原因
这是 Docker Compose 版本兼容性问题，通常发生在：
- 旧版本 Docker Compose (V1) 与新版本 Docker Engine 不兼容
- 容器配置缓存问题

## 解决方案

### 方案 1：升级到 Docker Compose V2（推荐）

```bash
# 卸载旧版本
sudo apt remove docker-compose

# 安装 Docker Compose V2（作为 Docker CLI 插件）
sudo apt update
sudo apt install docker-compose-plugin

# 验证安装
docker compose version
```

### 方案 2：清理并重新部署

```bash
# 1. 停止并删除所有容器
docker-compose -f docker-compose.prod.yml down -v

# 2. 清理 Docker 缓存
docker system prune -a

# 3. 重新运行部署脚本
./setup-ssl.sh 你的IP
```

### 方案 3：手动部署（如果上述方法都失败）

```bash
# 1. 构建 Go 服务器镜像
cd Server
docker build -t bomberman-server .
cd ..

# 2. 创建网络
docker network create game-network

# 3. 启动 Go 服务器
docker run -d \
  --name bomberman-server \
  --network game-network \
  -p 8080:8080 \
  --restart unless-stopped \
  bomberman-server

# 4. 启动 Nginx
docker run -d \
  --name bomberman-web \
  --network game-network \
  -p 80:80 \
  -p 443:443 \
  -v $(pwd)/export/web:/usr/share/nginx/html:ro \
  -v $(pwd)/nginx/nginx-ssl.conf:/etc/nginx/nginx.conf:ro \
  -v $(pwd)/ssl:/etc/nginx/ssl:ro \
  --restart unless-stopped \
  nginx:alpine
```

## 快速修复命令

```bash
# 一键修复（推荐先尝试这个）
docker-compose -f docker-compose.prod.yml down
docker system prune -f
./setup-ssl.sh 你的IP
```

## 验证

```bash
# 检查容器状态
docker ps

# 应该看到两个容器：
# - bomberman-server
# - bomberman-web

# 查看日志
docker logs bomberman-server
docker logs bomberman-web
```
