# Mission_4 — Landing Pad Detection

**Source:** `src/imagens/indoor_2025/mission_4.py`

**Status: incomplete.** The ALTITUDE and SEARCH states are partially implemented; APPROACH onward is a `pass` stub.

## Goal

Detect a "H inside circle" landing pad using a downward-facing camera and perform a precision landing on it.

## Detection — `Detection.detect_H_with_circle(img, debug=False)`

Static method. Detects the "H" helipad marker:

1. Converts to grayscale and applies Gaussian blur.
2. Binarizes with threshold 100 (dark H and circle on white background).
3. Finds external contours, filters by area `> 500`.
4. For each contour, checks if it is approximately circular (`|circle_area - contour_area| / circle_area < 0.25`).
5. Inside the circle ROI, detects internal contours and looks for exactly 3 black rectangles (two vertical bars + one horizontal crossbar of the "H").
6. Validates "H" heuristic: `max(heights) > 3 * max(widths)` — the two verticals must be tall and thin.

Returns `(True, center)` where `center = (cx, cy)` if both circle and H are found.

## State machine

```
ALTITUDE → SEARCH → APPROACH → STABILIZE → ANALYZE → LAND
```

| State | Status | Description |
|-------|--------|-------------|
| `ALTITUDE` | Implemented | `goto` current XY at `ALTITUDE = 1.25 m`, sleep 2 s |
| `SEARCH` | Partial | Reads frames from `cv2.VideoCapture(0)` — not finished |
| `APPROACH` | Stub | Not implemented |
| `STABILIZE` | Stub | Not implemented |
| `ANALYZE` | Stub | Not implemented |
| `LAND` | Stub | Not implemented |

## Camera

Mission_4 uses a separate **downward-facing USB camera** via `cv2.VideoCapture(0)`, not the ZED. This is for the landing pad view. The ZED is still passed in (for potential forward-facing tasks) but the pad detection frame comes from the USB cam.

```python
self.camera = cv2.VideoCapture(0)
```

Call `cleanup()` when done to release the camera resource.

## What needs to be implemented

1. In `SEARCH`: call `Detection.detect_H_with_circle(frame)` each loop iteration; transition to `APPROACH` when found.
2. `APPROACH`: fly toward the pad using XY error from `center`.
3. `STABILIZE`: hover and confirm detection stability.
4. `ANALYZE`: verify pad identity if multiple pads exist.
5. `LAND`: execute precision landing (via [Mav.land()](communication.md) or position setpoints).

## See also

- [Mav](communication.md) — `goto` and `land` used here
- [ZedSubscriber](zed_subscriber.md) — passed in but not used for pad detection
- [Precision landing](precision_landing.md) — a complete, standalone implementation of a similar flow using a downward camera and PID
- [Mission orchestrator](mission_orchestrator.md) — will call `run()` from `MISSION_4` state once implemented
