#!/bin/bash

# Install sudo and add the specified user to the sudo group.
# Must be run as root.

set -e

# Ensure standard system paths are available
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

# Get username from the first argument
USERNAME="$1"

# Check if username was provided
if [ -z "$USERNAME" ]; then
    echo "Error: Username is required."
    echo "Usage: bash $0 USERNAME"
    exit 1
fi

# Check if the user exists
if ! id "$USERNAME" &>/dev/null; then
    echo "Error: User '$USERNAME' does not exist."
    exit 1
fi

echo "Detected user: $USERNAME"
echo

echo "Updating package lists..."
apt update

echo "Installing sudo..."
apt install -y sudo

echo "Adding '$USERNAME' to the sudo group..."
usermod -aG sudo "$USERNAME"

echo
echo "Successfully added '$USERNAME' to the sudo group."
echo
echo "The user must log out and log back in for the new group membership to take effect."
echo "All done."
echo
