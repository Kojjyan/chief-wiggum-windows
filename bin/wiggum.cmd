@echo off
REM Windows wrapper for wiggum - calls bash to run the actual script
setlocal

REM Find bash.exe (Git Bash)
where bash >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    bash "%~dp0wiggum" %*
    exit /b %ERRORLEVEL%
)

REM Try common Git Bash locations
if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%~dp0wiggum" %*
    exit /b %ERRORLEVEL%
)

if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    "C:\Program Files (x86)\Git\bin\bash.exe" "%~dp0wiggum" %*
    exit /b %ERRORLEVEL%
)

echo Error: bash.exe not found. Please install Git for Windows.
exit /b 1
