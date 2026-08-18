#!/bin/bash
#
# MacBook Pro 9,2 Keyboard Mapping Installer
# Usage: wget -qO- url | sudo bash
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== MacBook Pro 9,2 Keyboard Mapping Setup ===${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: Please run with sudo${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}[1/4] Installing dependencies...${NC}"
apt update
apt install -y evtest inotify-tools

echo ""
echo -e "${YELLOW}[2/4] Creating keyboard mapping script...${NC}"

cat > /usr/local/bin/macbook_keyboard_mapping.sh << 'SCRIPT'
#!/bin/bash
BACKLIGHT="/sys/class/backlight/intel_backlight"
MAX_DISPLAY=$(cat $BACKLIGHT/max_brightness)
STEP_DISPLAY=100
KBD_LIGHT="/sys/class/leds/smc::kbd_backlight"
MAX_KBD=$(cat $KBD_LIGHT/max_brightness)
STEP_KBD=30

dec_display() {
    CURRENT=$(cat $BACKLIGHT/brightness)
    NEW=$((CURRENT - STEP_DISPLAY))
    [ $NEW -lt 1 ] && NEW=1
    echo $NEW > $BACKLIGHT/brightness
}

inc_display() {
    CURRENT=$(cat $BACKLIGHT/brightness)
    NEW=$((CURRENT + STEP_DISPLAY))
    [ $NEW -gt $MAX_DISPLAY ] && NEW=$MAX_DISPLAY
    echo $NEW > $BACKLIGHT/brightness
}

dec_kbd() {
    CURRENT=$(cat $KBD_LIGHT/brightness)
    NEW=$((CURRENT - STEP_KBD))
    [ $NEW -lt 0 ] && NEW=0
    echo $NEW > $KBD_LIGHT/brightness
}

inc_kbd() {
    CURRENT=$(cat $KBD_LIGHT/brightness)
    NEW=$((CURRENT + STEP_KBD))
    [ $NEW -gt $MAX_KBD ] && NEW=$MAX_KBD
    echo $NEW > $KBD_LIGHT/brightness
}

evtest --grab /dev/input/event7 | while read line; do
    if echo "$line" | grep -q "KEY_F1.*value 1"; then dec_display
    elif echo "$line" | grep -q "KEY_F2.*value 1"; then inc_display
    elif echo "$line" | grep -q "KEY_F5.*value 1"; then dec_kbd
    elif echo "$line" | grep -q "KEY_F6.*value 1"; then inc_kbd
    fi
done
SCRIPT

chmod +x /usr/local/bin/macbook_keyboard_mapping.sh
echo "  ✓ Script created"

echo ""
echo -e "${YELLOW}[3/4] Creating systemd service...${NC}"

cat > /etc/systemd/system/macbook-keyboard.service << 'SERVICE'
[Unit]
Description=MacBook Pro 9,2 Keyboard Mappings
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/macbook_keyboard_mapping.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable macbook-keyboard.service
systemctl start macbook-keyboard.service

echo ""
echo -e "${YELLOW}[4/4] Verifying...${NC}"
sleep 2

if systemctl is-active --quiet macbook-keyboard.service; then
    echo -e "  ${GREEN}✓ Service is running${NC}"
else
    echo -e "  ${RED}✗ Service failed${NC}"
    systemctl status macbook-keyboard.service --no-pager
    exit 1
fi

echo ""
echo -e "${GREEN}=== Setup completed! ===${NC}"
echo ""
echo "  Fn + F1 > Decrease display brightness"
echo "  Fn + F2 > Increase display brightness"
echo "  Fn + F5 > Decrease keyboard backlight"
echo "  Fn + F6 > Increase keyboard backlight"
echo ""
