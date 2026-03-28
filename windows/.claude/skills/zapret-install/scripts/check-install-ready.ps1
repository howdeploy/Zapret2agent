# check-install-ready.ps1
# Validates prerequisites before installing zapret-win-bundle.
# Output: JSON { ready: bool, blockers: [], warnings: [] }

# Use SilentlyContinue here: pre-flight check where missing components are expected
$ErrorActionPreference = "SilentlyContinue"

# Enforce TLS 1.2+ for GitHub API call
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

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
    if ($_.Exception.Response.StatusCode -eq 403) {
        $blockers += "github_rate_limit: GitHub API rate limit exceeded - wait a few minutes and try again"
    } else {
        $blockers += "no_github: cannot reach GitHub ($($_.Exception.Message)) - check internet connection"
    }
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

# 7. ARM64 check (use RuntimeInformation with WMI fallback)
$isArm64 = $false
try {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    $isArm64 = ($arch -eq [System.Runtime.InteropServices.Architecture]::Arm64)
} catch {
    $cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Architecture
    $isArm64 = ($cpu -eq 12)
}
if ($isArm64) {
    # ARM64 - check if test signing is enabled via registry (locale-independent)
    try {
        $bcdStore = "HKLM:\BCD00000000\Objects\{fa926493-6f1c-4193-a414-58f0b2456d1e}\Elements\16000049"
        $tsValue = (Get-ItemProperty -Path $bcdStore -ErrorAction Stop).Element
        if ($tsValue -ne 1) {
            $blockers += "arm64_no_testsign: ARM64 requires test-signing mode. Run: bcdedit /set testsigning on - then reboot"
        }
    } catch {
        # Fallback: try bcdedit with locale-independent check
        try {
            $bcdedit = & bcdedit /enum "{current}" 2>$null
            if ($bcdedit -notmatch "testsigning\s+(Yes|Да)") {
                $blockers += "arm64_no_testsign: ARM64 requires test-signing mode. Run: bcdedit /set testsigning on - then reboot"
            }
        } catch {
            $warnings += "arm64_testsign_check_failed: could not verify testsigning status"
        }
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
