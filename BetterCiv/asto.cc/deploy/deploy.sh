#!/bin/bash
# asto.cc 部署脚本
# 在服务器上运行：bash deploy.sh

set -e

APP_DIR="/var/www/asto/asto.cc"

echo "=== asto.cc 部署 ==="

cd "$APP_DIR"
echo "[1/3] Git pull..."
git pull origin main

echo "[2/3] 同步内容..."
python sync_content.py

echo "[3/3] 重启服务..."
sudo systemctl restart asto-cc

echo "=== 部署完成 ==="
sudo systemctl status asto-cc --no-pager -l
