# download-bundle.ps1
# Downloads latest zapret-win-bundle from GitHub and extracts to C:\zapret.
# Must run as Administrator.
# Output: JSON { success, version, extracted_to, errors[] }

$ErrorActionPreference = "Stop"

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
    $release = Invoke-RestMethod -Uri $releaseUrl -UseBasicParsing -TimeoutSec 30

    $version = $release.tag_name

    # Find zip asset
    $asset = $release.assets | Where-Object { $_.name -match "\.zip$" } | Select-Object -First 1

    if (-not $asset) {
        # Fallback: use source zip
        $downloadUrl = "https://github.com/bol-van/zapret-win-bundle/archive/refs/heads/master.zip"
        $version = "master"
    } else {
        $downloadUrl = $asset.browser_download_url
    }

    # Download
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($downloadUrl, $ZipPath)

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

    # Cleanup temp
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue

    $result = [ordered]@{
        success      = $true
        version      = $version
        extracted_to = $InstallDir
        errors       = @()
    }

} catch {
    $result = [ordered]@{
        success      = $false
        version      = $version
        extracted_to = $null
        errors       = @($_.Exception.Message)
    }
}

$result | ConvertTo-Json
