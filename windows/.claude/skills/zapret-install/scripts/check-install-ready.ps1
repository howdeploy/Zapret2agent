# check-install-ready.ps1
# Validates prerequisites before installing zapret-win-bundle.
# Output: JSON { ready: bool, blockers: [], warnings: [] }

$ErrorActionPreference = "SilentlyContinue"

$blockers = @()
$warnings = @()

# 1. Admin check
$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [System.Security.Principal.WindowsPrincipal]$id
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $blockers += "not_admin: must run as Administrator"
}

# 2. OS architecture
if (-not [System.Environment]::Is64BitOperatingSystem) {
    $blockers += "arch_not_x64: zapret-win-bundle requires 64-bit Windows"
}

# 3. PowerShell version (need 5.0+)
if ($PSVersionTable.PSVersion.Major -lt 5) {
    $blockers += "ps_too_old: PowerShell 5.0+ required, found $($PSVersionTable.PSVersion)"
}

# 4. Internet connectivity (try GitHub)
try {
    $resp = Invoke-WebRequest -Uri "https://api.github.com/repos/bol-van/zapret-win-bundle/releases/latest" `
        -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    if ($resp.StatusCode -ne 200) { throw "status $($resp.StatusCode)" }
} catch {
    $blockers += "no_github: cannot reach GitHub ($($_.Exception.Message)) - check internet connection"
}

# 5. Disk space (need 200 MB free on C:)
$disk = Get-PSDrive -Name "C" -ErrorAction SilentlyContinue
if ($disk) {
    $freeMB = [math]::Round($disk.Free / 1MB)
    if ($freeMB -lt 200) {
        $blockers += "low_disk: not enough space on C: (free: ${freeMB} MB, required: 200 MB)"
    }
} else {
    $warnings += "disk_check_failed: could not check free space on C:"
}

# 6. Check if existing install needs upgrade
$existingInstall = Test-Path "C:\zapret\zapret-winws\winws2.exe"
if ($existingInstall) {
    $warnings += "already_installed: zapret is already installed - will perform upgrade"
}

# 7. ARM64 check
$cpu = (Get-WmiObject Win32_Processor | Select-Object -First 1).Architecture
if ($cpu -eq 12) {
    # ARM64 - check if test signing is enabled
    try {
        $bcdedit = & bcdedit /enum "{current}" 2>$null
        if ($bcdedit -notmatch "testsigning\s+Yes") {
            $blockers += "arm64_no_testsign: ARM64 requires test-signing mode. Run: bcdedit /set testsigning on - then reboot"
        }
    } catch {
        $warnings += "arm64_testsign_check_failed: could not verify testsigning status"
    }
}

$result = [ordered]@{
    ready            = ($blockers.Count -eq 0)
    blockers         = @($blockers)
    warnings         = @($warnings)
    free_disk_mb     = if ($disk) { [math]::Round($disk.Free / 1MB) } else { $null }
    existing_install = $existingInstall
}

$result | ConvertTo-Json
