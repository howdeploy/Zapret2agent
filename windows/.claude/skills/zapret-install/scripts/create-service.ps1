# create-service.ps1
# Creates (or recreates) the winws2 Windows service from C:\zapret\config\zapret.conf.
# Must run as Administrator.
# Output: JSON { success, service_name, command_used, errors[] }

$ErrorActionPreference = "SilentlyContinue"

$InstallDir  = "C:\zapret\zapret-winws"
$ConfigPath  = "C:\zapret\config\zapret.conf"
$ServiceName = "winws2"
$DisplayName = "Zapret2 DPI Bypass"
$LogDir      = "C:\zapret\logs"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$errors = @()

try {
    # Read config
    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }
    $winws2Args = (Get-Content $ConfigPath -Raw -ErrorAction Stop).Trim()
    if ([string]::IsNullOrWhiteSpace($winws2Args)) {
        throw "Config file is empty: $ConfigPath"
    }

    $winws2Exe = "$InstallDir\winws2.exe"
    if (-not (Test-Path $winws2Exe)) {
        throw "winws2.exe not found: $winws2Exe - run zapret-install first"
    }

    # Delete existing service
    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.Status -eq "Running") {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        & sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 1
    }

    # Build service wrapper:
    # winws2.exe needs to run from its own directory (WinDivert.dll must be in same folder)
    $wrapperPath = "C:\zapret\config\service-wrapper.cmd"
    $wrapperContent = "@echo off`r`ncd /d `"$InstallDir`"`r`nwinws2.exe $winws2Args >> `"$LogDir\winws2.log`" 2>&1`r`n"
    [System.IO.File]::WriteAllText($wrapperPath, $wrapperContent, [System.Text.Encoding]::ASCII)

    $binPath = "cmd.exe /c `"$wrapperPath`""

    & sc.exe create $ServiceName `
        binPath= $binPath `
        start= auto `
        displayname= $DisplayName | Out-Null

    & sc.exe description $ServiceName "DPI bypass for Russian internet restrictions (zapret2 + WinDivert)" | Out-Null

    # Restart on failure: 3 attempts, 5 seconds apart
    & sc.exe failure $ServiceName reset= 60 actions= restart/5000/restart/5000/restart/5000 | Out-Null

    & sc.exe config $ServiceName obj= LocalSystem | Out-Null

    # Start service
    & sc.exe start $ServiceName 2>&1 | Out-Null
    Start-Sleep -Seconds 3

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    $started = ($svc -and $svc.Status -eq "Running")

    if (-not $started) {
        $evt = Get-EventLog -LogName System -Source "Service Control Manager" -Newest 5 -ErrorAction SilentlyContinue |
               Where-Object { $_.Message -match $ServiceName } |
               Select-Object -First 1
        if ($evt) {
            $errors += "service_start_failed: $($evt.Message)"
        } else {
            $errors += "service_start_failed: service created but not running - check: sc query winws2"
        }
    }

    $result = [ordered]@{
        success      = ($errors.Count -eq 0 -and $started)
        service_name = $ServiceName
        service_path = $wrapperPath
        args_used    = $winws2Args
        started      = $started
        errors       = @($errors)
    }

} catch {
    $result = [ordered]@{
        success      = $false
        service_name = $ServiceName
        service_path = $null
        args_used    = $null
        started      = $false
        errors       = @($_.Exception.Message)
    }
}

$result | ConvertTo-Json
