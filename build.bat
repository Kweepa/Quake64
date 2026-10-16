@echo off
setlocal
cd /d "%~dp0"

if exist "%~dp0setup-env.bat" call "%~dp0setup-env.bat"

set STEP=acme
if defined ACME if exist "%ACME%" goto run
where acme >nul 2>&1 && set ACME=acme && goto run
echo ACME not found. Set ACME in setup-env.bat (see setup-env.example.bat)
goto failed

:run
set STEP=check_irq_contract
python tools\check_irq_contract.py
if errorlevel 1 goto failed
set STEP=gentables
python tools\gentables.py
if errorlevel 1 goto failed
set STEP=genscreens
python tools\genscreens.py
if errorlevel 1 goto failed
set STEP=genlinebodies
python tools\genlinebodies.py
if errorlevel 1 goto failed
set STEP=genrotate
python tools\genrotate.py
if errorlevel 1 goto failed
set STEP=genuifont
python tools\genuifont.py
if errorlevel 1 goto failed
set STEP=genenemymuzzle
python tools\genenemymuzzle.py
if errorlevel 1 goto failed
set STEP=gensplat
python tools\gensplat.py
if errorlevel 1 goto failed
set STEP=gensounds
python tools\gensounds.py
if errorlevel 1 goto failed
set STEP=genenemies
python tools\genenemies.py
if errorlevel 1 goto failed
set STEP=genmap
python tools\genmap.py
if errorlevel 1 goto failed
set STEP=genitems
python tools\genitems.py
if errorlevel 1 goto failed
set STEP=genweapons
python tools\genweapons.py
if errorlevel 1 goto failed
set STEP=gen_menu_text
python tools\gen_menu_text.py
if errorlevel 1 goto failed
set STEP=gen_menu_cursor_sprites
python tools\gen_menu_cursor_sprites.py
if errorlevel 1 goto failed
set STEP=gen_menu_title
python tools\gen_menu_title.py
if errorlevel 1 goto failed
set STEP=gen_menu_wip_sprite
python tools\gen_menu_wip_sprite.py
if errorlevel 1 goto failed
set STEP=gen_splash
python tools\gen_splash.py
if errorlevel 1 goto failed
set STEP=genmusic
python tools\genmusic.py
if errorlevel 1 goto failed

set STEP=acme enemy_data_blob.asm
pushd src
"%ACME%" enemy_data_blob.asm
if errorlevel 1 goto failed_pop
set STEP=acme tables.asm
"%ACME%" tables.asm
if errorlevel 1 goto failed_pop
set STEP=acme sqtab.asm
"%ACME%" sqtab.asm
if errorlevel 1 goto failed_pop
set STEP=acme uifont.asm
"%ACME%" uifont.asm
if errorlevel 1 goto failed_pop
set STEP=acme screens.asm
"%ACME%" screens.asm
if errorlevel 1 goto failed_pop
set STEP=acme menu.asm
"%ACME%" menu.asm
if errorlevel 1 goto failed_pop
popd

if exist src\enemydata.prg move /y src\enemydata.prg enemydata.prg >nul
if exist src\tab.prg move /y src\tab.prg tab.prg >nul
if exist src\sqt.prg move /y src\sqt.prg sqt.prg >nul
if exist src\fnt.prg move /y src\fnt.prg fnt.prg >nul
if exist src\scr.prg move /y src\scr.prg scr.prg >nul
if exist src\menu.prg move /y src\menu.prg menu.prg >nul

set STEP=acme overlay.asm
pushd src
"%ACME%" --vicelabels ..\overlay.lbl overlay.asm
if errorlevel 1 goto failed_pop
popd

rem Bootstrap fixed GAME symbols, then build relocatable per-type AI modules.
set STEP=acme quake64.asm ai
pushd src
"%ACME%" -v3 --vicelabels ..\game-ai.lbl quake64.asm
if errorlevel 1 goto failed_pop
popd
set STEP=genaisymbols ai
python tools\genaisymbols.py --labels game-ai.lbl
if errorlevel 1 goto failed
set STEP=acme ai_grunt.asm
pushd src
"%ACME%" ai_grunt.asm
if errorlevel 1 goto failed_pop
set STEP=acme ai_rott.asm
"%ACME%" ai_rott.asm
if errorlevel 1 goto failed_pop
set STEP=acme ai_knight.asm
"%ACME%" ai_knight.asm
if errorlevel 1 goto failed_pop
set STEP=acme ai_ogre.asm
"%ACME%" ai_ogre.asm
if errorlevel 1 goto failed_pop
set STEP=acme ai_scrag.asm
"%ACME%" ai_scrag.asm
if errorlevel 1 goto failed_pop
set STEP=acme ai_zombie.asm
"%ACME%" ai_zombie.asm
if errorlevel 1 goto failed_pop
set STEP=acme ai_crush.asm
"%ACME%" ai_crush.asm
if errorlevel 1 goto failed_pop
set STEP=acme ai_chthon.asm
"%ACME%" ai_chthon.asm
if errorlevel 1 goto failed_pop
set STEP=acme ai_shambler.asm
"%ACME%" ai_shambler.asm
if errorlevel 1 goto failed_pop
set STEP=acme ai_demon.asm
"%ACME%" ai_demon.asm
if errorlevel 1 goto failed_pop
set STEP=acme skel_draw.asm
"%ACME%" skel_draw.asm
if errorlevel 1 goto failed_pop
popd
set STEP=genaimeta
python tools\genaimeta.py
if errorlevel 1 goto failed
set STEP=genaibanks
python tools\genaibanks.py
if errorlevel 1 goto failed
set STEP=checkaibanks
python tools\checkaibanks.py
if errorlevel 1 goto failed

rem Krill disk first (loadraw @ $EE08, needs TDE / real 1541)
set STEP=acme quake64.asm krill
pushd src
"%ACME%" -DUSE_KRILL=1 -v3 --vicelabels ..\game-krill.lbl quake64.asm
if errorlevel 1 goto failed_pop
set STEP=acme boot.asm krill
"%ACME%" -DUSE_KRILL=1 boot.asm
if errorlevel 1 goto failed_pop
set STEP=acme splashc.asm krill
"%ACME%" -DUSE_KRILL=1 splashc.asm
if errorlevel 1 goto failed_pop
popd

if exist src\game.prg move /y src\game.prg game.prg >nul
if exist src\boot.prg move /y src\boot.prg boot.prg >nul
if exist src\splashc.prg move /y src\splashc.prg splashc.prg >nul

set STEP=mkreloc krill
python tools\mkreloc.py --labels game-krill.lbl
if errorlevel 1 goto failed

set STEP=acme quake64.asm krill reloc
pushd src
"%ACME%" -DUSE_KRILL=1 -v3 --vicelabels ..\game-krill.lbl quake64.asm
if errorlevel 1 goto failed_pop
popd
if exist src\game.prg move /y src\game.prg game.prg >nul

set STEP=genaisymbols verify krill
python tools\genaisymbols.py --labels game-ai.lbl --verify-labels game-krill.lbl
if errorlevel 1 goto failed
set STEP=memoryreport krill
python tools\memoryreport.py --labels game-krill.lbl --json memory-report-krill.json
if errorlevel 1 goto failed
set STEP=checkheap krill
python tools\checkheap.py --labels game-krill.lbl --json heap-report-krill.json
if errorlevel 1 goto failed

rem MENU loads the menu music itself: loadraw on the Krill disk, KERNAL LOAD otherwise.
set STEP=acme menu.asm krill
pushd src
"%ACME%" -DUSE_KRILL=1 menu.asm
if errorlevel 1 goto failed_pop
popd
if exist src\menu.prg move /y src\menu.prg menu.prg >nul

set STEP=genqsyms krill
python tools\genqsyms.py --labels game-krill.lbl --krill
if errorlevel 1 goto failed
set STEP=acme quicksave.asm krill
pushd src
"%ACME%" -DUSE_KRILL=1 quicksave.asm
if errorlevel 1 goto failed_pop
popd
if exist src\qsave.prg move /y src\qsave.prg qsave.prg >nul

set STEP=mkdisk krill
python tools\mkdisk.py --krill --out quake64-krill.d64
if errorlevel 1 goto failed

rem Default disk: KERNAL LOAD (VICE virtual traps)
set STEP=acme quake64.asm
pushd src
"%ACME%" -v3 --vicelabels ..\game.lbl quake64.asm
if errorlevel 1 goto failed_pop
set STEP=acme boot.asm
"%ACME%" boot.asm
if errorlevel 1 goto failed_pop
set STEP=acme splashc.asm
"%ACME%" splashc.asm
if errorlevel 1 goto failed_pop
popd

if exist src\game.prg move /y src\game.prg game.prg >nul
if exist src\boot.prg move /y src\boot.prg boot.prg >nul
if exist src\splashc.prg move /y src\splashc.prg splashc.prg >nul

set STEP=mkreloc
python tools\mkreloc.py
if errorlevel 1 goto failed

set STEP=acme quake64.asm reloc
pushd src
"%ACME%" -v3 --vicelabels ..\game.lbl quake64.asm
if errorlevel 1 goto failed_pop
popd
if exist src\game.prg move /y src\game.prg game.prg >nul

set STEP=genaisymbols verify
python tools\genaisymbols.py --labels game-ai.lbl --verify-labels game.lbl
if errorlevel 1 goto failed
set STEP=memoryreport
python tools\memoryreport.py --labels game.lbl --json memory-report.json
if errorlevel 1 goto failed
set STEP=checkheap
python tools\checkheap.py --json heap-report.json
if errorlevel 1 goto failed

set STEP=acme menu.asm
pushd src
"%ACME%" menu.asm
if errorlevel 1 goto failed_pop
popd
if exist src\menu.prg move /y src\menu.prg menu.prg >nul

set STEP=genqsyms
python tools\genqsyms.py --labels game.lbl
if errorlevel 1 goto failed
set STEP=acme quicksave.asm
pushd src
"%ACME%" quicksave.asm
if errorlevel 1 goto failed_pop
popd
if exist src\qsave.prg move /y src\qsave.prg qsave.prg >nul

set STEP=mkdisk
python tools\mkdisk.py --out quake64.d64
if errorlevel 1 goto failed

set STEP=buildreport
python tools\buildreport.py
if errorlevel 1 goto failed

echo Built quake64.d64 and quake64-krill.d64
dir quake64.d64 quake64-krill.d64
exit /b 0

:failed_pop
popd
:failed
python tools\buildreport.py --failed "%STEP%"
exit /b 1
