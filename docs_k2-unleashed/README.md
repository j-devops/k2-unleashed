# K2 Unleashed - User Documentation

This directory contains end-user documentation and guides for K2 Unleashed.

## User Guides

### 🛏️ [Bed Leveling Guide](BED_LEVELING_GUIDE.md)
Complete step-by-step guide to enabling precision bed leveling with `SCREWS_TILT_CALCULATE` on K2 series printers.

**What you'll learn:**
- How to enable root access on K2 Pro
- Installing the missing Klipper module via SSH
- Configuring bed screw positions
- Creating calibration macros
- Interpreting clock-face output (CW/CCW adjustments)
- Achieving <0.3mm bed variance

**For:** K2 Plus, K2 Pro, K2 Base (all models)

---

### 🔧 [Diagnostics Guide](DIAGNOSTICS_GUIDE.md)
Comprehensive guide to using the diagnostic system for troubleshooting and health checks.

**What you'll learn:**
- Running automated health checks
- Testing individual components (motors, heaters, probe, fans)
- Interpreting test results
- Using G-code diagnostic commands
- Accessing the web-based test interface
- Troubleshooting common issues

**Best for:** Preventive maintenance and troubleshooting

---

### 💻 [CLI Guide](CLI_GUIDE.md)
Complete reference for the `k2-unleashed` command-line tool.

**What you'll learn:**
- Installing and configuring k2-unleashed
- Deploying features to your printer
- Managing backups and rollbacks
- Viewing logs and status
- Running health checks remotely
- All available commands and options

**Best for:** Power users and remote management

---

## Quick Links

- [Main README](../README.md) - Project overview and installation
- [Developer Specs](../specs/) - Technical specifications (for developers)
- [Web Dashboard](../web_dashboard/) - Web interface files
- [Scripts](../scripts/) - Deployment scripts

## Getting Help

- **Installation issues:** See the main [README.md](../README.md)
- **Troubleshooting:** Check the relevant guide above
- **Bug reports:** [GitHub Issues](https://github.com/j-devops/k2-unleashed/issues)
- **Questions:** [GitHub Discussions](https://github.com/j-devops/k2-unleashed/discussions)

## Contributing

Found an error or want to improve the documentation? PRs welcome!

1. Fork the repository
2. Make your changes
3. Submit a pull request

Please keep documentation:
- Clear and concise
- Beginner-friendly
- Well-formatted with examples
- Up-to-date with current features

## License

All documentation is licensed under GNU General Public License v3.0, same as the code.
