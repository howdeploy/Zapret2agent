# safe-mode.ps1
# Registers a Windows Scheduled Task that auto-stops winws2 service after N minutes.
# Use BEFORE applying new config. Confirm=cancel cancels the timer.
#
# Usage:
#   safe-mode.ps1 -Action arm   -Minutes 3    # set rollback timer
#   safe-mode.ps1 -Action cancel              # cancel timer (config OK)
#   safe-mode.ps1 -Action status              # check if timer is active

param(
    [ValidateSet("arm", "cancel", "status")]
    [string]$Action = "status",
    [int]$Minutes = 3
)

$ErrorActionPreference = "Stop"
$TaskName = "Zapret2_SafeMode_Rollback"

function Get-TaskStatus {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) { return @{ active = $false } }

    $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
    $nextRun = if ($info) { $info.NextRunTime.ToString("HH:mm:ss") } else { $null }

    return @{
        active   = $true
        state    = $task.State.ToString()
        next_run = $nextRun
    }
}

switch ($Action) {

    "arm" {
        # Remove existing task if any
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

        $triggerTime = (Get-Date).AddMinutes($Minutes)

        # Action: stop the winws2 service
        $taskAction = New-ScheduledTaskAction `
            -Execute "sc.exe" `
            -Argument "stop winws2"

        $trigger = New-ScheduledTaskTrigger `
            -Once `
            -At $triggerTime

        $settings = New-ScheduledTaskSettingsSet `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 1) `
            -StartWhenAvailable

        $principal = New-ScheduledTaskPrincipal `
            -UserId "SYSTEM" `
            -LogonType ServiceAccount `
            -RunLevel Highest

        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $taskAction `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Force | Out-Null

        $result = @{
            action    = "armed"
            message   = "Rollback timer set: winws2 will stop at $($triggerTime.ToString('HH:mm:ss')) if not cancelled"
            fires_at  = $triggerTime.ToString("HH:mm:ss")
            minutes   = $Minutes
        }
        $result | ConvertTo-Json
    }

    "cancel" {
        $existed = (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) -ne $null
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

        $result = @{
            action  = "cancelled"
            message = if ($existed) { "Rollback timer cancelled — config confirmed OK" } else { "No active timer found" }
        }
        $result | ConvertTo-Json
    }

    "status" {
        $status = Get-TaskStatus
        $status | ConvertTo-Json
    }
}
