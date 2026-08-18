#!/bin/bash
# Debian 13 Wi-Fi 5GHz setup
# Usage: sudo bash wifi.sh "SSID" "PASSWORD"

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo"
    exit 1
fi

SSID="$1"
PASS="$2"

if [ -z "$SSID" ] || [ -z "$PASS" ]; then
    echo "Usage: sudo bash $0 \"SSID\" \"PASSWORD\""
    exit 1
fi

echo "Updating and installing dependencies..."
apt update
apt install -y broadcom-sta-dkms wireless-tools wpasupplicant isc-dhcp-client linux-headers-$(uname -r) build-essential

echo "Removing b43 driver..."
modprobe -r b43 2>/dev/null || true
apt purge -y firmware-b43-installer b43-fwcutter 2>/dev/null || true

echo "Rebuilding wl driver..."
dkms remove broadcom-sta/6.30.223.271 --all 2>/dev/null || true
dkms add broadcom-sta/6.30.223.271
dkms build broadcom-sta/6.30.223.271
dkms install broadcom-sta/6.30.223.271

modprobe wl
sleep 3

wpa_passphrase "$SSID" "$PASS" | tee /etc/wpa_supplicant.conf > /dev/null

wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
dhclient wlan0

sleep 2
ip a show wlan0

systemctl enable wpa_supplicant

echo "Wi-Fi configured."
