# K2 Pro Firmware Error Handling & State Tracking Analysis

## Executive Summary
The K2 Series firmware has **significant limitations** in error handling and state tracking. Most critical error handling logic is hidden in proprietary binary blobs (.so files), making debugging and customization nearly impossible.

---

## 1. State Tracking Issues

### 1.1 Minimal State Representation
**Location:** `klippy/extras/print_stats.py:120`

The printer only tracks **5 basic states**:
- `standby` - Printer idle
- `printing` - Active print
- `paused` - Print paused
- `error` - Error occurred (but minimal details stored)
- `cancelled` - Print cancelled
- `complete` - Print finished successfully

**Problem:** No granular state tracking for:
- Homing status
- Leveling status
- Heating status
- Multi-color filament change states
- Recovery states
- Specific error conditions

### 1.2 Error Context is Just a String
**Location:** `klippy/extras/print_stats.py:84-92`

```python
def note_error(self, message):
    self._note_finish("error", message)

def _note_finish(self, state, error_message = ""):
    if self.print_start_time is None:
        return
    self.state = state
    self.error_message = error_message  # Just a plain string!
    # ... timestamps only
```

**Problem:**
- No structured error data (error codes, severity, stack traces)
- No error history or log
- No error classification
- Cannot differentiate between critical vs recoverable errors

---

## 2. Pause/Resume Error Handling

### 2.1 Single Boolean Flag
**Location:** `klippy/extras/pause_resume.py:48,188-192`

```python
self.resume_err = False  # Only boolean flag

def cmd_RESUME(self, gcmd):
    if self.resume_err == True:
        logging.info("resume_err is True")
        self.reactor.pause(self.reactor.monotonic() + 0.5)
        self.resume_err = False  # Just clears it!
        return
```

**Problem:**
- Only tracks IF an error occurred, not WHAT error
- Resume errors are cleared without any logging or recovery action
- No way to query error history

### 2.2 Error Recovery in Binary Blob
**Location:** `config/F012_CR0CN200400C10/gcode_macro.cfg:946-949`

```gcode
[gcode_macro RESUME_EXTERNAL_PROCESS]
gcode:
  BOX_ERROR_RESUME_PROCESS  # <-- This is in binary blob!
  RESUME_EXTERNAL
```

**Location:** `klippy/extras/box_wrapper.cpython-39.so` (1.7MB binary)

**Problem:**
- `BOX_ERROR_RESUME_PROCESS` logic is completely closed source
- Cannot inspect, debug, or modify error recovery behavior
- Cannot add custom error handling for multi-color system

---

## 3. Binary Blob Dependencies

### 3.1 Proprietary Components
**Location:** `klippy/extras/`

Seven proprietary binary modules control critical functionality:

| Binary Blob | Size | Purpose | Error Impact |
|-------------|------|---------|--------------|
| `box_wrapper.cpython-39.so` | 1.7MB | Multi-color filament box | **CRITICAL** - All CFS error handling |
| `prtouch_v3_wrapper.cpython-39.so` | ? | Pressure-based bed leveling | **HIGH** - Leveling failures |
| `serial_485_wrapper.cpython-39.so` | ? | RS485 communication with CFS | **CRITICAL** - Communication errors |
| `motor_control_wrapper.cpython-39.so` | ? | Motor diagnostics/protection | **HIGH** - Motor fault detection |
| `filament_rack_wrapper.cpython-39.so` | ? | Filament detection/management | **MEDIUM** - Runout detection |
| `prtouch_v1_wrapper.cpython-39.so` | ? | Legacy probe (unused in K2 Pro?) | LOW |
| `prtouch_v2_wrapper.cpython-39.so` | ? | Legacy probe (unused in K2 Pro?) | LOW |

### 3.2 Box (CFS) Error Commands in Binary
**From config analysis:**

These commands are called but **not open source**:
- `BOX_ERROR_RESUME_PROCESS` - Error recovery
- `BOX_CHECK_MATERIAL` - Material detection errors
- `BOX_CHECK_MATERIAL_REFILL` - Refill error handling
- `BOX_CUT_MATERIAL` - Cutting failures
- `BOX_SET_CURRENT_BOX_IDLE_MODE` - State transitions

**Impact:** Cannot debug or fix:
- Filament cutting failures
- Color change errors
- Material sensor issues
- Communication timeouts

---

## 4. Specific Error Handling Gaps

### 4.1 Filament Sensor
**Location:** `klippy/extras/filament_switch_sensor.py:57-61`

```python
def _exec_gcode(self, prefix, template):
    try:
        self.gcode.run_script(prefix + template.render() + "\nM400")
    except Exception:
        logging.exception("Script running error")  # Generic catch-all
    self.min_event_systime = self.reactor.monotonic() + self.event_delay
```

**Problem:**
- Generic exception handler swallows all errors
- Only logs to console, no user notification
- No retry logic
- No differentiation between sensor failure vs filament runout

### 4.2 Homing Failures
**Location:** `config/F012_CR0CN200400C10/gcode_macro.cfg:799-801`

```gcode
[gcode_macro PAUSE]
gcode:
  {% if printer.pause_resume.is_paused|lower == 'false' %}
    PAUSE_BASE
    PAUSE_EXTERNAL
```

**Problem:**
- No check if printer is homed before pausing
- No validation of position safety
- Can pause mid-homing with undefined behavior

### 4.3 Temperature Errors
**No structured handling for:**
- Heater thermal runaway
- Thermistor disconnection
- PID tuning failures
- Chamber heating failures

Only has `max_error` thresholds in config, but no recovery logic:
```cfg
[verify_heater chamber_heater]
max_error: 80 #120
```

---

## 5. State Persistence Issues

### 5.1 Power Loss Recovery
**Location:** `klippy/extras/pause_resume.py:74-114`

Power loss state is saved to:
- EEPROM (via `bl24c16f`)
- JSON file at `/mnt/UDISK/printer_data/gcodes/print_file_name.json`

**Problems:**
- State corruption if power fails during save
- No checksum or validation
- EEPROM has limited write cycles
- No backup mechanism

### 5.2 No Error History
There is **no persistent error log**. Errors are:
- Logged to console only
- Lost on restart
- Not accessible via API
- Cannot be reviewed for troubleshooting

---

## 6. Comparison: What's Missing vs Industry Standards

| Feature | K2 Pro | Prusa (Marlin) | Bambu Lab | Voron (Klipper) |
|---------|--------|----------------|-----------|-----------------|
| Error codes | ❌ String only | ✅ Numbered codes | ✅ Codes + descriptions | ⚠️ Custom macros |
| Error history | ❌ None | ✅ LCD log | ✅ Full history | ⚠️ Custom logging |
| State machine | ❌ 5 states | ✅ 20+ states | ✅ Detailed FSM | ✅ Extensible |
| Recovery actions | ❌ Binary blob | ✅ Configurable | ✅ Automated | ✅ Macro-based |
| Error diagnostics | ❌ Minimal | ✅ Detailed | ✅ AI-assisted | ✅ Community tools |
| Open source | ⚠️ Partial | ✅ Full | ❌ Closed | ✅ Full |

---

## 7. Recommended Improvements

### 7.1 Immediate Fixes (No Binary Changes)
1. **Add error logging macro**
   ```gcode
   [gcode_macro LOG_ERROR]
   gcode:
     # Log to file with timestamp
     # Store last 100 errors in memory
   ```

2. **State validation wrapper**
   ```gcode
   [gcode_macro SAFE_HOME]
   gcode:
     # Check printer state before homing
     # Validate position after homing
     # Log any failures
   ```

3. **Enhanced pause/resume**
   ```gcode
   [gcode_macro PAUSE]
   gcode:
     # Save full printer state
     # Validate safe pause position
     # Log pause reason
   ```

### 7.2 Medium-Term (Requires Python Changes)
1. **Structured error class**
   ```python
   class PrinterError:
       code: int
       severity: ErrorSeverity
       message: str
       timestamp: float
       context: dict
       stack_trace: str
   ```

2. **Error history buffer**
   ```python
   error_history = deque(maxlen=100)
   ```

3. **State machine enhancement**
   ```python
   states = ["standby", "homing", "heating", "leveling",
             "printing", "paused", "error_recoverable",
             "error_fatal", "cancelled", "complete"]
   ```

### 7.3 Long-Term (Ideal)
1. **Open source the binary blobs**
   - Especially `box_wrapper` and `serial_485_wrapper`
   - Allow community to fix bugs and add features

2. **Implement proper state machine**
   - Formal FSM with state transition validation
   - State history tracking
   - Rollback capability

3. **Add error recovery framework**
   - Automatic retry logic
   - User-configurable recovery actions
   - Error prediction (detect issues before failure)

---

## 8. Current Workarounds

### 8.1 Add Custom Error Logging
Create `config/F012_CR0CN200400C10/error_logging.cfg`:

```gcode
[gcode_macro _ERROR_LOG_INIT]
variable_errors: []
variable_max_errors: 50
gcode:

[gcode_macro LOG_ERROR]
gcode:
  {% set errors = printer["gcode_macro _ERROR_LOG_INIT"].errors %}
  {% set msg = params.MSG|default("Unknown error") %}
  {% set code = params.CODE|default(0) %}
  {% set new_error = {"time": printer.system_stats.cputime,
                      "msg": msg, "code": code} %}
  # Add to array (Jinja2 limitation: can't modify in place)
  SAVE_VARIABLE VARIABLE=last_error VALUE='{new_error}'
  {action_respond_info("ERROR: %s" % msg)}
```

### 8.2 State Validation Wrapper
```gcode
[gcode_macro SAFE_PAUSE]
gcode:
  {% if printer.print_stats.state != "printing" %}
    LOG_ERROR MSG="Cannot pause - not printing" CODE=101
    {action_respond_info("ERROR: Not printing")}
  {% elif not printer.toolhead.homed_axes %}
    LOG_ERROR MSG="Cannot pause - not homed" CODE=102
  {% else %}
    PAUSE
  {% endif %}
```

### 8.3 Monitor Binary Blob Calls
```gcode
[gcode_macro BOX_ERROR_RESUME_PROCESS_LOGGED]
rename_existing: BOX_ERROR_RESUME_PROCESS_ORIG
gcode:
  {action_respond_info("Calling BOX_ERROR_RESUME_PROCESS")}
  BOX_ERROR_RESUME_PROCESS_ORIG
  LOG_ERROR MSG="Box error resume called" CODE=200
```

---

## 9. Files to Investigate Further

1. **klippy/toolhead.py** - Motion control errors
2. **klippy/gcode.py** - G-code parsing errors
3. **klippy/extras/heaters.py** - Temperature control (not reviewed yet)
4. **klippy/extras/virtual_sdcard.py** - SD card/file errors

---

## 10. Conclusion

The K2 Pro firmware has **fundamental architectural issues** with error handling:

1. ❌ **No structured error tracking** - Just string messages
2. ❌ **No error history** - Lost on restart
3. ❌ **Critical logic in binary blobs** - Cannot debug or modify
4. ❌ **Minimal state tracking** - Only 5 basic states
5. ❌ **No recovery framework** - Errors just logged or ignored

**Recommendation:** Push Creality to:
1. Open source the binary blobs (especially `box_wrapper.cpython-39.so`)
2. Implement proper error codes and logging
3. Add structured state machine
4. Provide error recovery hooks for custom macros

**For now:** Implement workarounds in macros (see Section 8) to add basic error tracking and logging.
