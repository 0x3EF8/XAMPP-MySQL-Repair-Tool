@echo off
title MySQL Repair Tool

echo ------------------------------------------------------
echo   MySQL Repair Tool (Standard Mode)
echo ------------------------------------------------------

:: 1. Attempt to stop MySQL
echo [*] Checking for running MySQL...
:: Using a gentler check that works without admin
taskkill /IM mysqld.exe /T >nul 2>&1

:: 2. Set Paths
set "DATA_DIR=C:\xampp\mysql\data"
set "BACKUP_DIR=C:\xampp\mysql\backup\mysql"

:: 3. Check Access
if not exist "%DATA_DIR%" (
    echo [!] Error: Cannot find %DATA_DIR%
    pause
    exit /b
)

:: 4. Repair Aria
echo [*] Checking Aria files...
if exist "%DATA_DIR%\aria_log_control" (
    echo [*] Resetting aria_log_control...
    ren "%DATA_DIR%\aria_log_control" "aria_log_control_old_%RANDOM%"
)

:: 5. Restore System DB
echo [*] Restoring system database...
if exist "%DATA_DIR%\mysql" (
    echo [*] Archiving old system folder...
    ren "%DATA_DIR%\mysql" "mysql_old_%RANDOM%"
)

echo [*] Copying backup files...
xcopy "%BACKUP_DIR%" "%DATA_DIR%\mysql" /E /I /H /Y /Q >nul

if %ERRORLEVEL% EQU 0 (
    echo ------------------------------------------------------
    echo   SUCCESS: Repair tasks completed!
    echo   You can now try to start MySQL in XAMPP.
    echo ------------------------------------------------------
) else (
    echo ------------------------------------------------------
    echo   FAILED: Access Denied or Files in Use.
    echo   If this persists, you may need to right-click 
    echo   and 'Run as administrator' just once.
    echo ------------------------------------------------------
)

pause
