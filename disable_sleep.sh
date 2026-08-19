#!/bin/bash
#
# Disable Sleep on Lid Close - MacBook Pro 9,2
# Usage: sudo ./disable_sleep.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Disabling Sleep on Lid Close ===${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: Please run with sudo${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}[1/4] Configuring systemd-logind...${NC}"
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/99-disable-lid-switch.conf << 'EOF'
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
systemctl restart systemd-logind
echo "  ✓ systemd-logind configured"

echo ""
echo -e "${YELLOW}[2/4] Configuring acpid...${NC}"
cat > /etc/acpi/events/lid << 'EOF'
event=button/lid.*
action=/bin/true
EOF
systemctl restart acpid
echo "  ✓ acpid configured"

echo ""
echo -e "${YELLOW}[3/4] Masking sleep targets...${NC}"
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
echo "  ✓ Sleep targets masked"

echo ""
echo -e "${YELLOW}[4/4] Verification...${NC}"
echo "  systemd-logind:"
grep -E "^HandleLid" /etc/systemd/logind.conf.d/99-disable-lid-switch.conf | sed 's/^/    /'
echo ""
echo "  acpid:"
grep "event" /etc/acpi/events/lid | sed 's/^/    /'
grep "action" /etc/acpi/events/lid | sed 's/^/    /'

echo ""
echo -e "${GREEN}=== Sleep disabled successfully! ===${NC}"
echo ""
echo "The system will NOT sleep when you close the lid."
echo "A reboot is recommended for all changes to take effect."
echo ""
