# create-service.ps1
# Creates (or recreates) the winws2 Windows service from C:\zapret\config\zapret.conf.
# Must run as Administrator.
# Output: JSON { success, service_name, command_used, errors[] }

$ErrorActionPreference = "Stop"

$InstallDir  = "C:\zapret\zapret-winws"
$ConfigPath  = "C:\zapret\config\zapret.conf"
$ServiceName = "winws2"
$DisplayName = "Zapret2 DPI Bypass"
$LogDir      = "C:\zapret\logs"

# --- Security: validate winws2 args contain no shell metacharacters ---
function Test-SafeWinwsArgs([string]$args_str) {
    # Allowed: --flags, alphanumeric, hyphens, underscores, equals, colons, dots, commas,
    # forward/back slashes (paths), spaces, quotes (for paths with spaces)
    # Blocked: & | > < ; % ^ ! ` $( ) { } — cmd.exe/powershell metacharacters
    $dangerous = '[&|><;%\^!`\$\(\)\{\}]'
    if ($args_str -match $dangerous) {
        return $false
    }
    return $true
}

# --- Security: check admin privileges ---
$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [System.Security.Principal.WindowsPrincipal]$id
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [ordered]@{
        success      = $false
        service_name = $ServiceName
        service_path = $null
        args_used    = $null
        started      = $false
        errors       = @("Must run as Administrator")
    } | ConvertTo-Json
    return
}

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

    # CRITICAL: validate args before interpolating into service command
    if (-not (Test-SafeWinwsArgs $winws2Args)) {
        throw "SECURITY: config contains dangerous characters (& | > < ; % ^ ! `` `$). Refusing to create service. Check $ConfigPath for tampering."
    }

    $winws2Exe = "$InstallDir\winws2.exe"
    if (-not (Test-Path $winws2Exe)) {
        throw "winws2.exe not found: $winws2Exe - run zapret-install first"
    }

    # Delete existing service (wait for actual deletion)
    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.Status -eq "Running") {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        & sc.exe delete $ServiceName | Out-Null
        # Wait until service is actually deleted (up to 10s)
        for ($i = 0; $i -lt 10; $i++) {
            $check = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if (-not $check) { break }
            Start-Sleep -Seconds 1
        }
    }

    # Register winws2.exe directly with sc.exe (no cmd.exe wrapper — eliminates injection vector)
    # winws2.exe needs WinDivert.dll in same folder — use full path so it resolves correctly
    $binPath = "`"$winws2Exe`" $winws2Args"

    & sc.exe create $ServiceName `
        binPath= $binPath `
        start= auto `
        displayname= $DisplayName | Out-Null

    & sc.exe description $ServiceName "DPI bypass for Russian internet restrictions (zapret2 + WinDivert)" | Out-Null

    # Restart on failure: 3 attempts, 5 seconds apart
    & sc.exe failure $ServiceName reset= 60 actions= restart/5000/restart/5000/restart/5000 | Out-Null

    # Harden config directory ACL — only Administrators can write
    try {
        $acl = Get-Acl "C:\zapret\config"
        $acl.SetAccessRuleProtection($true, $false)
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "NT AUTHORITY\SYSTEM", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
        $usersRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Users", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.SetAccessRule($adminRule)
        $acl.SetAccessRule($systemRule)
        $acl.SetAccessRule($usersRule)
        Set-Acl "C:\zapret\config" $acl
    } catch {
        $errors += "acl_warning: could not harden config directory permissions"
    }

    # Start service
    & sc.exe start $ServiceName 2>&1 | Out-Null
    Start-Sleep -Seconds 3

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    $started = ($null -ne $svc -and $svc.Status -eq "Running")

    if (-not $started) {
        $evt = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'} `
               -MaxEvents 10 -ErrorAction SilentlyContinue |
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
        command_used = $binPath
        args_used    = $winws2Args
        started      = $started
        errors       = @($errors)
    }

} catch {
    $result = [ordered]@{
        success      = $false
        service_name = $ServiceName
        command_used = $null
        args_used    = $null
        started      = $false
        errors       = @($_.Exception.Message)
    }
}

$result | ConvertTo-Json
