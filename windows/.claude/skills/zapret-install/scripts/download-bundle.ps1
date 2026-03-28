# download-bundle.ps1
# Downloads latest zapret-win-bundle from GitHub and extracts to C:\zapret.
# Must run as Administrator.
# Output: JSON { success, version, extracted_to, errors[] }

$ErrorActionPreference = "Stop"

# Enforce TLS 1.2+ (PS 5.1 defaults to TLS 1.0 which GitHub rejects)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$InstallDir = "C:\zapret"
$TempDir    = "$env:TEMP\zapret-install"
$ZipPath    = "$TempDir\zapret-win-bundle.zip"

$errors = @()
$version = $null

try {
    # Create temp dir
    New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

    # Get latest release info
    $releaseUrl = "https://api.github.com/repos/bol-van/zapret-win-bundle/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $releaseUrl -UseBasicParsing -TimeoutSec 30
    } catch {
        if ($_.Exception.Response.StatusCode -eq 403) {
            throw "GitHub API rate limit exceeded. Wait a few minutes and try again, or use a VPN."
        }
        throw
    }

    $version = $release.tag_name

    # Find zip asset
    $asset = $release.assets | Where-Object { $_.name -match "\.zip$" } | Select-Object -First 1

    if (-not $asset) {
        throw "No .zip asset found in release $version. Check https://github.com/bol-van/zapret-win-bundle/releases manually."
    }

    $downloadUrl = $asset.browser_download_url

    # Download with TLS 1.2
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($downloadUrl, $ZipPath)

    # Verify download integrity — check file is a valid ZIP (PK header)
    $header = [System.IO.File]::ReadAllBytes($ZipPath)[0..1]
    if ($header[0] -ne 0x50 -or $header[1] -ne 0x4B) {
        throw "Downloaded file is not a valid ZIP archive. Possible network corruption or MITM. Re-download or check antivirus."
    }

    # Log SHA256 for audit trail
    $hash = (Get-FileHash $ZipPath -Algorithm SHA256).Hash
    $errors += "info: downloaded $($asset.name) v$version SHA256=$hash"

    # Stop service if running (for upgrade)
    $svc = Get-Service -Name "winws2" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Stop-Service -Name "winws2" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    # Backup existing config if upgrading
    if (Test-Path "$InstallDir\config") {
        $backupDir = "$InstallDir\backups\pre-upgrade-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item "$InstallDir\config" $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Extract zip
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Determine what's inside the zip (source zip has a wrapper folder)
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    $firstEntry = $zip.Entries[0].FullName
    $zip.Dispose()

    $extractTemp = "$TempDir\extracted"
    if (Test-Path $extractTemp) { Remove-Item $extractTemp -Recurse -Force }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $extractTemp)

    # Find the actual bundle root (handles wrapper folder from source zip)
    $bundleRoot = $extractTemp
    $subDirs = Get-ChildItem -Directory $extractTemp
    if ($subDirs.Count -eq 1 -and (Test-Path "$($subDirs[0].FullName)\zapret-winws")) {
        $bundleRoot = $subDirs[0].FullName
    }

    # Copy to install dir (preserve config\ if exists)
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    }

    Get-ChildItem $bundleRoot | ForEach-Object {
        $destPath = Join-Path $InstallDir $_.Name
        if ($_.Name -eq "config") { return }  # Never overwrite config on upgrade
        if (Test-Path $destPath) { Remove-Item $destPath -Recurse -Force }
        Copy-Item $_.FullName $destPath -Recurse -Force
    }

    # Create required directories
    New-Item -ItemType Directory -Force -Path "$InstallDir\config"  | Out-Null
    New-Item -ItemType Directory -Force -Path "$InstallDir\backups" | Out-Null
    New-Item -ItemType Directory -Force -Path "$InstallDir\logs"    | Out-Null

    # Write default config if none exists
    if (-not (Test-Path "$InstallDir\config\zapret.conf")) {
        "--wf-tcp=80,443 --wf-udp=443" | Set-Content "$InstallDir\config\zapret.conf" -Encoding UTF8
    }
    if (-not (Test-Path "$InstallDir\config\mode.txt")) {
        "direct" | Set-Content "$InstallDir\config\mode.txt" -Encoding UTF8
    }

    $result = [ordered]@{
        success      = $true
        version      = $version
        sha256       = $hash
        extracted_to = $InstallDir
        errors       = @()
    }

} catch {
    $result = [ordered]@{
        success      = $false
        version      = $version
        sha256       = $null
        extracted_to = $null
        errors       = @($_.Exception.Message)
    }
} finally {
    # Always clean up temp dir (even on failure)
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$result | ConvertTo-Json
