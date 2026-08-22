@echo off
setlocal
cd /d "%~dp0"

if exist "%~dp0setup-env.bat" call "%~dp0setup-env.bat"

if defined ACME if exist "%ACME%" goto run
where acme >nul 2>&1 && set ACME=acme && goto run
echo ACME not found. Set ACME in setup-env.bat (see setup-env.example.bat)
exit /b 1

:run
python tools\gentables.py
if errorlevel 1 exit /b 1
python tools\genlinebodies.py
if errorlevel 1 exit /b 1
python tools\genrotate.py
if errorlevel 1 exit /b 1
python tools\genuifont.py
if errorlevel 1 exit /b 1
python tools\genenemylod.py
if errorlevel 1 exit /b 1
python tools\genenemymuzzle.py
if errorlevel 1 exit /b 1
python tools\gensplat.py
if errorlevel 1 exit /b 1
python tools\genenemies.py
if errorlevel 1 exit /b 1
python tools\genmap.py
if errorlevel 1 exit /b 1
python tools\genitems.py
if errorlevel 1 exit /b 1
python tools\genweapons.py
if errorlevel 1 exit /b 1

pushd src
"%ACME%" -v3 --vicelabels ..\quake64.lbl quake64.asm
if errorlevel 1 (
  popd
  exit /b 1
)
popd

if exist src\quake64.prg move /y src\quake64.prg quake64.prg >nul

echo Built quake64.prg
dir quake64.prg
