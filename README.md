# XAMPP MySQL Repair Tool

A simple, one-click solution for the common "MySQL shutdown unexpectedly" error in XAMPP.

## 🚀 How to Use
1. **Close XAMPP Control Panel** (or stop the MySQL service).
2. **Double-click** `fix_mysql.bat`.
3. Wait for the **"SUCCESS"** message.
4. Open XAMPP and click **Start** on MySQL.

## 🛠️ What it Fixes
This tool automates the manual repair steps usually required when MySQL crashes:
- **Stops Stuck Processes:** Kills background `mysqld.exe` instances that lock files.
- **Resets Aria Logs:** Renames the corrupted `aria_log_control` file so MySQL can regenerate it.
- **Restores System DB:** Replaces the core `mysql` configuration folder with a fresh version from the XAMPP backup.

## ⚠️ Important Information
- **Root Password:** Your MySQL `root` password will be reset to **empty** (the default).
- **Users:** Custom user accounts (other than `root`) will need to be recreated.
- **Data Safety:** **Your databases are safe.** This tool does NOT touch your InnoDB data (`ibdata1`) or your project database folders.

## 🛑 Troubleshooting
If you see an **"Access Denied"** error:
This means Windows has locked the XAMPP folders. Simply right-click `fix_mysql.bat` and select **"Run as administrator"** just once to override the lock.