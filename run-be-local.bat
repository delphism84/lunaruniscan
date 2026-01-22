@echo off
setlocal

REM Run UniScan Node backend (node-api + dispatch-service) for local testing.
REM - Uses remote MongoDB URI (as requested).
REM - Opens each service in a separate terminal window.
REM
REM Requirements:
REM   - Node.js installed
REM   - npm install already done (or first run will install)
REM
REM Ports:
REM   - node-api WS: ws://0.0.0.0:45444/ws/sendReq
REM   - dispatch-service: http://127.0.0.1:50210/enqueue

REM For safety, do NOT hardcode credentials in this repo.
REM Set these environment variables before running:
REM   - MONGO_URI
REM   - MONGO_DB (default: uniscan)
REM   - INTERNAL_TOKEN (default: dev-internal-token)
if "%MONGO_URI%"=="" (
  echo ERROR: MONGO_URI is not set.
  echo Set it first, e.g.:
  echo   set MONGO_URI=mongodb://USER:PASS@HOST:PORT/uniscan?authSource=admin^&authMechanism=SCRAM-SHA-256
  exit /b 1
)
if "%MONGO_DB%"=="" set "MONGO_DB=uniscan"
if "%INTERNAL_TOKEN%"=="" set "INTERNAL_TOKEN=dev-internal-token"

REM node-api (WS gateway)
set "NODE_API_PORT=45444"
set "NODE_API_WS_PATH=/ws/sendReq"
set "NODE_API_DISPATCHER_URL=http://127.0.0.1:50210/enqueue"

REM dispatch-service
set "DISPATCH_PORT=50210"
set "NODE_API_INTERNAL_URL=http://127.0.0.1:45444/internal/dispatch"

echo Starting node-api (ws://0.0.0.0:%NODE_API_PORT%%NODE_API_WS_PATH%)...
start "uniscan-node-api" cmd /k ^
  "cd /d c:\rc\uniscan\lnuniserverbe\node-api ^
   && (if not exist node_modules npm install) ^
   && set PORT=%NODE_API_PORT% ^
   && set HOST=0.0.0.0 ^
   && set WS_PATH=%NODE_API_WS_PATH% ^
   && set MONGO_URI=%MONGO_URI% ^
   && set MONGO_DB=%MONGO_DB% ^
   && set DISPATCHER_URL=%NODE_API_DISPATCHER_URL% ^
   && set INTERNAL_TOKEN=%INTERNAL_TOKEN% ^
   && npm start"

REM small delay so node-api binds first
ping 127.0.0.1 -n 2 >nul

echo Starting dispatch-service (http://127.0.0.1:%DISPATCH_PORT%)...
start "uniscan-dispatch-service" cmd /k ^
  "cd /d c:\rc\uniscan\services\dispatch-service ^
   && (if not exist node_modules npm install) ^
   && set PORT=%DISPATCH_PORT% ^
   && set HOST=0.0.0.0 ^
   && set MONGO_URI=%MONGO_URI% ^
   && set MONGO_DB=%MONGO_DB% ^
   && set NODE_API_INTERNAL_URL=%NODE_API_INTERNAL_URL% ^
   && set INTERNAL_TOKEN=%INTERNAL_TOKEN% ^
   && npm start"

echo.
echo Done.
echo - App/PC Agent WS URL: ws://127.0.0.1:%NODE_API_PORT%%NODE_API_WS_PATH%
echo - dispatcher enqueue: http://127.0.0.1:%DISPATCH_PORT%/enqueue
exit /b 0

