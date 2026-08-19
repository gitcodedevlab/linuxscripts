#!/bin/bash
#
# MacBook Pro 9,2 - Keyboard Brightness & Backlight Installer
# Usage: wget -qO- https://raw.githubusercontent.com/user/repo/main/macbook-keyboard-setup.sh | sudo bash
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${GREEN}=== MacBook Pro 9,2 Keyboard Setup ===${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: Please run with sudo${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}[1/4] Installing acpid...${NC}"
apt update
apt install -y acpid

echo ""
echo -e "${YELLOW}[2/4] Creating brightness control script...${NC}"

sudo tee /usr/local/bin/brightness-control << 'EOF'
#!/bin/bash

BACKLIGHT="/sys/class/backlight/intel_backlight"
MAX_DISPLAY=$(cat $BACKLIGHT/max_brightness)
STEP_DISPLAY=180

KBD_LIGHT="/sys/class/leds/smc::kbd_backlight"
MAX_KBD=$(cat $KBD_LIGHT/max_brightness)
STEP_KBD=25

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

case "$1" in
    down) dec_display ;;
    up) inc_display ;;
    kbd-down) dec_kbd ;;
    kbd-up) inc_kbd ;;
esac
EOF

sudo chmod +x /usr/local/bin/brightness-control
echo "  ✓ Script created"
echo "  Screen brigthness step: 180"
echo "  Keyboard light step: 25"
echo "  Step delay: 0.05"

echo ""
echo -e "${YELLOW}[3/4] Creating udev rules...${NC}"

cat > /etc/udev/hwdb.d/99-macbook-keyboard.hwdb << 'UDEV'
# MacBook Pro 9,2 - Keyboard mappings
evdev:input:b0003v05ACp0252e*
 KEYBOARD_KEY_7003a=brightnessdown
 KEYBOARD_KEY_7003b=brightnessup
 KEYBOARD_KEY_7003e=kbdillumdown
 KEYBOARD_KEY_7003f=kbdillumup
UDEV

systemd-hwdb update
udevadm control --reload-rules
udevadm trigger --sysname-match=event*

echo "  ✓ udev rules applied"

echo ""
echo -e "${YELLOW}[4/4] Configuring acpid events...${NC}"

sudo tee /etc/acpi/events/brightness-down << 'EOF'
event=brightnessdown
action=/usr/local/bin/brightness-control down
EOF

sudo tee /etc/acpi/events/brightness-up << 'EOF'
event=brightnessup
action=/usr/local/bin/brightness-control up
EOF

sudo tee /etc/acpi/events/kbd-illum-down << 'EOF'
event=kbdillumdown
action=/usr/local/bin/brightness-control kbd-down
EOF

sudo tee /etc/acpi/events/kbd-illum-up << 'EOF'
event=kbdillumup
action=/usr/local/bin/brightness-control kbd-up
EOF

systemctl restart acpid

echo ""
echo -e "${GREEN}=== Setup completed successfully! ===${NC}"
echo ""
echo "Keyboard shortcuts configured:"
echo "  Fn + F1  -> Decrease display brightness (hold for continuous)"
echo "  Fn + F2  -> Increase display brightness (hold for continuous)"
echo "  Fn + F5  -> Decrease keyboard backlight (hold for continuous)"
echo "  Fn + F6  -> Increase keyboard backlight (hold for continuous)"
echo ""
