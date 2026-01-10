# K2 Unleashed - Documentation & Specifications

This directory contains detailed documentation, specifications, and guides for K2 Unleashed.

## Documents

### User Guides

- **[BED_LEVELING_GUIDE.md](BED_LEVELING_GUIDE.md)** - Complete guide to enabling precision bed leveling with `SCREWS_TILT_CALCULATE` on K2 series printers. Includes step-by-step installation and usage instructions.

- **[DIAGNOSTICS_GUIDE.md](DIAGNOSTICS_GUIDE.md)** - Comprehensive guide to the diagnostics system including all available tests, health checks, G-code commands, and troubleshooting.

- **[CLI_GUIDE.md](CLI_GUIDE.md)** - Complete reference for the `k2-unleashed` command-line tool including all commands, options, and usage examples.

### Technical Documentation

- **[WEB_DASHBOARD_DESIGN.md](WEB_DASHBOARD_DESIGN.md)** - Architecture and design documentation for the web-based monitoring dashboard. Includes API endpoints, data structures, and implementation details.

- **[FIRMWARE_ERROR_HANDLING_ANALYSIS.md](FIRMWARE_ERROR_HANDLING_ANALYSIS.md)** - Detailed analysis of error handling in the K2 firmware, identifying issues and providing recommendations for improvements.

- **[MONITORING_FIX_SUMMARY.md](MONITORING_FIX_SUMMARY.md)** - Technical deep-dive into the monitoring system fix that prevents print failures. Explains the smart caching system and non-blocking query implementation.

### Project Documentation

- **[IMPLEMENTATION_COMPLETE.md](IMPLEMENTATION_COMPLETE.md)** - Implementation summary and completion status of all K2 Unleashed features.

## Quick Links

- [Main README](../README.md) - Project overview and installation
- [Web Dashboard](../web_dashboard/) - Web interface files
- [Scripts](../scripts/) - Deployment and management scripts
- [Klipper Extras](../klippy/extras/) - Custom Klipper modules

## Contributing Documentation

When adding new documentation:

1. **Place it in this directory** - Keep the root clean
2. **Update this README** - Add your doc to the appropriate section
3. **Link from main README** - Add reference in main README.md
4. **Use clear titles** - Make documents easy to find
5. **Include examples** - Show, don't just tell
6. **Keep it current** - Update when features change

## Documentation Standards

- Use Markdown formatting
- Include code examples with syntax highlighting
- Add screenshots/images where helpful (store in `docs/img/`)
- Provide both quick-start and detailed sections
- Include troubleshooting sections
- Cross-reference related documents
- Keep a consistent tone and style

## License

All documentation is licensed under GNU General Public License v3.0, same as the code.
