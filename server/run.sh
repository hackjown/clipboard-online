#!/usr/bin/env bash
# 一键启动：自动创建虚拟环境并安装依赖
# 用法: ./run.sh
#       PORT=9000 CLIP_REGISTER=0 ./run.sh
set -euo pipefail
cd "$(dirname "$0")"
PORT="${PORT:-8099}"
HOST="${HOST:-0.0.0.0}"
PY="${PYTHON:-python3}"
if [ ! -d .venv ]; then
  echo ">> 创建虚拟环境 .venv"
  "$PY" -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
if ! python -c "import fastapi, uvicorn, multipart" 2>/dev/null; then
  echo ">> 安装依赖"
  pip install -q -r requirements.txt
fi
if [ "${CLIP_REGISTER:-1}" = "0" ]; then
  echo "!! CLIP_REGISTER=0：已关闭新用户注册"
fi
echo ">> http://$HOST:$PORT"
exec uvicorn app.main:app --host "$HOST" --port "$PORT" --proxy-headers --forwarded-allow-ips='*'
