# Stop Guessing - Add Precision Bed Leveling to Your K2 Pro in 5 Minutes

*Originally posted to [r/Creality_k2](https://www.reddit.com/r/Creality_k2/comments/1q3xc1d/stop_guessing_add_precision_bed_leveling_to_your/) by u/aerogrowz*

---

## Problem

Brand new K2 Pro kept having adhesion issues in front right corner on most prints. Bringing up Fluidd, the bed was tilted beyond 0.6mm from factory.

Typically anything above 0.5mm causes issues even with compensation.

**Goal:** Get below 0.3mm; chasing below that is magical unicorn land (charliiieee). Should be simple? Heh... well kind of...

## Creality K2 Pro: Enable SCREWS_TILT_CALCULATE for Manual Bed Leveling

The Creality K2 Pro doesn't include Klipper's `screws_tilt_adjust` module by default. This guide walks you through enabling it so you can get precise bed leveling instructions for each corner screw. Making this a 5-minute operation instead of a couple hours.

## What This Does

`SCREWS_TILT_CALCULATE` probes each bed screw location and tells you exactly how much to turn each screw to level the bed. Output looks like:

```
front left (base): x=35, y=35, z=2.48
front right: x=275, y=35, z=2.36 : adjust CW 00:15
rear right: x=275, y=275, z=2.71 : adjust CCW 00:50
rear left: x=35, y=275, z=2.47 : adjust CW 00:02
```

The "00:15" means 15 minutes on a clock face (1/4 turn). CW = clockwise, CCW = counter-clockwise.

## Prerequisites

* Creality K2 Pro with network connectivity
* Access to Fluidd web interface (`http://YOUR_PRINTER_IP:4408`)
* SSH client (Terminal on Mac/Linux, MobaXterm or PuTTY on Windows)

## Step 1: Enable Root Access on K2 Pro

1. On the K2 Pro touchscreen, go to **Settings**
2. Scroll down and select **Root account information**
3. Read the disclaimer, check the box **"I have read and understood the risks of Root login"**
4. Wait 30 seconds, then press **OK**
5. Note the password displayed (spoiler: it's `creality_2024`)

## Step 2: SSH Into the Printer

Open your terminal/SSH client and connect:

```bash
ssh root@YOUR_PRINTER_IP
```

When prompted for password, enter: `creality_2024`

## Step 3: Download the screws_tilt_adjust Module

The K2 Pro doesn't have `wget` or `curl`, so use Python:

```bash
cd /usr/share/klipper/klippy/extras
python3 -c "import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/Klipper3d/klipper/master/klippy/extras/screws_tilt_adjust.py', 'screws_tilt_adjust.py')"
```

Verify it downloaded:

```bash
ls -la screws_tilt_adjust.py
```

## Step 4: Add Configuration to printer.cfg

Open Fluidd in your browser: `http://YOUR_PRINTER_IP:4408`

Click the **Configuration** icon (gear/cog) in the left sidebar

Open **printer.cfg**

Add the following at the end of the file:

```ini
[screws_tilt_adjust]
screw1: 35, 35
screw1_name: front left
screw2: 275, 35
screw2_name: front right
screw3: 275, 275
screw3_name: rear right
screw4: 35, 275
screw4_name: rear left
horizontal_move_z: 5
speed: 150
screw_thread: CW-M4
```

## Step 5: Add Calibration Macro (Optional but Recommended)

Add this macro to printer.cfg for a one-command calibration that heats the bed first (tuned for PLA):

```ini
[gcode_macro SCREWS_CALIBRATION]
gcode:
    G28
    M190 S60          ; wait for bed to hit 60C (PLA temp)
    M109 S150         ; nozzle warm but not oozing
    G28 Z             ; re-home Z at temp
    SCREWS_TILT_CALCULATE
```

For ABS, change `M190 S60` to `M190 S90` or higher.

## Step 6: Restart Klipper

1. In Fluidd, click **Save** on printer.cfg
2. Click the power icon in the top right
3. Select **Restart Klipper**

## Step 7: Run the Calibration

In the Fluidd console, run:

```
SCREWS_CALIBRATION
```

Or if you didn't add the macro:

```
G28
SCREWS_TILT_CALCULATE
```

## Interpreting Results

The output tells you how to adjust each screw:

| Output | Meaning |
|--------|---------|
| `CW 00:15` | Turn clockwise 1/4 turn (15 minutes) |
| `CCW 00:30` | Turn counter-clockwise 1/2 turn (30 minutes) |
| `CW 01:00` | Turn clockwise 1 full turn |
| `(base)` | Reference screw - don't adjust this one |

**Goal:** Get all screws to show `00:00` or under `00:06` (6 minutes = 1/16 turn).

## Troubleshooting

### "Section 'screws_tilt_adjust' is not a valid config section"

The Python module didn't download correctly or Klipper wasn't restarted. Re-run Step 3 and verify the file exists, then restart Klipper.

### "Must home axis first"

Run `G28` before `SCREWS_TILT_CALCULATE`, or use the `SCREWS_CALIBRATION` macro which homes automatically.

### Coordinates seem wrong

The default coordinates are estimates. To find exact positions:

1. Home the printer
2. Manually jog the nozzle directly over each bed screw
3. Note the X,Y coordinates from Fluidd
4. Update the screw coordinates in printer.cfg

## Tips

* **Level at temperature** - the bed expands when heated, so always calibrate at your typical print temp
* **Iterate** - run calibration multiple times until adjustments are minimal
* **Don't chase perfection** - under 0.3mm range with mesh compensation is fine
* **Screw direction on K2 Pro** - CW raises the corner, CCW lowers it (looking at screw from above). So you have to do opposite of what it says when looking from bottom.

## Run Example

### Before

```
1:20 means 1 full turn and 20 minutes, CW=clockwise, CCW=counter-clockwise
12:56:58
// front left (base) : x=35.0, y=35.0, z=-0.11178
12:56:58
// front right : x=275.0, y=35.0, z=-0.24091 : adjust CW 00:11
12:56:58
// rear right : x=275.0, y=275.0, z=0.23172 : adjust CCW 00:29
12:56:58
// rear left : x=35.0, y=275.0, z=0.42728 : adjust CCW 00:46
12:56:58
// [DEBUG]multi_probe_end
13:08:11
$ SCREWS_CALIBRATION

13:08:56
// probe at 35.000,275.000 is z=0.074062 z_compensation=0.118000
13:08:56
// probe at 35.000,275.000 is z=0.192062
13:08:56
// 01:20 means 1 full turn and 20 minutes, CW=clockwise, CCW=counter-clockwise
13:08:56
// front left (base) : x=35.0, y=35.0, z=0.03359
13:08:56
// front right : x=275.0, y=35.0, z=-0.06172 : adjust CW 00:08
13:08:56
// rear right : x=275.0, y=275.0, z=0.01006 : adjust CW 00:02
13:08:56
// rear left : x=35.0, y=275.0, z=0.19206 : adjust CCW 00:14
13:08:56
// [DEBUG]multi_probe_end


13:12:12
// [PROBE_PRES_INFO]pres_bst_indx=49 pres_bst_time=-0.011
13:12:12
// [PROBE_STEP_INFO]step_bst_indx=34 step_bst_time=-0.011 tri_pose=599.831 bst_pose=599.776 bst_zoft=0.055 POS=[35.00,275.00,0.0933]
13:12:12
// probe at 35.000,275.000 is z=0.093312 z_compensation=0.055000
13:12:12
// probe at 35.000,275.000 is z=0.148312
13:12:12
// 01:20 means 1 full turn and 20 minutes, CW=clockwise, CCW=counter-clockwise
13:12:12
// front left (base) : x=35.0, y=35.0, z=0.02391
13:12:12
// front right : x=275.0, y=35.0, z=-0.03778 : adjust CW 00:05
13:12:12
// rear right : x=275.0, y=275.0, z=0.11322 : adjust CCW 00:08
13:12:12
// rear left : x=35.0, y=275.0, z=0.14831 : adjust CCW 00:11
13:12:12
// [DEBUG]multi_probe_end
```

### After (0.27mm)

Off to the magical Candy Mountain! 🦄

---

## K2 Series Variations

### K2 (Regular) - 260×260×260mm (Single Z)

**Note**: Some users mentioned `ccw-m4` for screw thread vs `cw-m4` (firmware or model difference)

```ini
[screws_tilt_adjust]
screw1: 30, 30
screw1_name: front left
screw2: 230, 30
screw2_name: front right
screw3: 230, 230
screw3_name: rear right
screw4: 30, 230
screw4_name: rear left
horizontal_move_z: 5
speed: 150
screw_thread: CW-M4
```

**Note:** Coordinates estimated at ~30mm inset. Verify by homing and moving nozzle over each screw to confirm actual positions.

### K2 Plus - 350×350×350mm (Dual Z Motors)

```ini
[screws_tilt_adjust]
screw1: 35, 35
screw1_name: front left
screw2: 315, 35
screw2_name: front right
screw3: 315, 315
screw3_name: rear right
screw4: 35, 315
screw4_name: rear left
horizontal_move_z: 5
speed: 150
screw_thread: CW-M4

[gcode_macro SCREWS_CALIBRATION]
gcode:
    G28
    M190 S60
    M109 S150
    Z_TILT_ADJUST          ; level gantry first (dual Z)
    G28 Z
    SCREWS_TILT_CALCULATE
```

**Important:** K2 Plus has dual independent Z motors with auto-tilt calibration. The macro runs `Z_TILT_ADJUST` first to level the gantry, then `SCREWS_TILT_CALCULATE` for manual screw adjustments.

When reading output:

* Only compare front-to-back **per side** (front left vs rear left, front right vs rear right)
* Ignore left-vs-right differences - `Z_TILT_ADJUST` handles that
* These adjustments are complementary, not conflicting

### All Models

* Same SSH password: `creality_2024`
* Same missing module issue
* Same installation process

---

## Credits

* [Klipper Documentation - Manual Level](https://www.klipper3d.org/Manual_Level.html)
* [jamincollins/k2-improvements](https://github.com/jamincollins/k2-improvements)
* [Guilouz Creality Helper Script](https://github.com/Guilouz/Creality-Helper-Script)
* Original Reddit post by u/aerogrowz on r/Creality_k2
