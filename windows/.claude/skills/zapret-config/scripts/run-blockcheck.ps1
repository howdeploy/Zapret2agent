# run-blockcheck.ps1
# Runs blockcheck2 via cygwin bash and captures output to log file.
# Must run as Administrator. All blockcheck prompts use defaults (non-interactive).
# Output: JSON { finished, log_path, exit_code, errors[] }

$ErrorActionPreference = "SilentlyContinue"

$CygwinBash  = "C:\zapret\cygwin\bin\bash.exe"
$BlogScript  = "C:\zapret\blockcheck\zapret2\blog.sh"
$LogPath     = "C:\zapret\blockcheck\blockcheck2.log"
$LogDir      = "C:\zapret\logs"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$errors = @()

# Check cygwin bash
if (-not (Test-Path $CygwinBash)) {
    @{
        finished  = $false
        log_path  = $null
        exit_code = $null
        errors    = @("cygwin bash not found: $CygwinBash - reinstall zapret")
    } | ConvertTo-Json
    return
}

# Check blog.sh (blockcheck entry point)
if (-not (Test-Path $BlogScript)) {
    @{
        finished  = $false
        log_path  = $null
        exit_code = $null
        errors    = @("blockcheck script not found: $BlogScript - reinstall zapret")
    } | ConvertTo-Json
    return
}

try {
    # Stop winws2 before blockcheck (blockcheck controls it internally during testing)
    $svc = Get-Service -Name "winws2" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Stop-Service -Name "winws2" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    # Run blockcheck non-interactively:
    # - bash runs blog.sh without interactive mode
    # - stdin redirected to NUL: all `read` prompts get empty input -> defaults accepted
    # - blockcheck output goes to C:\zapret\blockcheck\blockcheck2.log (written by blog.sh itself)
    # - window is visible so user can see progress (takes 5-10 min)
    $blogDir = Split-Path $BlogScript -Parent

    $proc = Start-Process `
        -FilePath $CygwinBash `
        -ArgumentList $BlogScript `
        -WorkingDirectory $blogDir `
        -RedirectStandardInput "NUL" `
        -Wait `
        -PassThru `
        -WindowStyle Normal

    $exitCode = $proc.ExitCode

    $logExists = (Test-Path $LogPath) -and ((Get-Item $LogPath).Length -gt 0)

    if (-not $logExists) {
        $errors += "no_output: blockcheck finished but log is empty - possibly blocked by antivirus"
    }

    @{
        finished  = $true
        log_path  = $LogPath
        exit_code = $exitCode
        log_size  = if ($logExists) { (Get-Item $LogPath).Length } else { 0 }
        errors    = @($errors)
    } | ConvertTo-Json

} catch {
    @{
        finished  = $false
        log_path  = $null
        exit_code = $null
        errors    = @($_.Exception.Message)
    } | ConvertTo-Json
}
