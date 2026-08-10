@echo off
REM ============================================================
REM  可鉴 Skills 服务启动脚本 (T19a)
REM  - 端口策略: 优先 8001; 被占(如幽灵进程残留)时自动改用 8002
REM  - 前端 kejian.js 有端口探测机制, 8001/8002 均可识别
REM  - 数据库: Skills/data/kejian_history.db (SQLite, 自动创建)
REM ============================================================
cd /d %~dp0

REM 探测 8001 是否可绑定
python -X utf8 -c "import socket,sys; s=socket.socket(); r=s.connect_ex(('127.0.0.1',8001)); s.close(); sys.exit(1 if r==0 else 0)"
if %errorlevel%==0 (
    set PORT=8001
) else (
    set PORT=8002
    echo [start_skills] 8001 occupied, fallback to 8002
)

echo [start_skills] starting Skills service on port %PORT%
python -X utf8 -m uvicorn src.main:app --host 127.0.0.1 --port %PORT%
