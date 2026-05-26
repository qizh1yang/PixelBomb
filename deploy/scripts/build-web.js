#!/usr/bin/env node
/**
 * PixelBomb Web Build Script — 免清缓存热更新系统
 *
 * 功能:
 *   1. 从 git commit hash (或时间戳) 生成版本号
 *   2. 将 index.pck / index.wasm 重命名为 game.{version}.{ext}
 *   3. 生成 manifest.json 资源索引
 *   4. 可选: 输出到独立 build/ 目录
 *
 * 用法:
 *   node deploy/scripts/build-web.js              # 原地更新 export/web/
 *   node deploy/scripts/build-web.js --out build  # 输出到 build/ 目录
 *   node deploy/scripts/build-web.js --help       # 显示帮助
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// ── 配置 ──────────────────────────────────────────────────────────────

const CONFIG = {
  // Godot 导出目录 (相对于项目根目录)
  exportDir: 'client/export/web',

  // 需要版本化的文件 (源文件名 → 目标文件名模板)
  // {name} = 原始基础名, {version} = 版本号, {ext} = 扩展名
  versionedFiles: [
    { src: 'index.pck',  tmpl: 'game.{version}.pck' },
    { src: 'index.wasm', tmpl: 'game.{version}.wasm' },
  ],

  // manifest 文件名
  manifestName: 'manifest.json',

  // 源模板目录 (HTML, SW, version-detector 的 git 跟踪源文件)
  templateDir: 'deploy/web-src',

  // 需要从 templateDir 复制到 exportDir 的模板文件
  templateFiles: [
    'index.html',
    'sw.js',
    'version-detector.js',
  ],

  // 是否保留原始未版本化的文件 (作为 fallback)
  keepOriginals: true,

  // 输出目录 (null = 原地更新 exportDir)
  outputDir: null,
};

// ── 工具函数 ──────────────────────────────────────────────────────────

function getProjectRoot() {
  // 从脚本位置向上找到项目根目录 (包含 .git 的目录)
  let dir = path.resolve(__dirname);
  while (dir !== path.dirname(dir)) {
    if (fs.existsSync(path.join(dir, '.git'))) return dir;
    dir = path.dirname(dir);
  }
  // fallback: 假设从项目根运行
  return process.cwd();
}

function getVersion() {
  try {
    const hash = execSync('git rev-parse --short HEAD', {
      cwd: getProjectRoot(),
      encoding: 'utf-8',
      timeout: 5000,
    }).trim();
    if (hash && hash.length >= 7) return hash.substring(0, 7);
  } catch (_) {
    // git 不可用，回退到时间戳
  }
  // 时间戳回退: YYYYMMDD-HHMMss
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-` +
         `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
}

function getFileSize(filePath) {
  try {
    return fs.statSync(filePath).size;
  } catch (_) {
    return 0;
  }
}

function parseArgs() {
  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--out':
        CONFIG.outputDir = args[++i] || 'build';
        break;
      case '--help':
      case '-h':
        console.log(`
PixelBomb Web Build Script
  用法: node deploy/scripts/build-web.js [选项]

  选项:
    --out <dir>   输出到指定目录 (默认: 原地更新 ${CONFIG.exportDir})
    --help, -h    显示此帮助信息

  示例:
    node deploy/scripts/build-web.js
    node deploy/scripts/build-web.js --out build
`);
        process.exit(0);
    }
  }
}

// ── 主流程 ────────────────────────────────────────────────────────────

function main() {
  parseArgs();

  const root = getProjectRoot();
  const srcDir = path.join(root, CONFIG.exportDir);
  const outDir = CONFIG.outputDir
    ? path.resolve(root, CONFIG.outputDir)
    : srcDir;

  console.log('╔══════════════════════════════════════════╗');
  console.log('║   PixelBomb Web Build — 热更新构建系统  ║');
  console.log('╚══════════════════════════════════════════╝');
  console.log(`  项目根目录: ${root}`);
  console.log(`  源目录:     ${srcDir}`);
  console.log(`  输出目录:   ${outDir}`);

  // 验证源目录
  if (!fs.existsSync(srcDir)) {
    console.error(`✗ 源目录不存在: ${srcDir}`);
    console.error('  请先执行 Godot Web Export 到 client/export/web/');
    process.exit(1);
  }

  // 生成版本号
  const version = getVersion();
  console.log(`  版本号:     ${version}`);

  // 确保输出目录存在
  if (outDir !== srcDir) {
    fs.mkdirSync(outDir, { recursive: true });
    console.log(`  创建输出目录: ${outDir}`);
  }

  // 复制非版本化文件
  const skipFiles = new Set(CONFIG.versionedFiles.map(f => f.src));
  skipFiles.add(CONFIG.manifestName);
  // 模板文件由 deploy/web-src/ 提供, 跳过 export 目录中的旧版
  CONFIG.templateFiles.forEach(f => skipFiles.add(f));

  if (outDir !== srcDir) {
    const allFiles = fs.readdirSync(srcDir);
    for (const file of allFiles) {
      const srcPath = path.join(srcDir, file);
      if (fs.statSync(srcPath).isDirectory()) continue;
      if (skipFiles.has(file)) continue;
      const dstPath = path.join(outDir, file);
      fs.copyFileSync(srcPath, dstPath);
    }
    console.log('  已复制静态文件到输出目录');
  }

  // 从 deploy/web-src/ 复制模板文件 (index.html, sw.js, version-detector.js)
  const templateDir = path.join(root, CONFIG.templateDir);
  if (fs.existsSync(templateDir)) {
    for (const file of CONFIG.templateFiles) {
      const srcPath = path.join(templateDir, file);
      const dstPath = path.join(outDir, file);
      if (fs.existsSync(srcPath)) {
        fs.copyFileSync(srcPath, dstPath);
        console.log(`  ✓ 模板: deploy/web-src/${file} → ${path.relative(root, dstPath)}`);
      } else {
        console.warn(`  ⚠ 模板不存在: ${srcPath}`);
      }
    }
  } else {
    console.warn(`  ⚠ 模板目录不存在: ${templateDir}`);
  }

  // 处理版本化文件
  const manifestFiles = {};
  const manifestFileSizes = {};

  for (const { src, tmpl } of CONFIG.versionedFiles) {
    const srcPath = path.join(srcDir, src);
    if (!fs.existsSync(srcPath)) {
      console.warn(`  ⚠ 跳过不存在的文件: ${src}`);
      continue;
    }

    const ext = path.extname(src);
    const dstName = tmpl.replace('{version}', version).replace('{ext}', ext);
    const dstPath = path.join(outDir, dstName);
    const fileSize = getFileSize(srcPath);

    fs.copyFileSync(srcPath, dstPath);
    console.log(`  ✓ ${src} → ${dstName} (${(fileSize / 1024 / 1024).toFixed(1)} MB)`);

    // 记录到 manifest
    const key = ext.replace('.', ''); // "pck" or "wasm"
    manifestFiles[key] = dstName;
    manifestFileSizes[dstName] = fileSize;
  }

  // 可选: 保留原始文件作为 fallback
  if (CONFIG.keepOriginals && outDir === srcDir) {
    // 文件已在原位，无需额外操作
    console.log('  原始文件已保留作为 fallback');
  }

  // 生成 manifest.json
  const manifest = {
    version: version,
    created_at: new Date().toISOString(),
    files: manifestFiles,
    fileSizes: manifestFileSizes,
  };

  const manifestPath = path.join(outDir, CONFIG.manifestName);
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2), 'utf-8');
  console.log(`  ✓ manifest.json 已生成 (version: ${version})`);

  // 输出摘要
  console.log('\n  ── 构建完成 ──');
  console.log(`  版本: ${version}`);
  console.log(`  输出: ${outDir}`);
  console.log('  文件:');
  for (const [key, filename] of Object.entries(manifestFiles)) {
    const size = manifestFileSizes[filename] || 0;
    console.log(`    - ${filename} (${(size / 1024 / 1024).toFixed(1)} MB)`);
  }
  console.log(`    - ${CONFIG.manifestName}`);
  console.log('\n  部署后用户无需清缓存即可加载最新版本。\n');
}

main();
