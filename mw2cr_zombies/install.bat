@echo off
setlocal
rem Installs Wolverines! Zombies into your MW2 Campaign Remastered folder.
rem Double-click it, or drag your game folder onto it.

set "SRC=%~dp0mod\zombies"
set "GAME=%~1"

if "%GAME%"=="" (
  for %%P in (
    "C:\Program Files (x86)\Call of Duty Modern Warfare 2 Campaign Remastered"
    "C:\Program Files\Call of Duty Modern Warfare 2 Campaign Remastered"
    "C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Modern Warfare 2 Campaign Remastered"
  ) do if exist "%%~P\MW2CR.exe" set "GAME=%%~P"
)
if "%GAME%"=="" set /p "GAME=Drag your MW2CR folder (the one with MW2CR.exe) into this window and press Enter: "
set "GAME=%GAME:"=%"

if not exist "%GAME%\MW2CR.exe" (
  echo Can't find MW2CR.exe in "%GAME%".
  pause
  exit /b 1
)

if exist "%GAME%\mods\nacht" (
  rmdir /s /q "%GAME%\mods\nacht"
  echo Removed the old Nacht mod.
)
xcopy /e /i /y "%SRC%" "%GAME%\mods\zombies" >nul
echo Installed to "%GAME%\mods\zombies".

if not exist "%GAME%\h2-mod.exe" (
  echo.
  echo h2-mod.exe isn't in that folder yet. Get it from https://github.com/alicealys/h2-mod
  echo and put it next to MW2CR.exe.
)
echo.
echo Next: start h2-mod.exe, open Mods, load "Wolverines! Zombies", then ZOMBIES - PLAY.
pause
