#!/bin/bash

set -euo pipefail

WIFI_IFACE="wlp2s0"
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant-${WIFI_IFACE}.conf"
BACKUP_DIR="/root/wifi-manager-backup"

log() {
    echo "[INFO] $*"
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

cleanup() {
    unset WIFI_SSID
    unset WIFI_PASSWORD
}

trap cleanup EXIT

# ----------------------------------------------------------------------
# Root check
# ----------------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root."
fi

if [ ! -f "${WPA_CONF}" ]; then
    error "Wi-Fi configuration file not found: ${WPA_CONF}"
fi

if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    error "A real terminal is required."
fi

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

# ----------------------------------------------------------------------
# Backup configuration
# ----------------------------------------------------------------------

backup_config() {
    local timestamp

    timestamp="$(date +%Y%m%d-%H%M%S)"

    cp -a "${WPA_CONF}" \
        "${BACKUP_DIR}/wpa_supplicant-${WIFI_IFACE}.${timestamp}.conf"

    log "Configuration backup created."
}

# ----------------------------------------------------------------------
# Generate WPA PSK
# ----------------------------------------------------------------------

generate_network() {
    local ssid="$1"
    local password="$2"
    local priority="$3"
    local temporary

    temporary="$(mktemp)"
    chmod 600 "${temporary}"

    printf '%s\n' "${password}" |
        /usr/bin/wpa_passphrase "${ssid}" > "${temporary}"

    sed -i '/^[[:space:]]*#psk=/d' "${temporary}"

    if [ -n "${priority}" ]; then
        sed -i "/^[[:space:]]*}/i\\    priority=${priority}" "${temporary}"
    fi

    cat "${temporary}"

    rm -f "${temporary}"
}

# ----------------------------------------------------------------------
# Get configured SSIDs
# ----------------------------------------------------------------------

get_ssids() {
    awk '
        /^[[:space:]]*network[[:space:]]*=[[:space:]]*{/ {
            in_network=1
            ssid=""
        }

        in_network && /^[[:space:]]*ssid=/ {
            line=$0
            sub(/^[[:space:]]*ssid="/, "", line)
            sub(/".*$/, "", line)
            ssid=line
        }

        in_network && /^[[:space:]]*}/ {
            if (ssid != "")
                print ssid
            in_network=0
        }
    ' "${WPA_CONF}"
}

# ----------------------------------------------------------------------
# Check whether an SSID already exists
# ----------------------------------------------------------------------

ssid_exists() {
    local target="$1"

    get_ssids | while IFS= read -r ssid; do
        if [ "${ssid}" = "${target}" ]; then
            exit 0
        fi
    done

    return 1
}

# ----------------------------------------------------------------------
# Add network
# ----------------------------------------------------------------------

add_network() {
    local priority
    local temporary

    echo
    echo "Add Wi-Fi network"
    echo "-----------------"

    read -r -p "Wi-Fi SSID: " WIFI_SSID < /dev/tty

    if [ -z "${WIFI_SSID}" ]; then
        error "SSID cannot be empty."
    fi

    if ssid_exists "${WIFI_SSID}"; then
        error "This SSID is already configured."
    fi

    read -r -s -p "Wi-Fi password: " WIFI_PASSWORD < /dev/tty
    echo > /dev/tty

    if [ -z "${WIFI_PASSWORD}" ]; then
        error "Password cannot be empty."
    fi

    read -r -p "Priority (higher value = preferred, default 0): " priority < /dev/tty

    if [ -z "${priority}" ]; then
        priority="0"
    fi

    if ! [[ "${priority}" =~ ^[0-9]+$ ]]; then
        error "Priority must be a non-negative integer."
    fi

    backup_config

    temporary="$(mktemp)"
    chmod 600 "${temporary}"

    generate_network \
        "${WIFI_SSID}" \
        "${WIFI_PASSWORD}" \
        "${priority}" > "${temporary}"

    printf '\n' >> "${WPA_CONF}"
    cat "${temporary}" >> "${WPA_CONF}"

    rm -f "${temporary}"

    unset WIFI_PASSWORD

    log "Network '${WIFI_SSID}' added."

    reconnect
}

# ----------------------------------------------------------------------
# Remove network
# ----------------------------------------------------------------------

remove_network() {
    local count=0
    local choice
    local selected_ssid
    local temporary

    echo
    echo "Configured Wi-Fi networks"
    echo "--------------------------"

    mapfile -t SSIDS < <(get_ssids)

    if [ "${#SSIDS[@]}" -eq 0 ]; then
        echo "No networks are configured."
        return
    fi

    for ssid in "${SSIDS[@]}"; do
        count=$((count + 1))
        echo "${count}) ${ssid}"
    done

    echo

    read -r -p "Select network to remove: " choice < /dev/tty

    if ! [[ "${choice}" =~ ^[0-9]+$ ]] ||
       [ "${choice}" -lt 1 ] ||
       [ "${choice}" -gt "${#SSIDS[@]}" ]; then
        error "Invalid selection."
    fi

    selected_ssid="${SSIDS[$((choice - 1))]}"

    echo
    read -r -p \
        "Remove '${selected_ssid}'? Type YES to confirm: " \
        confirmation < /dev/tty

    if [ "${confirmation}" != "YES" ]; then
        echo "Operation cancelled."
        return
    fi

    backup_config

    temporary="$(mktemp)"
    chmod 600 "${temporary}"

    awk -v target="${selected_ssid}" '
        BEGIN {
            skip=0
            found=0
        }

        /^[[:space:]]*network[[:space:]]*=[[:space:]]*{/ {
            block=$0
            buffer=$0
            skip=0
            found=0
            in_network=1
            next
        }

        in_network {
            buffer=buffer "\n" $0

            if ($0 ~ /^[[:space:]]*ssid="/) {
                line=$0
                sub(/^[[:space:]]*ssid="/, "", line)
                sub(/".*$/, "", line)

                if (line == target)
                    found=1
            }

            if ($0 ~ /^[[:space:]]*}/) {
                if (!found)
                    print buffer

                in_network=0
                buffer=""
            }

            next
        }

        {
            print
        }
    ' "${WPA_CONF}" > "${temporary}"

    install -o root -g root -m 600 \
        "${temporary}" \
        "${WPA_CONF}"

    rm -f "${temporary}"

    log "Network '${selected_ssid}' removed."

    reconnect
}

# ----------------------------------------------------------------------
# Change password
# ----------------------------------------------------------------------

change_password() {
    local count=0
    local choice
    local selected_ssid
    local password
    local temporary
    local network_block

    echo
    echo "Change Wi-Fi password"
    echo "---------------------"

    mapfile -t SSIDS < <(get_ssids)

    if [ "${#SSIDS[@]}" -eq 0 ]; then
        echo "No networks are configured."
        return
    fi

    for ssid in "${SSIDS[@]}"; do
        count=$((count + 1))
        echo "${count}) ${ssid}"
    done

    echo

    read -r -p "Select network: " choice < /dev/tty

    if ! [[ "${choice}" =~ ^[0-9]+$ ]] ||
       [ "${choice}" -lt 1 ] ||
       [ "${choice}" -gt "${#SSIDS[@]}" ]; then
        error "Invalid selection."
    fi

    selected_ssid="${SSIDS[$((choice - 1))]}"

    read -r -s -p "New Wi-Fi password: " password < /dev/tty
    echo > /dev/tty

    if [ -z "${password}" ]; then
        error "Password cannot be empty."
    fi

    backup_config

    temporary="$(mktemp)"
    chmod 600 "${temporary}"

    awk -v target="${selected_ssid}" '
        BEGIN {
            in_network=0
            found=0
        }

        /^[[:space:]]*network[[:space:]]*=[[:space:]]*{/ {
            in_network=1
            buffer=$0
            found=0
            next
        }

        in_network {
            buffer=buffer "\n" $0

            if ($0 ~ /^[[:space:]]*ssid="/) {
                line=$0
                sub(/^[[:space:]]*ssid="/, "", line)
                sub(/".*$/, "", line)

                if (line == target)
                    found=1
            }

            if ($0 ~ /^[[:space:]]*}/) {
                if (found)
                    print buffer

                in_network=0
                buffer=""
            }

            next
        }

        {
            print
        }
    ' "${WPA_CONF}" > "${temporary}"

    network_block="${temporary}"

    # Rebuild the configuration while replacing the selected block.
    temporary2="$(mktemp)"
    chmod 600 "${temporary2}"

    awk -v target="${selected_ssid}" -v newblock="${network_block}" '
        BEGIN {
            in_network=0
            found=0
        }

        /^[[:space:]]*network[[:space:]]*=[[:space:]]*{/ {
            in_network=1
            buffer=$0
            found=0
            next
        }

        in_network {
            buffer=buffer "\n" $0

            if ($0 ~ /^[[:space:]]*ssid="/) {
                line=$0
                sub(/^[[:space:]]*ssid="/, "", line)
                sub(/".*$/, "", line)

                if (line == target)
                    found=1
            }

            if ($0 ~ /^[[:space:]]*}/) {
                if (found)
                    print newblock
                else
                    print buffer

                in_network=0
                buffer=""
            }

            next
        }

        {
            print
        }
    ' "${WPA_CONF}" > "${temporary2}"

    # The previous block still contains the old PSK.
    # Replace its PSK with a newly generated one.
    generated="$(mktemp)"
    chmod 600 "${generated}"

    priority="$(
        awk -v target="${selected_ssid}" '
            BEGIN { in_network=0 }

            /^[[:space:]]*network[[:space:]]*=/ {
                in_network=1
                found=0
            }

            in_network && /^[[:space:]]*ssid="/ {
                line=$0
                sub(/^[[:space:]]*ssid="/, "", line)
                sub(/".*$/, "", line)

                if (line == target)
                    found=1
            }

            in_network && found && /^[[:space:]]*priority=/ {
                print $0
                exit
            }

            in_network && /^[[:space:]]*}/ {
                in_network=0
            }
        ' "${WPA_CONF}" |
        sed 's/[^0-9]//g'
    )"

    if [ -z "${priority}" ]; then
        priority="0"
    fi

    generate_network \
        "${selected_ssid}" \
        "${password}" \
        "${priority}" > "${generated}"

    # Replace the selected network block with the newly generated block.
    final="$(mktemp)"
    chmod 600 "${final}"

    awk -v target="${selected_ssid}" -v replacement="$(cat "${generated}")" '
        BEGIN {
            in_network=0
            found=0
        }

        /^[[:space:]]*network[[:space:]]*=[[:space:]]*{/ {
            in_network=1
            buffer=$0
            found=0
            next
        }

        in_network {
            buffer=buffer "\n" $0

            if ($0 ~ /^[[:space:]]*ssid="/) {
                line=$0
                sub(/^[[:space:]]*ssid="/, "", line)
                sub(/".*$/, "", line)

                if (line == target)
                    found=1
            }

            if ($0 ~ /^[[:space:]]*}/) {
                if (found)
                    print replacement
                else
                    print buffer

                in_network=0
                buffer=""
            }

            next
        }

        {
            print
        }
    ' "${WPA_CONF}" > "${final}"

    install -o root -g root -m 600 \
        "${final}" \
        "${WPA_CONF}"

    rm -f "${temporary}" "${temporary2}" "${generated}" "${final}"

    unset password

    log "Password updated for '${selected_ssid}'."

    reconnect
}

# ----------------------------------------------------------------------
# Reconnect
# ----------------------------------------------------------------------

reconnect() {
    log "Reloading Wi-Fi configuration..."

    ifdown "${WIFI_IFACE}" >/dev/null 2>&1 || true
    ifup "${WIFI_IFACE}" >/dev/null

    sleep 3

    if iw dev "${WIFI_IFACE}" link 2>/dev/null |
        grep -q "^Connected to"; then

        frequency="$(
            iw dev "${WIFI_IFACE}" link 2>/dev/null |
            awk '/freq:/ {print $2; exit}'
        )"

        log "Connected successfully."

        if [ -n "${frequency}" ]; then
            log "Frequency: ${frequency} MHz"
        fi
    else
        echo
        echo "[WARN] The interface did not connect immediately."
        echo "Check the configured password and network availability."
    fi
}

# ----------------------------------------------------------------------
# List networks
# ----------------------------------------------------------------------

list_networks() {
    echo
    echo "Configured Wi-Fi networks"
    echo "--------------------------"

    mapfile -t SSIDS < <(get_ssids)

    if [ "${#SSIDS[@]}" -eq 0 ]; then
        echo "No networks are configured."
        return
    fi

    local number=0

    for ssid in "${SSIDS[@]}"; do
        number=$((number + 1))
        echo "${number}) ${ssid}"
    done
}

# ----------------------------------------------------------------------
# Main menu
# ----------------------------------------------------------------------

while true; do

    echo
    echo "Wi-Fi Network Manager"
    echo "====================="
    echo
    echo "1) List configured networks"
    echo "2) Add a network"
    echo "3) Remove a network"
    echo "4) Change a network password"
    echo "5) Exit"
    echo

    read -r -p "Select an option: " option < /dev/tty

    case "${option}" in
        1)
            list_networks
            ;;
        2)
            add_network
            ;;
        3)
            remove_network
            ;;
        4)
            change_password
            ;;
        5)
            echo "Exiting."
            exit 0
            ;;
        *)
            echo "Invalid option."
            ;;
    esac

done
