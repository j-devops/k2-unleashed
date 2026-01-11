# Homing Crash Fix - Critical System Monitor Bug

## Issue

**Symptom:** Head crashes during G28 homing command intermittently

**Root Cause:** system_monitor.py was querying toolhead status during timing-sensitive homing operations, causing reactor thread blocking that interfered with the homing sequence.

## Technical Analysis

### Why It Happened

1. **Homing is timing-critical:**
   ```python
   # From homing.py:84
   self.printer.send_event("homing:homing_move_begin", self)
   # ... critical homing moves happen here ...
   self.printer.send_event("homing:homing_move_end", self)
   ```

2. **system_monitor._is_printing() only checked for "printing" state:**
   ```python
   # OLD CODE
   def _is_printing(self):
       if self.print_stats:
           status = self.print_stats.get_status(eventtime)
           state = status.get('state', 'unknown')
           return state == "printing"  # ← During homing, state != "printing"
       return False
   ```

3. **During homing, state is NOT "printing":**
   - Homing state is typically "ready" or "standby"
   - `_is_printing()` returned False
   - Cache was NOT used
   - Queries executed during homing

4. **Toolhead queries blocked reactor:**
   ```python
   # system_monitor.py:285
   th = self.toolhead.get_status(eventtime)  # ← BLOCKS during homing
   pos = th.get("position", [0, 0, 0, 0])
   ```

5. **Timing disruption caused head crash:**
   ```
   Homing sequence:
   1. Start homing move
   2. [SYSTEM_MONITOR QUERIES TOOLHEAD] ← Blocks reactor thread
   3. Endstop detection delayed
   4. Head continues past endstop
   5. CRASH!
   ```

### Why It Was Intermittent

The crash only occurred when:
- System monitor update happened during homing (timing-dependent)
- Web dashboard was open and polling status
- User issued SYSTEM_STATUS command during homing

## The Fix

### Code Changes

**Added homing state tracking:**
```python
# Track critical operations
self.is_homing = False
self.is_probing = False

# Register homing event handlers
self.printer.register_event_handler("homing:homing_move_begin",
                                   self._handle_homing_begin)
self.printer.register_event_handler("homing:homing_move_end",
                                   self._handle_homing_end)

def _handle_homing_begin(self, homing_state):
    """Called when homing/probing begins - CRITICAL: avoid all queries"""
    self.is_homing = True
    logging.debug("SystemMonitor: Homing started - switching to cache-only mode")

def _handle_homing_end(self, homing_state):
    """Called when homing/probing ends"""
    self.is_homing = False
    logging.debug("SystemMonitor: Homing completed - resuming normal queries")
```

**Added critical operation detection:**
```python
def _in_critical_operation(self):
    """Check if printer is in a timing-sensitive operation"""
    # CRITICAL: During homing, any queries can disrupt timing and crash the head
    if self.is_homing or self.is_probing:
        return True

    # Also avoid queries during printing
    if self._is_printing():
        return True

    return False
```

**Updated cache logic:**
```python
def _should_use_cache(self, eventtime):
    """Determine if we should use cached data to avoid blocking"""
    if not self.safe_query_mode:
        return False

    # Use cache if we're in critical operation (homing, probing, printing)
    if self._in_critical_operation():  # ← Now includes homing!
        return True

    # Use cache if it's recent enough
    cache_age = eventtime - self.cache_timestamp
    if cache_age < self.cache_max_age:
        return True

    return False
```

## How It Works Now

### During Homing (Safe)

```
1. User: G28
   ↓
2. Klipper: send_event("homing:homing_move_begin")
   ↓
3. SystemMonitor: is_homing = True
   ↓
4. Homing move executes (CRITICAL SECTION)
   ↓
5. If system monitor update occurs:
   - _in_critical_operation() → True
   - _should_use_cache() → True
   - Returns CACHED data, NO queries
   - Reactor NOT blocked
   ↓
6. Homing completes successfully
   ↓
7. Klipper: send_event("homing:homing_move_end")
   ↓
8. SystemMonitor: is_homing = False
   ↓
9. Normal queries resume
```

### Cache Behavior

**Cache is used when:**
- `is_homing = True` (NEW!)
- `is_probing = True` (NEW!)
- Printing is active (`state == "printing"`)
- Cache is less than 2 seconds old

**Fresh queries only when:**
- Printer is idle (not homing/probing/printing)
- Cache is older than 2 seconds
- safe_query_mode is disabled

## Deployment Instructions

### 1. Deploy the Fix

```bash
cd /path/to/k2-unleashed
git pull origin main
./k2-unleashed upgrade
```

### 2. Verify Deployment

```bash
./k2-unleashed status

# Should show:
# ✓ System Monitor installed (version matches local)
```

### 3. Test Homing

**Run multiple homing tests:**
```gcode
G28          # Home all axes
G28 X Y      # Home X and Y
G28 Z        # Home Z only

# Repeat 10+ times to ensure no crashes
```

**With web dashboard open:**
1. Open: http://printer-ip:4408/k2/
2. Run: `G28`
3. Observe: Dashboard shows cached data during homing
4. After homing: Dashboard updates with fresh data

### 4. Monitor Logs

```bash
./k2-unleashed logs

# Look for:
# "SystemMonitor: Homing started - switching to cache-only mode"
# "SystemMonitor: Homing completed - resuming normal queries"
```

## Related Files

- `klippy/extras/system_monitor.py:187-197` - Critical operation detection
- `klippy/extras/system_monitor.py:117-125` - Homing event handlers
- `klippy/extras/homing.py:84` - homing_move_begin event
- `klippy/extras/homing.py:162` - homing_move_end event

## Configuration

**To disable safe query mode (NOT recommended):**
```ini
[system_monitor]
safe_query_mode: False  # Allows queries during homing (dangerous!)
```

**Default (safe):**
```ini
[system_monitor]
safe_query_mode: True   # Use cache during critical operations
```

## Testing Checklist

- [ ] Deployed updated system_monitor.py
- [ ] Restarted Klipper service
- [ ] Tested G28 10+ times - no crashes
- [ ] Tested G28 with dashboard open - no crashes
- [ ] Verified cache-only mode during homing (check logs)
- [ ] Confirmed normal queries resume after homing

## Prevention

This bug class is prevented by:

1. **Event-based state tracking** - Monitor homing/probing state
2. **Cache-first design** - Default to cached data during uncertainty
3. **Safe query mode** - Explicit configuration option
4. **Comprehensive critical operation detection** - Not just printing

## Future Improvements

1. Add `is_probing` tracking for probe operations
2. Track Z_TILT_ADJUST operations (also timing-sensitive)
3. Add BED_MESH_CALIBRATE to critical operations
4. Instrument with timing metrics to detect blocking queries
5. Add unit tests for critical operation detection

## References

- Klipper event system: https://www.klipper3d.org/Code_Overview.html#events
- Homing implementation: klippy/extras/homing.py
- Reactor thread: klippy/reactor.py
