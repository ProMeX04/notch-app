#!/bin/bash
# Chạy đồng thời Go API backend và Vite React frontend

set -euo pipefail

# Lấy thư mục gốc của script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# Load biến môi trường từ file .env nếu có
if [ -f .env ]; then
  echo "Loading environment variables from .env..."
  set -a
  source .env
  set +a
fi

# Chạy Go API Backend ở background
echo "Starting Go API Backend on port 8080..."
cd api
go run ./cmd/portal-api &
BACKEND_PID=$!

# Đảm bảo tắt tiến trình Go API khi tắt script
trap 'echo "Stopping Go API Backend..."; kill $BACKEND_PID 2>/dev/null || true' EXIT SIGINT SIGTERM

# Chạy Vite React Frontend ở foreground
echo "Starting Vite React Frontend on port 5173..."
cd ../web
npm run dev
