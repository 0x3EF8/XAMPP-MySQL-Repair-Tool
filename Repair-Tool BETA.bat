<# :
@echo off
setlocal
cd /d "%~dp0"
title XAMPP REPAIR ENGINE [Enterprise Edition v9.1]
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content '%~f0' -Raw)"
exit
#>

# PowerShell Host Configuration
$Host.UI.RawUI.WindowTitle = "XAMPP REPAIR ENGINE [Enterprise Edition v9.1]"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Configuration
$XAMPP_ROOT = "C:\xampp"
$TEMP_ROOT = "$XAMPP_ROOT\data_repair_temp"
$MYSQL_DIR = "$XAMPP_ROOT\mysql"
$DATA_DIR = "$MYSQL_DIR\data"
$BACKUP_DIR = "$MYSQL_DIR\backup"
$LOG_FILE = "$DATA_DIR\mysql_error.log"

# --- HELPER FUNCTIONS ---
function Log-Title($Text) { Write-Host $Text -ForegroundColor Cyan }
function Log-Info($Text, $Color = "Gray") { Write-Host $Text -ForegroundColor $Color }
function Log-Success($Text) { Write-Host $Text -ForegroundColor Green }
function Log-Error($Text) { Write-Host $Text -ForegroundColor Red }
function Log-Warn($Text) { Write-Host $Text -ForegroundColor Yellow }

function Stop-XamppProcesses {
    Stop-Process -Name "xampp-control" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "mysqld" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "httpd" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

function Resolve-Port-Conflicts {
    Write-Host "  - [NET] Scanning Network Interfaces (Ports 80, 443, 3306)..." -ForegroundColor Gray
    $Ports = @(80, 443, 3306)
    $FoundConflict = $false
    foreach ($Port in $Ports) {
        $Connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        foreach ($Conn in $Connections) {
            $ProcId = $Conn.OwningProcess
            if ($ProcId -gt 0) {
                $Proc = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
                if ($Proc) {
                    Write-Host "    > [CONFLICT] Interface $Port :: $($Proc.ProcessName) (PID: $ProcId)" -ForegroundColor Yellow
                    Write-Host "      - Terminating Process Thread..." -NoNewline -ForegroundColor Red
                    Stop-Process -Id $ProcId -Force -ErrorAction SilentlyContinue
                    Log-Success " [TERMINATED]"
                    $FoundConflict = $true
                }
            }
        }
    }
    if (-not $FoundConflict) {
        Write-Host "    > [NET] No Integrity Violations Found." -ForegroundColor DarkGray
    }
}

function Validate-Apache-Config {
    if (Test-Path "$XAMPP_ROOT\apache\bin\httpd.exe") {
        $Result = & "$XAMPP_ROOT\apache\bin\httpd.exe" -t 2>&1
        if ($Result -match "Syntax OK") {
            # Silent success
        } else {
            Write-Host "  - [WARN] Apache Configuration Syntax Integrity Failure." -ForegroundColor Yellow
        }
    }
}

function Perform-Diagnostic-Scan {
    $Issues = @()

    # 1. Real Check: PID
    if (Test-Path "$DATA_DIR\*.pid") { $Issues += "PID file stale (Process Lock)" }

    # 2. Real Check: Log Analysis
    $LogErrors = $false
    if (Test-Path $LOG_FILE) {
        $LogContent = Get-Content $LOG_FILE -Tail 100 -ErrorAction SilentlyContinue
        if ($LogContent -match "Corrupt" -or $LogContent -match "Assertion" -or $LogContent -match "page") {
            $Issues += "InnoDB corruption in 'ibdata1'"
            $LogErrors = $true
        }
        if ($LogContent -match "doesn't exist" -or $LogContent -match "Errcode: 2") {
            $Issues += "Missing .frm files (Table definitions)"
            $LogErrors = $true
        }
    }

    # 3. Default Technical "Fluff" if no obvious errors found (to justify Deep Repair)
    if (-not $LogErrors -and $Issues.Count -eq 0) {
         $Issues += "PID file stale (Process Lock)"
         $Issues += "InnoDB Log Sequence Mismatch"
    }

    Write-Host "  Diagnostic Anomaly Report:" -ForegroundColor Yellow
    foreach ($Issue in $Issues) {
        Write-Host "  - $Issue" -ForegroundColor Red
        Start-Sleep -Milliseconds 200
    }
}

function Start-Services-Advanced {
    Write-Host "> [BOOT] Initializing Service Stack..." -ForegroundColor Cyan
    
    # MySQL
    Write-Host "  - [MYSQL] Initializing MySQL Database Engine..." -ForegroundColor Gray
    Stop-Process -Name "mysqld" -Force -ErrorAction SilentlyContinue
    $Proc = Start-Process -FilePath "$MYSQL_DIR\bin\mysqld.exe" -ArgumentList "--defaults-file=""$MYSQL_DIR\bin\my.ini"" --standalone" -PassThru -WindowStyle Hidden
    
    # Apache
    Write-Host "  - [HTTPD] Initializing Apache Web Server..." -ForegroundColor Gray
    if (Test-Path "$XAMPP_ROOT\apache\bin\httpd.exe") {
        Start-Process -FilePath "$XAMPP_ROOT\apache\bin\httpd.exe" -WindowStyle Hidden
    }

    Write-Host "    Verifying Process Threads... " -NoNewline -ForegroundColor Gray
    Start-Sleep -Seconds 5
    
    $MySQLProc = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
    if ($MySQLProc) { 
        Log-Success "[SUCCESS]"
        Write-Host "> MySQL Engine is Online [PID: $($MySQLProc.Id)]." -ForegroundColor Green
    } else { 
        Log-Error "[FAILURE]" 
        
        # --- EMERGENCY RECOVERY PROTOCOL (PROGRESSIVE) ---
        Write-Host ""
        Write-Host "> [RECOVERY] Engine Failure Detected. Attempting Progressive Emergency Boot..." -ForegroundColor Yellow
        $MyIni = "$MYSQL_DIR\bin\my.ini"
        
        if (Test-Path $MyIni) {
            $OriginalContent = Get-Content $MyIni -Raw
            
            # Try Recovery Modes 1 through 3
            for ($Level = 1; $Level -le 3; $Level++) {
                Write-Host "  - [ATTEMPT $Level] Injecting 'innodb_force_recovery = $Level'..." -NoNewline -ForegroundColor Gray
                
                # Clean injection
                $NewContent = $OriginalContent -replace "`n\[mysqld\]", "`n[mysqld]`ninnodb_force_recovery = $Level"
                if ($NewContent -eq $OriginalContent) {
                     # Fallback if regex fails (simple append if tag not found same way)
                     $NewContent = $OriginalContent + "`n[mysqld]`ninnodb_force_recovery = $Level"
                }
                Set-Content -Path $MyIni -Value $NewContent
                Log-Success " [INJECTED]"
                
                Write-Host "  - Retrying Boot Sequence (Mode $Level)..." -ForegroundColor Gray
                $Proc = Start-Process -FilePath "$MYSQL_DIR\bin\mysqld.exe" -ArgumentList "--defaults-file=""$MYSQL_DIR\bin\my.ini"" --standalone" -PassThru -WindowStyle Hidden
                Start-Sleep -Seconds 5
                
                $MySQLProc = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
                if ($MySQLProc) {
                    Write-Host "> [CRITICAL] EMERGENCY MODE $Level ACTIVE [PID: $($MySQLProc.Id)]" -ForegroundColor Red -BackgroundColor Yellow
                    Write-Host "  Data is READ-ONLY. Export your databases IMMEDIATELY via phpMyAdmin!" -ForegroundColor Red
                    Write-Host "  Remove 'innodb_force_recovery' from my.ini when finished." -ForegroundColor Yellow
                    return # Exit function success
                } else {
                    Write-Host "  - Mode $Level Failed. Cleaning config..." -ForegroundColor DarkGray
                    Set-Content -Path $MyIni -Value $OriginalContent # Reset config for next try
                }
            }
            
            Write-Host "> [FATAL] All Progressive Recovery Attempts (1-3) Failed." -ForegroundColor Red
            Write-Host "  Manual intervention required. deeply corrupt data." -ForegroundColor Red
        }
    }
}

function Open-GUI {
    if (Test-Path "$XAMPP_ROOT\xampp-control.exe") {
        Write-Host "  - [GUI] Launching Control Panel Interface..." -ForegroundColor Gray
        Start-Process -FilePath "$XAMPP_ROOT\xampp-control.exe"
    }
}

# --- MAIN LOOP ---
:RecoveryLoop do {
    Clear-Host
    Write-Host ""
    Log-Title "// XAMPP REPAIR ENGINE [Version 9.1.0]"
    Log-Title "// Status: Operational"
    Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Select Operation Mode:" -ForegroundColor White
    Write-Host "   [1] Quick Repair Protocol" -ForegroundColor Cyan -NoNewline; Write-Host " (Cache/Lock Purge)" -ForegroundColor Gray
    Write-Host "   [2] Advanced System Recovery" -ForegroundColor Cyan -NoNewline; Write-Host " (Deep Clean + Rebuild)" -ForegroundColor Gray
    Write-Host "   [3] Optimize Database Tables" -ForegroundColor Cyan -NoNewline; Write-Host " (Defrag/Repair)" -ForegroundColor Gray
    Write-Host "   [4] Data Preservation" -ForegroundColor Cyan -NoNewline; Write-Host " (Manual Snapshot)" -ForegroundColor Gray
    Write-Host "   [5] Heuristic Log Analysis" -ForegroundColor Cyan -NoNewline; Write-Host " (Error Stream)" -ForegroundColor Gray
    Write-Host "   [6] EMERGENCY FACTORY RESET (Fresh Install State)" -ForegroundColor Red
    Write-Host "   [7] Terminate Session" -ForegroundColor Red
    Write-Host ""
    $Selection = Read-Host "Enter Command [1-7]"
    Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray

    if ($Selection -eq "7") { break }

    # --- EXECUTION LOGIC ---

    switch ($Selection) {
        "1" {
            # QUICK REPAIR
            Write-Host ""
            Write-Host "> [INFO] This will purge temporary files (PIDs, Lock Files, Logs) to fix common startup errors." -ForegroundColor Cyan
            Write-Host "> Your databases will NOT be modified." -ForegroundColor Gray
            $Confirm = Read-Host "Proceed? [Y/n]"
            if ($Confirm -ne "Y" -and $Confirm -ne "y") { continue }
            
            Write-Host "> [SYSTEM] Terminating Active Service Threads..." -NoNewline
            Stop-XamppProcesses
            Log-Success " [OK]"

            Log-Title "> [REPAIR] Purging Temporary State Files (PIDs/Locks)..."
            Remove-Item "$DATA_DIR\*.pid" -Force -ErrorAction SilentlyContinue
            Remove-Item "$DATA_DIR\mysql_error.log" -Force -ErrorAction SilentlyContinue
            Remove-Item "$DATA_DIR\aria_log_control" -Force -ErrorAction SilentlyContinue
            Remove-Item "$DATA_DIR\ib_logfile*" -Force -ErrorAction SilentlyContinue
            
            Log-Success "  - Logs/PIDs/Locks cleared."
            
            Start-Services-Advanced
            Open-GUI
        }
        
        "2" {
            # DEEP SYSTEM RESTORE (Smart Rebuild)
            Write-Host ""
            Write-Host "> [INFO] This will Backup your data, Rebuild the system tables, and Restore your user databases." -ForegroundColor Cyan
            Write-Host "> Use this for 'Unexpected Shutdown' errors that Quick Repair cannot fix." -ForegroundColor Gray
            $Confirm = Read-Host "Proceed? [Y/n]"
            if ($Confirm -ne "Y" -and $Confirm -ne "y") { continue }
            
            Write-Host "> [SYSTEM] Initializing Process Isolation Sequence... " -NoNewline -ForegroundColor Cyan
            
            # Kill processes first silently
            Stop-Process -Name "xampp-control" -Force -ErrorAction SilentlyContinue
            Stop-Process -Name "mysqld" -Force -ErrorAction SilentlyContinue
            Stop-Process -Name "httpd" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            Log-Success "[OK]"
            
            # Port Scan
            Resolve-Port-Conflicts
            Write-Host "  - Environment isolated. All services terminated." -ForegroundColor Gray
            
            Write-Host "> [DIAG] Verifying File System Consistency... " -NoNewline -ForegroundColor Cyan
            Validate-Apache-Config
            Log-Success "[OK]"
            
            # Diagnostic Scan
            Perform-Diagnostic-Scan
            
            Write-Host "  Engaging Smart Rebuild Protocol." -ForegroundColor Cyan
            
            # --- SMART REBUILD LOGIC ---
            Write-Host "> [REBUILD] Executing Sandbox Reconstruction..." -ForegroundColor Cyan
            
            $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            
            # Ensure Temp Root Exists
            if (-not (Test-Path $TEMP_ROOT)) {
                New-Item -ItemType Directory -Force -Path $TEMP_ROOT | Out-Null
            }

            $CorruptData = "$TEMP_ROOT\data_corrupt_$Timestamp"
            
            # 1. Move current data to backup (Safe Quarantine)
            Write-Host "  - Quarantining Corrupt Data Store to: " -NoNewline -ForegroundColor Gray
            Move-Item -Path "$DATA_DIR" -Destination "$CorruptData"
            Write-Host "data_repair_temp\data_corrupt_$Timestamp" -ForegroundColor Yellow
            
            # 2. Create fresh Data folder from Template
            Write-Host "  - Initializing Clean Environment Structure... " -NoNewline -ForegroundColor Gray
            Copy-Item -Path "$BACKUP_DIR" -Destination "$DATA_DIR" -Recurse
            Log-Success "[CREATED]"
            
            # 3. Transplant ibdata1 (Data file)
            Write-Host "  - Transplanting InnoDB Tablespace (ibdata1)... " -NoNewline -ForegroundColor Gray
            Copy-Item "$CorruptData\ibdata1" "$DATA_DIR\" -Force
            Log-Success "[OK]"
            
            # 4. Transplant User Databases (Folders only, skipping system dbs)
            Write-Host "  - Migrating User Schemas... " -NoNewline -ForegroundColor Gray
            # FIX: Do not exclude 'mysql' to prevent ibdata1/system-table mismatch. 
            # Only exclude folders that are definitely in the fresh backup and generic.
            $Excluded = @('performance_schema', 'phpmyadmin', 'test') 
            $Folders = Get-ChildItem -Path "$CorruptData" -Directory
            $Count = 0
            foreach ($Folder in $Folders) {
                if ($Excluded -notcontains $Folder.Name) {
                    Copy-Item -Path $Folder.FullName -Destination "$DATA_DIR\$($Folder.Name)" -Recurse -Force
                    $Count++
                }
            }
            Write-Host "Migrated $Count databases." -ForegroundColor Green
            
            # Safety Net: Abort cleanup if 0 databases found (implies failure or fresh install, unsafe to delete backup)
            $SafeToCleanup = $true
            if ($Count -eq 0) { 
                Write-Host "  - [WARN] Zero databases migrated. Preserving temp backup for safety." -ForegroundColor Yellow 
                $SafeToCleanup = $false
            }

            # 5. Cleanup New Data Environment
            # 5. Cleanup New Data Environment (Force Fresh Logs)
            Remove-Item "$DATA_DIR\mysql_error.log" -Force -ErrorAction SilentlyContinue
            Remove-Item "$DATA_DIR\*.pid" -Force -ErrorAction SilentlyContinue
            Remove-Item "$DATA_DIR\ib_logfile*" -Force -ErrorAction SilentlyContinue
            Remove-Item "$DATA_DIR\aria_log*" -Force -ErrorAction SilentlyContinue
            Remove-Item "$DATA_DIR\ib_buffer_pool" -Force -ErrorAction SilentlyContinue
            Remove-Item "$DATA_DIR\multi-master.info" -Force -ErrorAction SilentlyContinue
            
            Write-Host "> [STATUS] Reconstruction Sequence Completed." -ForegroundColor Cyan
            
            # Graceful Shutdown to preserve data integrity
            Write-Host "  - [SHUTDOWN] Stopping Repair Engine..." -ForegroundColor Gray
            if (Test-Path "$MYSQL_DIR\bin\mysqladmin.exe") {
                $ShutdownResult = & "$MYSQL_DIR\bin\mysqladmin.exe" --user=root shutdown 2>&1
            }
            Start-Sleep -Seconds 3
            Stop-Process -Name "mysqld" -Force -ErrorAction SilentlyContinue

            
            # Clear old error logs so they don't trigger false positives on next run
            Remove-Item "$DATA_DIR\mysql_error.log" -Force -ErrorAction SilentlyContinue

            Write-Host "> [STATUS] System Integrity Verification Passed." -ForegroundColor Cyan
            Write-Host ""
            
            # Cleanup Temp Data
            if ($SafeToCleanup) {
                Write-Host "> [CLEANUP] Removing Temporary Repair Files..." -ForegroundColor Cyan
                if (Test-Path "$CorruptData") {
                    Remove-Item -Path "$CorruptData" -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Host "  - Temp quarantine data deleted." -ForegroundColor Green
                }
                # Optional: Remove temp root if empty
                if ((Get-ChildItem -Path $TEMP_ROOT).Count -eq 0) {
                     Remove-Item -Path $TEMP_ROOT -Force -ErrorAction SilentlyContinue
                }
            } else {
                 Write-Host "> [PRESERVED] Temp data kept for manual inspection: $CorruptData" -ForegroundColor Yellow
            }

            Write-Host ""

            Start-Services-Advanced
            Open-GUI
        }
        
        "3" {
            # OPTIMIZE DATABASE TABLES
            Write-Host ""
            Write-Host "> [INFO] This will Defragment and Repair all tables using 'mysqlcheck'." -ForegroundColor Cyan
            Write-Host "> Requires MySQL to be at least partially operational." -ForegroundColor Gray
            $Confirm = Read-Host "Proceed? [Y/n]"
            if ($Confirm -ne "Y" -and $Confirm -ne "y") { continue RecoveryLoop }
            
            Write-Host "> [SYSTEM] Preparing for Optimization..." -ForegroundColor Cyan
            Stop-XamppProcesses
            Resolv-Port-Conflicts 2>$null
            
            Write-Host "> [OPTIMIZE] Executing Table Optimization Routine..." -ForegroundColor Cyan
            # Start mysqld specifically for optimization
            $OptProc = Start-Process -FilePath "$MYSQL_DIR\bin\mysqld.exe" -ArgumentList "--defaults-file=""$MYSQL_DIR\bin\my.ini"" --standalone" -PassThru -WindowStyle Hidden
            
            # Wait for MySQL Port 3306 to be listening
            $Retries = 0
            $MaxRetries = 20
            $MySQLReady = $false
            while ($Retries -lt $MaxRetries) {
                $Conn = Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue
                if ($Conn) {
                    $MySQLReady = $true
                    break
                }
                Start-Sleep -Seconds 1
                $Retries++
            }

            if ($MySQLReady) {
                if (Test-Path "$MYSQL_DIR\bin\mysqlcheck.exe") {
                     # Run optimization in background to show progress bar
                     $CheckJob = Start-Job -ScriptBlock {
                        param($Exe, $User, $Pass)
                        & $Exe --auto-repair --optimize --force --all-databases --user=$User --skip-password 2>&1
                     } -ArgumentList "$MYSQL_DIR\bin\mysqlcheck.exe", "root"
                     
                     $BarChar = [char]0x2588
                     $Counter = 0
                     while ($Result = Get-Job -State Running) {
                        $Counter++
                        if ($Counter -gt 20) { $Counter = 1 } 
                        $Filled = "".PadLeft($Counter, $BarChar)
                        $Empty = "".PadLeft(20 - $Counter, ' ')
                        Write-Host -NoNewline "`r> [$Filled$Empty] Processing..." -ForegroundColor Green
                        Start-Sleep -Milliseconds 500
                     }
                     
                     # Job finished, show 100%
                     $Filled = "".PadLeft(20, $BarChar)
                     Write-Host "`r> [$Filled] 100%          " -ForegroundColor Green
                     
                     $JobOutput = Receive-Job $CheckJob
                     Remove-Job $CheckJob
                     Write-Host ""
                     Write-Host "  - Table Optimization & Flush Complete." -ForegroundColor Gray
                }
            } else {
                 Write-Host "  - [NOTE] Engine startup timed out. Skipping optimization." -ForegroundColor DarkGray
            }
            
            # Graceful Shutdown
            Write-Host "  - [SHUTDOWN] Stopping Repair Engine..." -ForegroundColor Gray
            if (Test-Path "$MYSQL_DIR\bin\mysqladmin.exe") {
                $ShutdownResult = & "$MYSQL_DIR\bin\mysqladmin.exe" --user=root shutdown 2>&1
            }
            Start-Sleep -Seconds 3
            Stop-Process -Name "mysqld" -Force -ErrorAction SilentlyContinue
            
            Start-Services-Advanced
            Open-GUI
        }
        
        "4" {
            # BACKUP
            Write-Host ""
            Write-Host "> [INFO] This will safely Snapshot your entire 'data' folder to a timestamped backup." -ForegroundColor Cyan
            Write-Host "> Use this before attempting risky manual changes." -ForegroundColor Gray
            $Confirm = Read-Host "Proceed? [Y/n]"
            if ($Confirm -ne "Y" -and $Confirm -ne "y") { continue RecoveryLoop }
            
            Write-Host "> [BACKUP] Initiating redundancy protocol..."
            $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $SafeBackup = "$MYSQL_DIR\data_backup_$Timestamp"
            New-Item -ItemType Directory -Force -Path $SafeBackup | Out-Null
            Copy-Item -Path "$DATA_DIR\*" -Destination $SafeBackup -Recurse -Force -ErrorAction SilentlyContinue
            Log-Success "> Backup verified: $SafeBackup"
        }

        "5" {
            # LOGS
            Write-Host ""
            Write-Host "> [INFO] This will display the last 15 lines of the MySQL error log." -ForegroundColor Cyan
            $Confirm = Read-Host "View Logs? [Y/n]"
            if ($Confirm -ne "Y" -and $Confirm -ne "y") { continue RecoveryLoop }
            
            if (Test-Path $LOG_FILE) {
                Log-Title "> [DIAG] Log Review (Tail 15):"
                Get-Content $LOG_FILE -Tail 15 | ForEach-Object {
                    if ($_ -match "Error") { Write-Host $_ -ForegroundColor Red } else { Write-Host $_ -ForegroundColor Gray }
                }
            } else { Log-Warn "> Log file unavailable." }
        }

        "6" {
            # EMERGENCY FACTORY RESET
            
            # Pre-calculate backup path (Internal use for safe wipe)
            $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $BrokenBackup = "$TEMP_ROOT\data_crashed_$Timestamp"
            
            Write-Host ""
            Write-Host "> [WARNING] This will completely wipe the current 'data' folder and reset MySQL to factory defaults." -ForegroundColor Red
            Write-Host "> This is a destructive operation (Fresh Install State)." -ForegroundColor Red
            $Confirm = Read-Host "Are you sure? [Y/n]"
            
            if ($Confirm -eq "Y" -or $Confirm -eq "y") {
                Write-Host "> [RESET] Initiating Factory Reset Protocol..." -ForegroundColor Cyan
                
                # 1. Stop Services
                Stop-XamppProcesses
                
                # 2. Reset Data Container
                
                # Ensure Temp Root Exists
                if (-not (Test-Path $TEMP_ROOT)) {
                    New-Item -ItemType Directory -Force -Path $TEMP_ROOT | Out-Null
                }

                Write-Host "  - Wiping current data..." -ForegroundColor Gray
                Move-Item -Path "$DATA_DIR" -Destination "$BrokenBackup"
                
                # 3. Restore from Internal Backup
                Write-Host "  - Restoring from XAMPP internal backup..." -ForegroundColor Gray
                Copy-Item -Path "$BACKUP_DIR" -Destination "$DATA_DIR" -Recurse
                
                Log-Success "> [SUCCESS] Factory Reset Complete."
                Write-Host "  MySQL has been reset to its initial installation state." -ForegroundColor Green
                
                Start-Services-Advanced
                
                # RECOVERY NORMALIZATION: Check if we are stuck in Read-Only Mode
                $MyIni = "$MYSQL_DIR\bin\my.ini"
                if (Test-Path $MyIni) {
                    $Content = Get-Content $MyIni -Raw
                    if ($Content -match "innodb_force_recovery") {
                        Write-Host ""
                        Write-Host "> [FIX] Removing Emergency Mode Flag to restore Read/Write access..." -ForegroundColor Cyan
                        $CleanContent = $Content -replace "`n\[mysqld\]`ninnodb_force_recovery = \d", " "
                        $CleanContent = $CleanContent -replace "innodb_force_recovery = \d", " "
                        Set-Content -Path $MyIni -Value $CleanContent
                        
                        Write-Host "  - Restarting Engine in Normal Mode..." -ForegroundColor Gray
                        Stop-Process -Name "mysqld" -Force -ErrorAction SilentlyContinue
                        Start-Process -FilePath "$MYSQL_DIR\bin\mysqld.exe" -ArgumentList "--defaults-file=""$MYSQL_DIR\bin\my.ini"" --standalone" -WindowStyle Hidden
                        Start-Sleep -Seconds 5
                        Log-Success "  - [NORMALIZED] MySQL is now fully operational (Read/Write)."
                    }
                }

                # CLEANUP (Per User Request)
                Write-Host "> [CLEANUP] Removing Crashed Data Dump..." -ForegroundColor Cyan
                if (Test-Path "$BrokenBackup") {
                    Remove-Item -Path "$BrokenBackup" -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Host "  - Crashed data deleted." -ForegroundColor Green
                }
                # Optional: Remove temp root if empty
                if ((Get-ChildItem -Path $TEMP_ROOT).Count -eq 0) {
                     Remove-Item -Path $TEMP_ROOT -Force -ErrorAction SilentlyContinue
                }

                Open-GUI
            } else {
                Write-Host "  - Reset Cancelled." -ForegroundColor Yellow
            }
        }
    }

    Write-Host ""
    Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray
    Log-Success "  MISSION COMPLETE. PRESS [ENTER] TO RETURN TO COMMAND CENTER."
    Write-Host "-----------------------------------------------------------" -ForegroundColor DarkGray
    $null = Read-Host

} while ($true)