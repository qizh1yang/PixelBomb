# HTTPS 部署指南 - 使用自签名证书

## 服务器信息

- **公网 IP**: 你的服务器 IP（例如：47.110.34.178）
- **访问地址**: https://你的IP地址

## 部署步骤

### 1. 生成 SSL 证书并启动服务

在 Linux 服务器上运行：

```bash
# 方式 1: 直接指定 IP 地址作为参数
chmod +x setup-ssl.sh
./setup-ssl.sh 47.110.34.178

# 方式 2: 使用环境变量
export SERVER_IP=47.110.34.178
./setup-ssl.sh

# 方式 3: 运行时输入（脚本会提示你输入）
./setup-ssl.sh
# 然后输入你的 IP 地址
```

### 2. 访问游戏

在浏览器中访问：**https://47.110.34.178**

### 3. 处理浏览器安全警告

由于使用自签名证书，浏览器会显示安全警告：

#### Chrome/Edge:
1. 看到 "您的连接不是私密连接" 警告
2. 点击 **"高级"**
3. 点击 **"继续前往 47.110.34.178（不安全）"**

#### Firefox:
1. 看到 "警告：潜在的安全风险"
2. 点击 **"高级"**
3. 点击 **"接受风险并继续"**

#### Safari:
1. 看到 "此连接不是私密连接"
2. 点击 **"显示详细信息"**
3. 点击 **"访问此网站"**

### 4. 验证

- ✅ 浏览器地址栏显示 HTTPS（带锁图标，可能有警告标记）
- ✅ 游戏正常加载
- ✅ 无 "Secure Context" 错误
- ✅ WebSocket 连接正常（WSS）

## 管理命令

```bash
# 查看日志
docker-compose -f docker-compose.prod.yml logs -f

# 重启服务
docker-compose -f docker-compose.prod.yml restart

# 停止服务
docker-compose -f docker-compose.prod.yml down

# 重新生成证书（如果过期）
./setup-ssl.sh
```

## 证书信息

- **位置**: `./ssl/`
- **有效期**: 365 天
- **类型**: 自签名证书
- **适用**: IP 地址 (47.110.34.178)

## 注意事项

### ✅ 优点
- 完全解决 Secure Context 问题
- 所有人都能通过 HTTPS 访问
- WebSocket 使用 WSS（安全）
- 免费，无需域名

### ⚠️ 限制
- 浏览器会显示安全警告（需要手动接受）
- 每个用户首次访问都需要接受证书
- 不适合公开的商业应用

### 🎯 适用场景
- 内部测试
- 朋友间分享
- 小范围演示
- 开发环境

## 升级到正式证书（可选）

如果将来需要去除浏览器警告，可以：

1. **购买域名**（约 ¥50-100/年）
2. **配置 DNS** 指向 47.110.34.178
3. **使用 Let's Encrypt** 获取免费正式证书
4. 我可以帮你配置

## 故障排查

### 证书错误
```bash
# 重新生成证书
rm -rf ssl/
./setup-ssl.sh
```

### 端口被占用
```bash
# 检查端口
netstat -tulpn | grep :443
netstat -tulpn | grep :80

# 停止占用端口的服务
docker-compose -f docker-compose.prod.yml down
```

### 防火墙问题
```bash
# 确保开放 80 和 443 端口
sudo ufw allow 80
sudo ufw allow 443
```
