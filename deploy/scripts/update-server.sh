#!/bin/bash
# PixelBomb Server Update Script
# 用法: 服务器上运行 bash update.sh

set -e

cd /root/PixelBomb

echo "========================================"
echo "  PixelBomb Server Update"
echo "========================================"

echo "[1/3] Pulling latest code from GitHub..."
git fetch origin main
git reset --hard origin/main

echo ""
echo "[2/3] Stopping services + rebuilding..."
docker-compose down
docker-compose up --build -d

echo ""
echo "[3/3] Checking status..."
sleep 3
docker-compose ps

echo ""
echo "========================================"
echo "  Update Complete!"
echo "========================================"
