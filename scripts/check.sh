#!/bin/bash
# Run health check on K2 printer

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load .env file
if [ ! -f "$PROJECT_ROOT/.env" ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Run: k2-unleashed init"
    exit 1
fi

set -a
source "$PROJECT_ROOT/.env"
set +a

# Build SSH command
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

if [ -n "$PRINTER_PASSWORD" ]; then
    if ! command -v sshpass &> /dev/null; then
        echo -e "${RED}Error: sshpass required for password authentication${NC}"
        exit 1
    fi
    ssh_cmd() { sshpass -p "$PRINTER_PASSWORD" ssh $SSH_OPTS -p $PRINTER_PORT ${PRINTER_USER}@${PRINTER_HOST} "$@"; }
else
    ssh_cmd() { ssh $SSH_OPTS -p $PRINTER_PORT ${PRINTER_USER}@${PRINTER_HOST} "$@"; }
fi

echo "========================================="
echo "K2 Unleashed - Health Check"
echo "========================================="
echo ""

# Test connection
echo -e "${BLUE}Connecting to printer...${NC}"
if ! ssh_cmd exit 2>/dev/null; then
    echo -e "${RED}✗${NC} Cannot connect to printer"
    exit 1
fi
echo -e "${GREEN}✓${NC} Connected to ${PRINTER_HOST}"
echo ""

# Check if diagnostics module is installed
echo -e "${BLUE}Checking for diagnostics module...${NC}"
REMOTE_CFG=$(ssh_cmd "for dir in /usr/data/printer_data/config /mnt/UDISK/printer_data/config /root/printer_data/config /home/*/printer_data/config; do if [ -f \$dir/printer.cfg ]; then echo \$dir/printer.cfg; break; fi; done" 2>/dev/null || echo "")

if [ -z "$REMOTE_CFG" ]; then
    echo -e "${RED}✗${NC} Could not locate printer.cfg"
    exit 1
fi

CFG_DIR=$(dirname "$REMOTE_CFG")

if ! ssh_cmd "grep -q '\[include diagnostics.cfg\]' $REMOTE_CFG" 2>/dev/null; then
    echo -e "${YELLOW}⚠${NC}  Diagnostics module not installed"
    echo ""
    echo "To install diagnostics:"
    echo "  k2-unleashed upgrade"
    exit 1
fi
echo -e "${GREEN}✓${NC} Diagnostics module installed"
echo ""

# Check if Klipper is running
echo -e "${BLUE}Checking Klipper status...${NC}"
if ! ssh_cmd "systemctl is-active --quiet klipper"; then
    echo -e "${RED}✗${NC} Klipper is not running"
    exit 1
fi
echo -e "${GREEN}✓${NC} Klipper is running"
echo ""

# Check if printer is idle (not printing)
echo -e "${BLUE}Checking printer state...${NC}"
PRINT_STATE=$(ssh_cmd "grep -E 'state.*printing|state.*paused' /tmp/klippy.log 2>/dev/null | tail -1" || echo "")
if echo "$PRINT_STATE" | grep -qi "printing\|paused"; then
    echo -e "${YELLOW}⚠${NC}  Printer appears to be printing/paused"
    echo ""
    echo "Health checks should only run when printer is idle."
    echo "Continue anyway? This may interfere with the print!"
    read -p "[y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Health check cancelled."
        exit 0
    fi
fi
echo -e "${GREEN}✓${NC} Printer is idle"
echo ""

# Run health check via Moonraker API
echo "========================================="
echo "Running Health Check..."
echo "========================================="
echo ""

# Try to run HEALTH_CHECK command via moonraker
MOONRAKER_URL="http://${PRINTER_HOST}:7125"

# Check if moonraker is accessible
if command -v curl &> /dev/null; then
    echo -e "${BLUE}Running diagnostics via Moonraker API...${NC}"

    # Execute HEALTH_CHECK gcode command
    RESULT=$(curl -s -X POST "${MOONRAKER_URL}/printer/gcode/script?script=HEALTH_CHECK" 2>/dev/null || echo "")

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Health check command sent"
        echo ""
        echo "Health check is running on the printer."
        echo ""
        echo "View results in:"
        echo "  - Mainsail/Fluidd console"
        echo "  - Web Dashboard: http://${PRINTER_HOST}:8080/diagnostics.html"
        echo "  - Logs: k2-unleashed logs"
        echo ""

        # Wait a moment then fetch recent logs
        echo "Waiting for tests to complete (15 seconds)..."
        sleep 15

        echo ""
        echo "========================================="
        echo "Recent Health Check Results:"
        echo "========================================="
        ssh_cmd "journalctl -u klipper --since '30 seconds ago' | grep -i 'health\|diagnostic\|test' | tail -20 || echo 'No results found in logs'"
    else
        echo -e "${YELLOW}⚠${NC}  Could not connect to Moonraker API"
        echo ""
        echo "Manual health check:"
        echo "  1. Open Mainsail/Fluidd"
        echo "  2. Run: HEALTH_CHECK"
        echo "  3. Or visit: http://${PRINTER_HOST}:8080/diagnostics.html"
    fi
else
    # Fallback: provide manual instructions
    echo -e "${YELLOW}⚠${NC}  curl not available for API check"
    echo ""
    echo "To run health check manually:"
    echo "  1. Open Mainsail/Fluidd console"
    echo "  2. Run command: HEALTH_CHECK"
    echo ""
    echo "Or use the web interface:"
    echo "  http://${PRINTER_HOST}:8080/diagnostics.html"
fi

echo ""
echo "========================================="
echo "Health Check Complete"
echo "========================================="
