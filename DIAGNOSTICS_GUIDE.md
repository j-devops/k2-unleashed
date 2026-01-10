# K2 Pro Comprehensive Diagnostics System

Complete guide to the diagnostic and health check system for the Creality K2 Pro.

---

## Overview

The diagnostics system provides:
- ✅ **Automated health checks** - Run comprehensive system tests
- ✅ **Individual test tools** - Test specific components
- ✅ **Web-based interface** - Beautiful UI for running and viewing tests
- ✅ **G-code commands** - Run tests from console or macros
- ✅ **Test history** - Track all test results
- ✅ **Error integration** - Tests log to system_monitor error history

---

## Available Tests

### 1. Homing Test
Tests axis homing functionality.

**Parameters:**
- `AXES`: Which axes to test (X, Y, Z, XY, XYZ)

**Checks:**
- Axes home successfully
- Endstops trigger correctly
- Final position is correct

**G-code:**
```gcode
DIAGNOSTIC_TEST TEST=homing AXES=XY
```

**Web UI:** Click "Homing Test" → Select axes → Run

---

### 2. Motor Movement Test
Tests motor movement accuracy.

**Parameters:**
- `AXIS`: Which axis to test (X, Y, or Z)
- `DISTANCE`: Distance to move (mm)

**Checks:**
- Motor moves commanded distance
- Movement accuracy within 0.5mm tolerance
- Returns to original position

**G-code:**
```gcode
TEST_MOTORS AXIS=X DISTANCE=10
```

**Web UI:** Click "Motor Test" → Select axis & distance → Run

**Results:**
- ✅ **Passed**: Movement within 0.5mm
- ⚠️ **Warning**: Movement within 2.0mm
- ❌ **Failed**: Movement error > 2.0mm

---

### 3. Heater Test
Tests heater response and stability.

**Parameters:**
- `HEATER`: Which heater (extruder, heater_bed, chamber_heater)
- `TEMP`: Target temperature (°C)

**Checks:**
- Heater reaches target temperature
- Heating rate is reasonable
- No thermal runaway

**G-code:**
```gcode
TEST_HEATERS HEATER=extruder TEMP=50
```

**Web UI:** Click "Heater Test" → Select heater & temp → Run

**Safety:**
- Times out after 60 seconds
- Auto turns off heater after test
- Won't test above configured max temp

---

### 4. Probe Accuracy Test
Tests probe repeatability.

**Parameters:**
- `SAMPLES`: Number of probe samples (default 10)

**Checks:**
- Probe triggers consistently
- Results are repeatable
- Range is within tolerance

**G-code:**
```gcode
TEST_PROBE SAMPLES=10
```

**Web UI:** Click "Probe Test"

**Note:** Runs Klipper's built-in `PROBE_ACCURACY` command.

---

### 5. Fan Test
Tests all cooling fans.

**Checks:**
- Each fan turns on when commanded
- Fans turn off correctly
- PWM control works

**G-code:**
```gcode
DIAGNOSTIC_TEST TEST=fans
```

**Web UI:** Click "Fan Test"

**Tested Fans:**
- fan0 (part cooling)
- fan1 (auxiliary)
- fan2 (chamber)

---

### 6. Endstop Test
Checks endstop states.

**Checks:**
- All endstops are readable
- Endstops are not stuck triggered
- Virtual endstop (probe) is working

**G-code:**
```gcode
DIAGNOSTIC_TEST TEST=endstops
```

**Web UI:** Click "Endstop Test"

**Note:** Results appear in console via `QUERY_ENDSTOPS`.

---

### 7. Belt Tension Test
Checks X/Y belt tension using belt modules.

**Checks:**
- Belt modules are present
- Belt tension is within spec
- Both belts are balanced

**G-code:**
```gcode
DIAGNOSTIC_TEST TEST=belt_tension
```

**Web UI:** Click "Belt Tension"

**Requires:** `[belt_mdl mdlx]` and `[belt_mdl mdly]` configured.

---

## Health Check

Runs comprehensive automated testing of all systems.

### What It Tests

1. ✅ Homing (X/Y only for safety)
2. ✅ Endstop states
3. ✅ All fans
4. ✅ Belt tension

**G-code:**
```gcode
HEALTH_CHECK
```

**Web UI:** Click "🏥 Run Full Health Check"

### Results

```
=== Health Check Results ===
Homing Test: PASSED - All axes homed successfully
Endstop Test: PASSED - Endstop query completed
Fan Test: PASSED - All fans working
Belt Tension Test: PASSED - Belt modules present
Overall: PASSED
```

### Auto Health Checks

Enable automatic periodic health checks:

```ini
[diagnostics]
auto_health_check: True
health_check_interval: 3600  # Run every hour (only when not printing)
```

**Safety:**
- Only runs when printer is in standby (not printing)
- Skips tests that could interfere with prints
- Logs results to error history

---

## Web Interface

### Accessing Diagnostics UI

1. **Standalone:** Open `web_dashboard/diagnostics.html` in browser
2. **URL:** `http://your-printer-ip:8080/diagnostics.html` (if deployed)

### Features

#### Health Summary Dashboard
Shows at-a-glance system health:
- Overall status (Good/Warning/Issues)
- Total tests run
- Tests passed
- Tests failed

#### Individual Test Buttons
Click any test to:
- Configure parameters
- Run the test
- View results immediately

#### Test Results
Each result shows:
- ✅ Pass/⚠️ Warning/❌ Fail status
- Test duration
- Detailed message
- Expandable technical details
- Timestamp

#### Test History
- Last 20 test results
- Color-coded by status
- Persistent during session
- Exportable (future)

---

## Integration with Macros

### Example: Pre-Print Check

```gcode
[gcode_macro PRE_PRINT_CHECK]
gcode:
  RESPOND MSG="Running pre-print diagnostics..."

  # Home and check
  DIAGNOSTIC_TEST TEST=homing AXES=XYZ

  # Check bed temp works
  TEST_HEATERS HEATER=heater_bed TEMP=60

  # Verify probe
  TEST_PROBE SAMPLES=5

  RESPOND MSG="Pre-print check complete"
```

### Example: Scheduled Maintenance

```gcode
[gcode_macro WEEKLY_MAINTENANCE]
gcode:
  {% if printer.print_stats.state != "printing" %}
    RESPOND MSG="Running weekly maintenance check..."

    # Full health check
    HEALTH_CHECK

    # Motor accuracy test
    TEST_MOTORS AXIS=X DISTANCE=50
    TEST_MOTORS AXIS=Y DISTANCE=50

    # Belt tension
    DIAGNOSTIC_TEST TEST=belt_tension

    RESPOND MSG="Maintenance check complete"
  {% else %}
    RESPOND MSG="Cannot run maintenance during print"
  {% endif %}
```

### Example: Error Recovery

```gcode
[gcode_macro RECOVER_FROM_ERROR]
gcode:
  # Log the recovery attempt
  LOG_ERROR CODE=R001 MSG="Attempting error recovery" SEVERITY=INFO

  # Test systems
  DIAGNOSTIC_TEST TEST=homing AXES=XY
  DIAGNOSTIC_TEST TEST=fans

  # If tests pass, ready to continue
  RESPOND MSG="Recovery tests complete"
```

---

## API Reference

### POST `/server/diagnostics/run_test`

Run a specific diagnostic test.

**Parameters:**
- `test`: Test name (homing, motor, heater, probe, fans, endstops, belt_tension)
- Test-specific params (axes, axis, distance, heater, temp, samples)

**Example:**
```bash
curl -X POST "http://printer:7125/server/diagnostics/run_test?test=motor&axis=X&distance=10"
```

**Response:**
```json
{
  "result": {
    "name": "Motor Movement Test",
    "description": "Test X axis movement by 10mm",
    "status": "passed",
    "message": "Motor moved correctly (10.003mm)",
    "details": {
      "expected_movement": 10,
      "actual_movement": 10.003,
      "error": 0.003
    },
    "duration": 2.145
  }
}
```

---

### POST `/server/diagnostics/health_check`

Run comprehensive health check.

**Example:**
```bash
curl -X POST "http://printer:7125/server/diagnostics/health_check"
```

**Response:**
```json
{
  "timestamp": 1704480000.0,
  "tests": [
    {
      "name": "Homing Test",
      "status": "passed",
      "message": "All axes homed successfully",
      "duration": 5.2
    },
    {
      "name": "Fan Test",
      "status": "passed",
      "message": "All fans working",
      "duration": 6.1
    }
  ],
  "overall_status": "passed"
}
```

---

### GET `/server/diagnostics/test_history?limit=20`

Get test history.

**Example:**
```bash
curl "http://printer:7125/server/diagnostics/test_history?limit=20"
```

**Response:**
```json
{
  "tests": [
    {
      "name": "Motor Movement Test",
      "status": "passed",
      "message": "Motor moved correctly",
      "timestamp": 1704480000.0
    }
  ],
  "total": 45
}
```

---

## Troubleshooting

### "Cannot run test while printing"

**Cause:** Diagnostics are blocked during active prints for safety.

**Solution:** Wait for print to finish or pause, then run test.

---

### Homing test fails

**Possible causes:**
- Endstop not wired correctly
- Endstop physically damaged
- Motor driver issue
- Belt too loose/tight

**Diagnosis:**
```gcode
QUERY_ENDSTOPS  # Check endstop states
DIAGNOSTIC_TEST TEST=endstops
```

---

### Motor test shows large error

**Possible causes:**
- Steps/mm calibration incorrect
- Belt slipping
- Motor losing steps
- Mechanical binding

**Diagnosis:**
```gcode
TEST_MOTORS AXIS=X DISTANCE=100  # Test longer distance
DIAGNOSTIC_TEST TEST=belt_tension
```

**Fix:**
1. Check `rotation_distance` in printer.cfg
2. Check belt tension
3. Check motor current settings
4. Recalibrate steps

---

### Heater test times out

**Possible causes:**
- Heater cartridge disconnected
- Insufficient power
- PID tuning needed
- Thermal runaway protection too strict

**Diagnosis:**
```gcode
# Check heater can turn on
SET_HEATER_TEMPERATURE HEATER=extruder TARGET=50
# Monitor in real-time
QUERY_HEATER HEATER=extruder
```

**Fix:**
1. Check heater wiring
2. Run PID calibration
3. Adjust `verify_heater` settings

---

### Probe test shows high variance

**Possible causes:**
- Probe dirty/contaminated
- Bed surface uneven
- Temperature affecting probe
- Mechanical flex

**Diagnosis:**
```gcode
TEST_PROBE SAMPLES=25  # More samples for better data
PROBE_ACCURACY SAMPLES=25
```

**Fix:**
1. Clean probe and bed
2. Let printer heat soak
3. Enable temperature compensation
4. Check z-axis mechanical rigidity

---

## Best Practices

### Before Every Print
```gcode
# Quick pre-flight check
DIAGNOSTIC_TEST TEST=homing AXES=XYZ
DIAGNOSTIC_TEST TEST=endstops
```

### Weekly Maintenance
```gcode
# Full system check
HEALTH_CHECK
TEST_MOTORS AXIS=X DISTANCE=50
TEST_MOTORS AXIS=Y DISTANCE=50
DIAGNOSTIC_TEST TEST=belt_tension
```

### After Any Modification
```gcode
# Verify changes didn't break anything
HEALTH_CHECK
TEST_PROBE SAMPLES=10
```

### Monthly Calibration
```gcode
# Comprehensive testing
HEALTH_CHECK
TEST_MOTORS AXIS=X DISTANCE=100
TEST_MOTORS AXIS=Y DISTANCE=100
TEST_MOTORS AXIS=Z DISTANCE=50
TEST_HEATERS HEATER=extruder TEMP=200
TEST_HEATERS HEATER=heater_bed TEMP=60
TEST_PROBE SAMPLES=25
```

---

## Future Enhancements

Planned features:
- [ ] Automated test scheduling
- [ ] Email/push notifications for failures
- [ ] Historical trending (track degradation over time)
- [ ] Predictive maintenance (detect issues before failure)
- [ ] Export test reports (PDF/CSV)
- [ ] Custom test sequences
- [ ] Comparison with baseline (detect changes)
- [ ] CFS-specific tests (when API available)
- [ ] Z-tilt calibration test
- [ ] Input shaper verification
- [ ] Extrusion calibration test

---

## Contributing

Found a bug or want to add a test? PRs welcome!

Areas for improvement:
- More comprehensive tests
- Better error messages
- Integration with existing Klipper tests
- Mobile app for diagnostics

---

## License

GPL v3 (same as Klipper)
