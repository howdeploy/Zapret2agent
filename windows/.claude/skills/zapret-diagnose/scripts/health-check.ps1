# health-check.ps1
# Quick aggregated health summary. Calls detect-state.ps1 internally.
# Output: JSON with overall_status and list of issues.

$ErrorActionPreference = "SilentlyContinue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Run full diagnostics
$stateJson = & powershell -ExecutionPolicy Bypass -File "$scriptDir\detect-state.ps1"
$state = $stateJson | ConvertFrom-Json

$issues  = @()
$overall = "healthy"

# --- Evaluate ---
if (-not $state.is_admin) {
    $issues += "not_admin: terminal must be run as Administrator"
    $overall = "error"
}

if (-not $state.zapret_installed) {
    $issues += "not_installed: zapret not found at C:\zapret"
    $overall = "not_installed"
} else {
    if (-not $state.windivert_present) {
        $issues += "windivert_missing: WinDivert64.sys not found - possibly removed by antivirus"
        $overall = "error"
    }

    switch ($state.service_status) {
        "absent"  {
            $issues += "service_absent: winws2 service not created"
            if ($overall -eq "healthy") { $overall = "degraded" }
        }
        "stopped" {
            $issues += "service_stopped: winws2 service is stopped"
            if ($overall -eq "healthy") { $overall = "degraded" }
        }
        "running" {
            # good
        }
        default {
            $issues += "service_unknown: service status is '$($state.service_status)'"
            if ($overall -eq "healthy") { $overall = "degraded" }
        }
    }

    if (-not $state.config_exists) {
        $issues += "no_config: config file C:\zapret\config\zapret.conf not found"
        if ($overall -eq "healthy") { $overall = "degraded" }
    }
}

if ($state.antivirus.Count -gt 0) {
    $avList = $state.antivirus -join ", "
    $issues += "antivirus_detected: antivirus found ($avList) - ensure C:\zapret is in exclusions"
    # Not an error, just a warning
}

if ($state.dns_hijacked) {
    # DNS hijacking IS critical - zapret won't bypass DNS-blocked sites without DNS fix
    $issues += "dns_hijacked: ISP is hijacking DNS for blocked sites - zapret alone won't help, DNS fix required"
    if ($overall -eq "healthy") { $overall = "degraded" }
}

# Build result
$result = [ordered]@{
    overall_status   = $overall
    issues           = @($issues)
    service_status   = $state.service_status
    zapret_installed = $state.zapret_installed
    is_admin         = $state.is_admin
    vpn_detected     = $state.vpn_detected
    vpn_type         = $state.vpn_type
    dns_hijacked     = $state.dns_hijacked
    current_mode     = $state.current_mode
    current_config   = $state.current_config
}

$result | ConvertTo-Json -Depth 3
