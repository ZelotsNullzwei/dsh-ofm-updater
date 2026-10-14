@echo off
REM ============================================================
REM  Our Free Model updater - double-click launcher
REM
REM  This file is intentionally ASCII-only.
REM  cmd.exe parses .bat files using the system ANSI codepage
REM  (GBK on a Simplified-Chinese Windows), so UTF-8 Chinese in
REM  a .bat turns into mojibake and gets executed as commands.
REM  All Chinese text lives in Update-OurFreeModel.ps1 instead
REM  (that file is UTF-8 with BOM, which PowerShell reads fine).
REM
REM  Why ship a .bat at all: on many machines the .ps1 extension
REM  has no file association, so double-clicking a .ps1 does
REM  nothing. A .bat always runs.
REM
REM  Any arguments are forwarded to the PowerShell script, e.g.
REM    Update-OurFreeModel.bat -DryRun
REM    Update-OurFreeModel.bat -Rollback
REM    Update-OurFreeModel.bat -English
REM ============================================================

setlocal
chcp 65001 >nul 2>nul

set "SCRIPT=%~dp0Update-OurFreeModel.ps1"

if not exist "%SCRIPT%" (
  echo.
  echo   ERROR: Update-OurFreeModel.ps1 not found next to this file.
  echo   Expected: %SCRIPT%
  echo.
  pause
  exit /b 1
)

REM Prefer PowerShell 7 if present, else Windows PowerShell 5.1.
set "PS=powershell"
where pwsh >nul 2>nul && set "PS=pwsh"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "CODE=%ERRORLEVEL%"

if not "%CODE%"=="0" echo   (exit code %CODE%)
echo.
echo   Press any key to close this window...
pause >nul
endlocal
