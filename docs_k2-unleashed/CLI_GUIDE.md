# K2 Unleashed - Command-Line Interface Guide

Complete guide to the `k2-unleashed` CLI tool for managing your K2 printer enhancements.

---

## Quick Start

```bash
# First-time setup
./k2-unleashed init              # Create .env configuration
nano .env                        # Edit printer IP address
./k2-unleashed status            # Test connection
./k2-unleashed upgrade           # Deploy features
```

---

## Installation

### Local Usage

```bash
# Clone repository
git clone https://github.com/YOUR_FORK/k2-unleashed.git
cd k2-unleashed

# Make executable (if needed)
chmod +x k2-unleashed

# Run commands
./k2-unleashed status
```

### System-Wide Installation

```bash
# Add to PATH for global access
sudo ln -s $(pwd)/k2-unleashed /usr/local/bin/k2-unleashed

# Now use from anywhere
k2-unleashed status
```

---

## Commands

### `k2-unleashed init`

Initialize configuration by creating `.env` file from template.

**Example:**
```bash
./k2-unleashed init
```

**Output:**
- Creates `.env` from `.env.example`
- Shows next steps for configuration

**Configuration Variables:**
- `PRINTER_HOST` - Printer IP address
- `PRINTER_USER` - SSH username (default: root)
- `PRINTER_PASSWORD` - SSH password (default: creality2024)
- `PRINTER_PORT` - SSH port (default: 22)
- `K2_MODEL` - Printer model (1=Plus, 2=Pro, 3=Base)
- `DEPLOY_CHOICE` - Features to install (1/2/3)
- `AUTO_CONFIRM` - Skip confirmation prompts (yes/no)

---

### `k2-unleashed status`

Check printer status and installed features.

**Example:**
```bash
k2-unleashed status
```

**Shows:**
- ✅ Connection status
- ✅ Klipper service status and uptime
- ✅ Installed enhanced features
- ✅ Recent errors (if any)
- ✅ System resources (CPU, RAM, disk)

**Use Cases:**
- Verify printer is online
- Check which features are installed
- Monitor system health
- Quick troubleshooting

---

### `k2-unleashed upgrade`

Deploy or upgrade enhanced features to printer.

**Example:**
```bash
k2-unleashed upgrade
```

**What it does:**
1. Tests SSH connection
2. Detects printer configuration
3. Backs up current printer.cfg
4. Deploys Python modules
5. Copies configuration files
6. Updates printer.cfg includes
7. Restarts Klipper
8. Verifies installation

**Features Deployed:**
Based on `DEPLOY_CHOICE` in `.env`:
- **1**: System Monitor only
- **2**: System Monitor + Diagnostics (recommended)
- **3**: Everything (monitor, diagnostics, web dashboard)

**Safety:**
- Creates automatic backup before changes
- Non-destructive (preserves existing configs)
- Idempotent (safe to run multiple times)

---

### `k2-unleashed backup`

Create backup of printer configuration.

**Example:**
```bash
k2-unleashed backup
```

**What gets backed up:**
- printer.cfg
- system_monitor.cfg (if installed)
- diagnostics.cfg (if installed)
- All .cfg files (archived)
- System information

**Backup Location:**
```
backups/backup_YYYYMMDD_HHMMSS/
├── printer.cfg
├── system_monitor.cfg
├── diagnostics.cfg
├── all_configs.tar.gz
└── backup_info.txt
```

**Use Cases:**
- Before making changes
- Before upgrading
- Regular backups (cron job)
- Before experimenting

**Recommended Schedule:**
```bash
# Weekly backup (add to crontab)
0 0 * * 0 /path/to/k2-unleashed backup
```

---

### `k2-unleashed rollback <backup_id>`

Restore configuration from backup.

**Example:**
```bash
# List available backups
k2-unleashed rollback

# Restore specific backup
k2-unleashed rollback 20240115_143022
```

**What it does:**
1. Validates backup exists
2. Creates safety backup of current config
3. Restores files from backup
4. Restarts Klipper
5. Verifies Klipper starts

**Safety Features:**
- Creates pre-rollback backup
- Confirms before restoring (unless AUTO_CONFIRM=yes)
- Validates backup integrity
- Clear rollback instructions if needed

**Backup ID Format:**
- YYYYMMDD_HHMMSS (e.g., 20240115_143022)
- Or just the timestamp portion

---

### `k2-unleashed check`

Run health check diagnostics on printer.

**Example:**
```bash
k2-unleashed check
```

**What it tests:**
- SSH connection
- Klipper status
- Diagnostics module installed
- Printer state (idle/printing)
- Runs HEALTH_CHECK via Moonraker API

**Tests Performed:**
1. Homing (X/Y axes)
2. Endstop states
3. Fan functionality
4. Belt tension

**Output:**
- Test results in console
- Results logged to error history
- Available in web dashboard

**Use Cases:**
- Pre-print verification
- After maintenance
- Troubleshooting issues
- Regular health monitoring

**Requirements:**
- Diagnostics module must be installed
- Printer must be idle (not printing)

---

### `k2-unleashed logs`

View Klipper logs in real-time.

**Example:**
```bash
k2-unleashed logs
```

**Features:**
- Live log streaming via SSH
- Follows new entries (like `tail -f`)
- Press Ctrl+C to exit

**Use Cases:**
- Debugging issues
- Monitoring print start
- Watching health check results
- Troubleshooting errors

**Alternative:**
```bash
# View specific time range
ssh root@printer-ip "journalctl -u klipper --since '1 hour ago'"

# Search for errors
ssh root@printer-ip "journalctl -u klipper | grep -i error"
```

---

## Options

### `-h, --help`

Show help message with all commands.

```bash
k2-unleashed --help
k2-unleashed -h
```

### `-v, --version`

Show version information.

```bash
k2-unleashed --version
k2-unleashed -v
```

### `-q, --quiet`

Suppress non-error output (future feature).

```bash
k2-unleashed -q status
```

---

## Configuration File (.env)

The `.env` file contains all printer connection and deployment settings.

**Required Variables:**
```bash
PRINTER_HOST=192.168.1.113    # Your printer's IP
PRINTER_USER=root              # SSH username
PRINTER_PORT=22                # SSH port
PRINTER_PASSWORD=creality2024  # SSH password (or use SSH keys)
K2_MODEL=2                     # 1=Plus, 2=Pro, 3=Base
DEPLOY_CHOICE=3                # 1=Monitor, 2=Monitor+Diag, 3=All
```

**Optional Variables:**
```bash
AUTO_CONFIRM=yes               # Skip confirmation prompts
```

**Security Best Practices:**
1. Use SSH key authentication instead of password:
   ```bash
   ssh-copy-id root@printer-ip
   # Then remove PRINTER_PASSWORD from .env
   ```

2. Never commit `.env` to git (already in `.gitignore`)

3. Restrict file permissions:
   ```bash
   chmod 600 .env
   ```

---

## Workflow Examples

### First-Time Setup

```bash
# 1. Clone and initialize
git clone https://github.com/YOUR_FORK/k2-unleashed.git
cd k2-unleashed
./k2-unleashed init

# 2. Configure
nano .env  # Set PRINTER_HOST to your printer's IP

# 3. Test connection
./k2-unleashed status

# 4. Deploy features
./k2-unleashed upgrade

# 5. Verify
./k2-unleashed check
```

### Regular Maintenance

```bash
# Weekly backup
./k2-unleashed backup

# Monthly health check
./k2-unleashed check

# Monitor logs
./k2-unleashed logs
```

### Troubleshooting

```bash
# Check status
./k2-unleashed status

# View recent errors
./k2-unleashed logs

# Run diagnostics
./k2-unleashed check

# If issues persist, rollback
./k2-unleashed rollback <backup_id>
```

### Upgrading Features

```bash
# Create backup first
./k2-unleashed backup

# Pull latest changes
git pull

# Upgrade printer
./k2-unleashed upgrade

# Verify
./k2-unleashed status
./k2-unleashed check
```

---

## Automation

### Cron Jobs

Add to crontab for automated tasks:

```bash
# Edit crontab
crontab -e

# Add automated backup (every Sunday at midnight)
0 0 * * 0 /path/to/k2-unleashed backup

# Add health check (every day at 6 AM)
0 6 * * * /path/to/k2-unleashed check
```

### CI/CD Integration

```bash
# Deploy via CI/CD (fully automated)
export AUTO_CONFIRM=yes
./k2-unleashed upgrade
```

### Scripts

```bash
#!/bin/bash
# Custom deployment script

# Backup before deploy
./k2-unleashed backup

# Deploy changes
./k2-unleashed upgrade

# Verify deployment
./k2-unleashed status

# Run health check
./k2-unleashed check
```

---

## Troubleshooting

### "Error: .env file not found"

```bash
# Initialize configuration
./k2-unleashed init

# Edit with your printer details
nano .env
```

### "Cannot connect to printer"

```bash
# Check network connectivity
ping $PRINTER_HOST

# Test SSH manually
ssh root@$PRINTER_HOST

# Verify .env settings
cat .env
```

### "Permission denied"

```bash
# Make executable
chmod +x k2-unleashed
chmod +x scripts/*.sh

# Or use bash explicitly
bash k2-unleashed status
```

### "Diagnostics not installed"

```bash
# Check deployment choice
grep DEPLOY_CHOICE .env

# Should be 2 or 3 for diagnostics
# Edit .env and change to DEPLOY_CHOICE=2

# Redeploy
./k2-unleashed upgrade
```

---

## File Structure

```
k2-unleashed/
├── k2-unleashed              # Main CLI tool
├── .env                      # Your configuration (not in git)
├── .env.example              # Configuration template
├── scripts/                  # Command implementations
│   ├── deploy.sh            # upgrade command
│   ├── install.sh           # local install (deprecated)
│   ├── status.sh            # status command
│   ├── backup.sh            # backup command
│   ├── rollback.sh          # rollback command
│   └── check.sh             # check command
├── backups/                  # Backup storage
│   └── backup_YYYYMMDD_HHMMSS/
├── klippy/extras/           # Python modules
│   ├── system_monitor.py
│   └── diagnostics.py
├── config/                   # Configuration files
│   └── F012_CR0CN200400C10/
│       ├── system_monitor.cfg
│       └── diagnostics.cfg
└── web_dashboard/           # Web interface
    ├── index.html
    └── diagnostics.html
```

---

## Advanced Usage

### Custom SSH Port

```bash
# Edit .env
PRINTER_PORT=2222

# Works with all commands
./k2-unleashed status
```

### Multiple Printers

```bash
# Use different .env files
./k2-unleashed --config printer1.env status
./k2-unleashed --config printer2.env status

# Or use multiple directories
mkdir printer1 printer2
cp .env printer1/
cp .env printer2/
# Edit each .env with different PRINTER_HOST
```

### SSH Key Authentication

```bash
# Copy SSH key to printer
ssh-copy-id root@printer-ip

# Remove password from .env
nano .env  # Comment out PRINTER_PASSWORD

# More secure and faster!
```

---

## Support

**Documentation:**
- `README.md` - Overview
- `DIAGNOSTICS_GUIDE.md` - Diagnostics reference
- `WEB_DASHBOARD_DESIGN.md` - Web UI docs
- `FIRMWARE_ERROR_HANDLING_ANALYSIS.md` - Error handling

**Help:**
- GitHub Issues: https://github.com/user/k2-unleashed/issues
- Run: `k2-unleashed --help`

---

## License

GPL v3 (same as Klipper)
