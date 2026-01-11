# CRITICAL BUG FOUND - Cache Logic Flaw

## Date: 2026-01-11

## The Bug

### Original Code (BROKEN)

```python
# klippy/extras/system_monitor.py:236
use_cache = self._should_use_cache(eventtime)

if use_cache and self.cache_timestamp > 0:  # ← BUG HERE!
    # Return cached status
    status = {...}
else:
    # Query toolhead (BLOCKS REACTOR!)
    status = self._get_state_status(eventtime)
```

### The Problem

**If homing happens BEFORE the cache is populated:**

1. User restarts Klipper
2. Immediately runs `G28` (homing)
3. `_handle_homing_begin()` fires → `is_homing = True`
4. `aggregate_status()` is called
5. `_should_use_cache()` returns `True` (because `is_homing == True`)
6. BUT `cache_timestamp == 0` (cache never populated)
7. **Condition fails:** `use_cache and self.cache_timestamp > 0` → False
8. **Falls through to else block** → Queries toolhead anyway!
9. **Reactor blocked during sensorless homing** → StallGuard detection fails
10. **Head crashes into side**

### Why Sensorless Homing is Extra Sensitive

**Physical endstop:** MCU detects pin state change in hardware
- Timing tolerance: ~10-20ms
- If delayed, head just travels a bit past endstop

**Sensorless homing:** TMC driver detects motor stall via StallGuard
- Timing tolerance: ~1-5ms
- Requires continuous monitoring of driver registers
- If reactor blocked for >5ms, stall detection window missed
- Motor keeps trying to drive → belt slips → crash

## The Fix

### New Code (FIXED)

```python
use_cache = self._should_use_cache(eventtime)

if use_cache:
    if self.cache_timestamp > 0:
        # Return cached status (normal case)
        logging.info("SystemMonitor: Using cached data during homing")
        status = {...}
    else:
        # Cache empty but in critical operation - return minimal safe status
        logging.info("SystemMonitor: Cache empty during critical operation - returning minimal status")
        status = {
            "timestamp": eventtime,
            "state": {"state": "homing"},
            "motion": {},
            "thermal": {},
            # ... empty dicts
        }
else:
    # Safe to query
    status = self._get_state_status(eventtime)
```

### Key Changes

1. **Removed `and self.cache_timestamp > 0` check**
   - Now: If `use_cache == True`, NEVER query, period

2. **Added empty cache fallback**
   - If cache empty during critical operation, return minimal status
   - Better to have stale/empty data than crash the head

3. **Changed logging.debug() to logging.info()**
   - Debug messages weren't showing in logs
   - Now we can actually SEE when cache protection is active

## Why This Wasn't Caught Earlier

1. **Testing scenario didn't trigger it**
   - During testing, cache was already populated from previous queries
   - Only happens on fresh restart → immediate homing

2. **Intermittent nature**
   - If web dashboard was polling before homing, cache was populated
   - Only crashed when homing immediately after restart with no polling

3. **Log level**
   - Used `logging.debug()` which didn't show in production logs
   - Couldn't see that cache protection wasn't working

## Evidence from Logs

**Before fix:**
```
[INFO] SystemMonitor initialized
[INFO] SystemMonitor ready
[DEBUG] _handle_homing_move_begin  ← Not our code!
ERROR: {"code":"key22", "msg":"No trigger on y after full movement"}
```

**Missing from logs:**
```
SystemMonitor: Homing started - switching to cache-only mode  ← Never appeared!
SystemMonitor: Using cached data during homing  ← Never appeared!
```

**Why?**
1. Messages used `logging.debug()` (not shown at INFO level)
2. Even if changed to `logging.info()`, cache logic was broken so messages wouldn't fire

**After fix (expected):**
```
[INFO] SystemMonitor initialized
[INFO] SystemMonitor ready
[INFO] SystemMonitor: Homing started - switching to cache-only mode
[INFO] SystemMonitor: Cache empty during critical operation - returning minimal status
... homing completes successfully ...
[INFO] SystemMonitor: Homing completed - resuming normal queries
```

## Impact

**Severity:** CRITICAL - Causes physical damage

**Affected:**
- Any printer using sensorless homing (TMC StallGuard)
- Only on fresh Klipper restart followed by immediate homing
- More likely on startup scripts that auto-home

**Damage:**
- Belt slipping (stretching, teeth damage)
- Potential frame damage from crashes
- Potential gantry misalignment

## Testing Protocol

To verify fix works:

1. **Deploy the fix:**
   ```bash
   ./k2-unleashed upgrade
   ```

2. **Restart Klipper:**
   ```bash
   ssh root@192.168.50.113 "systemctl restart klipper"
   ```

3. **Immediately home (before any queries):**
   ```gcode
   G28 Y
   ```

4. **Check logs for:**
   ```
   [INFO] SystemMonitor: Homing started - switching to cache-only mode
   [INFO] SystemMonitor: Cache empty during critical operation - returning minimal status
   [INFO] SystemMonitor: Homing completed - resuming normal queries
   ```

5. **Verify homing succeeded without crash**

6. **Test again with populated cache:**
   ```gcode
   SYSTEM_STATUS  # Populate cache
   G28 Y          # Should use cached data
   ```

7. **Check logs for:**
   ```
   [INFO] SystemMonitor: Homing started - switching to cache-only mode
   [INFO] SystemMonitor: Using cached data during homing (protecting timing)
   [INFO] SystemMonitor: Homing completed - resuming normal queries
   ```

## Lessons Learned

1. **Never assume cache is populated**
   - Always handle empty cache case
   - Critical operations should work even with no data

2. **Use appropriate log levels**
   - `logging.debug()` for verbose debugging
   - `logging.info()` for important events that should always show
   - Use INFO for: startup, critical operation changes, errors

3. **Test edge cases**
   - Fresh restart scenarios
   - Empty state conditions
   - Timing-sensitive operations

4. **Sensorless homing is EXTREMELY timing-sensitive**
   - Even 5ms delay can cause failure
   - StallGuard detection window is very narrow
   - Must NEVER block reactor during sensorless homing

5. **Physical endstops vs Sensorless homing**
   - Physical: Hardware-based, ~10-20ms tolerance
   - Sensorless: Software-based, ~1-5ms tolerance
   - Sensorless requires PERFECT timing

## Related Issues

- specs/HOMING_CRASH_FIX.md - Original fix attempt (incomplete)
- specs/ARCHITECTURAL_FRAGILITY_ANALYSIS.md - Root cause analysis
- specs/HOMING_TROUBLESHOOTING_GUIDE.md - Diagnostic guide

## Status

- ✅ Bug identified
- ✅ Fix implemented
- ✅ Committed and pushed
- ⏳ Needs deployment and testing
- ⏳ Needs production verification

---

**DEPLOY THIS FIX IMMEDIATELY - IT PREVENTS PHYSICAL DAMAGE**
