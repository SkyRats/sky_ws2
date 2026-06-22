# PID Controller

**Source:** `src/imagens/indoor_2025/mission_1.py` (class `PID`)  
Also duplicated (as `pid`) in `src/imagens/indoor_2025/imav_pid_mavros.py` and `src/imagens/mission_1.py`

Lightweight discrete PID with output clamping. Used to convert pixel error from the camera into a velocity command for the drone.

## Class

```python
class PID:
    def __init__(self, kp=0.0035, kd=0.0, ki=0.0):
        ...
```

| Param | Typical value | Effect |
|-------|--------------|--------|
| `kp` | `0.0035` | Proportional gain — main driver |
| `kd` | `0.0` | Derivative gain — dampens oscillation |
| `ki` | `0.0` | Integral gain — corrects steady-state error |

## Methods

### `update(err) → float`

```python
value = kp * err + (err - last_err) * kd + sum_err * ki
value = clamp(value, -2.0, 2.0)
```

Updates internal state and returns the control output clamped to `[-2, 2]` m/s.

### `refresh()`

Resets `last_err` and `last_sum_err` to zero. Call this before starting a new centering attempt to avoid integrator windup from a previous run.

## Tuning notes

Default gains (`kp=0.0035, kd=0, ki=0`) are tuned for pixel error units (~hundreds of pixels) mapping to velocity in m/s. At `kp=0.0035`:
- 100 px error → 0.35 m/s
- 571 px error → saturates at 2 m/s

The dead-zone check (`abs(err) < 20`) in [Mission_1](mission_1.md) avoids noisy small corrections near center.

## Usage

```python
pid = PID(kp=0.0035)
pid.refresh()

while True:
    gate_found, err_x, _, _ = detector.detect_gate_and_get_error()
    if gate_found:
        vel = pid.update(err_x - offset)
        mav.set_vel_relative(sideways=vel)
```

## See also

- [Mission_1](mission_1.md) — uses `PID` for horizontal gate centering
- [Precision landing](precision_landing.md) — uses the same pattern for X/Y landing pad centering
- [Gate detection](gate_detection.md) — produces the `err_x` / `err_y` inputs
