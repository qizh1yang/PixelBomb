# One-Click Deployment Script for Bomberman (Windows 11)
# Requires Docker Desktop (WSL2 mode recommended)

Write-Host "=========================================" -ForegroundColor Green
Write-Host "   Bomberman Game Deployment (Windows)   " -ForegroundColor Green
Write-Host "========================================="
Write-Host ""

# 1. Check Docker
if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
    Write-Host "Error: Docker is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Please install Docker Desktop: https://www.docker.com/products/docker-desktop/"
    exit 1
}

# 2. SSL Setup
$CertDir = ".\ssl"
if (-not (Test-Path $CertDir)) {
    New-Item -ItemType Directory -Force -Path $CertDir | Out-Null
}

if (-not (Test-Path "$CertDir\cert.pem") -or -not (Test-Path "$CertDir\key.pem")) {
    Write-Host "SSL certificate missing. Attempting to generate..." -ForegroundColor Yellow
    
    # Try to find OpenSSL (commonly in Git Bash or installable via winget)
    $OpenSSL = Get-Command "openssl" -ErrorAction SilentlyContinue
    
    if ($OpenSSL) {
        $ServerIP = Read-Host "Enter Server IP (Default: 127.0.0.1)"
        if ([string]::IsNullOrWhiteSpace($ServerIP)) { $ServerIP = "127.0.0.1" }
        
        Write-Host "Generating certificate for $ServerIP..."
        openssl req -x509 -nodes -days 365 `
            -newkey rsa:2048 `
            -keyout "$CertDir\key.pem" `
            -out "$CertDir\cert.pem" `
            -subj "//C=CN\ST=State\L=City\O=Game\CN=$ServerIP"
            
        Write-Host "Certificate generated." -ForegroundColor Green
    } else {
        Write-Host "Warning: OpenSSL not found." -ForegroundColor Red
        Write-Host "Please manually place 'cert.pem' and 'key.pem' in the 'ssl' folder."
        Write-Host "Or install OpenSSL for Windows / use Git Bash."
        exit 1
    }
} else {
    Write-Host "Existing SSL certificate found." -ForegroundColor Green
}

# 3. Deployment
Write-Host "Stopping existing containers..." -ForegroundColor Yellow
docker compose -f docker-compose.prod.yml down 2>$null

Write-Host "Starting deployment..." -ForegroundColor Green
docker compose -f docker-compose.prod.yml up -d --build

if ($?) {
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Green
    Write-Host "   Deployment Successful!                " -ForegroundColor Green
    Write-Host "========================================="
    Write-Host "Game is running at: https://127.0.0.1"
} else {
    Write-Host "Deployment failed. Check Docker logs." -ForegroundColor Red
}
