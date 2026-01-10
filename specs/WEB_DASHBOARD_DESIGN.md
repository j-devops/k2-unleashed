# K2 Pro Complete Status Dashboard

## Overview
A comprehensive web-based dashboard to monitor ALL aspects of the K2 Pro printer with complete error tracking and diagnostic capabilities.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Web Browser                          │
│  ┌───────────────────────────────────────────────────┐  │
│  │     React/Vue Dashboard (Frontend)                │  │
│  │  - Real-time state display                        │  │
│  │  - Error history viewer                           │  │
│  │  - Diagnostic tools                               │  │
│  │  - System health checks                           │  │
│  └─────────────────┬───────────────────────────────────┘  │
└────────────────────┼──────────────────────────────────────┘
                     │ WebSocket + REST API
┌────────────────────┼──────────────────────────────────────┐
│   Moonraker (if available) or Custom API Server         │
│  ┌─────────────────┴───────────────────────────────┐     │
│  │     Status Aggregator Module                    │     │
│  │  - Polls all Klipper objects                    │     │
│  │  - Aggregates state                             │     │
│  │  - Stores error history                         │     │
│  └─────────────────┬───────────────────────────────┘     │
└────────────────────┼──────────────────────────────────────┘
                     │ Klipper API
┌────────────────────┼──────────────────────────────────────┐
│                Klippy Core                                │
│  ┌─────────────────┴───────────────────────────────┐     │
│  │  Enhanced State Tracker (Python Module)         │     │
│  │  - Intercepts all state changes                 │     │
│  │  - Logs all errors with context                 │     │
│  │  - Provides unified status API                  │     │
│  └──────────────────────────────────────────────────┘     │
│                                                           │
│  Existing Modules:                                        │
│  - print_stats, pause_resume, toolhead                   │
│  - heaters, fans, sensors                                │
│  - box (CFS), prtouch, motor_control                     │
└───────────────────────────────────────────────────────────┘
```

---

## Features

### 1. Real-Time System Status

#### 1.1 Printer State
- **Current State**: standby, printing, paused, error, etc.
- **Homed Axes**: X, Y, Z status with visual indicators
- **Position**: Current X, Y, Z, E coordinates
- **Velocity/Acceleration**: Current limits and actual values
- **Uptime**: System uptime and print time

#### 1.2 Thermal Status
- **Hotend**
  - Current temp / Target temp
  - PID status
  - Heating rate
  - Power percentage
- **Heated Bed**
  - Current / Target
  - Power percentage
  - Thermal runaway state
- **Chamber**
  - Temperature
  - Heater state
  - Fan control

#### 1.3 Motion System
- **Motors**
  - X, Y, Z, E current positions
  - Enabled/disabled state
  - Current settings (mA)
  - Stall detection status
  - Temperature (if available)
- **Kinematics**
  - CoreXY tension balance
  - Z-tilt status
  - Bed mesh active/loaded

#### 1.4 CFS / Multi-Color Box
- **Connection Status**: RS485 communication state
- **Active Material**: Current filament loaded (T0-T15)
- **Buffer Status**: Filament buffer level
- **RFID Data**: Material type, color, remaining length
- **Cutting Status**: Cutter position, last cut result
- **Errors**: Communication errors, jam detection, sensor failures

#### 1.5 Sensors
- **Filament Sensor**: Triggered/clear
- **Probe (PRTouch)**
  - Z-offset
  - Last probe result
  - Temperature compensation
- **Fans**
  - Hotend fan RPM
  - Part cooling fan speed
  - Chamber fan speed
  - Auxiliary fans
- **Endstops**
  - X, Y, Z status
  - Virtual Z endstop (probe)

### 2. Error History & Logging

#### 2.1 Error Log Display
```
┌─────────────────────────────────────────────────────────┐
│ Error History                           [Clear] [Export]│
├──────┬───────────┬─────────┬────────────────────────────┤
│ Time │ Severity  │ Code    │ Message                    │
├──────┼───────────┼─────────┼────────────────────────────┤
│ 14:23│ ERROR     │ E301    │ Heater thermal runaway     │
│ 14:20│ WARNING   │ W102    │ Bed mesh not loaded        │
│ 14:15│ INFO      │ I001    │ Print started              │
│ 14:10│ ERROR     │ E205    │ CFS communication timeout  │
└──────┴───────────┴─────────┴────────────────────────────┘
```

#### 2.2 Error Details View
Click on any error to see:
- Full error context
- Stack trace (if available)
- Related state at time of error
- Suggested recovery actions
- Related documentation links

#### 2.3 Error Categories
- **CRITICAL**: System shutdown required
- **ERROR**: Operation failed, user intervention needed
- **WARNING**: Potential issue, monitoring required
- **INFO**: Normal state changes

### 3. Diagnostic Tools

#### 3.1 System Health Checks
Run comprehensive diagnostics:
- ✓ All axes homed and responding
- ✓ All heaters within tolerance
- ✓ Bed mesh loaded and valid
- ✓ CFS communication active
- ✓ All sensors reporting
- ✓ Filament loaded and detected
- ✓ Z-tilt calibrated
- ✓ Motor currents correct

#### 3.2 Interactive Tests
- **Home Axes**: Test homing of X, Y, Z individually
- **Move Commands**: Jog X/Y/Z with visual feedback
- **Heat Test**: Test heater response
- **Probe Test**: Run probe accuracy test
- **CFS Test**: Test filament load/unload
- **Motor Test**: Test motor movement and stallguard
- **Fan Test**: Test all fans at different speeds

#### 3.3 Configuration Viewer
- View current printer.cfg settings
- Highlight non-default values
- Show active overrides
- Compare to factory defaults

### 4. Advanced Monitoring

#### 4.1 Real-Time Graphs
- Temperature curves (hotend, bed, chamber)
- Position tracking during print
- Velocity/acceleration profiles
- CPU usage
- Network latency

#### 4.2 Resource Monitor
- CPU usage
- Memory usage
- Disk space
- Network bandwidth
- MCU load

#### 4.3 Statistics
- Total print time
- Total filament used
- Success rate
- Average print speed
- Error frequency by type

---

## Implementation Plan

### Phase 1: Backend (Klipper Module)

#### File: `klippy/extras/system_monitor.py`

```python
# Complete system status aggregator
class SystemMonitor:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.error_history = deque(maxlen=500)
        self.state_history = deque(maxlen=100)

        # Register for ALL state change events
        self.printer.register_event_handler("klippy:ready", ...)
        self.printer.register_event_handler("klippy:shutdown", ...)

        # Register webhooks for web UI
        webhooks = self.printer.lookup_object('webhooks')
        webhooks.register_endpoint("system_monitor/status",
                                   self.handle_status_request)
        webhooks.register_endpoint("system_monitor/errors",
                                   self.handle_errors_request)
        webhooks.register_endpoint("system_monitor/diagnostics",
                                   self.handle_diagnostics_request)

    def aggregate_status(self):
        # Collect from all subsystems
        return {
            "state": self.get_printer_state(),
            "motion": self.get_motion_status(),
            "thermal": self.get_thermal_status(),
            "sensors": self.get_sensor_status(),
            "cfs": self.get_cfs_status(),
            "resources": self.get_resource_status()
        }

    def log_error(self, severity, code, message, context=None):
        error = {
            "timestamp": time.time(),
            "severity": severity,
            "code": code,
            "message": message,
            "context": context or {}
        }
        self.error_history.append(error)
        # Also write to persistent log
        self.write_error_log(error)
```

#### File: `klippy/extras/error_tracker.py`

```python
# Intercept errors from all modules
class ErrorTracker:
    ERROR_CODES = {
        # Motion errors
        "E001": "Homing failed - X axis",
        "E002": "Homing failed - Y axis",
        "E003": "Homing failed - Z axis",
        "E004": "Endstop not triggered",

        # Thermal errors
        "E101": "Heater not heating",
        "E102": "Thermal runaway detected",
        "E103": "Thermistor disconnected",
        "E104": "Heater temperature drop",

        # CFS errors
        "E201": "CFS communication timeout",
        "E202": "Filament jam detected",
        "E203": "RFID read failure",
        "E204": "Cutting failure",

        # Probe errors
        "E301": "Probe not triggered",
        "E302": "Probe triggered before move",
        "E303": "Bed mesh generation failed",

        # System errors
        "E401": "MCU communication lost",
        "E402": "Out of memory",
        "E403": "Config error"
    }
```

### Phase 2: Frontend (Web Dashboard)

#### Tech Stack
- **Framework**: React (or Vue.js)
- **Real-time**: WebSocket via Moonraker API
- **Charts**: Chart.js or D3.js
- **UI**: Material-UI or Tailwind CSS
- **State**: Redux or Zustand

#### Main Components

```
src/
├── components/
│   ├── StatusOverview.jsx          # Main dashboard
│   ├── ErrorHistory.jsx            # Error log viewer
│   ├── ThermalMonitor.jsx          # Temperature graphs
│   ├── MotionStatus.jsx            # Position/motors
│   ├── CFSMonitor.jsx              # Multi-color status
│   ├── DiagnosticPanel.jsx         # Test tools
│   ├── ConfigViewer.jsx            # Configuration
│   └── ResourceMonitor.jsx         # System resources
├── services/
│   ├── api.js                      # Moonraker API client
│   ├── websocket.js                # Real-time updates
│   └── errorCodes.js               # Error code definitions
├── hooks/
│   ├── usePrinterStatus.js         # Status polling
│   ├── useErrorHistory.js          # Error tracking
│   └── useWebSocket.js             # WebSocket connection
└── App.jsx
```

#### Example Component: StatusOverview.jsx

```jsx
import React from 'react';
import { usePrinterStatus } from '../hooks/usePrinterStatus';

export function StatusOverview() {
  const { status, loading, error } = usePrinterStatus();

  if (loading) return <LoadingSpinner />;
  if (error) return <ErrorDisplay error={error} />;

  return (
    <div className="dashboard-grid">
      <StateCard state={status.state} />
      <PositionCard position={status.motion.position} />
      <ThermalCard thermal={status.thermal} />
      <CFSCard cfs={status.cfs} />
      <SensorGrid sensors={status.sensors} />
    </div>
  );
}
```

### Phase 3: Moonraker Integration

#### File: `moonraker/components/k2_monitor.py`

```python
# Moonraker component to expose system_monitor data
class K2Monitor:
    def __init__(self, config):
        self.server = config.get_server()
        self.klippy = self.server.lookup_component('klippy_connection')

        # Register API endpoints
        self.server.register_endpoint(
            "/api/k2/status", ["GET"],
            self._handle_status_request
        )
        self.server.register_endpoint(
            "/api/k2/errors", ["GET"],
            self._handle_errors_request
        )

        # Subscribe to Klipper events
        self.klippy.register_subscription("system_monitor/status")

    async def _handle_status_request(self, web_request):
        result = await self.klippy.request("system_monitor/status")
        return result
```

---

## API Endpoints

### GET `/api/k2/status`
Returns complete system status:
```json
{
  "state": {
    "current": "printing",
    "homed_axes": ["x", "y", "z"],
    "print_progress": 45.2
  },
  "motion": {
    "position": {"x": 150.0, "y": 150.0, "z": 5.2, "e": 123.4},
    "velocity": {"current": 150, "max": 600},
    "acceleration": {"current": 5000, "max": 30000}
  },
  "thermal": {
    "extruder": {"current": 220.5, "target": 220, "power": 45},
    "heater_bed": {"current": 60.2, "target": 60, "power": 15},
    "chamber": {"current": 35.0, "target": 0, "power": 0}
  },
  "cfs": {
    "connected": true,
    "active_material": "T01",
    "materials": [
      {"slot": "T00", "type": "PLA", "color": "Red", "remaining": 850},
      {"slot": "T01", "type": "PLA", "color": "Blue", "remaining": 750}
    ],
    "buffer_level": 65
  },
  "sensors": {
    "filament_sensor": {"triggered": true, "enabled": true},
    "probe": {"z_offset": -0.05, "last_result": 0.002},
    "fans": {
      "hotend": {"speed": 255, "rpm": 7200},
      "part_cooling": {"speed": 127, "target": 50},
      "chamber": {"speed": 200, "target": 78}
    }
  },
  "resources": {
    "cpu_usage": 25.5,
    "memory_usage": 45.2,
    "mcu_load": 12.3
  }
}
```

### GET `/api/k2/errors?limit=50&offset=0`
Returns error history:
```json
{
  "errors": [
    {
      "timestamp": 1704472980.123,
      "severity": "ERROR",
      "code": "E102",
      "message": "Thermal runaway detected on heater_bed",
      "context": {
        "heater": "heater_bed",
        "current_temp": 85.5,
        "target_temp": 60.0,
        "rate": 5.2
      }
    }
  ],
  "total": 142,
  "has_more": true
}
```

### POST `/api/k2/diagnostic/run`
Run diagnostic test:
```json
{
  "test": "home_all",
  "parameters": {}
}
```

---

## Database Schema (Error Persistence)

### SQLite Database: `printer_data/database/k2_monitor.db`

```sql
CREATE TABLE errors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp REAL NOT NULL,
    severity TEXT NOT NULL,
    code TEXT NOT NULL,
    message TEXT NOT NULL,
    context TEXT,  -- JSON
    resolved BOOLEAN DEFAULT 0,
    INDEX idx_timestamp (timestamp),
    INDEX idx_severity (severity),
    INDEX idx_code (code)
);

CREATE TABLE state_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp REAL NOT NULL,
    state TEXT NOT NULL,
    context TEXT,  -- JSON
    INDEX idx_timestamp (timestamp)
);

CREATE TABLE diagnostics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp REAL NOT NULL,
    test_name TEXT NOT NULL,
    result TEXT NOT NULL,
    details TEXT,  -- JSON
    INDEX idx_timestamp (timestamp)
);
```

---

## UI Mockup

```
┌──────────────────────────────────────────────────────────────────────┐
│ K2 Pro System Monitor                    [Settings] [Diagnostics]    │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│ ┌─ Current State ───────────────┐  ┌─ Position ──────────────────┐  │
│ │ ● PRINTING                    │  │ X: 150.23 / 302.00          │  │
│ │ Progress: 45.2%               │  │ Y: 200.45 / 332.00          │  │
│ │ Layer: 125 / 280              │  │ Z:  12.80 / 303.00          │  │
│ │ Time: 2h 15m / 5h 30m         │  │ E: 1234.5                   │  │
│ └───────────────────────────────┘  └─────────────────────────────┘  │
│                                                                       │
│ ┌─ Thermal ─────────────────────────────────────────────────────┐   │
│ │ Hotend:   220.5°C / 220°C  ████████████░░  45% power         │   │
│ │ Bed:       60.2°C /  60°C  ████░░░░░░░░░  15% power         │   │
│ │ Chamber:   35.0°C /   0°C  OFF                                │   │
│ │ [Temperature Graph - Last 10min]                             │   │
│ └───────────────────────────────────────────────────────────────┘   │
│                                                                       │
│ ┌─ CFS Multi-Color ──────────────────┐  ┌─ Sensors ──────────────┐ │
│ │ Status: ● Connected               │  │ Filament: ● Detected   │ │
│ │ Active: T01 (Blue PLA)            │  │ Probe: ✓ Ready         │ │
│ │ Buffer: ████████░░ 65%            │  │ Z-Offset: -0.050mm     │ │
│ │                                   │  │ Fans: ✓ All running    │ │
│ │ Materials Loaded:                 │  │ Endstops: ✓ Clear      │ │
│ │ T00: Red PLA    (850g)           │  └────────────────────────┘ │
│ │ T01: Blue PLA   (750g) [ACTIVE]  │                             │
│ │ T02: White PLA  (920g)           │                             │
│ └───────────────────────────────────┘                             │
│                                                                       │
│ ┌─ Recent Errors ───────────────────────────────────────────────┐   │
│ │ 14:23  ERROR    E102  Thermal runaway detected    [Details]  │   │
│ │ 14:20  WARNING  W205  CFS buffer low               [Details]  │   │
│ │ 14:15  INFO     I001  Print started                          │   │
│ │                                          [View All] [Export]  │   │
│ └───────────────────────────────────────────────────────────────┘   │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Deployment

### Option 1: Standalone App
- Run separate web server on port 8080
- Package as static HTML/JS bundle
- Deploy to `/usr/data/www/k2-monitor/`

### Option 2: Integrate with Mainsail/Fluidd
- Create plugin for existing interface
- Add new "System Monitor" tab
- Use existing WebSocket connection

### Option 3: Embedded in Printer
- Serve from Klipper's built-in web server
- Minimal dependencies
- Works offline

---

## Next Steps

1. **Implement backend module** (`system_monitor.py`)
2. **Create error tracking** (`error_tracker.py`)
3. **Build basic frontend** (React dashboard)
4. **Test with real printer**
5. **Add diagnostic tools**
6. **Create documentation**

Would you like me to start implementing any specific part?
