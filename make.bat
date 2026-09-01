@echo off
setlocal
cd /d "%~dp0"
call build.bat
if errorlevel 1 exit /b 1

if exist "%~dp0setup-env.bat" call "%~dp0setup-env.bat"
if defined VICE if exist "%VICE%" goto launch
if defined VICE_BIN if exist "%VICE_BIN%\x64sc.exe" (
  set VICE=%VICE_BIN%\x64sc.exe
  goto launch
)
echo VICE not found — quake64.d64 is built; run it manually.
exit /b 0

:launch
if not exist "%~dp0quake64.d64" (
  echo quake64.d64 missing after build
  exit /b 1
)
start "" "%VICE%" -silent -pal -autostartprgmode 0 -trapdevice8 +drive8truedrive -8 "%~dp0quake64.d64" -autostart "%~dp0quake64.d64"
