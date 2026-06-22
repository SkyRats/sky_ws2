# Precision Landing — Standalone Color Blob Script

**Source:** `src/imagens/indoor_2025/imav_pid_mavros.py`

Standalone script for a survey-then-land mission using a downward-facing USB camera. Not integrated into the main `mission.py` flow — run independently when testing color-blob landing.

## Overview

Takeoff → survey altitude → find colored pad → PID-center → land.

## Configuration

```python
SURVEY_ALT = 2.0          # meters
TIMEOUT = 4               # seconds for PID centering loop
COLOR_TO_LAND = "blue"    # which pad color to target
```

Supported colors and their HSV ranges:

| Color | Lower HSV | Upper HSV |
|-------|-----------|-----------|
| `purple` | `[127, 52, 0]` | `[169, 255, 255]` |
| `red` | `[0, 100, 100]` | `[10, 255, 255]` |
| `green` | `[40, 100, 100]` | `[80, 255, 255]` |
| `blue` | `[100, 100, 100]` | `[140, 255, 255]` |

## `find_biggest_err(Image, lower, upper) → (err_x, err_y)`

Pure function. Finds the largest contour (area `> 1000 px`) matching the HSV range and returns pixel offset of its centroid from the image center.

- `err_x` positive → target is to the right
- `err_y` positive → target is above center (image Y flipped)
- Returns `(None, None)` if no matching contour found

## State machine

```
TAKEOFF → SURVEY → CENTRALIZE → LAND → END
```

| State | Description |
|-------|-------------|
| `TAKEOFF` | `mav.takeoff(SURVEY_ALT)`, sleep 8 s |
| `SURVEY` | Grab frame, call `find_biggest_err`. If found → verify (grab again), go to CENTRALIZE. If not found → LAND. |
| `CENTRALIZE` | PID loop for `TIMEOUT` seconds. `pid_x` controls sideways (Y axis), `pid_y` controls forward (X axis). Tiny upward drift (+0.03 m/s) keeps altitude stable. Goes to LAND when `|err_x| < 40 and |err_y| < 40`. |
| `LAND` | Stop, call `mav.land()`, sleep 15 s, go to END. |
| `END` | Release camera, `running = False`. |

## PID setup

```python
pid_x = pid(0.003, 0.0, 0.0)   # sideways
pid_y = pid(0.003, 0.0, 0.0)   # forward
```

See [PID](pid.md) for implementation details.

## Camera

Uses `cv2.VideoCapture(0)` — expects a downward-facing USB camera at index 0. Frames are resized to 640 px wide before processing.

## Running

```bash
cd src/imagens/indoor_2025
python3 imav_pid_mavros.py
```

Requires MAVROS and the camera driver to be running. The ZED is not used here.

## Relationship to Mission_4

This script implements a complete version of what [Mission_4](mission_4.md) is meant to do. The detection approach differs (color blob vs. H-circle shape), but the PID centering and land sequence are the same pattern.

## See also

- [Mav](communication.md) — used for all movement and landing
- [PID](pid.md) — `pid` class (lowercase, same implementation)
- [Mission_4](mission_4.md) — integration target that should subsume this logic
