# backup-config.ps1
# Backup or restore C:\zapret\config\zapret.conf
# Usage:
#   backup-config.ps1 -Action backup   # create timestamped backup
#   backup-config.ps1 -Action restore  # restore most recent backup
#   backup-config.ps1 -Action list     # list available backups
#
# Output: JSON { success, backup_path, errors[] }

param(
    [ValidateSet("backup", "restore", "list")]
    [string]$Action = "backup"
)

$ErrorActionPreference = "SilentlyContinue"

$ConfigPath  = "C:\zapret\config\zapret.conf"
$BackupDir   = "C:\zapret\backups"
$MaxBackups  = 20

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

switch ($Action) {

    "backup" {
        if (-not (Test-Path $ConfigPath)) {
            @{ success = $false; backup_path = $null; errors = @("Config file not found: $ConfigPath") } | ConvertTo-Json
            return
        }

        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$BackupDir\zapret.conf.$stamp"

        Copy-Item $ConfigPath $backupPath -Force

        # Rotate: keep only MaxBackups most recent
        $existing = Get-ChildItem "$BackupDir\zapret.conf.*" | Sort-Object LastWriteTime -Descending
        if ($existing.Count -gt $MaxBackups) {
            $existing | Select-Object -Skip $MaxBackups | Remove-Item -Force
        }

        @{
            success     = $true
            backup_path = $backupPath
            content     = (Get-Content $ConfigPath -Raw).Trim()
            errors      = @()
        } | ConvertTo-Json
    }

    "restore" {
        $backups = Get-ChildItem "$BackupDir\zapret.conf.*" | Sort-Object LastWriteTime -Descending
        if ($backups.Count -eq 0) {
            @{ success = $false; backup_path = $null; errors = @("No backups found in $BackupDir") } | ConvertTo-Json
            return
        }

        $latest = $backups[0]
        Copy-Item $latest.FullName $ConfigPath -Force

        @{
            success     = $true
            backup_path = $latest.FullName
            content     = (Get-Content $ConfigPath -Raw).Trim()
            errors      = @()
        } | ConvertTo-Json
    }

    "list" {
        $backups = Get-ChildItem "$BackupDir\zapret.conf.*" -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending |
                   ForEach-Object {
                       @{
                           path    = $_.FullName
                           date    = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                           content = (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue).Trim()
                       }
                   }

        @{
            success = $true
            count   = @($backups).Count
            backups = @($backups)
            errors  = @()
        } | ConvertTo-Json -Depth 4
    }
}
