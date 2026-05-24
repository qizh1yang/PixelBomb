#!/bin/bash

# Script to add 2GB Swap for low-memory servers (CentOS/Debian/Ubuntu)
# Run this if your deployment hangs during "go build" or "npm install"

set -e

echo "Checking for existing swap..."
if [ -f /swapfile ]; then
    echo "Swapfile already exists."
    exit 0
fi

echo "Creating 2GB swap file..."
# Create a 2GB file
dd if=/dev/zero of=/swapfile bs=1M count=2048

# Set permissions
chmod 600 /swapfile

# Mark as swap
mkswap /swapfile

# Enable swap
swapon /swapfile

# Make permanent
if ! grep -q "/swapfile" /etc/fstab; then
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
fi

echo "========================================="
echo "Success! 2GB Swap added."
echo "========================================="
free -h
echo ""
echo "You can now verify installation by running: free -h"
echo "Then try running ./deploy.sh again."
