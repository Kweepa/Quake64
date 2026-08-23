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
python tools\genscreens.py
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
python tools\gen_menu_text.py
if errorlevel 1 exit /b 1

pushd src
"%ACME%" tables.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" sqtab.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" uifont.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" screens.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" -v3 --vicelabels ..\game.lbl quake64.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" menu.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" boot.asm
if errorlevel 1 (
  popd
  exit /b 1
)
popd

if exist src\tab.prg move /y src\tab.prg tab.prg >nul
if exist src\sqt.prg move /y src\sqt.prg sqt.prg >nul
if exist src\fnt.prg move /y src\fnt.prg fnt.prg >nul
if exist src\scr.prg move /y src\scr.prg scr.prg >nul
if exist src\game.prg move /y src\game.prg game.prg >nul
if exist src\menu.prg move /y src\menu.prg menu.prg >nul
if exist src\boot.prg move /y src\boot.prg boot.prg >nul

python tools\mkdisk.py
if errorlevel 1 exit /b 1

echo Built quake64.d64
dir quake64.d64
