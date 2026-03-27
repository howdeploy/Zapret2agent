# parse-blockcheck-summary.ps1
# Parses blockcheck2 output log and extracts working bypass strategies.
# Handles the new blockcheck2 format with !!!!! AVAILABLE !!!!! markers.
# Output: JSON { strategies: [], best_strategy, dns_hijack_warning, errors[] }

param(
    [Parameter(Mandatory=$true)]
    [string]$LogPath
)

$ErrorActionPreference = "SilentlyContinue"

if (-not (Test-Path $LogPath)) {
    @{
        strategies        = @()
        best_strategy     = $null
        dns_hijack_warning = $false
        errors            = @("Log file not found: $LogPath")
    } | ConvertTo-Json
    return
}

$lines = Get-Content $LogPath -ErrorAction SilentlyContinue
if (-not $lines -or $lines.Count -eq 0) {
    @{
        strategies        = @()
        best_strategy     = $null
        dns_hijack_warning = $false
        errors            = @("Log file is empty: $LogPath")
    } | ConvertTo-Json
    return
}

# --- Parse ---
$httpStrategies = @()
$tlsStrategies  = @()
$quicStrategies = @()
$dnsHijackWarning = $false
$errors = @()

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]

    # Detect DNS hijack warning from blockcheck
    if ($line -match 'POSSIBLE DNS HIJACK DETECTED') {
        $dnsHijackWarning = $true
    }

    # Find AVAILABLE marker, then grab the next strategy line
    if ($line -match '!!!!! AVAILABLE !!!!!') {
        for ($j = $i + 1; $j -lt [Math]::Min($i + 4, $lines.Count); $j++) {
            $next = $lines[$j].Trim()
            if ($next -match '^\-\s+curl_test_(\w+)\s[^:]+:\s+winws2\s+(.+)$') {
                $testType  = $Matches[1].ToLower()   # http, tls12, tls13, quic, etc.
                $winws2Args = $Matches[2].Trim()

                # Extract --lua-desync value (may appear multiple times; take all)
                $desyncValues = @()
                $winws2Args | Select-String '--lua-desync=(\S+)' -AllMatches | ForEach-Object {
                    $_.Matches | ForEach-Object { $desyncValues += $_.Groups[1].Value }
                }
                $luaDesync = $desyncValues -join ':'

                if (-not $luaDesync) { break }

                $entry = @{
                    lua_desync = $luaDesync
                    test_type  = $testType
                    raw_args   = $winws2Args
                }

                if ($testType -match 'quic') {
                    if ($quicStrategies.lua_desync -notcontains $luaDesync) { $quicStrategies += $entry }
                } elseif ($testType -match 'tls') {
                    if ($tlsStrategies.lua_desync -notcontains $luaDesync) { $tlsStrategies += $entry }
                } else {
                    if ($httpStrategies.lua_desync -notcontains $luaDesync) { $httpStrategies += $entry }
                }
                break
            }
        }
    }
}

# --- Select best strategies ---

# Priority for HTTP/TLS: prefer strategies with tcp_md5 (most reliable fooling method),
# then fakedsplit, fakeddisorder, multidisorder, multisplit, fake
function Select-BestDesync($strategyList) {
    if ($strategyList.Count -eq 0) { return $null }

    $priorities = @(
        { param($s) $s.lua_desync -match 'fakedsplit' -and $s.lua_desync -match 'tcp_md5' },
        { param($s) $s.lua_desync -match 'fakeddisorder' -and $s.lua_desync -match 'tcp_md5' },
        { param($s) $s.lua_desync -match 'fakedsplit' },
        { param($s) $s.lua_desync -match 'fakeddisorder' },
        { param($s) $s.lua_desync -match 'multidisorder' },
        { param($s) $s.lua_desync -match 'multisplit' },
        { param($s) $s.lua_desync -match 'syndata' },
        { param($s) $s.lua_desync -match 'fake' },
        { param($s) $true }  # fallback: first available
    )

    foreach ($test in $priorities) {
        $match = $strategyList | Where-Object { & $test $_ } | Select-Object -First 1
        if ($match) { return $match }
    }
    return $null
}

$bestHttp  = Select-BestDesync $httpStrategies
$bestTls   = Select-BestDesync $tlsStrategies
$bestQuic  = Select-BestDesync $quicStrategies

# Build full service config from best strategies
function Build-ServiceConfig($httpEntry, $tlsEntry, $quicEntry) {
    $httpDesync = if ($httpEntry) { $httpEntry.lua_desync } else { $null }
    $tlsDesync  = if ($tlsEntry)  { $tlsEntry.lua_desync  }
                  elseif ($httpEntry) { $httpEntry.lua_desync }  # fall back to HTTP strategy for TLS
                  else { $null }
    $quicDesync = if ($quicEntry) { $quicEntry.lua_desync } else { "fake" }

    if (-not $tlsDesync -and -not $httpDesync) { return $null }

    $parts = @()
    $parts += "--wf-tcp=80,443 --wf-udp=443,50000-65535"

    if ($httpDesync) {
        $parts += "--filter-tcp=80 --payload=http_req --lua-desync=$httpDesync"
    }

    if ($tlsDesync) {
        $parts += "--filter-tcp=443 --filter-l7=tls --lua-desync=$tlsDesync"
    }

    if ($quicDesync) {
        $quicPath = "C:\zapret\zapret-winws\files\quic_initial_www_google_com.bin"
        if (Test-Path $quicPath) {
            $parts += "--filter-l7=quic --lua-desync=$quicDesync --dpi-desync-fake-quic=`"$quicPath`""
        } else {
            $parts += "--filter-l7=quic --lua-desync=$quicDesync"
        }
    }

    return $parts -join " --new "
}

$fullConfig = Build-ServiceConfig $bestHttp $bestTls $bestQuic

# --- Compile results ---
$allStrategies = @()
foreach ($s in $httpStrategies)  { $allStrategies += @{ type = "http";  lua_desync = $s.lua_desync; raw_args = $s.raw_args } }
foreach ($s in $tlsStrategies)   { $allStrategies += @{ type = "tls";   lua_desync = $s.lua_desync; raw_args = $s.raw_args } }
foreach ($s in $quicStrategies)  { $allStrategies += @{ type = "quic";  lua_desync = $s.lua_desync; raw_args = $s.raw_args } }

$totalFound = $httpStrategies.Count + $tlsStrategies.Count + $quicStrategies.Count

if ($totalFound -eq 0) {
    if ($dnsHijackWarning) {
        $errors += "dns_hijack: ISP DNS hijacking detected - fix DNS first, then re-run blockcheck"
    } else {
        $errors += "no_strategies: blockcheck found no working strategies for this network"
    }
}

$bestStrategyInfo = $null
if ($fullConfig) {
    $bestSource = if ($bestTls) { "tls" } elseif ($bestHttp) { "http" } else { $null }
    $bestDesync = if ($bestTls) { $bestTls.lua_desync } elseif ($bestHttp) { $bestHttp.lua_desync } else { $null }
    $bestStrategyInfo = @{
        source      = $bestSource
        lua_desync  = $bestDesync
        full_config = $fullConfig
    }
}

@{
    strategies         = @($allStrategies)
    best_strategy      = $bestStrategyInfo
    http_count         = $httpStrategies.Count
    tls_count          = $tlsStrategies.Count
    quic_count         = $quicStrategies.Count
    dns_hijack_warning = $dnsHijackWarning
    log_path           = $LogPath
    errors             = @($errors)
} | ConvertTo-Json -Depth 4
