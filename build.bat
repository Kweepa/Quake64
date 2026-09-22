@echo off
setlocal
cd /d "%~dp0"

if exist "%~dp0setup-env.bat" call "%~dp0setup-env.bat"

if defined ACME if exist "%ACME%" goto run
where acme >nul 2>&1 && set ACME=acme && goto run
echo ACME not found. Set ACME in setup-env.bat (see setup-env.example.bat)
exit /b 1

:run
python tools\check_irq_contract.py
if errorlevel 1 exit /b 1
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
python tools\genenemymuzzle.py
if errorlevel 1 exit /b 1
python tools\gensplat.py
if errorlevel 1 exit /b 1
python tools\gensounds.py
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
python tools\gen_menu_cursor_sprites.py
if errorlevel 1 exit /b 1
python tools\gen_menu_title.py
if errorlevel 1 exit /b 1
python tools\gen_menu_wip_sprite.py
if errorlevel 1 exit /b 1
python tools\gen_splash.py
if errorlevel 1 exit /b 1

pushd src
"%ACME%" enemy_data_blob.asm
if errorlevel 1 (
  popd
  exit /b 1
)
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
"%ACME%" menu.asm
if errorlevel 1 (
  popd
  exit /b 1
)
popd

if exist src\enemydata.prg move /y src\enemydata.prg enemydata.prg >nul
if exist src\tab.prg move /y src\tab.prg tab.prg >nul
if exist src\sqt.prg move /y src\sqt.prg sqt.prg >nul
if exist src\fnt.prg move /y src\fnt.prg fnt.prg >nul
if exist src\scr.prg move /y src\scr.prg scr.prg >nul
if exist src\menu.prg move /y src\menu.prg menu.prg >nul

pushd src
"%ACME%" --vicelabels ..\overlay.lbl overlay.asm
if errorlevel 1 (
  popd
  exit /b 1
)
popd

rem Bootstrap fixed GAME symbols, then build relocatable per-type AI modules.
pushd src
"%ACME%" -v3 --vicelabels ..\game-ai.lbl quake64.asm
if errorlevel 1 (
  popd
  exit /b 1
)
popd
python tools\genaisymbols.py --labels game-ai.lbl
if errorlevel 1 exit /b 1
pushd src
"%ACME%" ai_rott.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" ai_knight.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" ai_ogre.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" ai_scrag.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" ai_zombie.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" ai_crush.asm
if errorlevel 1 (
  popd
  exit /b 1
)
popd
python tools\genaimeta.py
if errorlevel 1 exit /b 1
python tools\genaibanks.py
if errorlevel 1 exit /b 1
python tools\checkaibanks.py
if errorlevel 1 exit /b 1

rem Krill disk first (loadraw @ $EE08, needs TDE / real 1541)
pushd src
"%ACME%" -DUSE_KRILL=1 -v3 --vicelabels ..\game-krill.lbl quake64.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" -DUSE_KRILL=1 boot.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" -DUSE_KRILL=1 splashc.asm
if errorlevel 1 (
  popd
  exit /b 1
)
popd

if exist src\game.prg move /y src\game.prg game.prg >nul
if exist src\boot.prg move /y src\boot.prg boot.prg >nul
if exist src\splashc.prg move /y src\splashc.prg splashc.prg >nul

python tools\mkreloc.py --labels game-krill.lbl
if errorlevel 1 exit /b 1

pushd src
"%ACME%" -DUSE_KRILL=1 -v3 --vicelabels ..\game-krill.lbl quake64.asm
if errorlevel 1 (
  popd
  exit /b 1
)
popd
if exist src\game.prg move /y src\game.prg game.prg >nul

python tools\genaisymbols.py --labels game-ai.lbl --verify-labels game-krill.lbl
if errorlevel 1 exit /b 1
python tools\memoryreport.py --labels game-krill.lbl --json memory-report-krill.json
if errorlevel 1 exit /b 1
python tools\checkheap.py --labels game-krill.lbl --json heap-report-krill.json
if errorlevel 1 exit /b 1

python tools\mkdisk.py --krill --out quake64-krill.d64
if errorlevel 1 exit /b 1

rem Default disk: KERNAL LOAD (VICE virtual traps)
pushd src
"%ACME%" -v3 --vicelabels ..\game.lbl quake64.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" boot.asm
if errorlevel 1 (
  popd
  exit /b 1
)
"%ACME%" splashc.asm
if errorlevel 1 (
  popd
  exit /b 1
)
popd

if exist src\game.prg move /y src\game.prg game.prg >nul
if exist src\boot.prg move /y src\boot.prg boot.prg >nul
if exist src\splashc.prg move /y src\splashc.prg splashc.prg >nul

python tools\mkreloc.py
if errorlevel 1 exit /b 1

pushd src
"%ACME%" -v3 --vicelabels ..\game.lbl quake64.asm
if errorlevel 1 (
  popd
  exit /b 1
)
popd
if exist src\game.prg move /y src\game.prg game.prg >nul

python tools\genaisymbols.py --labels game-ai.lbl --verify-labels game.lbl
if errorlevel 1 exit /b 1
python tools\memoryreport.py --labels game.lbl --json memory-report.json
if errorlevel 1 exit /b 1
python tools\checkheap.py --json heap-report.json
if errorlevel 1 exit /b 1

python tools\mkdisk.py --out quake64.d64
if errorlevel 1 exit /b 1

echo Built quake64.d64 and quake64-krill.d64
dir quake64.d64 quake64-krill.d64
