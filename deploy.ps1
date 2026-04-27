#Requires -Version 5.1
<#
    Deploy script for stone-sand.ru
    Usage:
      .\deploy.ps1            # upload index.html only
      .\deploy.ps1 -All       # upload index.html + img/ folder
      .\deploy.ps1 -DryRun    # preview what would be uploaded
#>
param(
    [switch]$All,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot
$RemoteHost  = 'nomak'
$RemoteRoot  = '/var/www/stone-sand'

function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function OK($m)   { Write-Host "[OK] $m"  -ForegroundColor Green }
function Warn($m) { Write-Host "[!]  $m"  -ForegroundColor Yellow }

$indexPath = Join-Path $ProjectRoot 'index.html'
if (-not (Test-Path $indexPath)) { throw "index.html not found in $ProjectRoot" }

$localSize = (Get-Item $indexPath).Length
$localHash = (Get-FileHash $indexPath -Algorithm MD5).Hash.ToLower()
Step "Local: index.html ($localSize bytes, MD5 $localHash)"

if ($DryRun) {
    Warn "DRY-RUN: scp $indexPath ${RemoteHost}:${RemoteRoot}/index.html"
} else {
    Step "Uploading index.html..."
    & scp $indexPath "${RemoteHost}:${RemoteRoot}/index.html"
    if ($LASTEXITCODE -ne 0) { throw "scp index.html failed with exit code $LASTEXITCODE" }
    OK "index.html uploaded"
}

if ($All) {
    $imgDir = Join-Path $ProjectRoot 'img'
    if (Test-Path $imgDir) {
        if ($DryRun) {
            Warn "DRY-RUN: scp -r $imgDir/. ${RemoteHost}:${RemoteRoot}/img/"
        } else {
            Step "Uploading img/ folder..."
            & scp -r "$imgDir/." "${RemoteHost}:${RemoteRoot}/img/"
            if ($LASTEXITCODE -ne 0) { throw "scp img/ failed with exit code $LASTEXITCODE" }
            OK "img/ folder uploaded"
        }
    }
}

if (-not $DryRun) {
    Step "Verifying remote MD5..."
    $remoteCheck = & ssh $RemoteHost "md5sum ${RemoteRoot}/index.html | awk '{print `$1}'"
    if ($LASTEXITCODE -ne 0) { throw "ssh verification failed" }
    $remoteHash = $remoteCheck.Trim().ToLower()
    if ($remoteHash -eq $localHash) {
        OK "MD5 match: $remoteHash"
    } else {
        Warn "MD5 MISMATCH! local=$localHash remote=$remoteHash"
        exit 1
    }

    Step "Checking https://stone-sand.ru/ ..."
    try {
        $resp = Invoke-WebRequest -Uri ("https://stone-sand.ru/?v=" + (Get-Date -UFormat %s)) -UseBasicParsing -TimeoutSec 10
        if ($resp.StatusCode -eq 200) {
            OK ("HTTP 200, Last-Modified: " + $resp.Headers['Last-Modified'])
        } else {
            Warn "Site responded with $($resp.StatusCode)"
        }
    } catch {
        Warn "HTTPS check failed: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "Done. Open https://stone-sand.ru/ with Ctrl+F5 to bypass browser cache." -ForegroundColor Green
}
