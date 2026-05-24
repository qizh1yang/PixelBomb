# Web 加载优化指南

## 当前文件大小分析

```
index.pck     130.55 MB  ← 主要问题！
index.wasm     34.47 MB
index.js        0.26 MB
其他文件       < 0.1 MB
总计：        ~165 MB
```

## 已实施的优化

### 1. Nginx 压缩优化 ✅
- 启用 gzip 压缩（压缩级别 6）
- 压缩 `.pck` 和 `.wasm` 文件
- 预计减少 30-50% 传输大小

### 2. 浏览器缓存优化 ✅
- 静态资源缓存 7 天
- 减少重复访问的加载时间

## 进一步优化建议

### 方案 1：优化 Godot 导出（推荐）

**减小 .pck 文件大小**：

1. **移除未使用的资源**
   - 检查项目中是否有未使用的图片、音频、字体
   - 删除测试资源

2. **压缩纹理**
   - Project → Project Settings → Import Defaults
   - Texture → Compress Mode: VRAM Compressed
   - 可减少 50-70% 大小

3. **优化音频**
   - 使用 OGG 格式替代 WAV
   - 降低采样率（44.1kHz → 22.05kHz）

4. **字体子集化**
   - 只包含需要的汉字
   - 使用 FontForge 或在线工具裁剪字体

### 方案 2：启用 CDN（生产环境）

使用阿里云 CDN 加速静态资源：
- 首次加载：慢
- 后续访问：极快
- 成本：约 ¥0.2/GB 流量

### 方案 3：渐进式加载

修改 Godot 导出设置：
- Export → Resources → Export Mode: Export as Patch
- 将大资源分离成独立文件
- 实现按需加载

## 当前加载时间估算

**1Mbps 带宽**：
- 首次加载：~22 分钟（165MB）
- 启用压缩后：~11 分钟（~82MB）

**10Mbps 带宽**：
- 首次加载：~2.2 分钟
- 启用压缩后：~1.1 分钟

**100Mbps 带宽**：
- 首次加载：~13 秒
- 启用压缩后：~6.5 秒

## 立即生效的优化

重新部署以应用 Nginx 优化：

```bash
# 上传新的 nginx-ssl.conf
scp d:\Godot_PJ\Object\map\nginx\nginx-ssl.conf root@47.110.34.178:/root/map/nginx/

# 重启 Nginx 容器
docker restart bomberman-web
```

## 最佳实践

对于 130MB 的游戏：
1. ✅ 启用 gzip 压缩（已完成）
2. ✅ 启用浏览器缓存（已完成）
3. ⭐ **优化资源大小**（最重要！）
4. 💰 考虑使用 CDN（可选）
