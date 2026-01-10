# K2 Pro Web Dashboard

A comprehensive web-based monitoring dashboard for the Creality K2 Pro 3D printer with complete error tracking.

## Features

- ✅ **Real-time status monitoring** - All printer states, positions, temperatures
- ✅ **Complete error history** - Track all errors with timestamps and context
- ✅ **CFS/Multi-color status** - Monitor filament box connection and materials
- ✅ **Resource monitoring** - CPU, memory, MCU load tracking
- ✅ **Clean, responsive UI** - Works on desktop and mobile
- ✅ **Auto-refresh** - Real-time updates every second

## Installation

### Step 1: Install Backend Module

1. The `system_monitor.py` module should already be in `klippy/extras/`

2. Add to your printer.cfg:
   ```ini
   [include system_monitor.cfg]
   ```

3. Restart Klipper:
   ```bash
   sudo systemctl restart klipper
   ```

4. Verify it's working:
   ```gcode
   SYSTEM_STATUS
   ```

### Step 2: Deploy Web Dashboard

#### Option A: Serve from Nginx (Recommended)

1. Copy dashboard to web directory:
   ```bash
   sudo mkdir -p /usr/data/www/k2-monitor
   sudo cp index.html /usr/data/www/k2-monitor/
   ```

2. Add nginx config (`/etc/nginx/sites-available/k2-monitor`):
   ```nginx
   server {
       listen 8080;
       server_name _;

       root /usr/data/www/k2-monitor;
       index index.html;

       location / {
           try_files $uri $uri/ =404;
       }

       # Proxy to Moonraker
       location /server/ {
           proxy_pass http://localhost:7125/server/;
       }

       location /printer/ {
           proxy_pass http://localhost:7125/printer/;
       }
   }
   ```

3. Enable and restart:
   ```bash
   sudo ln -s /etc/nginx/sites-available/k2-monitor /etc/nginx/sites-enabled/
   sudo systemctl restart nginx
   ```

4. Access at: `http://your-printer-ip:8080`

#### Option B: Direct Access

Simply open `index.html` in a browser and change `MOONRAKER_URL` to your printer's IP:

```javascript
const MOONRAKER_URL = 'http://192.168.1.100:7125';
```

## Usage

### Viewing Status

The dashboard automatically updates every second showing:

- **Printer State**: Current status (printing, paused, etc.)
- **Position**: X, Y, Z, E coordinates
- **Temperatures**: Hotend, bed, chamber (current/target)
- **CFS**: Multi-color box connection and active material
- **Resources**: System CPU/MCU load

### Error Monitoring

All errors are logged with:
- Timestamp
- Severity (INFO, WARNING, ERROR, CRITICAL)
- Error code
- Detailed message
- System state at time of error

Click **Clear** to clear error history (also clears from backend).

### G-code Commands

From the console or macros:

```gcode
# View system status
SYSTEM_STATUS

# Log custom error
LOG_ERROR CODE=E999 MSG="Custom error message"

# Show recent errors
SHOW_ERRORS LIMIT=10
```

### API Endpoints

The backend exposes these Moonraker endpoints:

#### GET `/server/system_monitor/status`
Get complete system status (JSON)

#### GET `/server/system_monitor/errors?limit=50&offset=0`
Get error history with pagination

#### POST `/server/system_monitor/log_error`
Log a custom error
```json
{
  "severity": "ERROR",
  "code": "E999",
  "message": "Custom error",
  "context": {}
}
```

#### POST `/server/system_monitor/clear_errors`
Clear all error history

## Customization

### Update Interval

In `index.html`, change:
```javascript
const UPDATE_INTERVAL = 1000; // ms (default: 1 second)
```

### Error Log Persistence

In `system_monitor.cfg`:
```ini
[system_monitor]
persist_errors: True
error_log_path: /usr/data/printer_data/logs/system_errors.jsonl
```

### Adding Custom Error Codes

Edit `klippy/extras/system_monitor.py` to add your error codes and tracking logic.

## Troubleshooting

### Dashboard shows "Connecting to printer..."

1. Check Moonraker is running:
   ```bash
   sudo systemctl status moonraker
   ```

2. Verify system_monitor loaded:
   ```bash
   grep "SystemMonitor" /tmp/klippy.log
   ```

3. Check browser console for errors (F12)

### Errors not showing

1. Check error log file exists:
   ```bash
   cat /usr/data/printer_data/logs/system_errors.jsonl
   ```

2. Test logging manually:
   ```gcode
   LOG_ERROR CODE=TEST MSG="Test error"
   SHOW_ERRORS
   ```

### CFS status shows "No"

This is normal if:
- CFS is not connected
- `box_wrapper.cpython-39.so` doesn't expose status (it's proprietary)

The system monitor will show what's available from the binary blob.

## Integration with Macros

### Log errors from macros:

```gcode
[gcode_macro START_PRINT]
gcode:
  {% if not printer.toolhead.homed_axes %}
    LOG_ERROR CODE=E001 MSG="Printer not homed before print start"
    {action_raise_error("Printer must be homed first")}
  {% endif %}
  # ... rest of macro
```

### Enhanced error handling:

```gcode
[gcode_macro SAFE_HOME]
gcode:
  {% if printer.print_stats.state == "printing" %}
    LOG_ERROR CODE=E005 MSG="Cannot home while printing"
  {% else %}
    G28
    LOG_ERROR CODE=I001 MSG="Homing completed" SEVERITY=INFO
  {% endif %}
```

## Future Enhancements

- [ ] Temperature graphs (historical data)
- [ ] Print time estimation
- [ ] Material usage tracking
- [ ] Email/push notifications for errors
- [ ] Diagnostic test tools (one-click tests)
- [ ] Export error history to CSV
- [ ] Dark/light theme toggle
- [ ] Mobile app (React Native)

## Contributing

This is custom firmware for the K2 Pro. Improvements welcome!

## License

GPL v3 (same as Klipper)
