# detect-state.ps1
# Outputs JSON with full Windows system state for zapret agent.
# No side effects. Safe to run without confirmation.

$ErrorActionPreference = "SilentlyContinue"

function Get-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]$id
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Arch {
    if ([System.Environment]::Is64BitOperatingSystem) {
        $cpu = (Get-WmiObject Win32_Processor | Select-Object -First 1).Architecture
        # 12 = ARM64
        if ($cpu -eq 12) { return "arm64" }
        return "x64"
    }
    return "x86"
}

function Get-VpnInfo {
    $result = @{ detected = $false; type = $null; interface = $null }

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

    foreach ($a in $adapters) {
        $desc = $a.InterfaceDescription.ToLower()
        $name = $a.Name.ToLower()

        if ($desc -match "wireguard" -or $name -match "wireguard") {
            $result.detected = $true; $result.type = "wireguard"; $result.interface = $a.Name; break
        }
        if ($desc -match "openvpn|tap-windows|tap adapter" -or $name -match "openvpn") {
            $result.detected = $true; $result.type = "openvpn"; $result.interface = $a.Name; break
        }
        if ($desc -match "outline|v2ray|xray|sing-box" -or $name -match "tun\d|utun") {
            $result.detected = $true; $result.type = "other"; $result.interface = $a.Name; break
        }
    }

    # Check running VPN services
    if (-not $result.detected) {
        $vpnServices = @("WireGuardTunnel*", "OpenVPNService*", "OutlineService")
        foreach ($svc in $vpnServices) {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue | Where-Object Status -eq "Running" | Select-Object -First 1
            if ($s) {
                $result.detected = $true
                if ($s.Name -match "WireGuard") { $result.type = "wireguard" }
                elseif ($s.Name -match "OpenVPN") { $result.type = "openvpn" }
                else { $result.type = "other" }
                break
            }
        }
    }
    return $result
}

function Get-DnsHijacked {
    # Compare resolution of a known blocked domain via system DNS vs Google 8.8.8.8
    # If results have no overlap, ISP is hijacking DNS for this domain
    try {
        $testDomain = "rutracker.org"
        $sysResult    = Resolve-DnsName $testDomain -Type A -ErrorAction Stop
        $googleResult = Resolve-DnsName $testDomain -Type A -Server "8.8.8.8" -ErrorAction Stop

        $sysIPs    = @($sysResult    | Where-Object { $_.Type -eq 'A' } | Select-Object -ExpandProperty IPAddress)
        $googleIPs = @($googleResult | Where-Object { $_.Type -eq 'A' } | Select-Object -ExpandProperty IPAddress)

        if ($sysIPs.Count -gt 0 -and $googleIPs.Count -gt 0) {
            $overlap = $sysIPs | Where-Object { $googleIPs -contains $_ }
            if ($overlap.Count -eq 0) { return $true }
        }
    } catch {}
    return $false
}

function Get-ActiveAdapter {
    $gw = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
          Sort-Object RouteMetric | Select-Object -First 1
    if ($gw) {
        $adapter = Get-NetAdapter -InterfaceIndex $gw.ifIndex -ErrorAction SilentlyContinue
        return $adapter.Name
    }
    return $null
}

function Get-AntivirusProducts {
    $avList = @()
    try {
        $avProducts = Get-WmiObject -Namespace "root\SecurityCenter2" -Class "AntiVirusProduct" -ErrorAction Stop
        foreach ($av in $avProducts) {
            $avList += $av.displayName
        }
    } catch {}
    if ($avList.Count -eq 0) {
        # Fallback: check known AV services
        $knownAV = @("WinDefend", "MsMpSvc", "kavfsgt", "avp", "avgnt", "bdagent", "ekrn")
        foreach ($svcName in $knownAV) {
            $s = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($s) { $avList += $svcName }
        }
    }
    return $avList
}

# --- Collect data ---

$zapretPath     = "C:\zapret"
$winws2Path     = "$zapretPath\zapret-winws\winws2.exe"
$windivertPath  = "$zapretPath\zapret-winws\WinDivert64.sys"
$configPath     = "$zapretPath\config\zapret.conf"
$modePath       = "$zapretPath\config\mode.txt"

$zapretInstalled = (Test-Path $winws2Path)
$windivertPresent = (Test-Path $windivertPath)

$serviceStatus = "absent"
$svc = Get-Service -Name "winws2" -ErrorAction SilentlyContinue
if ($svc) {
    $serviceStatus = $svc.Status.ToString().ToLower()
}

$configExists  = (Test-Path $configPath)
$currentConfig = if ($configExists) { (Get-Content $configPath -Raw).Trim() } else { $null }
$currentMode   = if (Test-Path $modePath) { (Get-Content $modePath -Raw).Trim() } else { "unknown" }

$os = (Get-WmiObject Win32_OperatingSystem)
$osCaption  = $os.Caption
$osVersion  = $os.Version
$psVersion  = "$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"

$vpnInfo    = Get-VpnInfo
$dnsHijack  = Get-DnsHijacked
$activeAd   = Get-ActiveAdapter
$antivirus  = Get-AntivirusProducts

$allAdapters = Get-NetAdapter | Where-Object Status -eq "Up" | ForEach-Object {
    @{ name = $_.Name; description = $_.InterfaceDescription; status = $_.Status.ToString() }
}

$dnsCfg = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Where-Object { $_.ServerAddresses.Count -gt 0 } |
          Select-Object -First 1 -ExpandProperty ServerAddresses |
          Select-Object -First 1

# --- Output JSON ---
$state = [ordered]@{
    os                = $osCaption
    os_version        = $osVersion
    arch              = Get-Arch
    ps_version        = $psVersion
    is_admin          = (Get-IsAdmin)
    zapret_installed  = $zapretInstalled
    zapret_path       = if ($zapretInstalled) { $zapretPath } else { $null }
    winws2_path       = if ($zapretInstalled) { $winws2Path } else { $null }
    windivert_present = $windivertPresent
    service_status    = $serviceStatus
    vpn_detected      = $vpnInfo.detected
    vpn_type          = $vpnInfo.type
    vpn_interface     = $vpnInfo.interface
    dns_hijacked      = $dnsHijack
    dns_server        = $dnsCfg
    active_adapter    = $activeAd
    network_adapters  = @($allAdapters)
    antivirus         = @($antivirus)
    current_mode      = $currentMode
    config_exists     = $configExists
    current_config    = $currentConfig
}

$state | ConvertTo-Json -Depth 5
