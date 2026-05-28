# Sync Godot Web Export to Remote Server
# 用法: .\sync-to-server.ps1 [-ServerIP 106.52.195.78] [-User root]

param(
    [string]$ServerIP = "106.52.195.78",
    [string]$User = "root"
)

$ErrorActionPreference = "Stop"
$webDir = "d:/ALL_code/Godot/PixelBomb/client/export/web"
$remoteDir = "/root/PixelBomb/client/export/web"
$scriptDir = "d:/ALL_code/Godot/PixelBomb/deploy/scripts"

Write-Host "========================================" -ForegroundColor Green
Write-Host "  PixelBomb Remote Server Sync" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Step 1: Run build-web.js
Write-Host "[1/3] Running build-web.js..." -ForegroundColor Yellow
$currentDir = Get-Location
Set-Location $scriptDir
node build-web.js
Set-Location $currentDir
Write-Host "  Build OK." -ForegroundColor Green
Write-Host ""

# Step 2: Upload files via SCP
Write-Host "[2/3] Uploading to $ServerIP ..." -ForegroundColor Yellow
scp -r "$webDir\*" "$User@$ServerIP`:$remoteDir/"
Write-Host "  Upload OK." -ForegroundColor Green
Write-Host ""

# Step 3: Restart nginx on server
Write-Host "[3/3] Restarting nginx on server..." -ForegroundColor Yellow
ssh "$User@$ServerIP" "cd /root/PixelBomb && docker restart pb-nginx"
Write-Host "  Restart OK." -ForegroundColor Green
Write-Host ""

Write-Host "========================================" -ForegroundColor Green
Write-Host "  Sync Complete!  https://$ServerIP" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
