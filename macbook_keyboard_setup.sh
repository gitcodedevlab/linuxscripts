cat > ~/macbook-keyboard-setup.sh << 'EOF'
#!/bin/bash
#
# MacBook Pro 9,2 Keyboard Mapping Installer
# Usage: curl -sSL https://your-url/macbook-keyboard-setup.sh | sudo bash
# Or: wget -qO- https://your-url/macbook-keyboard-setup.sh | sudo bash
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== MacBook Pro 9,2 Keyboard Mapping Setup ===${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: Please run with sudo${NC}"
    echo "Usage: curl -sSL https://your-url/script.sh | sudo bash"
    exit 1
fi

# Variables
SCRIPT_PATH="/usr/local/bin/macbook_keyboard_mapping.sh"
SERVICE_PATH="/etc/systemd/system/macbook-keyboard.service"
SERVICE_NAME="macbook-keyboard.service"

# Function to check if a package is installed
is_package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# Function to check if service is running
is_service_running() {
    systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

echo ""
echo -e "${YELLOW}[1/5] Checking and installing dependencies...${NC}"

NEED_INSTALL=0
for pkg in evtest inotify-tools; do
    if is_package_installed "$pkg"; then
        echo "  ✓ $pkg already installed"
    else
        echo "  ✗ $pkg needs to be installed"
        NEED_INSTALL=1
    fi
done

if [ $NEED_INSTALL -eq 1 ]; then
    echo "  Installing missing packages..."
    apt update -qq && apt install -y evtest inotify-tools
    echo "  ✓ Dependencies installed"
else
    echo "  ✓ All dependencies already installed"
fi

echo ""
echo -e "${YELLOW}[2/5] Creating keyboard mapping script...${NC}"

cat > "$SCRIPT_PATH" << 'SCRIPT'
#!/bin/bash

# MacBook Pro 9,2 - Brightness and Keyboard Light Control

# Display brightness
BACKLIGHT="/sys/class/backlight/intel_backlight"
MAX_DISPLAY=$(cat $BACKLIGHT/max_brightness)
STEP_DISPLAY=100

# Keyboard backlight
KBD_LIGHT="/sys/class/leds/smc::kbd_backlight"
MAX_KBD=$(cat $KBD_LIGHT/max_brightness)
STEP_KBD=30

# Function to decrease display brightness
dec_display() {
    CURRENT=$(cat $BACKLIGHT/brightness)
    NEW=$((CURRENT - STEP_DISPLAY))
    [ $NEW -lt 1 ] && NEW=1
    echo $NEW > $BACKLIGHT/brightness
}

# Function to increase display brightness
inc_display() {
    CURRENT=$(cat $BACKLIGHT/brightness)
    NEW=$((CURRENT + STEP_DISPLAY))
    [ $NEW -gt $MAX_DISPLAY ] && NEW=$MAX_DISPLAY
    echo $NEW > $BACKLIGHT/brightness
}

# Function to decrease keyboard backlight
dec_kbd() {
    CURRENT=$(cat $KBD_LIGHT/brightness)
    NEW=$((CURRENT - STEP_KBD))
    [ $NEW -lt 0 ] && NEW=0
    echo $NEW > $KBD_LIGHT/brightness
}

# Function to increase keyboard backlight
inc_kbd() {
    CURRENT=$(cat $KBD_LIGHT/brightness)
    NEW=$((CURRENT + STEP_KBD))
    [ $NEW -gt $MAX_KBD ] && NEW=$MAX_KBD
    echo $NEW > $KBD_LIGHT/brightness
}

# Listen for keyboard events
evtest --grab /dev/input/event7 | while read line; do
    if echo "$line" | grep -q "KEY_F1.*value 1"; then
        dec_display
    elif echo "$line" | grep -q "KEY_F2.*value 1"; then
        inc_display
    elif echo "$line" | grep -q "KEY_F5.*value 1"; then
        dec_kbd
    elif echo "$line" | grep -q "KEY_F6.*value 1"; then
        inc_kbd
    fi
done
SCRIPT

chmod +x "$SCRIPT_PATH"
echo "  ✓ Script created at $SCRIPT_PATH"

echo ""
echo -e "${YELLOW}[3/5] Creating systemd service...${NC}"

cat > "$SERVICE_PATH" << 'SERVICE'
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

echo "  ✓ Service created at $SERVICE_PATH"

echo ""
echo -e "${YELLOW}[4/5] Enabling and starting service...${NC}"

systemctl daemon-reload

if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo "  ✓ Service already enabled"
else
    systemctl enable "$SERVICE_NAME"
    echo "  ✓ Service enabled"
fi

if is_service_running; then
    echo "  ✓ Service already running"
else
    systemctl start "$SERVICE_NAME"
    echo "  ✓ Service started"
fi

echo ""
echo -e "${YELLOW}[5/5] Verifying installation...${NC}"

sleep 2

if is_service_running; then
    echo -e "  ${GREEN}✓ Service is running${NC}"
else
    echo -e "  ${RED}✗ Service is NOT running${NC}"
    echo "  Checking status:"
    systemctl status "$SERVICE_NAME" --no-pager
    exit 1
fi

echo ""
echo -e "${GREEN}=== Setup completed successfully! ===${NC}"
echo ""
echo "Keyboard shortcuts configured:"
echo "  Fn + F1  -> Decrease display brightness"
echo "  Fn + F2  -> Increase display brightness"
echo "  Fn + F5  -> Decrease keyboard backlight"
echo "  Fn + F6  -> Increase keyboard backlight"
echo ""
echo "Service: $SERVICE_NAME"
echo "  - Status:  systemctl status $SERVICE_NAME"
echo "  - Stop:    systemctl stop $SERVICE_NAME"
echo "  - Restart: systemctl restart $SERVICE_NAME"
echo "  - Logs:    journalctl -u $SERVICE_NAME -f"
echo ""
echo -e "${GREEN}All done!${NC}"
EOF
