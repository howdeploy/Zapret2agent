# verify-install.ps1
# Post-installation verification. Checks all components are in place.
# Output: JSON { success, checks: { name, ok, detail }[], errors[] }

# Use SilentlyContinue here: verification script where missing components are expected
$ErrorActionPreference = "SilentlyContinue"

$InstallDir = "C:\zapret"
$checks     = @()
$errors     = @()

function Add-Check($name, $ok, $detail = "") {
    $script:checks += [ordered]@{ name = $name; ok = $ok; detail = $detail }
    if (-not $ok) { $script:errors += "${name}: $detail" }
}

# 1. winws2.exe present
$winws2 = "$InstallDir\zapret-winws\winws2.exe"
Add-Check "winws2_binary" (Test-Path $winws2) `
    (if (Test-Path $winws2) { "found: $winws2" } else { "NOT found: $winws2 - antivirus may have removed it" })

# 2. WinDivert64.sys present
$wdSys = "$InstallDir\zapret-winws\WinDivert64.sys"
Add-Check "windivert_sys" (Test-Path $wdSys) `
    (if (Test-Path $wdSys) { "found" } else { "NOT found - antivirus may have removed WinDivert64.sys" })

# 3. WinDivert.dll present
$wdDll = "$InstallDir\zapret-winws\WinDivert.dll"
Add-Check "windivert_dll" (Test-Path $wdDll) `
    (if (Test-Path $wdDll) { "found" } else { "NOT found" })

# 4. Config file exists
$conf = "$InstallDir\config\zapret.conf"
$confExists = Test-Path $conf
Add-Check "config_file" $confExists `
    (if ($confExists) { (Get-Content $conf -Raw).Trim() } else { "NOT found: $conf" })

# 5. Service exists
$svc = Get-Service -Name "winws2" -ErrorAction SilentlyContinue
Add-Check "service_exists" ($null -ne $svc) `
    (if ($svc) { "exists, status: $($svc.Status)" } else { "winws2 service not found" })

# 6. Service running
$svcRunning = ($svc -and $svc.Status -eq "Running")
Add-Check "service_running" $svcRunning `
    (if ($svcRunning) { "running" } else { "not running - start with: sc start winws2" })

# 7. Lua scripts present
$luaDir = "$InstallDir\zapret-winws\lua"
Add-Check "lua_scripts" (Test-Path "$luaDir\zapret-lib.lua") `
    (if (Test-Path "$luaDir\zapret-lib.lua") { "Lua scripts found" } else { "Lua scripts not found in $luaDir" })

# 8. blockcheck tool present
$bc2 = "$InstallDir\blockcheck\blockcheck2.cmd"
Add-Check "blockcheck_tool" (Test-Path $bc2) `
    (if (Test-Path $bc2) { "found" } else { "NOT found - cannot run strategy autodetect" })

# 9. cygwin bash present (required for blockcheck)
$cygwinBash = "$InstallDir\cygwin\bin\bash.exe"
Add-Check "cygwin_bash" (Test-Path $cygwinBash) `
    (if (Test-Path $cygwinBash) { "found" } else { "NOT found - blockcheck requires cygwin bash" })

$allOk = ($errors.Count -eq 0)

$result = [ordered]@{
    success   = $allOk
    checks    = @($checks)
    errors    = @($errors)
    next_step = if ($allOk) {
        "Install successful! Next: run zapret-config to find optimal strategy."
    } else {
        "Issues found. Check errors list above."
    }
}

$result | ConvertTo-Json -Depth 4
