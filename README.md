# K2 Unleashed - Enhanced Monitoring & Diagnostics for Creality K2 Series

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

---

## ⚠️ DANGER - READ THIS FIRST ⚠️

### THIS SOFTWARE IS NOT FOR THE FAINT OF HEART

**STOP RIGHT NOW** if you:
- Don't understand SSH, Python, or Klipper configuration
- Haven't backed up your printer's configuration
- Can't recover from a bricked printer
- Aren't comfortable with command-line tools
- Don't have time to troubleshoot issues

### SERIOUS WARNINGS

🔥 **YOU CAN BRICK YOUR PRINTER** - Incorrect installation or configuration can render your printer inoperable.

🔥 **YOU CAN CAUSE FIRES** - Bugs in temperature monitoring, heater control, or thermal runaway protection could cause fires. Never leave your printer unattended.

🔥 **YOU CAN DAMAGE HARDWARE** - Incorrect motor movements, homing sequences, or probe configurations can physically damage your printer.

🔥 **YOU CAN LOSE DATA** - Installation requires modifying system files. Data loss is possible.

🔥 **YOU VOID WARRANTIES** - Using this software likely voids your Creality warranty. You're on your own.

🔥 **NO SUPPORT GUARANTEE** - This is community software. We help when we can, but we're not your tech support.

🔥 **ACTIVE DEVELOPMENT** - This software is under active development and may contain bugs, incomplete features, and breaking changes.

### WHAT THIS SOFTWARE DOES

This software **directly modifies your printer's control system** by:
- Installing custom Klipper modules that run with root privileges
- Modifying printer.cfg which controls ALL printer behavior
- Querying hardware sensors and actuators in real-time
- Running web servers on your printer
- Executing G-code and system commands automatically
- Storing persistent data on your printer's filesystem

### DISCLAIMER - NO WARRANTY

```
THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
```

**Translation:** If this software bricks your printer, burns down your house, or causes any other damage - that's YOUR problem, not ours. Use at your own risk.

### YOU HAVE BEEN WARNED

By using this software, you acknowledge that:
- ✅ You understand the risks
- ✅ You accept full responsibility for any damage
- ✅ You have backed up your printer configuration
- ✅ You can restore your printer if something goes wrong
- ✅ You won't blame us when things break

**Still here? Good. You're brave (or foolish). Let's continue...**

---

## About This Project

This is a fork of the official Creality K2 series Klipper firmware with community-developed enhancements.

**Base:** Clone from https://github.com/Klipper3d/klipper/

[![Klipper](docs/img/klipper-logo-small.png)](https://www.klipper3d.org/)

**Upstream:** https://github.com/CrealityOfficial/K2_Series_Klipper

Used on Creality K2 series devices (K2 Plus, K2 Pro, K2 Base)

## Configuration Files by Model

The configuration files are organized by internal model codes in the `config/` directory:

| Model Code | Printer Model | Build Volume | Z Motors | Board Variant |
|------------|---------------|--------------|----------|---------------|
| **F008** | K2 Plus | 350×350×350mm | Dual Z | Standard |
| **F008_CR0CN240319C13** | K2 Plus | 350×350×350mm | Dual Z | Alternate board revision |
| **F012_CR0CN200400C10** | K2 Pro | 300×300×300mm | Single Z | 8GB storage |
| **F021_CR0CN200400C10** | K2 Base | 260×260×260mm | Single Z | 8GB storage |

**How to identify your model:**
- Check your printer's control board version number
- K2 Plus uses F008 configs (dual Z motors with z_tilt leveling)
- K2 Pro uses F012 configs (single Z motor, 300mm build plate)
- K2 Base uses F021 configs (single Z motor, 260mm build plate)

release： https://github.com/CrealityOfficial/K2_Series_Klipper/releases

firmware-recovery-tool: https://wiki.creality.com/en/k2-flagship-series/k2-plus/firmware-flashing

---

## 🆕 Enhanced Features (Community Additions)

This fork includes significant improvements over the stock firmware:

### 📊 System Monitor
Complete real-time monitoring and error tracking system.

**Features:**
- ✅ Real-time status aggregation (all temps, positions, states)
- ✅ Complete error history with codes and context
- ✅ Persistent error logging (survives restarts)
- ✅ Web-based dashboard with auto-refresh
- ✅ G-code commands for status queries
- ✅ Moonraker API integration

**Files:**
- `klippy/extras/system_monitor.py` - Backend module
- `config/F012_CR0CN200400C10/system_monitor.cfg` - Configuration
- `web_dashboard/index.html` - Web interface

**Quick Start:**
```ini
# Add to printer.cfg
[include system_monitor.cfg]
```

**G-code Commands:**
```gcode
SYSTEM_STATUS          # Display complete system status
LOG_ERROR CODE=E999 MSG="Custom error"  # Log errors
SHOW_ERRORS LIMIT=10   # Show recent errors
```

**Web Dashboard:** `http://your-printer-ip:8080/`

**Documentation:** See [specs/WEB_DASHBOARD_DESIGN.md](specs/WEB_DASHBOARD_DESIGN.md) (developer specs)

---

### 🔧 Diagnostic Tools
Comprehensive system testing and health checks.

**Features:**
- ✅ Automated health checks (homing, motors, heaters, fans, etc.)
- ✅ Individual component tests
- ✅ Web-based test interface
- ✅ Test history tracking
- ✅ Error integration with system monitor
- ✅ Pre-print validation

**Available Tests:**
- Homing test (all axes)
- Motor movement accuracy
- Heater response and stability
- Probe accuracy and repeatability
- Fan functionality
- Endstop states
- Belt tension (using belt_mdl)

**Files:**
- `klippy/extras/diagnostics.py` - Diagnostic engine
- `config/F012_CR0CN200400C10/diagnostics.cfg` - Configuration
- `web_dashboard/diagnostics.html` - Test interface

**Quick Start:**
```ini
# Add to printer.cfg
[include diagnostics.cfg]
```

**G-code Commands:**
```gcode
HEALTH_CHECK                    # Run full health check
DIAGNOSTIC_TEST TEST=homing     # Run specific test
TEST_MOTORS AXIS=X DISTANCE=10  # Test motor accuracy
TEST_HEATERS HEATER=extruder TEMP=50  # Test heater
TEST_PROBE SAMPLES=10           # Test probe accuracy
```

**Web Interface:** `http://your-printer-ip:8080/diagnostics.html`

**Documentation:** See [docs_k2-unleashed/DIAGNOSTICS_GUIDE.md](docs_k2-unleashed/DIAGNOSTICS_GUIDE.md) (user guide)

---

### 📝 Error Handling Analysis
Detailed analysis of firmware error handling issues and recommendations.

**What's Covered:**
- State tracking limitations
- Error context problems
- Binary blob dependencies (CFS, PRTouch, etc.)
- Comparison with industry standards
- Recommended improvements
- Practical workarounds

**Documentation:** See [specs/FIRMWARE_ERROR_HANDLING_ANALYSIS.md](specs/FIRMWARE_ERROR_HANDLING_ANALYSIS.md)

---

## Installation

### Quick Start (Recommended)

The easiest way to use K2 Unleashed is with the command-line tool:

```bash
# 1. Clone repository
git clone https://github.com/YOUR_FORK/k2-unleashed.git
cd k2-unleashed

# 2. Initialize configuration
./k2-unleashed init

# 3. Edit .env with your printer's IP address
nano .env

# 4. Deploy enhanced features
./k2-unleashed upgrade

# 5. Verify installation
./k2-unleashed status
./k2-unleashed check
```

**Optional:** Add to PATH for system-wide access:
```bash
sudo ln -s $(pwd)/k2-unleashed /usr/local/bin/k2-unleashed
# Now use from anywhere: k2-unleashed status
```

### CLI Commands

```bash
k2-unleashed status        # Check printer status
k2-unleashed upgrade       # Deploy/upgrade features
k2-unleashed backup        # Backup configuration
k2-unleashed rollback <ID> # Restore from backup
k2-unleashed check         # Run health check
k2-unleashed logs          # View Klipper logs
k2-unleashed --help        # Show all commands
```

### Manual Installation (Advanced)

If you prefer manual installation or need to customize:

1. **Deploy Python modules** to printer via SSH
2. **Copy config files** to printer's config directory
3. **Add includes** to printer.cfg:
   ```ini
   [include system_monitor.cfg]
   [include diagnostics.cfg]
   ```
4. **Restart Klipper**

See individual scripts in `scripts/` directory for details.

---

## Documentation

### User Guides
- `README.md` - This file (overview and installation)
- [docs_k2-unleashed/](docs_k2-unleashed/) - **User documentation directory**
  - [BED_LEVELING_GUIDE.md](docs_k2-unleashed/BED_LEVELING_GUIDE.md) - Precision bed leveling guide
  - [DIAGNOSTICS_GUIDE.md](docs_k2-unleashed/DIAGNOSTICS_GUIDE.md) - Complete diagnostics guide
  - [CLI_GUIDE.md](docs_k2-unleashed/CLI_GUIDE.md) - CLI tool usage guide

### Developer Specs
- [specs/](specs/) - **Technical specifications directory**
  - [FIRMWARE_ERROR_HANDLING_ANALYSIS.md](specs/FIRMWARE_ERROR_HANDLING_ANALYSIS.md) - Error handling analysis
  - [WEB_DASHBOARD_DESIGN.md](specs/WEB_DASHBOARD_DESIGN.md) - Dashboard architecture and API
  - [MONITORING_FIX_SUMMARY.md](specs/MONITORING_FIX_SUMMARY.md) - Monitoring fix technical details
  - [IMPLEMENTATION_COMPLETE.md](specs/IMPLEMENTATION_COMPLETE.md) - Implementation status

### Other
- `web_dashboard/README.md` - Web interface installation

---

## Known Issues

### Binary Blobs (Proprietary Code)
The following modules are **closed source** and cannot be modified:
- `box_wrapper.cpython-39.so` (1.7MB) - CFS/multi-color control
- `prtouch_v3_wrapper.cpython-39.so` - PRTouch bed leveling
- `serial_485_wrapper.cpython-39.so` - RS485 CFS communication
- `motor_control_wrapper.cpython-39.so` - Motor diagnostics
- `filament_rack_wrapper.cpython-39.so` - Filament management

**Impact:**
- Cannot debug CFS errors
- Cannot customize multi-color behavior
- Limited error recovery options

**Workaround:**
Use the system monitor and diagnostics to track errors around these modules.

### Error Tracking Limitations
Stock firmware has minimal error tracking. The system_monitor module addresses this by:
- Adding structured error codes
- Tracking error history
- Providing context for each error
- Persisting errors to log file

---

## Contributing

Improvements welcome! Areas for contribution:
- Additional diagnostic tests
- Better error handling
- Enhanced web interface
- Documentation improvements
- Bug fixes

**Please note:** We cannot modify the proprietary binary blobs. Focus contributions on:
- Klipper Python modules
- Configuration improvements
- Web interface enhancements
- Documentation

---

## Support

- **Issues:** File in this repository's issue tracker
- **Discussions:** Use GitHub Discussions
- **Official Creality Support:** https://www.creality.com/pages/contact-us

---

## Credits

- **Base Firmware:** [Klipper3d](https://github.com/Klipper3d/klipper/)
- **K2 Adaptations:** Creality
- **Enhanced Features:** Community contributors

---

## License

K2 Unleashed is licensed under the **GNU General Public License v3.0** (GPLv3), the same license as Klipper.

### What This Means

**You are free to:**
- ✅ Use this software for any purpose (personal, commercial, etc.)
- ✅ Study how the program works and modify it
- ✅ Redistribute copies
- ✅ Distribute modified versions

**Under these conditions:**
- ⚠️ You must disclose the source code of any modifications
- ⚠️ You must license modified versions under GPLv3
- ⚠️ You must state significant changes made to the software
- ⚠️ You cannot add additional restrictions

### No Warranty

This program is distributed **WITHOUT ANY WARRANTY**; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

### Full License Text

See [LICENSE](LICENSE) file for the complete GNU General Public License v3.0 text.

### Copyright Notices

- **Klipper base:** Copyright (C) Kevin O'Connor <kevin@koconnor.net>
- **K2 adaptations:** Copyright (C) Creality
- **K2 Unleashed enhancements:** Copyright (C) 2025 K2 Unleashed Contributors

All contributions to this project are licensed under GPLv3.
