#!/bin/bash
# Rollback K2 printer configuration to a backup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
BACKUP_ID="$1"

if [ -z "$BACKUP_ID" ]; then
    echo "Usage: k2-unleashed rollback <backup_timestamp>"
    echo ""
    echo "Available backups:"
    if [ -d "$PROJECT_ROOT/backups" ]; then
        ls -1 "$PROJECT_ROOT/backups" | grep "^backup_" | sed 's/backup_/  /'
    else
        echo "  (none)"
    fi
    exit 1
fi

# Load .env file
if [ ! -f "$PROJECT_ROOT/.env" ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Run: k2-unleashed init"
    exit 1
fi

set -a
source "$PROJECT_ROOT/.env"
set +a

# Find backup directory
BACKUP_DIR="$PROJECT_ROOT/backups/backup_$BACKUP_ID"
if [ ! -d "$BACKUP_DIR" ]; then
    # Try without backup_ prefix
    BACKUP_DIR="$PROJECT_ROOT/backups/$BACKUP_ID"
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}Error: Backup not found: $BACKUP_ID${NC}"
        echo ""
        echo "Available backups:"
        ls -1 "$PROJECT_ROOT/backups" 2>/dev/null | grep "^backup_" | sed 's/backup_/  /' || echo "  (none)"
        exit 1
    fi
fi

# Build SSH/SCP commands
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
SCP_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

if [ -n "$PRINTER_PASSWORD" ]; then
    if ! command -v sshpass &> /dev/null; then
        echo -e "${RED}Error: sshpass required for password authentication${NC}"
        exit 1
    fi
    ssh_cmd() { sshpass -p "$PRINTER_PASSWORD" ssh $SSH_OPTS -p $PRINTER_PORT ${PRINTER_USER}@${PRINTER_HOST} "$@"; }
    scp_cmd() { sshpass -p "$PRINTER_PASSWORD" scp $SCP_OPTS -P $PRINTER_PORT "$@"; }
else
    ssh_cmd() { ssh $SSH_OPTS -p $PRINTER_PORT ${PRINTER_USER}@${PRINTER_HOST} "$@"; }
    scp_cmd() { scp $SCP_OPTS -P $PRINTER_PORT "$@"; }
fi

echo "========================================="
echo "K2 Unleashed - Rollback Configuration"
echo "========================================="
echo ""

# Show backup info
if [ -f "$BACKUP_DIR/backup_info.txt" ]; then
    cat "$BACKUP_DIR/backup_info.txt"
    echo ""
fi

# Test connection
echo -e "${BLUE}Connecting to printer...${NC}"
if ! ssh_cmd exit 2>/dev/null; then
    echo -e "${RED}✗${NC} Cannot connect to printer"
    exit 1
fi
echo -e "${GREEN}✓${NC} Connected"
echo ""

# Find config directory - try multiple common locations
REMOTE_CFG=$(ssh_cmd "for dir in /usr/data/printer_data/config /mnt/UDISK/printer_data/config /root/printer_data/config /home/*/printer_data/config; do if [ -f \$dir/printer.cfg ]; then echo \$dir/printer.cfg; break; fi; done" 2>/dev/null || echo "")

if [ -z "$REMOTE_CFG" ]; then
    echo -e "${RED}Error: Could not locate printer.cfg${NC}"
    exit 1
fi

CFG_DIR=$(dirname "$REMOTE_CFG")
echo -e "${BLUE}Config directory:${NC} $CFG_DIR"
echo ""

# Confirm rollback
if [ "$AUTO_CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}WARNING: This will overwrite current configuration!${NC}"
    read -p "Continue with rollback? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Rollback cancelled."
        exit 0
    fi
fi

# Create safety backup first
echo -e "${BLUE}Creating safety backup of current config...${NC}"
SAFETY_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ssh_cmd "cp $CFG_DIR/printer.cfg $CFG_DIR/printer.cfg.pre_rollback.$SAFETY_TIMESTAMP"
echo -e "${GREEN}✓${NC} Safety backup created: printer.cfg.pre_rollback.$SAFETY_TIMESTAMP"
echo ""

# Restore files
echo -e "${BLUE}Restoring configuration files...${NC}"

if [ -f "$BACKUP_DIR/printer.cfg" ]; then
    echo "Restoring printer.cfg..."
    scp_cmd "$BACKUP_DIR/printer.cfg" ${PRINTER_USER}@${PRINTER_HOST}:${CFG_DIR}/
    echo -e "${GREEN}✓${NC} printer.cfg restored"
fi

for cfg in system_monitor.cfg diagnostics.cfg; do
    if [ -f "$BACKUP_DIR/$cfg" ]; then
        echo "Restoring $cfg..."
        scp_cmd "$BACKUP_DIR/$cfg" ${PRINTER_USER}@${PRINTER_HOST}:${CFG_DIR}/
        echo -e "${GREEN}✓${NC} $cfg restored"
    fi
done

echo ""

# Restart Klipper
echo -e "${BLUE}Restarting Klipper...${NC}"
if ssh_cmd "systemctl is-active --quiet klipper"; then
    ssh_cmd "systemctl restart klipper"
    echo -e "${GREEN}✓${NC} Klipper restart initiated"

    echo "Waiting for Klipper to restart (10 seconds)..."
    sleep 10

    if ssh_cmd "systemctl is-active --quiet klipper"; then
        echo -e "${GREEN}✓${NC} Klipper is running"
    else
        echo -e "${RED}✗${NC} Klipper failed to start"
        echo "Check logs: k2-unleashed logs"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠${NC}  Klipper not running, please restart manually"
fi

echo ""
echo "========================================="
echo "Rollback Complete!"
echo "========================================="
echo ""
echo -e "${GREEN}Configuration restored from:${NC}"
echo "  $BACKUP_DIR"
echo ""
echo -e "${YELLOW}Safety backup saved as:${NC}"
echo "  $CFG_DIR/printer.cfg.pre_rollback.$SAFETY_TIMESTAMP"
echo ""
echo "Verify with: k2-unleashed status"
