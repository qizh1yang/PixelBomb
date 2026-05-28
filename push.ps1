# Push to GitHub
# 用法: .\push.ps1 "提交信息"

param(
    [string]$Message = ""
)

$ErrorActionPreference = "Stop"
$root = "d:/ALL_code/Godot/PixelBomb"

Write-Host "========================================" -ForegroundColor Green
Write-Host "  Push to GitHub" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Step 1: Run build-web.js
Write-Host "[1/3] Running build-web.js..." -ForegroundColor Yellow
Push-Location "$root/deploy/scripts"
node build-web.js
Pop-Location
Write-Host "  Build OK." -ForegroundColor Green
Write-Host ""

# Step 2: Git add all changes
Write-Host "[2/3] Staging changes..." -ForegroundColor Yellow
Push-Location $root
git add .
Pop-Location
Write-Host "  Staged." -ForegroundColor Green
Write-Host ""

# Step 3: Commit and push
Write-Host "[3/3] Committing and pushing..." -ForegroundColor Yellow
Push-Location $root
if ([string]::IsNullOrWhiteSpace($Message)) {
    $Message = "更新游戏版本 $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
}
git commit -m $Message
git push origin main
Pop-Location
Write-Host "  Pushed." -ForegroundColor Green
Write-Host ""

Write-Host "========================================" -ForegroundColor Green
Write-Host "  Done! Server: bash update-server.sh" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
