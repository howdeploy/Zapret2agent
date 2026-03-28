# Zapret2agent Windows — Installer
# Run as: powershell -ExecutionPolicy Bypass -File install.ps1
# Or double-click install.bat
#
# Default: local install — run 'claude' from THIS directory
# -Global:  copy skills to ~/.claude/skills/ — run 'claude' from any directory

param(
    [switch]$Global
)

$ErrorActionPreference = "Stop"
$RepoDir = $PSScriptRoot  # Always the directory where this script lives

function Write-Color($msg, $color = "White") { Write-Host $msg -ForegroundColor $color }
function Write-OK($msg)   { Write-Color "  [OK] $msg" "Green" }
function Write-FAIL($msg) { Write-Color "  [!!] $msg" "Red" }
function Write-INFO($msg) { Write-Color "  [..] $msg" "Cyan" }
function Write-HEAD($msg) { Write-Color "`n=== $msg ===" "Yellow" }

Write-HEAD "Zapret2agent Windows Installer"

# --- Verify we're in the right place ---
$skillsSource = "$RepoDir\.claude\skills"
if (-not (Test-Path $skillsSource)) {
    Write-FAIL "Skills not found at $skillsSource"
    Write-FAIL "Run this script from inside the zapret2agent-windows directory."
    exit 1
}

# --- Detect AI agent ---
Write-HEAD "Detecting AI agent"
$claudePath = Get-Command "claude" -ErrorAction SilentlyContinue
$codexPath  = Get-Command "codex"  -ErrorAction SilentlyContinue

if (-not $claudePath -and -not $codexPath) {
    Write-FAIL "Neither 'claude' nor 'codex' found in PATH."
    Write-Color "  Install Claude Code: https://claude.ai/download" "Yellow"
    Write-Color "  Or Codex CLI:        https://github.com/openai/codex" "Yellow"
    exit 1
}

$agentName = if ($claudePath) { "Claude Code" } else { "Codex" }
$agentCmd  = if ($claudePath) { "claude" } else { "codex" }
Write-OK "Found: $agentName"

# --- Skills ---
Write-HEAD "Registering skills"

$skillNames = @("zapret-diagnose", "zapret-install", "zapret-config", "zapret-manage", "zapret-modes")

if ($Global) {
    # Copy skills to ~/.claude/skills/ and fix absolute paths in SKILL.md files
    $skillsDest = "$env:USERPROFILE\.claude\skills"
    New-Item -ItemType Directory -Force -Path $skillsDest | Out-Null

    foreach ($skillName in $skillNames) {
        $src = "$skillsSource\$skillName"
        $dst = "$skillsDest\$skillName"

        if (-not (Test-Path $src)) {
            Write-FAIL "Skill missing in repo: $skillName"
            exit 1
        }

        if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
        Copy-Item $src $dst -Recurse -Force

        # Fix relative paths in SKILL.md so scripts resolve correctly from any CWD
        # Before: .claude\skills\zapret-config\scripts\foo.ps1
        # After:  C:\Users\USERNAME\.claude\skills\zapret-config\scripts\foo.ps1
        $skillMd = "$dst\SKILL.md"
        if (Test-Path $skillMd) {
            $content = Get-Content $skillMd -Raw -Encoding UTF8
            foreach ($sn in $skillNames) {
                $relPath = ".claude\skills\$sn\"
                $absPath = "$skillsDest\$sn\"
                $content = $content.Replace($relPath, $absPath)
            }
            [System.IO.File]::WriteAllText($skillMd, $content, [System.Text.Encoding]::UTF8)
        }

        Write-OK "Skill installed: $skillName"
    }

    # Copy CLAUDE.md — backup existing if present, never overwrite silently
    $claudeMdDest = "$env:USERPROFILE\.claude\CLAUDE.md"
    if (Test-Path $claudeMdDest) {
        $backupPath = "$env:USERPROFILE\.claude\CLAUDE.md.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $claudeMdDest $backupPath -Force
        Write-INFO "Existing CLAUDE.md backed up to: $backupPath"

        # Append zapret instructions instead of overwriting
        $marker = "# --- Zapret2agent Windows ---"
        $existing = Get-Content $claudeMdDest -Raw -Encoding UTF8
        if ($existing -notmatch [regex]::Escape($marker)) {
            $zapretContent = Get-Content "$RepoDir\CLAUDE.md" -Raw -Encoding UTF8
            $appendContent = "`n`n$marker`n$zapretContent"
            [System.IO.File]::AppendAllText($claudeMdDest, $appendContent, [System.Text.Encoding]::UTF8)
            Write-OK "Zapret2agent instructions appended to existing CLAUDE.md"
        } else {
            Write-OK "Zapret2agent section already present in CLAUDE.md"
        }
    } else {
        Copy-Item "$RepoDir\CLAUDE.md" $claudeMdDest -Force
        Write-OK "CLAUDE.md installed to ~/.claude/"
    }

    Write-HEAD "Done (global install)"
    Write-Color "`nSkills available from any directory." "Green"
    Write-Color ""
    Write-Color "How to use:" "Yellow"
    Write-Color "  1. Open terminal AS ADMINISTRATOR (any directory)" "White"
    Write-Color "  2. Run: $agentCmd" "White"
    Write-Color "  3. Say (in Russian): zapusti diagnostiku" "White"

} else {
    # Local install — skills already live in the repo at .claude\skills\
    # Just verify they're all present.
    $allOk = $true
    foreach ($skillName in $skillNames) {
        if (Test-Path "$skillsSource\$skillName") {
            Write-OK "Skill ready: $skillName"
        } else {
            Write-FAIL "Skill missing: $skillName - re-clone the repo"
            $allOk = $false
        }
    }

    if (-not $allOk) { exit 1 }

    Write-HEAD "Done (local install)"
    Write-Color "`nSkills are ready." "Green"
    Write-Color ""
    Write-Color "IMPORTANT: always run $agentCmd from THIS directory:" "Yellow"
    Write-Color "  cd `"$RepoDir`"" "White"
    Write-Color "  $agentCmd" "White"
    Write-Color ""
    Write-Color "How to use:" "Yellow"
    Write-Color "  1. Open terminal AS ADMINISTRATOR in this directory" "White"
    Write-Color "  2. Run: $agentCmd" "White"
    Write-Color "  3. Say (in Russian): zapusti diagnostiku" "White"
}
