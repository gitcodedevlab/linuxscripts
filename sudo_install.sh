#!/bin/bash
# Script to setup sudo and user privileges on fresh Debian install
# Run as root

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (su -)"
    exit 1
fi

read -p "Enter your username to add to sudo group: " USERNAME

echo "Installing sudo..."
apt update
apt install -y sudo

echo "Adding $USERNAME to sudo group..."
usermod -aG sudo "$USERNAME"

echo "Enabling sudo without password for $USERNAME (optional)..."
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USERNAME

echo "Applying group changes without logout..."
su - "$USERNAME" -c "newgrp sudo" <<EOF
echo "Group applied. You can now use sudo."
exit
EOF

echo "Done."
