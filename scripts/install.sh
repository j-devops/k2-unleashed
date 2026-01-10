#!/bin/bash
# Install K2 Pro Enhanced Features
# Installs system monitor, diagnostics, and web dashboard

set -e  # Exit on error

echo "========================================="
echo "K2 Pro Enhanced Features Installer"
echo "========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: Do not run as root${NC}"
    echo "Run without sudo. Script will ask for sudo when needed."
    exit 1
fi

# Determine printer model
echo -e "${YELLOW}Which K2 model do you have?${NC}"
echo "1) K2 Plus (F008)"
echo "2) K2 Pro (F012)"
echo "3) K2 Base (F021)"
read -p "Enter choice [1-3]: " model_choice

case $model_choice in
    1) CONFIG_DIR="config/F008" ;;
    2) CONFIG_DIR="config/F012_CR0CN200400C10" ;;
    3) CONFIG_DIR="config/F021_CR0CN200400C10" ;;
    *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
esac

echo ""
echo -e "${GREEN}Selected: $CONFIG_DIR${NC}"
echo ""

# Check if config files exist
if [ ! -d "$CONFIG_DIR" ]; then
    echo -e "${RED}Error: Config directory not found: $CONFIG_DIR${NC}"
    exit 1
fi

# Find printer.cfg location
PRINTER_CFG=""
if [ -f "/usr/data/printer_data/config/printer.cfg" ]; then
    PRINTER_CFG="/usr/data/printer_data/config/printer.cfg"
elif [ -f "/home/$USER/printer_data/config/printer.cfg" ]; then
    PRINTER_CFG="/home/$USER/printer_data/config/printer.cfg"
elif [ -f "$HOME/printer_data/config/printer.cfg" ]; then
    PRINTER_CFG="$HOME/printer_data/config/printer.cfg"
else
    echo -e "${YELLOW}Could not auto-detect printer.cfg location${NC}"
    read -p "Enter path to printer.cfg: " PRINTER_CFG
fi

if [ ! -f "$PRINTER_CFG" ]; then
    echo -e "${RED}Error: printer.cfg not found at: $PRINTER_CFG${NC}"
    exit 1
fi

echo -e "${GREEN}Found printer.cfg: $PRINTER_CFG${NC}"
echo ""

# Ask what to install
echo -e "${YELLOW}What would you like to install?${NC}"
echo "1) System Monitor only (minimal)"
echo "2) System Monitor + Diagnostics (recommended)"
echo "3) Everything (monitor, diagnostics, web dashboard)"
read -p "Enter choice [1-3]: " install_choice

INSTALL_MONITOR=false
INSTALL_DIAGNOSTICS=false
INSTALL_WEB=false

case $install_choice in
    1) INSTALL_MONITOR=true ;;
    2) INSTALL_MONITOR=true; INSTALL_DIAGNOSTICS=true ;;
    3) INSTALL_MONITOR=true; INSTALL_DIAGNOSTICS=true; INSTALL_WEB=true ;;
    *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
esac

echo ""
echo "========================================="
echo "Installation Plan:"
echo "========================================="
if [ "$INSTALL_MONITOR" = true ]; then
    echo -e "${GREEN}✓${NC} System Monitor"
fi
if [ "$INSTALL_DIAGNOSTICS" = true ]; then
    echo -e "${GREEN}✓${NC} Diagnostics"
fi
if [ "$INSTALL_WEB" = true ]; then
    echo -e "${GREEN}✓${NC} Web Dashboard"
fi
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "========================================="
echo "Installing..."
echo "========================================="

# Backup printer.cfg
echo "Creating backup of printer.cfg..."
cp "$PRINTER_CFG" "${PRINTER_CFG}.backup.$(date +%Y%m%d_%H%M%S)"
echo -e "${GREEN}✓${NC} Backup created"

# Install System Monitor
if [ "$INSTALL_MONITOR" = true ]; then
    echo ""
    echo "Installing System Monitor..."

    # Check if already included
    if grep -q "^\[include system_monitor.cfg\]" "$PRINTER_CFG"; then
        echo -e "${YELLOW}System monitor already included in printer.cfg${NC}"
    else
        echo "[include system_monitor.cfg]" >> "$PRINTER_CFG"
        echo -e "${GREEN}✓${NC} Added to printer.cfg"
    fi

    # Copy config file to printer config directory
    CONFIG_DEST="$(dirname $PRINTER_CFG)"
    if [ ! -f "$CONFIG_DEST/system_monitor.cfg" ]; then
        cp "$CONFIG_DIR/system_monitor.cfg" "$CONFIG_DEST/"
        echo -e "${GREEN}✓${NC} Config file copied"
    else
        echo -e "${YELLOW}Config file already exists, skipping${NC}"
    fi
fi

# Install Diagnostics
if [ "$INSTALL_DIAGNOSTICS" = true ]; then
    echo ""
    echo "Installing Diagnostics..."

    # Check if already included
    if grep -q "^\[include diagnostics.cfg\]" "$PRINTER_CFG"; then
        echo -e "${YELLOW}Diagnostics already included in printer.cfg${NC}"
    else
        echo "[include diagnostics.cfg]" >> "$PRINTER_CFG"
        echo -e "${GREEN}✓${NC} Added to printer.cfg"
    fi

    # Copy config file
    CONFIG_DEST="$(dirname $PRINTER_CFG)"
    if [ ! -f "$CONFIG_DEST/diagnostics.cfg" ]; then
        cp "$CONFIG_DIR/diagnostics.cfg" "$CONFIG_DEST/"
        echo -e "${GREEN}✓${NC} Config file copied"
    else
        echo -e "${YELLOW}Config file already exists, skipping${NC}"
    fi
fi

# Install Web Dashboard
if [ "$INSTALL_WEB" = true ]; then
    echo ""
    echo "Installing Web Dashboard..."

    # Create web directory
    WEB_DIR="/usr/data/www/k2-monitor"
    sudo mkdir -p "$WEB_DIR"

    # Copy files
    sudo cp web_dashboard/index.html "$WEB_DIR/"
    sudo cp web_dashboard/diagnostics.html "$WEB_DIR/"
    echo -e "${GREEN}✓${NC} Web files copied to $WEB_DIR"

    echo ""
    echo -e "${YELLOW}Note: You may need to configure nginx to serve these files${NC}"
    echo "See web_dashboard/README.md for nginx configuration"
fi

# Restart Klipper
echo ""
echo "========================================="
echo "Restarting Klipper..."
echo "========================================="

if systemctl is-active --quiet klipper; then
    sudo systemctl restart klipper
    echo -e "${GREEN}✓${NC} Klipper restarted"

    # Wait for Klipper to come back up
    echo "Waiting for Klipper to start..."
    sleep 5

    if systemctl is-active --quiet klipper; then
        echo -e "${GREEN}✓${NC} Klipper is running"
    else
        echo -e "${RED}Warning: Klipper failed to start${NC}"
        echo "Check logs with: journalctl -u klipper -f"
    fi
else
    echo -e "${YELLOW}Klipper service not found, please restart manually${NC}"
fi

# Final instructions
echo ""
echo "========================================="
echo "Installation Complete!"
echo "========================================="
echo ""

if [ "$INSTALL_MONITOR" = true ]; then
    echo -e "${GREEN}System Monitor Commands:${NC}"
    echo "  SYSTEM_STATUS          - View system status"
    echo "  LOG_ERROR CODE=E999 MSG='test' - Log error"
    echo "  SHOW_ERRORS LIMIT=10   - Show recent errors"
    echo ""
fi

if [ "$INSTALL_DIAGNOSTICS" = true ]; then
    echo -e "${GREEN}Diagnostic Commands:${NC}"
    echo "  HEALTH_CHECK           - Run full health check"
    echo "  TEST_MOTORS AXIS=X DISTANCE=10"
    echo "  TEST_HEATERS HEATER=extruder TEMP=50"
    echo "  TEST_PROBE SAMPLES=10"
    echo ""
fi

if [ "$INSTALL_WEB" = true ]; then
    echo -e "${GREEN}Web Dashboard:${NC}"
    echo "  Main Dashboard:   http://$(hostname -I | awk '{print $1}'):8080/index.html"
    echo "  Diagnostics:      http://$(hostname -I | awk '{print $1}'):8080/diagnostics.html"
    echo ""
    echo -e "${YELLOW}Note: Configure nginx if not already done${NC}"
    echo "See: web_dashboard/README.md"
    echo ""
fi

echo -e "${GREEN}Documentation:${NC}"
echo "  - README.md - Overview and quick start"
echo "  - FIRMWARE_ERROR_HANDLING_ANALYSIS.md - Error handling analysis"
echo "  - WEB_DASHBOARD_DESIGN.md - Dashboard documentation"
echo "  - DIAGNOSTICS_GUIDE.md - Complete diagnostics guide"
echo ""

echo -e "${GREEN}Backup:${NC}"
echo "  Your original printer.cfg has been backed up to:"
echo "  ${PRINTER_CFG}.backup.*"
echo ""

echo "========================================="
echo -e "${GREEN}All done! Enjoy your enhanced K2 Pro!${NC}"
echo "========================================="
