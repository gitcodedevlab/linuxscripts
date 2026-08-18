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

cat > /usr/local/bin/brightness-control << 'SCRIPT'
#!/bin/bash

BACKLIGHT="/sys/class/backlight/intel_backlight"
MAX_DISPLAY=$(cat $BACKLIGHT/max_brightness)
STEP_DISPLAY=180

echo -e "${GREEN}=== MacBook Pro 9,2 Keyboard Setup ===${NC}"

KBD_LIGHT="/sys/class/leds/smc::kbd_backlight"
MAX_KBD=$(cat $KBD_LIGHT/max_brightness)
STEP_KBD=25

REPEAT_DELAY=0.2

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
    down)
        dec_display
        if [ "$2" = "--repeat" ]; then
            while [ "$(cat $BACKLIGHT/brightness)" -gt 1 ]; do
                sleep $REPEAT_DELAY
                dec_display
            done
        fi
        ;;
    up)
        inc_display
        if [ "$2" = "--repeat" ]; then
            while [ "$(cat $BACKLIGHT/brightness)" -lt $MAX_DISPLAY ]; do
                sleep $REPEAT_DELAY
                inc_display
            done
        fi
        ;;
    kbd-down)
        dec_kbd
        if [ "$2" = "--repeat" ]; then
            while [ "$(cat $KBD_LIGHT/brightness)" -gt 0 ]; do
                sleep $REPEAT_DELAY
                dec_kbd
            done
        fi
        ;;
    kbd-up)
        inc_kbd
        if [ "$2" = "--repeat" ]; then
            while [ "$(cat $KBD_LIGHT/brightness)" -lt $MAX_KBD ]; do
                sleep $REPEAT_DELAY
                inc_kbd
            done
        fi
        ;;
esac
SCRIPT

chmod +x /usr/local/bin/brightness-control
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

cat > /etc/acpi/events/brightness-down << 'ACPI'
event=brightnessdown
action=/usr/local/bin/brightness-control down --repeat
ACPI

cat > /etc/acpi/events/brightness-up << 'ACPI'
event=brightnessup
action=/usr/local/bin/brightness-control up --repeat
ACPI

cat > /etc/acpi/events/kbd-illum-down << 'ACPI'
event=kbdillumdown
action=/usr/local/bin/brightness-control kbd-down --repeat
ACPI

cat > /etc/acpi/events/kbd-illum-up << 'ACPI'
event=kbdillumup
action=/usr/local/bin/brightness-control kbd-up --repeat
ACPI

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
