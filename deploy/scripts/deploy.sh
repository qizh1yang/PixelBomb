#!/bin/bash

# One-Click Deployment Script for Bomberman (CentOS/Debian/Ubuntu)
# Automatically handles dependencies, SSL, and Docker startup.

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   Bomberman Game Deployment Script      ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""

# 1. Check for Root Privileges
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}Please run as root (sudo ./deploy.sh)${NC}"
    exit 1
fi

# 2. Detect OS and Install Dependencies
if [ -f /etc/redhat-release ]; then
    OS="CentOS"
    echo -e "${YELLOW}Detected CentOS/RHEL system.${NC}"
    echo "Installing dependencies..."
    yum install -y openssl wget curl
elif [ -f /etc/debian_version ]; then
    OS="Debian"
    echo -e "${YELLOW}Detected Debian/Ubuntu system.${NC}"
    echo "Installing dependencies..."
    apt-get update && apt-get install -y openssl wget curl
else
    echo -e "${RED}Unsupported OS. Please ensure openssl, wget, and curl are installed manually.${NC}"
fi

# 3. Check Docker installation
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed.${NC}"
    echo "Please install Docker first: https://docs.docker.com/engine/install/"
    exit 1
fi

# 4. SSL Configuration
CERT_DIR="./ssl"
mkdir -p "$CERT_DIR"

if [ ! -f "$CERT_DIR/cert.pem" ] || [ ! -f "$CERT_DIR/key.pem" ]; then
    echo -e "${YELLOW}SSL configuration missing. Generating self-signed certificate...${NC}"
    
    # Get Public IP
    PUBLIC_IP=$(curl -s https://api.ipify.org || echo "127.0.0.1")
    read -p "Enter Server IP (Default: $PUBLIC_IP): " SERVER_IP
    SERVER_IP=${SERVER_IP:-$PUBLIC_IP}
    
    # Generate Cert
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$CERT_DIR/key.pem" \
        -out "$CERT_DIR/cert.pem" \
        -subj "/C=CN/ST=State/L=City/O=Game/CN=$SERVER_IP"
        
    echo -e "${GREEN}SSL Certificate generated for IP: $SERVER_IP${NC}"
else
    echo -e "${GREEN}Existing SSL certificate found.${NC}"
fi

# 5. Check Export Directory
if [ ! -d "./export/web" ]; then
    echo -e "${RED}Error: ./export/web directory not found!${NC}"
    echo "Please export the Godot project to HTML5 and place it in ./export/web"
    exit 1
fi

# 6. Launch Docker Compose
echo ""
echo -e "${YELLOW}Stopping existing containers...${NC}"

# Force remove any existing containers with the same name
docker rm -f bomberman-server bomberman-web 2>/dev/null || true

docker-compose -f docker-compose.yml down || docker compose -f docker-compose.yml down || true

echo ""
echo -e "${GREEN}Starting deployment...${NC}"

# Try docker compose v2 first, then v1
if docker compose version &> /dev/null; then
    docker compose -f docker-compose.yml up -d --build
elif command -v docker-compose &> /dev/null; then
    docker-compose -f docker-compose.yml up -d --build
else
    echo -e "${RED}Error: Docker Compose not found.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   Deployment Successful!                ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "Game is running at: https://$SERVER_IP"
