# manage-service.ps1
# Start, stop, restart, or check status of the winws2 service.
#
# Usage:
#   manage-service.ps1 -Action status
#   manage-service.ps1 -Action start
#   manage-service.ps1 -Action stop
#   manage-service.ps1 -Action restart

param(
    [ValidateSet("status", "start", "stop", "restart")]
    [string]$Action = "status"
)

$ErrorActionPreference = "Stop"
$ServiceName = "winws2"
$LogPath     = "C:\zapret\logs\winws2.log"

function Get-ServiceState {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) { return "absent" }
    return $svc.Status.ToString().ToLower()
}

function Get-RecentLog {
    if (-not (Test-Path $LogPath)) { return $null }
    try {
        $lines = Get-Content $LogPath -Tail 10 -ErrorAction SilentlyContinue
        return ($lines -join "`n")
    } catch { return $null }
}

switch ($Action) {

    "status" {
        $state = Get-ServiceState
        $svc   = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

        $result = [ordered]@{
            service_name = $ServiceName
            status       = $state
            start_type   = if ($svc) { $svc.StartType.ToString() } else { $null }
            recent_log   = Get-RecentLog
            errors       = @()
        }

        if ($state -eq "running") {
            $proc = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
            if ($proc) { $result["pid"] = $proc.ProcessId }
        }

        $result | ConvertTo-Json
    }

    "start" {
        $before = Get-ServiceState

        if ($before -eq "absent") {
            @{
                success = $false
                status  = "absent"
                errors  = @("winws2 service is not installed. Run zapret-install.")
            } | ConvertTo-Json
            return
        }

        if ($before -eq "running") {
            @{
                success = $true
                status  = "running"
                errors  = @()
                message = "Service already running"
            } | ConvertTo-Json
            return
        }

        & sc.exe start $ServiceName | Out-Null
        Start-Sleep -Seconds 3

        $after = Get-ServiceState

        @{
            success = ($after -eq "running")
            status  = $after
            errors  = if ($after -ne "running") { @("Service did not start. Status: $after. Check log: $LogPath") } else { @() }
        } | ConvertTo-Json
    }

    "stop" {
        $before = Get-ServiceState

        if ($before -eq "absent") {
            @{ success = $false; status = "absent"; errors = @("Service not installed") } | ConvertTo-Json
            return
        }

        if ($before -eq "stopped") {
            @{ success = $true; status = "stopped"; errors = @(); message = "Service already stopped" } | ConvertTo-Json
            return
        }

        & sc.exe stop $ServiceName | Out-Null
        Start-Sleep -Seconds 3

        $after = Get-ServiceState

        @{
            success = ($after -eq "stopped")
            status  = $after
            errors  = if ($after -ne "stopped") { @("Failed to stop service. Status: $after") } else { @() }
        } | ConvertTo-Json
    }

    "restart" {
        $stopState = Get-ServiceState
        if ($stopState -eq "running") {
            & sc.exe stop $ServiceName | Out-Null
            Start-Sleep -Seconds 3
        }

        & sc.exe start $ServiceName | Out-Null
        Start-Sleep -Seconds 3

        $final = Get-ServiceState

        @{
            success = ($final -eq "running")
            status  = $final
            errors  = if ($final -ne "running") { @("Service did not start after restart. Status: $final") } else { @() }
        } | ConvertTo-Json
    }
}
