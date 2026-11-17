@echo off
rem Double-click to add another Claude profile. Each run makes the next free letter: B, then C, then D...
rem For another name or colour, run it from a terminal: Setup.cmd -Name Work -Color Green
rem To re-make the launchers and icons of the profiles you already have: Setup.cmd -Refresh
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
echo.
pause
