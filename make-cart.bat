@echo off
setlocal
cd /d "%~dp0"

if not exist "quake64.d64" (
  echo quake64.d64 not found — run build.bat first.
  exit /b 1
)

python --version >nul 2>&1
if errorlevel 1 (
  echo Python is not installed or not in PATH.
  exit /b 1
)

if not exist "3rdparty\disk2easyflash.py" (
  echo 3rdparty\disk2easyflash.py not found.
  echo Download v1.1 from https://github.com/milasoft64/Disk2Easyflash-v1
  echo   ^(v1.1/disk2easyflash_v1.1.py^) and save it as 3rdparty\disk2easyflash.py
  exit /b 1
)

python 3rdparty\disk2easyflash.py --crt quake64.d64 quake64.crt
if errorlevel 1 exit /b 1

echo Built quake64.crt
dir quake64.crt
