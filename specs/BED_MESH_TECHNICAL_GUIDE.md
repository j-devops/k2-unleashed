# K2 Bed Mesh System - Technical Overview

## Configuration (K2 Pro Example)

From `config/F012_CR0CN200400C10/printer.cfg:405-418`:

```ini
[bed_mesh]
speed: 100                    # Speed (mm/s) of non-probing moves
mesh_min: 5,5                 # Minimum X,Y coordinates to probe
mesh_max: 295,295             # Maximum X,Y coordinates (300mm bed)
probe_count: 7,7              # 7x7 grid = 49 probe points
mesh_pps: 2, 2                # Points Per Segment for interpolation
fade_start: 5.0               # Z height where fade begins
fade_end: 50.0                # Z height where compensation ends
bicubic_tension: 0.2          # Tension for bicubic interpolation
algorithm: bicubic            # Interpolation algorithm (bicubic or lagrange)
horizontal_move_z: 5          # Z height for travel moves
split_delta_z: 0.01           # Max Z adjustment per move segment
move_check_distance: 1        # Distance for move splitting
```

## High-Level Overview: How Bed Mesh Works

### 1. Calibration Phase (`BED_MESH_CALIBRATE`)

**What it does:** Probes the bed at multiple points to create a height map.

```
Process Flow:
┌─────────────────────────────────────────────────┐
│ 1. Generate Probe Points (7x7 = 49 points)     │
│    - Uses zig-zag pattern for efficiency       │
│    - Even rows: left→right, Odd rows: right→left│
└─────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────┐
│ 2. PRTouch Probes Each Point                    │
│    - Moves to X,Y position                      │
│    - Probes Z height with strain gauge          │
│    - Stores (X, Y, Z) coordinate                │
└─────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────┐
│ 3. Build Probed Matrix (7x7 array)             │
│    - Organize points into 2D grid               │
│    - Apply probe Z offset                       │
└─────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────┐
│ 4. Interpolate Mesh (bicubic algorithm)        │
│    - With mesh_pps=2, creates refined mesh      │
│    - 7 probed → 19 interpolated points per axis │
│    - Final mesh: 19x19 = 361 points             │
└─────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────┐
│ 5. Save Profile to printer.cfg                 │
│    - Stored as [bed_mesh default]              │
│    - Auto-loaded on startup                     │
└─────────────────────────────────────────────────┘
```

**Code:** `bed_mesh.py:674-798` (BedMeshCalibrate.cmd_BED_MESH_CALIBRATE)

### 2. Runtime Compensation (During Printing)

**What it does:** Adjusts Z height in real-time based on X,Y position.

```
Every Move Command:
┌─────────────────────────────────────────────────┐
│ User issues: G1 X100 Y150 Z0.2                  │
└─────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────┐
│ BedMesh.move() intercepts the move              │
│ - Calculates Z adjustment for current position  │
│ - Uses bilinear interpolation on mesh grid      │
└─────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────┐
│ calc_z(x=100, y=150)                            │
│ - Finds 4 nearest mesh points                   │
│ - Interpolates Z adjustment: e.g., +0.05mm      │
└─────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────┐
│ Apply fade factor (Z height dependent)          │
│ - Z=0-5mm:  100% compensation (factor=1.0)      │
│ - Z=5-50mm: Gradual fade 100%→0%                │
│ - Z>50mm:   0% compensation (factor=0.0)        │
└─────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────┐
│ Split long moves into segments                  │
│ - Each segment ≤ move_check_distance (1mm)      │
│ - Recalculates Z for each segment               │
│ - Ensures smooth Z compensation                 │
└─────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────┐
│ Execute: G1 X100 Y150 Z0.25 (0.2 + 0.05 adjust) │
└─────────────────────────────────────────────────┘
```

**Code:** `bed_mesh.py:245-285` (BedMesh.move)

## Key Code Components

### 1. Point Generation (`bed_mesh.py:380-422`)

```python
def _generate_points(self, error):
    x_cnt = 7  # probe_count X
    y_cnt = 7  # probe_count Y
    min_x, min_y = 5, 5      # mesh_min
    max_x, max_y = 295, 295  # mesh_max

    # Calculate spacing between points
    x_dist = (max_x - min_x) / (x_cnt - 1)  # 290/6 = 48.33mm
    y_dist = (max_y - min_y) / (y_cnt - 1)  # 290/6 = 48.33mm

    points = []
    for i in range(y_cnt):  # Y rows
        for j in range(x_cnt):  # X columns
            if not i % 2:
                # Even rows: left to right
                pos_x = min_x + j * x_dist
            else:
                # Odd rows: right to left (zig-zag)
                pos_x = max_x - j * x_dist
            points.append((pos_x, pos_y))
        pos_y += y_dist
```

**Example probe pattern (7x7):**
```
Row 6: (5,295) → (53,295) → (101,295) → ... → (295,295)
       ↓
Row 5: (295,247) ← (247,247) ← (199,247) ← ... ← (5,247)
       ↓
Row 4: (5,199) → (53,199) → (101,199) → ... → (295,199)
       ...
Row 0: (295,5) ← (247,5) ← (199,5) ← ... ← (5,5)
```

### 2. Z Calculation with Interpolation (`bed_mesh.py:965-978`)

```python
def calc_z(self, x, y):
    # Uses optimized C implementation via mymovie module
    return mymovie.Py_zmesh_calc_c(x, y, self.info_array_addr_int)

    # Python reference implementation (commented out for speed):
    # 1. Find mesh indices for X,Y position
    # 2. Get 4 surrounding mesh points
    # 3. Bilinear interpolation:
    #    z0 = lerp(tx, tbl[yidx][xidx], tbl[yidx][xidx+1])
    #    z1 = lerp(tx, tbl[yidx+1][xidx], tbl[yidx+1][xidx+1])
    #    return lerp(ty, z0, z1)
```

**Bilinear Interpolation Example:**
```
Mesh points:          Nozzle at (X=52, Y=53)

  (48,101) +0.10     (96,101) +0.05
       ┌────────────────┐
       │                │
       │    *           │  * = nozzle position
       │  (52,53)       │
       │                │
       └────────────────┘
  (48,5)   +0.15     (96,5)   +0.12

Interpolated Z = bilinear(+0.10, +0.05, +0.15, +0.12) ≈ +0.13mm
```

### 3. Fade System (`bed_mesh.py:209-215`)

```python
def get_z_factor(self, z_pos):
    if z_pos >= 50.0:  # fade_end
        return 0.0  # No compensation
    elif z_pos >= 5.0:  # fade_start
        # Linear fade from 100% to 0%
        return (50.0 - z_pos) / 45.0  # fade_dist = 50-5 = 45
    else:
        return 1.0  # Full compensation
```

**Fade visualization:**
```
Z Height (mm) │ Factor │ Example Adjustment
──────────────┼────────┼───────────────────
    0.0       │  100%  │ +0.13mm → +0.13mm
    2.0       │  100%  │ +0.13mm → +0.13mm
    5.0       │  100%  │ +0.13mm → +0.13mm  ← fade_start
   10.0       │   89%  │ +0.13mm → +0.11mm
   20.0       │   67%  │ +0.13mm → +0.09mm
   30.0       │   44%  │ +0.13mm → +0.06mm
   40.0       │   22%  │ +0.13mm → +0.03mm
   50.0       │    0%  │ +0.13mm → +0.00mm  ← fade_end
   60.0       │    0%  │ +0.13mm → +0.00mm
```

### 4. Move Splitting (`bed_mesh.py:259-285`)

```python
def move(self, newpos, speed):
    factor = get_z_factor(newpos[2])

    if self.z_mesh is None or not factor:
        # No mesh or compensation disabled
        self.toolhead.move(newpos, speed)
    else:
        # Split long moves into small segments
        # Uses C++ splitter for performance
        self.splitter.build_move(self.move_array_addr_int)

        while True:
            self.splitter.split_for_loop(...)
            if segment_complete:
                self.toolhead.simple_move(segment)
            elif all_done:
                break
```

**Why split moves?**
```
Without splitting:
G1 X0 Y0 Z0.2 → X100 Y100 Z0.2
- Calculates Z adjustment only at start and end
- Bed curves between points are ignored
- Result: bumpy first layer

With splitting (every 1mm):
G1 X0 Y0 Z0.2 → many small moves → X100 Y100 Z0.2
- Recalculates Z every 1mm
- Follows bed contours precisely
- Result: smooth first layer
```

## Integration with PRTouch

### PRTouch Configuration (`printer.cfg:370-398`)

```ini
[prtouch_v3]
z_offset: 0                          # Probe trigger offset
speed: 5                             # Probe descent speed
samples: 1                           # Probes per point
samples_result: average              # How to combine samples
samples_tolerance: 0.5               # Max deviation allowed
samples_tolerance_retries: 5         # Retries if tolerance exceeded

# Temperature compensation (strain gauge drift)
temp_non_linaer_a = 0.00002375
temp_non_linaer_b = -0.003775
temp_non_linaer_c = 0.165
enable_not_linear_comp: True         # Use non-linear temp compensation

# PRTouch cleaning (keeps probe accurate)
prth_clr_brush_pos = 160, 326.5      # Silicone brush position
prth_clr_probe_pos = 145, 306.5      # Height check position
prth_clr_pose = 170, 306.5, 10       # Nozzle wipe position
```

### How PRTouch Works with Bed Mesh

1. **Probing Process:**
   - PRTouch uses a strain gauge in the hotend
   - When nozzle touches bed, strain increases
   - Binary blob `prtouch_v3_wrapper.cpython-39.so` handles detection
   - Returns Z height at trigger point

2. **Temperature Compensation:**
   - Strain gauge readings drift with temperature
   - Non-linear compensation formula applied to each measurement
   - Stored in `ZMesh.z_temp_compensation` (bed_mesh.py:979-988)

3. **Probe Cleaning:**
   - Before mesh calibration, nozzle is cleaned on silicone brush
   - Ensures consistent probe trigger height
   - Critical for repeatable measurements

## Interpolation Algorithms

### Bicubic (Default on K2)

**Advantages:**
- Smooth curves between points
- Better handling of complex bed shapes
- C¹ continuity (smooth first derivative)

**Math:** Uses 16 surrounding points with cubic polynomial:
```
f(x,y) = Σ(i=0→3)Σ(j=0→3) aᵢⱼ·xⁱ·yʲ
```

**Code:** `bed_mesh.py` - implemented in C++ via `mymovie.Py_zmesh_calc_c`

### Lagrange (Alternative)

**Advantages:**
- Exact fit through all probe points
- No tension parameter needed

**Disadvantages:**
- Can oscillate between points (Runge's phenomenon)
- Less smooth than bicubic

**Math:** Lagrange polynomial interpolation using barycentric weights

## Performance Optimizations

### 1. C++ Implementation (bed_mesh.py:8)
```python
import mymodule.mymovie as mymovie
```

Critical functions implemented in compiled C++ for speed:
- `Py_zmesh_calc_c()` - Z interpolation (called every move)
- `Py_get_z_factor()` - Fade calculation
- `PyMoveSplitter` - Move segmentation

### 2. NumPy Arrays (bed_mesh.py:91-92)
```python
self.move_array = np.array(self._move_array, dtype=np.float64)
self.move_array_addr_int = self.move_array.ctypes.data
```

Uses memory-mapped NumPy arrays to share data between Python and C++ without copying.

### 3. Mesh Caching (bed_mesh.py:867-869)
```python
self.__mesh_matrix = np.full(self.mesh_y_count * self.mesh_x_count, 0., dtype=np.float64)
self.__mesh_matrix_addr = self.__mesh_matrix.ctypes.data
```

Interpolated mesh stored in contiguous memory for fast lookups.

## Common G-code Commands

```gcode
BED_MESH_CALIBRATE PROFILE=default    # Run full calibration
BED_MESH_PROFILE LOAD=default         # Load saved mesh
BED_MESH_PROFILE SAVE=default         # Save current mesh
BED_MESH_CLEAR                        # Disable mesh compensation
BED_MESH_OUTPUT                       # Print mesh to console
BED_MESH_MAP                          # Output mesh as JSON
BED_MESH_SET_ENABLE                   # Enable compensation
BED_MESH_SET_DISABLE                  # Disable compensation
```

## Practical Example: First Layer

```gcode
# Start print at Z=0.2mm
G1 X50 Y50 Z0.2

# Bed mesh calculates adjustment at (50, 50)
# Let's say mesh shows bed is +0.08mm high at this point

# Actual Z sent to motors: 0.2 + 0.08 = 0.28mm
# Nozzle maintains 0.2mm gap from actual bed surface
```

**Result:** Even if bed is warped, nozzle stays consistent distance from surface.

## Files of Interest

- **Core Module:** `klippy/extras/bed_mesh.py` (1597 lines)
- **C++ Optimizations:** Binary module `mymodule/mymovie.so`
- **PRTouch Driver:** `prtouch_v3_wrapper.cpython-39.so` (proprietary)
- **K2 Pro Config:** `config/F012_CR0CN200400C10/printer.cfg`
- **K2 Plus Config:** `config/F008/printer.cfg` (larger bed: 350x350mm)

## Limitations & Considerations

1. **Proprietary PRTouch:** Closed-source binary limits debugging probe issues
2. **Mesh Resolution:** 7x7 = 49 points may miss small defects
3. **Interpolation Assumptions:** Bicubic assumes smooth bed surface
4. **Temperature Drift:** Strain gauge readings change with hotend temp
5. **Fade Zone:** No compensation above 50mm (usually not an issue)

## Why This Matters

Without bed mesh:
- Bed warping causes adhesion problems
- First layer varies in thickness
- Prints fail or have poor quality

With bed mesh:
- Compensates for bed imperfections automatically
- Consistent first layer across entire bed
- Successful prints even on slightly warped beds
