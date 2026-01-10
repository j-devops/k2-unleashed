#!/bin/bash
# Backup K2 printer configuration

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
echo "K2 Unleashed - Backup Configuration"
echo "========================================="
echo ""

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

# Create backup directory
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$PROJECT_ROOT/backups/backup_$BACKUP_TIMESTAMP"
mkdir -p "$BACKUP_DIR"

echo -e "${BLUE}Backing up to:${NC} $BACKUP_DIR"
echo ""

# Backup printer.cfg
echo "Backing up printer.cfg..."
scp_cmd ${PRINTER_USER}@${PRINTER_HOST}:${CFG_DIR}/printer.cfg "$BACKUP_DIR/" 2>/dev/null
echo -e "${GREEN}✓${NC} printer.cfg"

# Backup enhanced feature configs if they exist
for cfg in system_monitor.cfg diagnostics.cfg; do
    if ssh_cmd "test -f $CFG_DIR/$cfg" 2>/dev/null; then
        echo "Backing up $cfg..."
        scp_cmd ${PRINTER_USER}@${PRINTER_HOST}:${CFG_DIR}/$cfg "$BACKUP_DIR/" 2>/dev/null || true
        echo -e "${GREEN}✓${NC} $cfg"
    fi
done

# Backup any custom macros
echo "Backing up custom configs..."
ssh_cmd "cd $CFG_DIR && tar czf /tmp/k2_configs_$BACKUP_TIMESTAMP.tar.gz *.cfg 2>/dev/null || true"
scp_cmd ${PRINTER_USER}@${PRINTER_HOST}:/tmp/k2_configs_$BACKUP_TIMESTAMP.tar.gz "$BACKUP_DIR/all_configs.tar.gz" 2>/dev/null || true
ssh_cmd "rm -f /tmp/k2_configs_$BACKUP_TIMESTAMP.tar.gz" 2>/dev/null || true
echo -e "${GREEN}✓${NC} all configs archived"

# Save system info
echo "Saving system info..."
cat > "$BACKUP_DIR/backup_info.txt" <<EOF
K2 Unleashed Backup
===================
Date: $(date)
Printer: ${PRINTER_HOST}
User: ${PRINTER_USER}
Config Directory: ${CFG_DIR}
K2 Model: ${K2_MODEL}

Klipper Version:
$(ssh_cmd "cd ~/klipper 2>/dev/null && git describe --always 2>/dev/null || echo 'Unknown'" || echo "Unknown")

Included Files:
$(ls -lh "$BACKUP_DIR")
EOF
echo -e "${GREEN}✓${NC} backup_info.txt"

echo ""
echo "========================================="
echo "Backup Complete!"
echo "========================================="
echo ""
echo -e "${GREEN}Backup saved to:${NC}"
echo "  $BACKUP_DIR"
echo ""
echo -e "${GREEN}Files backed up:${NC}"
ls -lh "$BACKUP_DIR"
echo ""
echo "To restore this backup:"
echo "  k2-unleashed rollback $BACKUP_TIMESTAMP"
