# RectDetection — Green Gate Detection

**Source:** `src/imagens/indoor_2025/rect_detection.py`

`RectDetection` takes a single RGB + depth frame pair and detects the competition gate (two vertical green posts). It is instantiated per frame — not a persistent object.

## Constructor

```python
RectDetection(image, image_depth, color)
```

| Param | Type | Description |
|-------|------|-------------|
| `image` | `np.ndarray` | BGR uint8 from ZED left camera |
| `image_depth` | `np.ndarray` | float32 depth map (meters) |
| `color` | `str` | Color to detect — currently only `'green'` is configured |

### Internal constants

| Attribute | Value | Purpose |
|-----------|-------|---------|
| `erode_iterations` | 2 | Noise removal on color mask |
| `dilate_iterations` | 5 | Fills gaps in detected posts |
| `color_ranges['green']` | HSV `[38,23,0]`–`[98,118,128]` | Green gate post color range |
| `delta` | 30 px | Dead-zone width around image center |
| `DEPTH_TOLERANCE_M` | 0.05 m | Depth band used to isolate the nearest plane |

## Methods

### `detect_gate_and_get_error() → (gate_found, error_x, error_y, color_detected)`

Main detection method. Works in two stages:

**Stage 1 — Depth isolation**  
Finds the minimum valid depth in the bottom 2/3 of the image (top third is usually sky/ceiling). Keeps only pixels within `[min_depth, min_depth + DEPTH_TOLERANCE_M]`. This strips background clutter at different distances.

**Stage 2 — Color + shape filtering**  
Converts the depth-masked image to HSV and applies the green range. Finds contours and keeps only those with aspect ratio `h > 3w` (tall, thin vertical posts) and area `> 250 px`.  
- Left post: contour center must be left of `center_x - delta - 10`  
- Right post: contour center must be right of `center_x + delta`

Returns:
- `gate_found`: `True` only when both a left and right post are found
- `error_x`: horizontal pixel offset of gate midpoint from image center (positive = gate is right of center)
- `error_y`: vertical pixel offset (positive = gate is above center)
- `color_detected`: `True` if any green pixels were found regardless of gate shape

Draws debug overlays directly onto `self.image`: center lines, bounding boxes, midpoint circle, distance text.

---

### `detect_gate_depth_and_get_error(depth_tolerance=0.2) → (gate_found, error_x)`

Alternative method using depth symmetry instead of shape filtering.

**Logic:**
1. Splits the bottom 2/3 of the depth map into left and right halves (separated by `delta`).
2. Checks that `|left_min_depth - right_min_depth| < depth_tolerance` — symmetric objects at the same distance.
3. Checks that both halves have green contours with area `> 500`.
4. Returns the horizontal error between the two nearest-point centers.

Use this when the posts are wide and don't pass the `h > 3w` vertical aspect filter.

---

### `is_at_target_distance(target_distance) → (reached, min_depth)`

Checks if the nearest object in the bottom 2/3 of the depth frame is at or closer than `target_distance` meters.

Returns:
- `reached`: `True` if `min_depth <= target_distance`
- `min_depth`: the measured minimum depth, or `None` if no valid data

Used by [Mission_1](mission_1.md) in the `ADJUSTMENT` state to approach the gate before searching sideways.

## Example (per frame)

```python
detector = RectDetection(zed_node.frame, zed_node.depth_frame, 'green')

# Check approach distance
reached, dist = detector.is_at_target_distance(target_distance=0.8)

# Detect and get centering error
gate_found, err_x, err_y, color = detector.detect_gate_and_get_error()
if gate_found:
    vel = pid.update(err_x)
    mav.set_vel_relative(sideways=vel)
```

## Depth filtering rationale

Cropping the top third removes the ceiling, which is often the nearest surface and would otherwise dominate `min_depth`. The tight tolerance (`0.05 m`) ensures the selected depth plane corresponds to the gate frame itself, not a wall behind it.

## See also

- [PID controller](pid.md) — converts `error_x` into a velocity command
- [Mission_1](mission_1.md) — uses all three methods here in sequence
- [ZedSubscriber](zed_subscriber.md) — provides `frame` and `depth_frame`
