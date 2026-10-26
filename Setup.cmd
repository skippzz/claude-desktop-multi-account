@echo off
rem Double-click to add a second Claude profile named B.
rem For another name, run it from a terminal: Setup.cmd -Name Work
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
echo.
pause
