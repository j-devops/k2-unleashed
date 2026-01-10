# K2 Unleashed - Developer Specifications

This directory contains technical specifications, architecture documentation, and implementation details for developers working on K2 Unleashed.

## Technical Specifications

### 🔍 [Firmware Error Handling Analysis](FIRMWARE_ERROR_HANDLING_ANALYSIS.md)
Deep-dive analysis of error handling in the K2 firmware.

**Contains:**
- State tracking limitations
- Error context problems
- Binary blob dependency analysis (CFS, PRTouch, etc.)
- Comparison with industry standards (Marlin, RepRapFirmware)
- Recommended improvements
- Practical workarounds

**Audience:** Developers investigating firmware issues, contributors proposing improvements

---

### 🌐 [Web Dashboard Design](WEB_DASHBOARD_DESIGN.md)
Complete architecture and design documentation for the web-based monitoring dashboard.

**Contains:**
- System architecture overview
- API endpoint specifications
- Data structures and schemas
- Frontend implementation details
- WebSocket communication protocol
- State management design
- Security considerations

**Audience:** Frontend developers, API consumers, dashboard contributors

---

### 🛠️ [Monitoring Fix Summary](MONITORING_FIX_SUMMARY.md)
Technical deep-dive into the monitoring system fix that prevents print failures.

**Contains:**
- Root cause analysis (timing interference)
- Smart caching system implementation
- Non-blocking query pattern
- Print-aware mode logic
- Performance impact analysis
- Testing recommendations
- Future improvement ideas

**Audience:** Backend developers, performance engineers, contributors debugging timing issues

---

### ✅ [Implementation Complete](IMPLEMENTATION_COMPLETE.md)
Project completion summary and implementation status.

**Contains:**
- Feature completion checklist
- Implementation timeline
- Known limitations
- Future roadmap
- Testing status
- Deployment notes

**Audience:** Project maintainers, contributors, release managers

---

## For End Users

**Looking for guides and how-tos?** See [User Documentation](../docs_k2-unleashed/)

User guides include:
- Bed leveling guide
- Diagnostics guide
- CLI tool usage

## Development Resources

### Source Code
- [klippy/extras/system_monitor.py](../klippy/extras/system_monitor.py) - Monitoring module
- [klippy/extras/diagnostics.py](../klippy/extras/diagnostics.py) - Diagnostics module
- [k2-unleashed](../k2-unleashed) - CLI tool
- [scripts/](../scripts/) - Deployment scripts
- [web_dashboard/](../web_dashboard/) - Web UI

### Configuration
- [config/](../config/) - Printer configurations by model

### Testing
- Run tests: `./scripts/check.sh`
- Deploy to test printer: `./k2-unleashed upgrade`

## Contributing

Want to contribute to K2 Unleashed? Great!

### Getting Started
1. Read the relevant spec documents
2. Check [GitHub Issues](https://github.com/j-devops/k2-unleashed/issues)
3. Fork the repository
4. Make your changes
5. Add tests if applicable
6. Submit a pull request

### Contribution Guidelines
- Follow existing code style
- Add GPL v3 headers to new files
- Update documentation
- Test on actual hardware when possible
- Explain the "why" in commit messages

### Areas for Contribution
- Additional diagnostic tests
- Better error handling
- Enhanced web interface
- Documentation improvements
- Bug fixes
- Performance optimizations

## Architecture Principles

K2 Unleashed follows these principles:

1. **Non-blocking** - Never interfere with print quality
2. **Graceful degradation** - Work even when components fail
3. **GPL v3 compliant** - Open source all the way
4. **Production-ready** - Tested on real hardware
5. **Well-documented** - Code and architecture explained

## License

All code and specifications are licensed under GNU General Public License v3.0.

See [LICENSE](../LICENSE) for full text.
