#!/bin/bash
#
# Enable Sleep on Lid Close - MacBook Pro 9,2
# Usage: sudo ./enable_sleep.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Enabling Sleep on Lid Close ===${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: Please run with sudo${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}[1/4] Restoring systemd-logind...${NC}"
rm -f /etc/systemd/logind.conf.d/99-disable-lid-switch.conf
systemctl restart systemd-logind
echo "  ✓ systemd-logind restored"

echo ""
echo -e "${YELLOW}[2/4] Restoring acpid...${NC}"
rm -f /etc/acpi/events/lid
systemctl restart acpid
echo "  ✓ acpid restored"

echo ""
echo -e "${YELLOW}[3/4] Unmasking sleep targets...${NC}"
systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
echo "  ✓ Sleep targets unmasked"

echo ""
echo -e "${YELLOW}[4/4] Verification...${NC}"
echo "  systemd-logind:"
if [ -f /etc/systemd/logind.conf.d/99-disable-lid-switch.conf ]; then
    echo "    WARNING: Config file still exists!"
else
    echo "    Config file removed."
fi
echo ""
echo "  acpid:"
if [ -f /etc/acpi/events/lid ]; then
    echo "    WARNING: acpid config still exists!"
else
    echo "    acpid config removed."
fi

echo ""
echo -e "${GREEN}=== Sleep enabled successfully! ===${NC}"
echo ""
echo "The system WILL sleep when you close the lid."
echo "A reboot is recommended for all changes to take effect."
echo ""
