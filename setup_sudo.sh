#!/bin/bash
# Script to install sudo, add user to sudo group
# Run as root

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (su -)"
    exit 1
fi

read -p "Enter username to add to sudo group: " USERNAME

echo "Updating packages..."
apt update

echo "Installing sudo..."
apt install -y sudo

echo "Adding $USERNAME to sudo group..."
usermod -aG sudo "$USERNAME"

echo "Applying group changes without logout..."
su - "$USERNAME" -c "newgrp sudo" <<EOF
echo "Group applied. You can now use sudo."
exit
EOF

echo "All done."
