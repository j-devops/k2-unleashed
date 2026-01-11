# Bed Mesh: Compensation Limits, Flow Rate, Z-Tilt & Z-Offset Interactions

## Critical Question: What's the actual compensation range before print issues?

### Hard Limits (Code Enforcement)

**From `bed_mesh.py:189-197`:**
```python
min_z, max_z = mesh.get_z_range()
if self.__fade_dist <= max(abs(min_z), abs(max_z)):
    self.z_mesh = None
    self.fade_target = 0.
    raise self.gcode.error(
        "bed_mesh: Mesh extends outside of the fade range, "
        "please see the fade_start and fade_end options in"
        "example-extras.cfg. fade distance: %.2f mesh min: %.4f"
        "mesh max: %.4f" % (self.__fade_dist, min_z, max_z))
```

**Translation:**
```
fade_dist = fade_end - fade_start = 50mm - 5mm = 45mm

Maximum allowed mesh deviation:
  max(abs(min_z), abs(max_z)) <= 45mm

Example limits:
  ✓ Mesh ranges from -2mm to +3mm → max = 3mm → OK
  ✓ Mesh ranges from -5mm to +5mm → max = 5mm → OK
  ✗ Mesh ranges from -50mm to +50mm → max = 50mm → ERROR
```

### K2 Configuration Limits

**K2 Pro (F012):**
```ini
[bed_mesh]
fade_start: 5.0
fade_end: 50.0
# fade_dist = 45mm
# Max compensation: ±45mm (theoretical, impractical)
```

**K2 Plus (F008):**
```ini
[bed_mesh]
fade_start: 5.0
fade_end: 50.0
# fade_dist = 45mm
# Max compensation: ±45mm (theoretical, impractical)
```

### Practical Limits (Real-World)

While the code allows up to ±45mm, **practical printing limits are MUCH lower**:

#### 1. First Layer Adhesion
```
Typical nozzle-to-bed gap: 0.2mm
Acceptable variance: ±0.05mm (±25% of layer height)

If mesh compensation > ±0.5mm at first layer:
  → Adhesion becomes unreliable
  → Parts may warp or detach
  → Elephant's foot or insufficient squish
```

#### 2. Layer Height Changes
```
Standard layer height: 0.2mm
Max recommended Z variation per layer: 0.1mm (50% of layer height)

If bed warp > 2mm across 100mm travel:
  → Slope = 2mm / 100mm = 0.02 = 2%
  → At 0.2mm layer, next layer varies by 0.04mm
  → This is manageable

If bed warp > 5mm across 100mm travel:
  → Slope = 5mm / 100mm = 0.05 = 5%
  → At 0.2mm layer, next layer varies by 0.1mm
  → Approaching problematic levels
```

#### 3. Real-World Safe Limits

| Condition | Max Deviation | Consequence if Exceeded |
|-----------|---------------|-------------------------|
| **First layer (Z<5mm)** | ±0.5mm | Adhesion failure, warping |
| **Low layers (Z<10mm)** | ±1.0mm | Layer bonding issues |
| **Mid layers (Z<30mm)** | ±2.0mm | Visible layer inconsistency |
| **High layers (Z>30mm)** | ±5.0mm | Minimal impact (fading out) |

**Recommendation:** If your mesh shows deviations > ±2mm, **fix the bed physically** rather than relying on mesh compensation.

---

## Flow Rate Effects

### Does Bed Mesh Affect Extrusion Rate?

**Short answer: YES, indirectly through Z changes.**

### How It Works

Bed mesh **only modifies Z position**, not E-axis commands. However, Z changes affect print geometry:

```gcode
# User command
G1 X100 Y100 Z0.2 E10

# With bed mesh compensation (+0.1mm at this location)
# Actual executed move:
G1 X100 Y100 Z0.3 E10  (Z adjusted from 0.2 to 0.3)

# E-axis command unchanged!
# But nozzle is now 0.3mm from bed instead of 0.2mm
```

### Impact on First Layer

**Scenario 1: Bed is 0.1mm too high (mesh compensates +0.1mm)**
```
Commanded layer height: 0.2mm
Actual nozzle height: 0.3mm (0.2 + 0.1 compensation)
Extrusion flow: Same (E value unchanged)

Result:
  - Less squish/compression
  - Potential under-extrusion appearance
  - Reduced adhesion
  - Thicker actual layer height
```

**Scenario 2: Bed is 0.1mm too low (mesh compensates -0.1mm)**
```
Commanded layer height: 0.2mm
Actual nozzle height: 0.1mm (0.2 - 0.1 compensation)
extrusion flow: Same (E value unchanged)

Result:
  - More squish/compression
  - Potential over-extrusion appearance
  - Better adhesion (to a point)
  - Thinner actual layer height
  - Risk of nozzle dragging
```

### Why Flow Rate Isn't Automatically Adjusted

**From `kinematics/extruder.py`:**
```python
# Bed mesh is a move_transform applied AFTER gcode parsing
# E-axis calculations happen before bed mesh sees the move
# Therefore: E = f(commanded_Z), not f(actual_Z)
```

The extruder calculates flow based on:
```
E_mm³ = (nozzle_diameter * layer_height * line_width) * distance
```

Where `layer_height` is the **commanded** height, not actual compensated height.

### Practical Implications

**For small deviations (±0.2mm):**
- Negligible flow impact
- Bed mesh handles this well

**For medium deviations (±0.5mm):**
- Noticeable flow variation
- First layer may look slightly under/over-extruded
- Still printable but not ideal

**For large deviations (±1mm+):**
- Significant flow mismatch
- First layer quality severely degraded
- **Fix the bed physically**

### Advanced: Compensating Flow (Not Implemented)

Hypothetically, to truly compensate flow, you'd need:
```python
# Calculate actual Z change
z_adjustment = mesh.calc_z(x, y)
actual_z = commanded_z + z_adjustment

# Recalculate E based on actual_z
# This would require modifying extruder.py
# Currently NOT done in K2 firmware
```

**Why it's not implemented:**
1. Complex - would require tight integration between bed_mesh and extruder
2. Performance overhead - recalculating E for every segment
3. Diminishing returns - proper bed tramming is better solution
4. Edge cases - what about retractions, wipes, etc.?

---

## K2 Plus: Z-Tilt and Bed Mesh Interaction

### What is Z-Tilt?

K2 Plus has **two independent Z motors** (K2 Pro has one):

```
K2 Plus (F008) Configuration:

[stepper_z]          [stepper_z1]
Left motor           Right motor
X = -15mm            X = 375mm
    │                    │
    └────────────────────┘
         Gantry

[z_tilt]
z_positions:         # Motor locations
    -15,175          # Left motor
    375,175          # Right motor
points:              # Probe points
    5,175            # Left probe
    345,175          # Right probe

retries: 10
retry_tolerance: 0.1mm
```

### Z-Tilt Operation (Before Bed Mesh)

**Process:**
```
1. Home all axes (both Z motors move together)
   ↓
2. Run Z_TILT_ADJUST
   ↓
3. Probe at left point (X=5, Y=175)
   → Measure Z height: e.g., 0.50mm
   ↓
4. Probe at right point (X=345, Y=175)
   → Measure Z height: e.g., 0.55mm
   ↓
5. Calculate tilt: right side is 0.05mm higher
   ↓
6. Adjust motors independently:
   - stepper_z: stays at current position
   - stepper_z1: moves down 0.05mm
   ↓
7. Verify by re-probing
   ↓
8. If deviation > retry_tolerance (0.1mm), retry
   ↓
9. Once level, proceed to bed mesh
```

**From `z_tilt.py:38-43`:**
```python
for s, a in zip(self.z_steppers, adjustments):
    if s.get_name() == "stepper_z":
        z_tilt.stepper_z_adjustment += a
    elif s.get_name() == "stepper_z1":
        z_tilt.stepper_z1_adjustment += a
```

### Execution Order: Z-Tilt → Bed Mesh

**Typical start_print macro:**
```gcode
G28                    # Home all axes
Z_TILT_ADJUST          # Level the gantry (K2 Plus only)
BED_MESH_CALIBRATE     # Probe bed mesh
# Now start printing
```

**Why this order matters:**
1. **Z-Tilt first**: Levels the gantry to be parallel to bed
2. **Bed Mesh second**: Compensates for remaining bed surface variations

**Analogy:**
```
Z-Tilt = Adjusting table legs so table is level
Bed Mesh = Compensating for bumps/dips in table surface
```

### What Z-Tilt Fixes

```
Before Z-Tilt:
    Gantry tilted:

    Left: 0.50mm    Right: 0.55mm
      \                /
       \              /
        \____________/
            Bed

After Z-Tilt:
    Gantry level:

    Left: 0.525mm   Right: 0.525mm
      _______________
            Bed
```

**Z-Tilt corrects:**
- Gantry tilt from assembly tolerances
- Uneven frame settling
- Different Z motor positions
- Thermal expansion differences

**Z-Tilt does NOT correct:**
- Bed surface warping
- Bed bowing/doming
- Local high/low spots

### What Bed Mesh Fixes (After Z-Tilt)

```
After Z-Tilt (gantry level), bed still has variations:

       0.52mm    0.48mm    0.50mm
         │         │         │
    _____│_________│_________│_____  ← Gantry (now level)
         │  ╱──╲  │   ╱─╲   │
         │ ╱    ╲ │  ╱   ╲  │
        _│╱______╲│_╱_____╲_│_____  ← Bed (not flat)
```

Bed mesh creates compensation map for these surface variations.

### K2 Plus vs K2 Pro

| Feature | K2 Plus (F008) | K2 Pro (F012) |
|---------|----------------|---------------|
| Z Motors | 2 (stepper_z, stepper_z1) | 1 (stepper_z) |
| Z-Tilt | Yes ([z_tilt]) | No |
| Mesh Grid | 9x9 (81 points) | 7x7 (49 points) |
| Bed Size | 350x350mm | 300x300mm |
| Mesh Area | 5,5 to 345,345 | 5,5 to 295,295 |

**Why K2 Plus needs z_tilt:**
- Larger bed = more prone to gantry tilt
- Dual Z = can independently adjust each side
- Without z_tilt, bed mesh would try to compensate for gantry tilt
- Z-tilt fixes the gantry, bed mesh only handles bed surface

### Bed Mesh Without Z-Tilt (K2 Pro)

K2 Pro has single Z motor, so gantry tilt cannot be automatically corrected:

**Manual correction required:**
```
1. Use eccentric nuts to adjust gantry level
2. Manually tram gantry to bed using dial indicator
3. Then run BED_MESH_CALIBRATE
```

**If gantry is tilted on K2 Pro:**
```
Bed mesh sees large gradient:

Left side: all points -0.5mm
Right side: all points +0.5mm

Mesh will compensate, but:
  - Uses up compensation range
  - May exceed practical limits
  - First layer quality varies across bed
```

**Recommendation:** Physically level K2 Pro gantry before relying on bed mesh.

---

## Z-Offset and Bed Mesh Interaction

### What is Z-Offset?

**From PRTouch config:**
```ini
[prtouch_v3]
z_offset: 0    # Distance from probe trigger to nozzle tip
```

**Purpose:**
```
PRTouch probe triggers when strain gauge detects bed
Nozzle tip might be slightly above/below trigger point
z_offset compensates for this difference

Example:
  Probe triggers at Z=0.5mm
  Nozzle tip is actually at Z=0.3mm
  z_offset = -0.2mm (nozzle is 0.2mm below trigger)
```

### Execution Order

```
1. Probe trigger detected
   ↓
2. Apply z_offset
   → Adjusted trigger height
   ↓
3. Use adjusted height for bed mesh calibration
   → Build mesh matrix
   ↓
4. During printing, apply mesh compensation
   → Runtime Z adjustment
```

### Z-Offset Affects Mesh Calibration

**Scenario: z_offset = -0.2mm**

```
Probe point (50, 50):
  Raw trigger: 0.50mm
  + z_offset: -0.20mm
  = Recorded height: 0.30mm

Probe point (100, 100):
  Raw trigger: 0.55mm
  + z_offset: -0.20mm
  = Recorded height: 0.35mm

Mesh stores: 0.30mm and 0.35mm
Relative difference: 0.05mm ← This is what matters
```

**Key insight:** z_offset shifts the entire mesh uniformly, but **relative differences remain unchanged**.

### Z-Offset Does NOT Affect Mesh Compensation

During printing, bed mesh compensates based on **relative** heights:

```
If mesh at (50,50) = 0.30mm
And mesh at (100,100) = 0.35mm

Difference = +0.05mm

When printing at (100,100):
  Commanded Z: 0.2mm
  Mesh compensation: +0.05mm (relative to average)
  Actual Z: 0.25mm

z_offset already applied during calibration
No further z_offset adjustment needed
```

### Changing Z-Offset After Mesh Calibration

**What happens:**
```
1. Calibrate mesh with z_offset = 0
   → Mesh stored with these values

2. Change z_offset to -0.2mm
   → Probe trigger point changes
   → But mesh is NOT automatically updated

3. Print with old mesh + new z_offset
   → MISMATCH!
   → First layer will be 0.2mm too low
```

**Solution:** Always recalibrate mesh after changing z_offset:
```gcode
# Change z_offset
# Save config
# Restart Klipper
G28                    # Home
Z_TILT_ADJUST          # If K2 Plus
BED_MESH_CALIBRATE     # Recalibrate with new offset
```

### Z-Offset vs Manual Z Adjustment

**Z-Offset (PRTouch config):**
- Changes probe trigger-to-nozzle distance
- Permanent (saved in config)
- Affects all future probing
- **Requires mesh recalibration**

**Manual Z Adjustment (Babystepping):**
```gcode
SET_GCODE_OFFSET Z=+0.05  # Move nozzle 0.05mm up
```
- Temporary offset during print
- Does NOT affect mesh
- Does NOT require recalibration
- Useful for fine-tuning first layer

**Best practice:**
```
1. Set z_offset correctly once (use paper test)
2. Calibrate bed mesh
3. Use SET_GCODE_OFFSET for fine-tuning if needed
4. If SET_GCODE_OFFSET always needed, update z_offset and recalibrate
```

---

## Common Issues and Solutions

### Issue 1: First Layer Varies Across Bed

**Symptoms:**
- Left side too squished, right side too high (or vice versa)
- Consistent pattern across bed

**Likely Cause: Gantry Tilt (K2 Plus)**
```
Solution:
  1. Run Z_TILT_ADJUST
  2. Recalibrate bed mesh
  3. If issue persists, check z_tilt.retry_tolerance
```

**Likely Cause: Gantry Tilt (K2 Pro)**
```
Solution:
  1. Manually tram gantry using eccentric nuts
  2. Use dial indicator to verify level
  3. Recalibrate bed mesh
```

### Issue 2: Mesh Calibration Fails

**Error:**
```
"bed_mesh: Mesh extends outside of the fade range"
```

**Meaning:**
- Bed deviation exceeds ±45mm (fade_dist)
- **This is extremely bad** - your bed is severely warped

**Solutions:**
1. **Check physical bed mounting** - screws tight?
2. **Replace bed** if warped beyond repair
3. **Temporarily increase fade_end** (not recommended):
   ```ini
   [bed_mesh]
   fade_end: 100.0  # Increase fade distance
   ```

### Issue 3: Mesh Shows > ±2mm Deviation

**Visualization:**
```
BED_MESH_OUTPUT shows:
  Min: -2.5mm
  Max: +3.0mm
  Range: 5.5mm
```

**This is problematic** - bed mesh will struggle to compensate.

**Solutions:**
1. **Physical bed leveling:**
   - Adjust bed screws to reduce tilt
   - Use glass or aluminum bed if warped

2. **Check bed temperature:**
   - Bed warps when heated
   - Calibrate mesh at print temperature

3. **Check frame:**
   - Warped aluminum extrusions
   - Loose bolts allowing movement

### Issue 4: Z-Offset Changed, Prints Fail

**What happened:**
```
1. Mesh calibrated with z_offset = 0
2. Changed z_offset = -0.3mm (lowered nozzle)
3. First layer now drags/fails
```

**Why:**
- Mesh values still based on old z_offset
- Nozzle now 0.3mm lower than mesh expects

**Fix:**
```gcode
G28
Z_TILT_ADJUST  # If K2 Plus
BED_MESH_CALIBRATE PROFILE=default
SAVE_CONFIG
```

### Issue 5: Flow Looks Wrong Despite Good Mesh

**Symptoms:**
- Some areas over-extruded, others under-extruded
- Mesh compensation working (verified with BED_MESH_OUTPUT)

**Likely Cause:**
- Bed mesh compensates Z, not E
- Large Z variations (>1mm) cause flow mismatch

**Solutions:**
1. **Fix bed physically** - reduce deviation to <0.5mm
2. **Adjust flow rate** - slight increase/decrease in slicer
3. **Use linear advance** - helps with flow consistency
4. **Check actual layer heights** - use dial indicator during print

---

## Summary: Practical Guidelines

### Maximum Safe Compensation

| Layer Range | Max Deviation | Action if Exceeded |
|-------------|---------------|-------------------|
| First layer (0-0.5mm) | ±0.2mm | Critical - fix bed |
| Low layers (0.5-5mm) | ±0.5mm | Important - improve bed |
| Mid layers (5-30mm) | ±1.5mm | Acceptable with caution |
| High layers (30-50mm) | ±3mm | Fading out, minimal impact |

**Code hard limit:** ±45mm (fade_dist), but **practical limit is ±2mm maximum**.

### Flow Rate

- Bed mesh **does not adjust extrusion rate**
- Small Z variations (<0.5mm): negligible impact
- Large Z variations (>1mm): visible flow mismatch
- **Fix bed physically rather than relying on extreme compensation**

### K2 Plus Z-Tilt

- **Always run Z_TILT_ADJUST before bed mesh**
- Z-tilt levels gantry (macro-level)
- Bed mesh compensates surface (micro-level)
- Order: `G28 → Z_TILT_ADJUST → BED_MESH_CALIBRATE`

### Z-Offset

- Set once during initial setup
- **Recalibrate mesh after changing z_offset**
- Use `SET_GCODE_OFFSET Z=` for temporary adjustments
- Z-offset shifts entire mesh uniformly, doesn't affect relative compensation

### Best Practices

1. **Physical bed preparation:**
   - Tram bed properly (manual or z_tilt)
   - Aim for <1mm deviation across bed
   - Use quality bed surface (glass, PEI, etc.)

2. **Calibration sequence:**
   ```gcode
   G28                        # Home
   Z_TILT_ADJUST              # K2 Plus only
   BED_MESH_CALIBRATE         # At print temperature
   SAVE_CONFIG
   ```

3. **Maintenance:**
   - Recalibrate mesh monthly or when bed changed
   - Check mesh deviation with `BED_MESH_OUTPUT`
   - If deviation increases, check physical bed

4. **Troubleshooting:**
   - First layer issues → check z_offset, recalibrate mesh
   - Gantry tilt → run Z_TILT_ADJUST (K2 Plus) or tram manually (K2 Pro)
   - Extreme deviation → fix bed physically, don't rely on mesh
