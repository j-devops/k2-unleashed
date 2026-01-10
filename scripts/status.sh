#!/bin/bash
# Check K2 printer status via SSH

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
echo "K2 Unleashed - Printer Status"
echo "========================================="
echo ""

# Test connection
echo -e "${BLUE}Connection:${NC} ${PRINTER_USER}@${PRINTER_HOST}:${PRINTER_PORT}"
if ! ssh_cmd exit 2>/dev/null; then
    echo -e "${RED}✗${NC} Cannot connect to printer"
    exit 1
fi
echo -e "${GREEN}✓${NC} Connected"
echo ""

# Get version information
echo -e "${BLUE}K2 Unleashed Version:${NC}"
LOCAL_VERSION="unknown"
if [ -f "$PROJECT_ROOT/VERSION" ]; then
    LOCAL_VERSION=$(cat "$PROJECT_ROOT/VERSION")
fi
echo -e "  Local:     ${GREEN}${LOCAL_VERSION}${NC}"

REMOTE_VERSION=$(ssh_cmd "cat /usr/data/k2-unleashed/VERSION 2>/dev/null || cat /root/k2-unleashed/VERSION 2>/dev/null || echo 'not installed'" 2>/dev/null)
if [ "$REMOTE_VERSION" = "not installed" ]; then
    echo -e "  Installed: ${YELLOW}not installed${NC}"
    echo -e "  ${YELLOW}Run 'k2-unleashed upgrade' to install${NC}"
else
    echo -e "  Installed: ${BLUE}${REMOTE_VERSION}${NC}"
    if [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
        echo -e "  ${YELLOW}⚠ Version mismatch - run 'k2-unleashed upgrade'${NC}"
    fi
fi
echo ""

# Get Klipper status
echo -e "${BLUE}Klipper Service:${NC}"
# Try systemctl first, fall back to init.d for OpenWrt/BusyBox
if ssh_cmd "command -v systemctl >/dev/null 2>&1" 2>/dev/null; then
    # Standard Linux with systemd
    if ssh_cmd "systemctl is-active --quiet klipper"; then
        echo -e "${GREEN}✓${NC} Running"
        UPTIME=$(ssh_cmd "systemctl show klipper -p ActiveEnterTimestamp --value" | xargs -I {} date -d {} +%s 2>/dev/null || echo "")
        if [ -n "$UPTIME" ]; then
            NOW=$(date +%s)
            DIFF=$((NOW - UPTIME))
            HOURS=$((DIFF / 3600))
            MINS=$(((DIFF % 3600) / 60))
            echo "  Uptime: ${HOURS}h ${MINS}m"
        fi
    else
        echo -e "${RED}✗${NC} Not running"
    fi
else
    # OpenWrt/BusyBox with init.d
    if ssh_cmd "/etc/init.d/klipper status >/dev/null 2>&1" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Running"
    elif ssh_cmd "pgrep -f klippy >/dev/null 2>&1" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Running (detected via process)"
    else
        echo -e "${RED}✗${NC} Not running"
    fi
fi
echo ""

# Check for enhanced features
echo -e "${BLUE}Enhanced Features:${NC}"

# Find printer.cfg - try multiple common locations
REMOTE_CFG=$(ssh_cmd "for dir in /usr/data/printer_data/config /mnt/UDISK/printer_data/config /root/printer_data/config /home/*/printer_data/config; do if [ -f \$dir/printer.cfg ]; then echo \$dir/printer.cfg; break; fi; done" 2>/dev/null || echo "")

if [ -n "$REMOTE_CFG" ]; then
    CFG_DIR=$(dirname "$REMOTE_CFG")

    # Check system monitor
    if ssh_cmd "test -f $CFG_DIR/system_monitor.cfg && grep -q '\[include system_monitor.cfg\]' $REMOTE_CFG"; then
        echo -e "${GREEN}✓${NC} System Monitor installed"
    else
        echo -e "${YELLOW}○${NC} System Monitor not installed"
    fi

    # Check diagnostics
    if ssh_cmd "test -f $CFG_DIR/diagnostics.cfg && grep -q '\[include diagnostics.cfg\]' $REMOTE_CFG"; then
        echo -e "${GREEN}✓${NC} Diagnostics installed"
    else
        echo -e "${YELLOW}○${NC} Diagnostics not installed"
    fi

    # Check web dashboard
    if ssh_cmd "test -f /usr/data/www/k2/index.html"; then
        echo -e "${GREEN}✓${NC} Web Dashboard installed"
        PRINTER_IP=$(ssh_cmd "hostname -I | awk '{print \$1}'" 2>/dev/null || echo "$PRINTER_HOST")
        echo "  URL: http://${PRINTER_IP}:4408/k2/"
    else
        echo -e "${YELLOW}○${NC} Web Dashboard not installed"
    fi
else
    echo -e "${YELLOW}○${NC} Could not locate printer.cfg"
fi
echo ""

# Check for recent errors
echo -e "${BLUE}Recent Errors:${NC}"
# Try journalctl first, fall back to log files for OpenWrt
if ssh_cmd "command -v journalctl >/dev/null 2>&1" 2>/dev/null; then
    ERROR_COUNT=$(ssh_cmd "journalctl -u klipper --since '1 hour ago' | grep -ic 'error\|exception' || echo 0" 2>/dev/null | tr -d '\n' || echo "0")
else
    # OpenWrt/BusyBox - check klippy.log directly
    ERROR_COUNT=$(ssh_cmd "tail -1000 /tmp/klippy.log 2>/dev/null | grep -ic 'error\|exception' || echo 0" 2>/dev/null | tr -d '\n' || echo "0")
fi

# Clean up ERROR_COUNT (remove any newlines or spaces)
ERROR_COUNT=$(echo "$ERROR_COUNT" | tr -d ' \n' | head -1)
ERROR_COUNT=${ERROR_COUNT:-0}

if [ "$ERROR_COUNT" -eq 0 ] 2>/dev/null; then
    echo -e "${GREEN}✓${NC} No recent errors"
else
    echo -e "${YELLOW}⚠${NC}  $ERROR_COUNT error(s) found in recent logs"
    echo "  Run: k2-unleashed logs"
fi
echo ""

# System resources
echo -e "${BLUE}System Resources:${NC}"

# CPU usage - BusyBox compatible
CPU=$(ssh_cmd "top -bn1 | grep -i 'cpu:' | head -1 | awk '{print \$2}' | cut -d'%' -f1 | tr -d ' \n'" 2>/dev/null)
if [ -z "$CPU" ] || [ "$CPU" = "" ]; then
    # Alternative: calculate from idle percentage
    IDLE=$(ssh_cmd "top -bn1 | grep -i 'cpu:' | head -1 | sed 's/.*idle//' | awk '{print \$1}' | cut -d'%' -f1 | tr -d ' \n'" 2>/dev/null)
    if [ -n "$IDLE" ] && [ "$IDLE" != "" ]; then
        CPU=$((100 - IDLE)) 2>/dev/null || CPU="N/A"
    else
        CPU="N/A"
    fi
fi

# Memory usage - BusyBox compatible
MEM=$(ssh_cmd "free | awk 'NR==2{printf \"%.0f%%\", \$3*100/\$2}'" 2>/dev/null | tr -d '\n' || echo "N/A")

# Disk usage - try /usr/data first, fall back to root
DISK=$(ssh_cmd "df -h /usr/data 2>/dev/null | awk 'NR==2{print \$5}' | tr -d '\n'" 2>/dev/null)
if [ -z "$DISK" ]; then
    DISK=$(ssh_cmd "df -h / | awk 'NR==2{print \$5}' | tr -d '\n'" 2>/dev/null || echo "N/A")
fi

echo "  CPU:  ${CPU}%"
echo "  RAM:  ${MEM}"
echo "  Disk: ${DISK}"
echo ""

echo "========================================="
echo "Run 'k2-unleashed check' for health check"
echo "========================================="
