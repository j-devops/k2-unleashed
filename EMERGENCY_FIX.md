# EMERGENCY FIX - Disable System Monitor NOW

## Problem

- Head is physically crashing into the side
- Belt is slipping
- Causing physical damage
- The homing fix is NOT working despite deployment

## Immediate Solution: Disable System Monitor Temporarily

SSH to the printer and disable system_monitor:

```bash
ssh root@192.168.50.113
cd /mnt/UDISK/printer_data/config
nano printer.cfg
```

**Comment out the system_monitor include:**
```ini
# [include system_monitor.cfg]   ← Add # to disable
```

Save (Ctrl+X, Y, Enter) and restart:
```bash
systemctl restart klipper
```

## Then Fix the Y Endstop Hardware

The "key22" error means the Y endstop is NOT triggering. This is likely a hardware problem now.

### Check Endstop Status

After restarting Klipper (with system_monitor disabled), run:

```gcode
QUERY_ENDSTOPS
```

You should see:
```
x: open
y: open
z: TRIGGERED
```

**Manually press the Y endstop switch** (on the back of the machine) and run again:
```gcode
QUERY_ENDSTOPS
```

**If Y doesn't change to TRIGGERED:**
- The endstop is broken OR
- Wiring is disconnected from pin PB12 OR
- Wrong endstop is configured

### Check Physical Damage

1. **Check the belt** - Is it stripped? Loose? Slipping on the pulley?
2. **Check the Y endstop** - Is it physically damaged from the crashes?
3. **Check the Y carriage** - Any damage from hitting the side?

## Why the Fix Didn't Work

Looking at the logs:
- System monitor IS loaded
- Event handlers ARE registered
- BUT the cache protection code ISN'T running

**Possible reasons:**
1. The file deployed is an old version without the fix
2. There's a Python syntax error preventing the code from executing
3. The event handlers are registered but the is_homing flag isn't being set

## Verify What's Actually on the Printer

SSH and check the actual file:

```bash
ssh root@192.168.50.113
grep -A 5 "_handle_homing_begin" /usr/share/klipper/klippy/extras/system_monitor.py
```

**Should see:**
```python
def _handle_homing_begin(self, homing_state):
    """Called when homing/probing begins - CRITICAL: avoid all queries"""
    self.is_homing = True
    logging.debug("SystemMonitor: Homing started - switching to cache-only mode")
```

**If you don't see this**, the file didn't deploy correctly.

## Emergency Rollback

If nothing else works, rollback to before system_monitor was added:

```bash
ssh root@192.168.50.113
cd /mnt/UDISK/printer_data/config
cp printer.cfg.backup.20260111_041411 printer.cfg
systemctl restart klipper
```

## Next Steps (After Endstop is Fixed)

1. Fix the endstop hardware issue first
2. Verify deployment actually works
3. Implement Option 1 (pre-computed status snapshot) as proper fix
4. This event handler approach clearly has issues

---

**PRIORITY: Stop damage, disable system_monitor, fix endstop hardware.**
