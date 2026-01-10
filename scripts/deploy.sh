#!/bin/bash
# Network Deploy Script for K2 Pro Enhanced Features
# Deploys system monitor, diagnostics, and web dashboard via SSH
# Fully automated - reads configuration from .env file

set -e  # Exit on error

echo "========================================="
echo "K2 Pro Enhanced Features Network Deploy"
echo "========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: Do not run as root${NC}"
    exit 1
fi

# Check dependencies
for cmd in ssh scp; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd not found. Please install openssh-client${NC}"
        exit 1
    fi
done

# Load .env file
if [ ! -f ".env" ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo ""
    echo "Please create a .env file based on .env.example:"
    echo "  cp .env.example .env"
    echo "  # Edit .env with your printer details"
    echo ""
    exit 1
fi

# Source .env file
echo -e "${BLUE}Loading configuration from .env...${NC}"
set -a  # Export all variables
source .env
set +a

# Validate required variables
REQUIRED_VARS=("PRINTER_HOST" "PRINTER_USER" "PRINTER_PORT" "K2_MODEL" "DEPLOY_CHOICE")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: $var not set in .env file${NC}"
        exit 1
    fi
done

echo -e "${GREEN}✓${NC} Configuration loaded"
echo ""

# Set defaults
PRINTER_USER=${PRINTER_USER:-root}
PRINTER_PORT=${PRINTER_PORT:-22}
AUTO_CONFIRM=${AUTO_CONFIRM:-no}

# Build SSH command
SSH_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
SCP_OPTS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

if [ -n "$PRINTER_PASSWORD" ]; then
    # Use sshpass if password is provided
    if ! command -v sshpass &> /dev/null; then
        echo -e "${YELLOW}Warning: sshpass not found. Password authentication requires sshpass.${NC}"
        echo "Install with: sudo apt-get install sshpass"
        echo "Or set up SSH key authentication (recommended)"
        exit 1
    fi
    ssh_cmd() { sshpass -p "$PRINTER_PASSWORD" ssh $SSH_OPTS -p $PRINTER_PORT ${PRINTER_USER}@${PRINTER_HOST} "$@"; }
    scp_cmd() { sshpass -p "$PRINTER_PASSWORD" scp $SCP_OPTS -P $PRINTER_PORT "$@"; }
else
    # Use SSH key authentication (recommended)
    ssh_cmd() { ssh $SSH_OPTS -p $PRINTER_PORT ${PRINTER_USER}@${PRINTER_HOST} "$@"; }
    scp_cmd() { scp $SCP_OPTS -P $PRINTER_PORT "$@"; }
fi

# Test SSH connection
echo -e "${YELLOW}Testing connection to ${PRINTER_USER}@${PRINTER_HOST}:${PRINTER_PORT}...${NC}"

if ! ssh_cmd exit 2>/dev/null; then
    if [ -z "$PRINTER_PASSWORD" ]; then
        echo -e "${RED}Error: Cannot connect with SSH keys${NC}"
        echo ""
        echo "Options:"
        echo "1. Set up SSH key authentication (recommended):"
        echo "   ssh-copy-id -p $PRINTER_PORT ${PRINTER_USER}@${PRINTER_HOST}"
        echo ""
        echo "2. Add PRINTER_PASSWORD to .env file (less secure):"
        echo "   PRINTER_PASSWORD=your_password_here"
        exit 1
    else
        echo -e "${RED}Error: SSH connection failed${NC}"
        echo "Check PRINTER_HOST, PRINTER_PORT, and PRINTER_PASSWORD in .env"
        exit 1
    fi
fi

echo -e "${GREEN}✓${NC} SSH connection successful"

# Get local version
LOCAL_VERSION="unknown"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/VERSION" ]; then
    LOCAL_VERSION=$(cat "$SCRIPT_DIR/VERSION")
fi

# Check remote version if installed
echo ""
echo -e "${YELLOW}Checking installed version...${NC}"
REMOTE_VERSION=$(ssh_cmd "cat /usr/data/k2-unleashed/VERSION 2>/dev/null || cat /root/k2-unleashed/VERSION 2>/dev/null || echo 'not installed'" 2>/dev/null)

if [ "$REMOTE_VERSION" = "not installed" ]; then
    echo -e "${YELLOW}K2 Unleashed is not currently installed${NC}"
    echo -e "Installing version: ${GREEN}${LOCAL_VERSION}${NC}"
else
    echo -e "Installed version: ${BLUE}${REMOTE_VERSION}${NC}"
    echo -e "Local version:     ${GREEN}${LOCAL_VERSION}${NC}"

    if [ "$REMOTE_VERSION" = "$LOCAL_VERSION" ]; then
        echo -e "${YELLOW}Reinstalling same version${NC}"
    elif [ "$REMOTE_VERSION" \< "$LOCAL_VERSION" ]; then
        echo -e "${GREEN}Upgrading${NC} from ${REMOTE_VERSION} to ${LOCAL_VERSION}"
    else
        echo -e "${YELLOW}Downgrading${NC} from ${REMOTE_VERSION} to ${LOCAL_VERSION}"
    fi
fi

# Detect printer model configuration
echo ""
echo -e "${YELLOW}Detecting printer configuration...${NC}"

REMOTE_CFG=$(ssh_cmd "for dir in /usr/data/printer_data/config /mnt/UDISK/printer_data/config /root/printer_data/config /home/*/printer_data/config; do if [ -f \$dir/printer.cfg ]; then echo \$dir/printer.cfg; break; fi; done" 2>/dev/null || echo "")
REMOTE_CFG_DIR=$(dirname "$REMOTE_CFG" 2>/dev/null || echo "")

if [ -z "$REMOTE_CFG_DIR" ]; then
    echo -e "${RED}Error: Could not auto-detect config directory${NC}"
    echo "Please check printer configuration and ensure Klipper is installed"
    exit 1
fi

echo -e "${GREEN}✓${NC} Config directory: $REMOTE_CFG_DIR"

# Check if printer.cfg exists
if ! ssh_cmd "test -f $REMOTE_CFG_DIR/printer.cfg"; then
    echo -e "${RED}Error: printer.cfg not found at $REMOTE_CFG_DIR/printer.cfg${NC}"
    exit 1
fi

# Map K2 model from .env
case $K2_MODEL in
    1)
        LOCAL_CONFIG_DIR="config/F008"
        MODEL_NAME="K2 Plus"
        ;;
    2)
        LOCAL_CONFIG_DIR="config/F012_CR0CN200400C10"
        MODEL_NAME="K2 Pro"
        ;;
    3)
        LOCAL_CONFIG_DIR="config/F021_CR0CN200400C10"
        MODEL_NAME="K2 Base"
        ;;
    *)
        echo -e "${RED}Error: Invalid K2_MODEL in .env (must be 1, 2, or 3)${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Selected: $MODEL_NAME${NC}"

# Check if local config files exist
if [ ! -d "$LOCAL_CONFIG_DIR" ]; then
    echo -e "${RED}Error: Local config directory not found: $LOCAL_CONFIG_DIR${NC}"
    exit 1
fi

# Check if required files exist locally
for file in system_monitor.cfg diagnostics.cfg; do
    if [ ! -f "$LOCAL_CONFIG_DIR/$file" ]; then
        echo -e "${RED}Error: Required file not found: $LOCAL_CONFIG_DIR/$file${NC}"
        exit 1
    fi
done

# Map deployment choice from .env
DEPLOY_MONITOR=false
DEPLOY_DIAGNOSTICS=false
DEPLOY_WEB=false

case $DEPLOY_CHOICE in
    1) DEPLOY_MONITOR=true ;;
    2) DEPLOY_MONITOR=true; DEPLOY_DIAGNOSTICS=true ;;
    3) DEPLOY_MONITOR=true; DEPLOY_DIAGNOSTICS=true; DEPLOY_WEB=true ;;
    *)
        echo -e "${RED}Error: Invalid DEPLOY_CHOICE in .env (must be 1, 2, or 3)${NC}"
        exit 1
        ;;
esac

# Deployment plan
echo ""
echo "========================================="
echo "Deployment Plan:"
echo "========================================="
echo -e "${BLUE}Target:${NC} ${PRINTER_USER}@${PRINTER_HOST}:${PRINTER_PORT}"
echo -e "${BLUE}Model:${NC} $MODEL_NAME"
echo -e "${BLUE}Config:${NC} $REMOTE_CFG_DIR"
echo ""
echo "Components:"
if [ "$DEPLOY_MONITOR" = true ]; then
    echo -e "${GREEN}✓${NC} System Monitor (klippy module + config)"
fi
if [ "$DEPLOY_DIAGNOSTICS" = true ]; then
    echo -e "${GREEN}✓${NC} Diagnostics (klippy module + config)"
fi
if [ "$DEPLOY_WEB" = true ]; then
    echo -e "${GREEN}✓${NC} Web Dashboard (HTML files)"
fi
echo ""

# Auto-confirm or prompt
if [ "$AUTO_CONFIRM" != "yes" ]; then
    read -p "Continue with deployment? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

echo ""
echo "========================================="
echo "Starting Deployment..."
echo "========================================="

# Create temporary directory on remote
TEMP_DIR="/tmp/k2_deploy_$$"
echo ""
echo "Creating temporary directory on printer..."
ssh_cmd "mkdir -p $TEMP_DIR"
echo -e "${GREEN}✓${NC} Created $TEMP_DIR"

# Backup existing configs
echo ""
echo "Backing up existing configs..."
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ssh_cmd "cp $REMOTE_CFG_DIR/printer.cfg $REMOTE_CFG_DIR/printer.cfg.backup.$BACKUP_TIMESTAMP 2>/dev/null || true"
echo -e "${GREEN}✓${NC} Backup created: printer.cfg.backup.$BACKUP_TIMESTAMP"

# Deploy System Monitor
if [ "$DEPLOY_MONITOR" = true ]; then
    echo ""
    echo -e "${BLUE}[1/3] Deploying System Monitor...${NC}"

    # Copy Python module
    echo "  Copying system_monitor.py..."
    scp_cmd klippy/extras/system_monitor.py ${PRINTER_USER}@${PRINTER_HOST}:${TEMP_DIR}/
    ssh_cmd "cp $TEMP_DIR/system_monitor.py /usr/share/klipper/klippy/extras/ || cp $TEMP_DIR/system_monitor.py ~/klipper/klippy/extras/"
    echo -e "  ${GREEN}✓${NC} Module deployed"

    # Copy config
    echo "  Copying system_monitor.cfg..."
    scp_cmd "$LOCAL_CONFIG_DIR/system_monitor.cfg" ${PRINTER_USER}@${PRINTER_HOST}:${REMOTE_CFG_DIR}/
    echo -e "  ${GREEN}✓${NC} Config deployed"

    # Update printer.cfg if needed
    echo "  Updating printer.cfg..."
    if ssh_cmd "grep -q '^\[include system_monitor.cfg\]' $REMOTE_CFG_DIR/printer.cfg"; then
        echo -e "  ${YELLOW}Already included in printer.cfg${NC}"
    else
        ssh_cmd "echo '[include system_monitor.cfg]' >> $REMOTE_CFG_DIR/printer.cfg"
        echo -e "  ${GREEN}✓${NC} Added to printer.cfg"
    fi

    # Create log directory
    ssh_cmd "mkdir -p /usr/data/printer_data/logs 2>/dev/null || mkdir -p ~/printer_data/logs 2>/dev/null || true"
    echo -e "  ${GREEN}✓${NC} Log directory ready"

    # Deploy VERSION file for tracking
    echo "  Deploying version info..."
    ssh_cmd "mkdir -p /usr/data/k2-unleashed 2>/dev/null || mkdir -p ~/k2-unleashed 2>/dev/null || true"
    if [ -f "$SCRIPT_DIR/VERSION" ]; then
        scp_cmd "$SCRIPT_DIR/VERSION" ${PRINTER_USER}@${PRINTER_HOST}:${TEMP_DIR}/
        ssh_cmd "cp $TEMP_DIR/VERSION /usr/data/k2-unleashed/VERSION 2>/dev/null || cp $TEMP_DIR/VERSION ~/k2-unleashed/VERSION"
        echo -e "  ${GREEN}✓${NC} Version ${LOCAL_VERSION} registered"
    fi
fi

# Deploy Diagnostics
if [ "$DEPLOY_DIAGNOSTICS" = true ]; then
    echo ""
    echo -e "${BLUE}[2/3] Deploying Diagnostics...${NC}"

    # Copy Python module
    echo "  Copying diagnostics.py..."
    scp_cmd klippy/extras/diagnostics.py ${PRINTER_USER}@${PRINTER_HOST}:${TEMP_DIR}/
    ssh_cmd "cp $TEMP_DIR/diagnostics.py /usr/share/klipper/klippy/extras/ || cp $TEMP_DIR/diagnostics.py ~/klipper/klippy/extras/"
    echo -e "  ${GREEN}✓${NC} Module deployed"

    # Copy config
    echo "  Copying diagnostics.cfg..."
    scp_cmd "$LOCAL_CONFIG_DIR/diagnostics.cfg" ${PRINTER_USER}@${PRINTER_HOST}:${REMOTE_CFG_DIR}/
    echo -e "  ${GREEN}✓${NC} Config deployed"

    # Update printer.cfg if needed
    echo "  Updating printer.cfg..."
    if ssh_cmd "grep -q '^\[include diagnostics.cfg\]' $REMOTE_CFG_DIR/printer.cfg"; then
        echo -e "  ${YELLOW}Already included in printer.cfg${NC}"
    else
        ssh_cmd "echo '[include diagnostics.cfg]' >> $REMOTE_CFG_DIR/printer.cfg"
        echo -e "  ${GREEN}✓${NC} Added to printer.cfg"
    fi
fi

# Deploy Web Dashboard
if [ "$DEPLOY_WEB" = true ]; then
    echo ""
    echo -e "${BLUE}[3/3] Deploying Web Dashboard...${NC}"

    # Create web directory
    WEB_DIR="/usr/data/www/k2-monitor"
    echo "  Creating web directory..."
    ssh_cmd "mkdir -p $WEB_DIR"
    echo -e "  ${GREEN}✓${NC} Created $WEB_DIR"

    # Copy HTML files
    echo "  Copying web files..."
    scp_cmd web_dashboard/index.html ${PRINTER_USER}@${PRINTER_HOST}:${WEB_DIR}/
    scp_cmd web_dashboard/diagnostics.html ${PRINTER_USER}@${PRINTER_HOST}:${WEB_DIR}/
    echo -e "  ${GREEN}✓${NC} Web files deployed"

    # Fix file permissions so nginx can read them
    echo "  Setting file permissions..."
    ssh_cmd "chmod 644 ${WEB_DIR}/*.html"
    echo -e "  ${GREEN}✓${NC} Permissions set"

    # Configure nginx to serve the dashboard
    echo "  Configuring nginx..."
    if ! ssh_cmd "grep -q '/k2-monitor/' /etc/nginx/nginx.conf" 2>/dev/null; then
        # Backup nginx config
        ssh_cmd "cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup 2>/dev/null || true"

        # Download, modify, and upload nginx config
        scp_cmd ${PRINTER_USER}@${PRINTER_HOST}:/etc/nginx/nginx.conf /tmp/nginx.conf.k2 2>/dev/null

        # Add k2-monitor location block using awk
        awk '/location = \/index.html/ {print; print ""; print "        location /k2-monitor/ {"; print "            alias /usr/data/www/k2-monitor/;"; print "            index index.html;"; print "            add_header Cache-Control \"no-store, no-cache, must-revalidate\";"; print "        }"; next}1' /tmp/nginx.conf.k2 > /tmp/nginx.conf.k2.new

        # Upload and test
        scp_cmd /tmp/nginx.conf.k2.new ${PRINTER_USER}@${PRINTER_HOST}:/etc/nginx/nginx.conf

        if ssh_cmd "nginx -t" 2>/dev/null; then
            ssh_cmd "nginx -s reload" 2>/dev/null
            echo -e "  ${GREEN}✓${NC} Nginx configured and reloaded"
        else
            echo -e "  ${YELLOW}⚠${NC}  Nginx config test failed, restoring backup"
            ssh_cmd "mv /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf" 2>/dev/null
        fi
    else
        echo -e "  ${YELLOW}⚠${NC}  Nginx already configured"
    fi

    # Get printer IP for display
    PRINTER_IP=$(ssh_cmd "hostname -I | awk '{print \$1}'" 2>/dev/null || echo "$PRINTER_HOST")

    echo ""
    echo -e "  ${YELLOW}Web dashboard URLs:${NC}"
    echo "    Main:        http://${PRINTER_IP}:4408/k2-monitor/"
    echo "    Diagnostics: http://${PRINTER_IP}:4408/k2-monitor/diagnostics.html"
    echo ""
    echo -e "  ${GREEN}Access via Fluidd on port 4408${NC}"
fi

# Cleanup temporary directory
echo ""
echo "Cleaning up..."
ssh_cmd "rm -rf $TEMP_DIR"
echo -e "${GREEN}✓${NC} Temporary files removed"

# Restart Klipper
echo ""
echo "========================================="
echo "Restarting Klipper..."
echo "========================================="

# Try systemctl first, fall back to init.d for OpenWrt
if ssh_cmd "command -v systemctl >/dev/null 2>&1" 2>/dev/null; then
    # Standard Linux with systemd
    if ssh_cmd "systemctl is-active --quiet klipper"; then
        ssh_cmd "systemctl restart klipper"
        echo -e "${GREEN}✓${NC} Klipper restart initiated"

        # Wait for Klipper to restart
        echo "Waiting for Klipper to restart (10 seconds)..."
        sleep 10

        if ssh_cmd "systemctl is-active --quiet klipper"; then
            echo -e "${GREEN}✓${NC} Klipper is running"

            # Check for errors in log
            echo ""
            echo "Checking for startup errors..."
            ERRORS=$(ssh_cmd "journalctl -u klipper --since '1 minute ago' | grep -i 'error\|exception' | tail -5" || echo "")

            if [ -n "$ERRORS" ]; then
                echo -e "${YELLOW}Warning: Found recent errors in log:${NC}"
                echo "$ERRORS"
                echo ""
                echo -e "${YELLOW}Check full logs with: ssh $PRINTER_HOST journalctl -u klipper -f${NC}"
            else
                echo -e "${GREEN}✓${NC} No errors detected"
            fi
        else
            echo -e "${RED}Warning: Klipper failed to start${NC}"
            echo "Check logs with: ssh $PRINTER_HOST journalctl -u klipper -f"
        fi
    else
        echo -e "${YELLOW}Warning: Could not detect Klipper service${NC}"
        echo "Please restart Klipper manually"
    fi
else
    # OpenWrt/BusyBox with init.d
    ssh_cmd "/etc/init.d/klipper restart" 2>/dev/null || ssh_cmd "killall klippy; sleep 2; /etc/init.d/klipper start" 2>/dev/null
    echo -e "${GREEN}✓${NC} Klipper restart initiated"

    # Wait for Klipper to restart
    echo "Waiting for Klipper to restart (10 seconds)..."
    sleep 10

    if ssh_cmd "pgrep -f klippy >/dev/null 2>&1" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Klipper is running"

        # Check for errors in log
        echo ""
        echo "Checking for startup errors..."
        ERRORS=$(ssh_cmd "tail -50 /tmp/klippy.log 2>/dev/null | grep -i 'error\|exception' | tail -5" || echo "")

        if [ -n "$ERRORS" ]; then
            echo -e "${YELLOW}Warning: Found recent errors in log:${NC}"
            echo "$ERRORS"
            echo ""
            echo -e "${YELLOW}Check full logs with: k2-unleashed logs${NC}"
        else
            echo -e "${GREEN}✓${NC} No errors detected"
        fi
    else
        echo -e "${RED}Warning: Klipper failed to start${NC}"
        echo "Check logs with: k2-unleashed logs"
    fi
fi

# Test deployment
echo ""
echo "========================================="
echo "Testing Deployment..."
echo "========================================="

if [ "$DEPLOY_MONITOR" = true ]; then
    echo ""
    echo "Testing System Monitor..."

    # Check if module loaded
    if ssh_cmd "grep -q 'SystemMonitor' /tmp/klippy.log 2>/dev/null"; then
        echo -e "${GREEN}✓${NC} System Monitor loaded successfully"
    else
        echo -e "${YELLOW}⚠${NC}  Could not verify System Monitor loaded (check manually)"
    fi
fi

if [ "$DEPLOY_DIAGNOSTICS" = true ]; then
    echo ""
    echo "Testing Diagnostics..."

    # Check if module loaded
    if ssh_cmd "grep -q 'Diagnostics' /tmp/klippy.log 2>/dev/null"; then
        echo -e "${GREEN}✓${NC} Diagnostics loaded successfully"
    else
        echo -e "${YELLOW}⚠${NC}  Could not verify Diagnostics loaded (check manually)"
    fi
fi

# Final summary
echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""

# Show version deployed
echo -e "${GREEN}Version Deployed:${NC}"
echo "  K2 Unleashed ${LOCAL_VERSION}"
echo ""

# Show backup info
echo -e "${GREEN}Backup:${NC}"
echo "  Original printer.cfg saved as:"
echo "  $REMOTE_CFG_DIR/printer.cfg.backup.$BACKUP_TIMESTAMP"
echo ""

# Show verification commands
echo -e "${GREEN}Verify Installation:${NC}"
echo "  SSH to printer:"
echo "    ssh ${PRINTER_USER}@${PRINTER_HOST}"
echo ""
echo "  Test commands (via Mainsail/Fluidd console):"

if [ "$DEPLOY_MONITOR" = true ]; then
    echo "    SYSTEM_STATUS          # View system status"
    echo "    LOG_ERROR CODE=TEST MSG='deployment test'"
    echo "    SHOW_ERRORS LIMIT=5"
fi

if [ "$DEPLOY_DIAGNOSTICS" = true ]; then
    echo "    HEALTH_CHECK           # Run full health check"
    echo "    TEST_MOTORS AXIS=X DISTANCE=10"
fi

if [ "$DEPLOY_WEB" = true ]; then
    echo ""
    echo -e "${GREEN}Web Dashboards:${NC}"
    PRINTER_IP=$(ssh_cmd "hostname -I | awk '{print \$1}'" 2>/dev/null || echo "$PRINTER_HOST")
    echo "    Main:        http://${PRINTER_IP}:4408/k2-monitor/"
    echo "    Diagnostics: http://${PRINTER_IP}:4408/k2-monitor/diagnostics.html"
    echo ""
    echo -e "  ${GREEN}Access via same port as Fluidd (4408)${NC}"
fi

echo ""
echo -e "${GREEN}Documentation:${NC}"
echo "  Copied to your local directory:"
echo "    - README.md"
echo "    - FIRMWARE_ERROR_HANDLING_ANALYSIS.md"
echo "    - WEB_DASHBOARD_DESIGN.md"
echo "    - DIAGNOSTICS_GUIDE.md"
echo ""

# Rollback instructions
echo -e "${YELLOW}Rollback Instructions:${NC}"
echo "  If you need to revert:"
echo "    ssh ${PRINTER_USER}@${PRINTER_HOST}"
echo "    cd $REMOTE_CFG_DIR"
echo "    cp printer.cfg.backup.$BACKUP_TIMESTAMP printer.cfg"
echo "    systemctl restart klipper"
echo ""

echo "========================================="
echo -e "${GREEN}All done! Your K2 $MODEL_NAME is enhanced!${NC}"
echo "========================================="
echo ""

exit 0
