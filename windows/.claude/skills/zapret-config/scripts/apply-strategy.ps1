# apply-strategy.ps1
# Writes new winws2 args to zapret.conf and recreates the service atomically.
# Must run as Administrator.
# Output: JSON { success, applied_args, service_started, errors[] }

param(
    [Parameter(Mandatory=$true)]
    [string]$WinArgs
)

$ErrorActionPreference = "Stop"

$ConfigPath  = "C:\zapret\config\zapret.conf"
$ConfigDir   = "C:\zapret\config"
$ServiceName = "winws2"
$errors      = @()

# Security: validate winws2 args contain no shell metacharacters
function Test-SafeWinwsArgs([string]$args_str) {
    $dangerous = '[&|><;%\^!`\$\(\)\{\}]'
    return -not ($args_str -match $dangerous)
}

try {
    # Validate args
    if ([string]::IsNullOrWhiteSpace($WinArgs)) {
        throw "winws2 args cannot be empty"
    }

    if (-not (Test-SafeWinwsArgs $WinArgs)) {
        throw "SECURITY: args contain dangerous characters (& | > < ; % ^ !). Refusing to apply. Check input for tampering."
    }

    # Ensure config dir exists
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null

    # Write new config atomically (write to temp, then move — Move-Item -Force replaces target)
    $tempPath = "$ConfigPath.tmp"
    $WinArgs.Trim() | Set-Content $tempPath -Encoding UTF8
    Move-Item $tempPath $ConfigPath -Force

    # Stop service
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    # Recreate service with new args
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $createScript = Join-Path (Split-Path $scriptDir -Parent) "..\zapret-install\scripts\create-service.ps1"
    $createScript = [System.IO.Path]::GetFullPath($createScript)

    if (Test-Path $createScript) {
        $createResult = & $createScript | ConvertFrom-Json
        $serviceStarted = $createResult.started
        if (-not $serviceStarted -and $createResult.errors) {
            $errors += $createResult.errors
        }
    } else {
        # Fallback: restart existing service
        Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $svc2 = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        $serviceStarted = ($null -ne $svc2 -and $svc2.Status -eq "Running")
        if (-not $serviceStarted) {
            $errors += "service_not_started: service did not start after applying strategy"
        }
    }

    @{
        success         = ($errors.Count -eq 0)
        applied_args    = $WinArgs.Trim()
        service_started = $serviceStarted
        config_path     = $ConfigPath
        errors          = @($errors)
    } | ConvertTo-Json

} catch {
    @{
        success         = $false
        applied_args    = $WinArgs
        service_started = $false
        config_path     = $ConfigPath
        errors          = @($_.Exception.Message)
    } | ConvertTo-Json
}
