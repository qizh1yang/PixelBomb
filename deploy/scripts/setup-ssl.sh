#!/bin/bash

# SSL Setup Script for IP-based Deployment
# Generates self-signed SSL certificate
# Compatible with OpenSSL 1.0.2+

set -e

echo "========================================="
echo "SSL Certificate Setup"
echo "========================================="
echo ""

# Configuration
CERT_DIR="./ssl"
DAYS_VALID=365

# Get server IP from argument, environment variable, or prompt user
if [ -n "$1" ]; then
    SERVER_IP="$1"
elif [ -n "$SERVER_IP" ]; then
    echo "Using SERVER_IP from environment: $SERVER_IP"
else
    read -p "请输入服务器公网 IP 地址: " SERVER_IP
    if [ -z "$SERVER_IP" ]; then
        echo "错误: IP 地址不能为空"
        exit 1
    fi
fi

# Create SSL directory
mkdir -p "$CERT_DIR"

echo ""
echo "Generating self-signed SSL certificate..."
echo "Server IP: $SERVER_IP"
echo "Valid for: $DAYS_VALID days"
echo ""

# Create OpenSSL config file for SAN (Subject Alternative Name)
cat > "$CERT_DIR/openssl.cnf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=CN
ST=State
L=City
O=Organization
CN=$SERVER_IP

[v3_req]
subjectAltName = @alt_names

[alt_names]
IP.1 = $SERVER_IP
EOF

# Generate private key and certificate using config file
openssl req -x509 -nodes -days $DAYS_VALID \
    -newkey rsa:2048 \
    -keyout "$CERT_DIR/key.pem" \
    -out "$CERT_DIR/cert.pem" \
    -config "$CERT_DIR/openssl.cnf" \
    -extensions v3_req

# Clean up config file
rm -f "$CERT_DIR/openssl.cnf"

echo ""
echo "========================================="
echo "SSL Certificate Generated!"
echo "========================================="
echo ""
echo "Certificate: $CERT_DIR/cert.pem"
echo "Private Key: $CERT_DIR/key.pem"
echo ""
echo "IMPORTANT: Browser Security Warning"
echo "========================================="
echo "Since this is a self-signed certificate, browsers will show"
echo "a security warning when you first visit the site."
echo ""
echo "To proceed:"
echo "1. Visit https://$SERVER_IP"
echo "2. Click 'Advanced' or 'Details'"
echo "3. Click 'Proceed to $SERVER_IP (unsafe)' or 'Accept Risk'"
echo ""
echo "This is safe for testing and internal use."
echo "For production, consider using a domain + Let's Encrypt."
echo ""

# Check Docker Compose version
echo "Checking Docker Compose version..."
COMPOSE_VERSION=$(docker-compose --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
echo "Current version: $COMPOSE_VERSION"

# Try to stop existing containers first
echo "Stopping existing containers..."
docker-compose -f docker-compose.yml down 2>/dev/null || true

echo "Starting deployment..."
# Use docker compose (V2) if available, otherwise fall back to docker-compose (V1)
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    echo "Using Docker Compose V2..."
    docker compose -f docker-compose.yml up -d --build
else
    echo "Using Docker Compose V1..."
    docker-compose -f docker-compose.yml up -d --build
fi

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Access your game at: https://$SERVER_IP"
echo ""
echo "Note: You will need to accept the security warning"
echo "      in your browser the first time."
echo ""
