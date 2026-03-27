# manage-hostlist.ps1
# Manage C:\zapret\zapret-winws\files\user-hostlist.txt
#
# Usage:
#   manage-hostlist.ps1 -Action list
#   manage-hostlist.ps1 -Action add    -Domains "youtube.com,discord.com"
#   manage-hostlist.ps1 -Action remove -Domains "discord.com"
#   manage-hostlist.ps1 -Action merge-seed -SeedPath "data\seed-list.txt"

param(
    [ValidateSet("list", "add", "remove", "merge-seed")]
    [string]$Action = "list",
    [string]$Domains = "",
    [string]$SeedPath = ""
)

$ErrorActionPreference = "SilentlyContinue"

$HostlistPath = "C:\zapret\zapret-winws\files\user-hostlist.txt"
$HostlistDir  = Split-Path $HostlistPath -Parent

New-Item -ItemType Directory -Force -Path $HostlistDir | Out-Null

# Ensure hostlist file exists
if (-not (Test-Path $HostlistPath)) {
    "" | Set-Content $HostlistPath -Encoding UTF8
}

function Normalize-Domain($d) {
    $d = $d.Trim().ToLower()
    $d = $d -replace '^https?://', ''
    $d = $d -replace '/$', ''
    $d = $d -replace '^www\.', ''
    return $d
}

function Get-CurrentDomains {
    $lines = Get-Content $HostlistPath -Encoding UTF8 -ErrorAction SilentlyContinue
    return @($lines | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' })
}

function Save-Domains($domainList) {
    $sorted = $domainList | Sort-Object -Unique
    $sorted | Set-Content $HostlistPath -Encoding UTF8
}

switch ($Action) {

    "list" {
        $current = Get-CurrentDomains
        @{
            success = $true
            count   = $current.Count
            domains = @($current)
            path    = $HostlistPath
            errors  = @()
        } | ConvertTo-Json
    }

    "add" {
        if ([string]::IsNullOrWhiteSpace($Domains)) {
            @{ success = $false; added = @(); errors = @("No domains specified (-Domains)") } | ConvertTo-Json
            return
        }

        $toAdd   = $Domains -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object { Normalize-Domain $_ }
        $current = Get-CurrentDomains

        $added   = @()
        $skipped = @()
        foreach ($d in $toAdd) {
            if (-not $d) { continue }
            if ($current -contains $d) {
                $skipped += $d
            } else {
                $current += $d
                $added   += $d
            }
        }

        Save-Domains $current

        @{
            success = $true
            added   = @($added)
            skipped = @($skipped)
            total   = @(Get-CurrentDomains).Count
            errors  = @()
        } | ConvertTo-Json
    }

    "remove" {
        if ([string]::IsNullOrWhiteSpace($Domains)) {
            @{ success = $false; removed = @(); errors = @("No domains specified (-Domains)") } | ConvertTo-Json
            return
        }

        $toRemove = $Domains -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object { Normalize-Domain $_ }
        $current  = Get-CurrentDomains

        $removed  = @()
        $notFound = @()
        foreach ($d in $toRemove) {
            if ($current -contains $d) {
                $current = $current | Where-Object { $_ -ne $d }
                $removed += $d
            } else {
                $notFound += $d
            }
        }

        Save-Domains $current

        @{
            success   = $true
            removed   = @($removed)
            not_found = @($notFound)
            total     = @(Get-CurrentDomains).Count
            errors    = @()
        } | ConvertTo-Json
    }

    "merge-seed" {
        if ([string]::IsNullOrWhiteSpace($SeedPath) -or -not (Test-Path $SeedPath)) {
            @{
                success = $false
                added   = @()
                errors  = @("Seed file not found: $SeedPath")
            } | ConvertTo-Json
            return
        }

        $seedDomains = Get-Content $SeedPath -Encoding UTF8 -ErrorAction SilentlyContinue |
                       Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' } |
                       ForEach-Object { Normalize-Domain $_ }

        $current  = Get-CurrentDomains
        $added    = @()

        foreach ($d in $seedDomains) {
            if ($d -and $current -notcontains $d) {
                $current += $d
                $added   += $d
            }
        }

        Save-Domains $current

        @{
            success = $true
            added   = @($added)
            total   = @(Get-CurrentDomains).Count
            errors  = @()
        } | ConvertTo-Json
    }
}
