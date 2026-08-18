#!/bin/bash

set -euo pipefail

# Debian 13 / Broadcom BCM4331 Wi-Fi installer
#
# Target hardware:
#   Broadcom BCM4331
#   PCI ID: 14e4:4331
#
# Network stack:
#   broadcom-sta-dkms / wl
#   wpa_supplicant
#   ifupdown
#   isc-dhcp-client
#
# Intended usage:
#   wget -qO- https://raw.githubusercontent.com/USER/REPO/main/install-wifi.sh | sudo bash

WIFI_IFACE="wlp2s0"
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant-${WIFI_IFACE}.conf"
INTERFACES_FILE="/etc/network/interfaces"
BACKUP_DIR="/root/wifi-install-backup"

TEMP_WPA=""

log() {
    echo "[INFO] $*"
}

warn() {
    echo "[WARN] $*" >&2
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

cleanup() {
    if [ -n "${TEMP_WPA}" ]; then
        rm -f "${TEMP_WPA}"
    fi

    unset WIFI_SSID
    unset WIFI_PASSWORD
}

trap cleanup EXIT

# ----------------------------------------------------------------------
# Root check
# ----------------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root. Use: sudo bash"
fi

# ----------------------------------------------------------------------
# Operating system check
# ----------------------------------------------------------------------

if [ ! -r /etc/os-release ]; then
    error "Cannot determine the operating system."
fi

. /etc/os-release

if [ "${ID:-}" != "debian" ]; then
    error "This script is intended for Debian."
fi

if [ "${VERSION_CODENAME:-}" != "trixie" ]; then
    error "This script is intended for Debian 13 (Trixie). Detected: ${VERSION_CODENAME:-unknown}"
fi

log "Debian 13 (Trixie) detected."

# ----------------------------------------------------------------------
# Check PCI hardware
# ----------------------------------------------------------------------

if ! command -v lspci >/dev/null 2>&1; then
    log "Installing pciutils..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y pciutils
fi

if ! lspci -nn | grep -qi "14e4:4331"; then
    error "Broadcom BCM4331 (PCI ID 14e4:4331) was not detected."
fi

log "Broadcom BCM4331 detected."

# ----------------------------------------------------------------------
# Check wireless interface
# ----------------------------------------------------------------------

if ! ip link show "${WIFI_IFACE}" >/dev/null 2>&1; then
    error "Wireless interface ${WIFI_IFACE} was not found."
fi

log "Wireless interface ${WIFI_IFACE} detected."

# ----------------------------------------------------------------------
# Backup existing configuration
# ----------------------------------------------------------------------

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

if [ -f "${INTERFACES_FILE}" ]; then
    cp -a "${INTERFACES_FILE}" \
        "${BACKUP_DIR}/interfaces.${TIMESTAMP}"
fi

if [ -f "${WPA_CONF}" ]; then
    cp -a "${WPA_CONF}" \
        "${BACKUP_DIR}/wpa_supplicant-${WIFI_IFACE}.conf.${TIMESTAMP}"
fi

log "Configuration backup created in ${BACKUP_DIR}."

# ----------------------------------------------------------------------
# Configure APT repositories
# ----------------------------------------------------------------------

log "Checking APT repositories..."

if [ ! -f /etc/apt/sources.list ]; then
    error "/etc/apt/sources.list does not exist."
fi

# Back up sources.list before modifying it.
cp -a /etc/apt/sources.list \
    "${BACKUP_DIR}/sources.list.${TIMESTAMP}"

# Debian 13 can use the traditional sources.list format.
# Ensure the required components are present:
#   main contrib non-free non-free-firmware
#
# Existing repository URLs and suites are preserved.

python3 - <<'PY'
from pathlib import Path

path = Path("/etc/apt/sources.list")

required = ["main", "contrib", "non-free", "non-free-firmware"]
lines = path.read_text().splitlines()

output = []

for line in lines:
    stripped = line.strip()

    if not stripped or stripped.startswith("#"):
        output.append(line)
        continue

    parts = stripped.split()

    if parts[0] not in ("deb", "deb-src") or len(parts) < 4:
        output.append(line)
        continue

    # Repository components begin at field 4.
    components = parts[3:]

    for component in required:
        if component not in components:
            components.append(component)

    parts[3:] = components
    output.append(" ".join(parts))

path.write_text("\n".join(output) + "\n")
PY

log "APT repositories configured."

apt-get update

# ----------------------------------------------------------------------
# Install required packages
# ----------------------------------------------------------------------

log "Installing required packages..."

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    broadcom-sta-dkms \
    dkms \
    linux-headers-amd64 \
    wpasupplicant \
    isc-dhcp-client \
    ifupdown \
    iw \
    pciutils \
    python3

# ----------------------------------------------------------------------
# Build/install Broadcom STA module
# ----------------------------------------------------------------------

log "Checking Broadcom STA DKMS module..."

if ! /usr/sbin/dkms status 2>/dev/null |
    grep -q "broadcom-sta"; then

    log "Building Broadcom STA kernel module..."

    /usr/sbin/dkms autoinstall
fi

if ! modinfo wl >/dev/null 2>&1; then
    error "The wl kernel module is not available."
fi

log "Broadcom wl kernel module is available."

# ----------------------------------------------------------------------
# Configure module blacklist
# ----------------------------------------------------------------------

BLACKLIST_FILE="/etc/modprobe.d/broadcom-wl.conf"

cat > "${BLACKLIST_FILE}" <<'EOF'
# Use Broadcom STA (wl) for BCM4331.
# Prevent b43/bcma from claiming the device.

blacklist b43
blacklist bcma
EOF

chmod 644 "${BLACKLIST_FILE}"

log "b43/bcma blacklist configured."

# ----------------------------------------------------------------------
# Load wl
# ----------------------------------------------------------------------

modprobe wl

log "wl kernel module loaded."

# ----------------------------------------------------------------------
# Stop any manually configured Wi-Fi instance
# ----------------------------------------------------------------------

systemctl stop "wpa_supplicant@${WIFI_IFACE}.service" 2>/dev/null || true

if command -v dhclient >/dev/null 2>&1; then
    dhclient -r "${WIFI_IFACE}" >/dev/null 2>&1 || true
fi

# ----------------------------------------------------------------------
# Collect Wi-Fi credentials
# ----------------------------------------------------------------------

if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    error "A real terminal is required to enter Wi-Fi credentials."
fi

echo
echo "Wi-Fi configuration"
echo "-------------------"

while true; do
    read -r -p "Wi-Fi SSID: " WIFI_SSID < /dev/tty

    if [ -n "${WIFI_SSID}" ]; then
        break
    fi

    echo "SSID cannot be empty." > /dev/tty
done

while true; do
    read -r -s -p "Wi-Fi password: " WIFI_PASSWORD < /dev/tty
    echo > /dev/tty

    if [ -n "${WIFI_PASSWORD}" ]; then
        break
    fi

    echo "Password cannot be empty." > /dev/tty
done

# ----------------------------------------------------------------------
# Generate WPA configuration
# ----------------------------------------------------------------------

log "Generating WPA configuration..."

TEMP_WPA="$(mktemp)"
chmod 600 "${TEMP_WPA}"

printf '%s\n' "${WIFI_PASSWORD}" |
    /usr/bin/wpa_passphrase "${WIFI_SSID}" > "${TEMP_WPA}"

# Remove the plaintext password comment generated by wpa_passphrase.
sed -i '/^[[:space:]]*#psk=/d' "${TEMP_WPA}"

install -o root -g root -m 600 \
    "${TEMP_WPA}" \
    "${WPA_CONF}"

rm -f "${TEMP_WPA}"
TEMP_WPA=""

unset WIFI_PASSWORD

log "WPA configuration installed."

# ----------------------------------------------------------------------
# Configure ifupdown
# ----------------------------------------------------------------------

if ! grep -qE \
    "^[[:space:]]*iface[[:space:]]+${WIFI_IFACE}[[:space:]]+inet[[:space:]]+dhcp" \
    "${INTERFACES_FILE}" 2>/dev/null; then

    cat >> "${INTERFACES_FILE}" <<EOF

allow-hotplug ${WIFI_IFACE}
iface ${WIFI_IFACE} inet dhcp
    wpa-conf ${WPA_CONF}
EOF

    log "ifupdown configuration added for ${WIFI_IFACE}."
else
    log "ifupdown configuration for ${WIFI_IFACE} already exists."
fi

# ----------------------------------------------------------------------
# Enable networking at boot
# ----------------------------------------------------------------------

systemctl enable networking.service >/dev/null 2>&1 || true

# ----------------------------------------------------------------------
# Bring up wireless interface
# ----------------------------------------------------------------------

log "Bringing up ${WIFI_IFACE}..."

ifdown "${WIFI_IFACE}" >/dev/null 2>&1 || true

ifup "${WIFI_IFACE}" || {
    error "Failed to bring up ${WIFI_IFACE}."
}

# ----------------------------------------------------------------------
# Wait for Wi-Fi association
# ----------------------------------------------------------------------

log "Waiting for Wi-Fi association..."

CONNECTED=0

for _ in $(seq 1 20); do
    if iw dev "${WIFI_IFACE}" link 2>/dev/null |
        grep -q "^Connected to"; then

        CONNECTED=1
        break
    fi

    sleep 1
done

if [ "${CONNECTED}" -ne 1 ]; then
    error "Wi-Fi association failed."
fi

# ----------------------------------------------------------------------
# Verify frequency
# ----------------------------------------------------------------------

FREQUENCY="$(
    iw dev "${WIFI_IFACE}" link 2>/dev/null |
    awk '/freq:/ {print $2; exit}'
)"

if [ -z "${FREQUENCY}" ]; then
    error "Unable to determine Wi-Fi frequency."
fi

FREQUENCY_INT="${FREQUENCY%.*}"

if [ "${FREQUENCY_INT}" -lt 5000 ]; then
    warn "The connection is not using 5 GHz."
    warn "Current frequency: ${FREQUENCY} MHz"
else
    log "5 GHz connection confirmed: ${FREQUENCY} MHz."
fi

# ----------------------------------------------------------------------
# Verify IPv4 address
# ----------------------------------------------------------------------

IPV4="$(
    ip -4 -o addr show dev "${WIFI_IFACE}" scope global |
    awk '{print $4}' |
    head -n1
)"

if [ -z "${IPV4}" ]; then
    error "No IPv4 address was assigned to ${WIFI_IFACE}."
fi

log "IPv4 address: ${IPV4}"

# ----------------------------------------------------------------------
# Test Internet connectivity
# ----------------------------------------------------------------------

log "Testing Internet connectivity through ${WIFI_IFACE}..."

if ping -I "${WIFI_IFACE}" -c 3 -W 5 1.1.1.1 >/dev/null 2>&1; then
    log "Internet connectivity test passed."
else
    warn "Internet connectivity test failed."
fi

# ----------------------------------------------------------------------
# Display final status
# ----------------------------------------------------------------------

echo
echo "========================================"
echo "Wi-Fi installation completed"
echo "========================================"
echo
echo "Wireless interface: ${WIFI_IFACE}"
echo "IPv4 address:       ${IPV4}"
echo "Frequency:          ${FREQUENCY} MHz"
echo

iw dev "${WIFI_IFACE}" link 2>/dev/null || true

echo
echo "The Wi-Fi configuration is persistent and"
echo "will automatically reconnect after reboot."
echo
echo "WPA configuration:"
echo "  ${WPA_CONF}"
echo
echo "Configuration backups:"
echo "  ${BACKUP_DIR}"
echo

exit 0
