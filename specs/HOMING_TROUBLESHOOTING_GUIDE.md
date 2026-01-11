# Homing Troubleshooting Guide - Y Endstop Not Triggering

## Current Issue

**Error:** `{"code":"key22", "msg":"No trigger on y after full movement", "values": ["y"]}`

This error means the Y-axis endstop did not trigger during the entire homing move.

## Diagnostic Steps

### Step 1: Verify Fix Deployment

First, check if the homing crash fix is actually deployed on the printer:

```bash
# From your development machine
./k2-unleashed status
```

Look for:
- ✓ System Monitor version matches
- ✓ Timestamp shows recent deployment

If not deployed:
```bash
./k2-unleashed upgrade
```

### Step 2: Test Homing State Tracking

After deployment, run the new diagnostic command:

```gcode
DEBUG_HOMING
```

**Before homing**, you should see:
```
=== Homing Debug Info ===
is_homing: False
is_probing: False
in_critical_operation: False
safe_query_mode: True
would_use_cache: False  (or True if cache is recent)
cache_age: X.XXX seconds
is_printing: False
```

**During homing** (if you can trigger it), you should see:
```
is_homing: True
in_critical_operation: True
would_use_cache: True
```

### Step 3: Check Logs for Cache Protection

SSH into the printer and check the Klipper log:

```bash
# SSH to printer
ssh root@<printer-ip>

# Follow the log
tail -f /mnt/UDISK/printer_data/logs/klippy.log
```

When you run `G28 Y`, you should see:
```
SystemMonitor: Homing started - switching to cache-only mode
SystemMonitor: Using cached data during homing (protecting timing)
SystemMonitor: Homing completed - resuming normal queries
```

**If you DON'T see these messages:**
- The fix isn't deployed
- The homing events aren't being triggered
- Need to investigate event registration

**If you DO see these messages but still get "key22" error:**
- The system_monitor fix is working correctly
- The Y endstop legitimately isn't triggering
- This is likely a hardware/mechanical issue

## Step 4: Test Y Endstop Hardware

### Check Endstop Status

Run the Klipper endstop query command:

```gcode
QUERY_ENDSTOPS
```

Expected output:
```
x: open
y: open
z: TRIGGERED  (if PRTouch is loaded)
```

Now **manually press the Y endstop** and run again:
```gcode
QUERY_ENDSTOPS
```

Expected output:
```
x: open
y: TRIGGERED  <-- Should change!
z: TRIGGERED
```

**If Y endstop status doesn't change:**
- Endstop is broken
- Wiring issue (pin PB12)
- Wrong endstop configured

### Check Endstop Pin Configuration

From printer.cfg:
```ini
[stepper_y]
endstop_pin: PB12
position_endstop: -6.5
position_min: -6.5
position_max: 332
homing_speed: 100
```

**Key questions:**
1. Is the endstop connected to pin PB12?
2. Is the endstop at position -6.5mm?
3. Does the Y carriage actually reach the endstop during homing?

### Verify Mechanical Movement

**Manually test Y-axis homing:**

1. Power off the printer
2. Manually move Y carriage to center (position ~165mm)
3. Power on
4. Run `G28 Y`

**Watch carefully:**
- Does the Y carriage move toward the back (negative direction)?
- Does it reach the physical endstop?
- Does the endstop click when touched?
- Does the carriage stop moving?

**If carriage doesn't reach endstop:**
- Mechanical obstruction
- Wrong direction (check `dir_pin: PB9`)
- Position limits preventing movement

**If carriage reaches endstop but doesn't stop:**
- Endstop not triggering (hardware fault)
- Wiring issue
- Wrong pin configuration

## Step 5: Check for Other Interference

Even with the system_monitor fix, other things could interfere:

### Disable Web Dashboard Temporarily

Stop any web polling:
```bash
# Close all browser windows showing the dashboard
```

Try homing again:
```gcode
G28 Y
```

**If homing works without dashboard:**
- Dashboard polling is still causing issues
- May need to add rate limiting to dashboard

### Check for Other Modules

List loaded Klipper modules:
```gcode
HELP
```

Look for other custom modules that might query status:
- Custom display modules
- Third-party monitoring tools
- OctoPrint plugins (if using OctoPrint)

## Diagnosis Decision Tree

```
┌─────────────────────────────────────┐
│ Y endstop "key22" error             │
└─────────────┬───────────────────────┘
              │
              ▼
    ┌─────────────────────┐
    │ Is fix deployed?    │
    │ (check version)     │
    └──┬──────────────┬───┘
       │              │
      NO             YES
       │              │
       ▼              ▼
  Deploy fix    ┌─────────────────────┐
       │        │ Do logs show cache  │
       └───────▶│ protection active?  │
                └──┬──────────────┬───┘
                   │              │
                  NO             YES
                   │              │
                   ▼              ▼
            Event handlers   ┌─────────────────┐
            not working      │ Does QUERY_     │
            (check logs)     │ ENDSTOPS work?  │
                             └──┬──────────┬───┘
                                │          │
                               NO         YES
                                │          │
                                ▼          ▼
                           Hardware    Does carriage
                           failure     reach endstop?
                                       │          │
                                      NO         YES
                                       │          │
                                       ▼          ▼
                                  Mechanical  Endstop
                                  issue       wiring/pin
```

## Common Causes and Solutions

### Cause 1: Fix Not Deployed
**Symptom:** No "cache-only mode" messages in logs

**Solution:**
```bash
./k2-unleashed upgrade
service klipper restart
```

### Cause 2: Endstop Hardware Failure
**Symptom:** QUERY_ENDSTOPS shows "open" even when manually pressed

**Solution:**
- Check wiring from endstop to pin PB12
- Check endstop switch itself (use multimeter to test continuity)
- Replace endstop if faulty

### Cause 3: Wrong Endstop Position
**Symptom:** Carriage doesn't reach endstop during homing

**Solution:**
Adjust `position_endstop` and `position_min`:
```ini
[stepper_y]
position_endstop: -8.0  # Try different values
position_min: -8.0      # Must match position_endstop
```

### Cause 4: Mechanical Obstruction
**Symptom:** Carriage stops moving before reaching endstop

**Solution:**
- Check for physical obstructions on Y-axis rails
- Check belt tension (too tight can prevent movement)
- Lubricate rails if needed

### Cause 5: Wrong Homing Direction
**Symptom:** Carriage moves wrong direction during G28 Y

**Solution:**
Invert direction pin in printer.cfg:
```ini
[stepper_y]
dir_pin: !PB9  # Add or remove ! to invert
```

## Testing After Fix

Once you've identified and fixed the issue:

```gcode
# Test homing multiple times
G28 Y
G28 Y
G28 Y

# Test full homing
G28

# Check for errors
SHOW_ERRORS
```

## Monitoring Commands

**Check homing state:**
```gcode
DEBUG_HOMING
```

**Check endstop status:**
```gcode
QUERY_ENDSTOPS
```

**Check system status:**
```gcode
SYSTEM_STATUS
```

**View recent errors:**
```gcode
SHOW_ERRORS LIMIT=20
```

## Log Analysis

**Good homing sequence (fixed):**
```
SystemMonitor: Homing started - switching to cache-only mode
SystemMonitor: Using cached data during homing (protecting timing)
<homing completes successfully>
SystemMonitor: Homing completed - resuming normal queries
```

**Bad homing sequence (not fixed):**
```
<no cache protection messages>
No trigger on y after full movement
Transition to state: 'Shutdown'
```

**Hardware issue:**
```
SystemMonitor: Homing started - switching to cache-only mode
SystemMonitor: Using cached data during homing (protecting timing)
<endstop never triggers>
No trigger on y after full movement
SystemMonitor: Homing completed - resuming normal queries
Transition to state: 'Shutdown'
```

Note: Even with cache protection, if the endstop genuinely doesn't trigger, you'll still get "key22" error. This means the fix is working, but there's a hardware problem.

## Next Steps

Based on your findings:

1. **If cache protection is NOT working:**
   - Re-deploy the fix
   - Check event handler registration
   - Verify system_monitor is loading

2. **If cache protection IS working but still getting "key22":**
   - Focus on hardware diagnostics
   - Test endstop with QUERY_ENDSTOPS
   - Check mechanical movement
   - Inspect wiring

3. **If problem persists:**
   - Capture full klippy.log during failed homing
   - Share DEBUG_HOMING output
   - Share QUERY_ENDSTOPS output before/after pressing endstop
   - Note mechanical observations (does carriage reach endstop?)

## Emergency Workaround

If you need to print urgently and can't fix the Y endstop issue:

**Disable Y homing** (NOT RECOMMENDED - only for emergency):

```gcode
# In printer.cfg, comment out the Y endstop:
# [stepper_y]
# endstop_pin: PB12
# ...

# Add manual position setting:
FORCE_MOVE STEPPER=stepper_y DISTANCE=-50 VELOCITY=50  # Move to known position
SET_KINEMATIC_POSITION X=0 Y=0 Z=0  # Tell Klipper where we are
```

**WARNING:** This is dangerous and should only be used as last resort. You could crash the head if you get the position wrong!

## Contact Information

If these steps don't resolve the issue, please provide:

1. Output of `DEBUG_HOMING`
2. Output of `QUERY_ENDSTOPS` (before and after manually pressing Y endstop)
3. Relevant section from klippy.log showing homing attempt
4. Printer model and hardware configuration
5. Mechanical observations during homing

---

**Document Version:** 1.0
**Last Updated:** 2026-01-11
**Related:** HOMING_CRASH_FIX.md, ARCHITECTURAL_FRAGILITY_ANALYSIS.md
