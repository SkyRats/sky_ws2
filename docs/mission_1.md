# Mission_1 — Gate Traversal

**Source:** `src/imagens/indoor_2025/mission_1.py`

Finds a green gate using the ZED camera, centers on it, and flies through it. Uses depth data for initial approach and a PID controller for lateral centering.

## State machine

```
ADJUSTMENT → SIDE_FLY → CENTRALIZE → PASS → FINISHED
     ↓            ↓           ↓
   ERROR        ERROR       ERROR
```

| State | Description |
|-------|-------------|
| `ADJUSTMENT` | Fly forward until nearest object is ≤ 0.8 m |
| `SIDE_FLY` | Strafe sideways until gate is detected |
| `CENTRALIZE` | PID-center on gate midpoint |
| `PASS` | Fly forward at 0.5 m/s for 5 s to pass through |
| `FINISHED` | Return `(True, False)` |
| `ERROR` | Return `(False, True)`, stop the drone |

## `run() → (done: bool, problem: bool)`

Called once per `state_machine()` iteration from the [Mission orchestrator](mission_orchestrator.md). Steps through whichever state is active.

### ADJUSTMENT

- Timeout: 15 s
- Speed: 0.2 m/s forward
- Uses `RectDetection.is_at_target_distance(0.8)` to check distance
- Stops and transitions to SIDE_FLY when target reached

### SIDE_FLY

- Timeout: 180 s (3 min)
- Speed: 0.2 m/s sideways (negative = left)
- Calls `RectDetection.detect_gate_and_get_error()` each frame
- Stops and transitions to CENTRALIZE when gate found

### CENTRALIZE

- Timeout: 20 s
- PID: `kp=0.0035, kd=0, ki=0`
- Error dead-zone: `abs(err_x - offset) < 20` px (`offset = 10`)
- If gate lost: tries a small back-and-forth search (0.1 m/s), up to 10 retries
- Stops for 5 s when centered, then transitions to PASS

### PASS

- Fixed maneuver: forward at 0.5 m/s for 5 s
- No visual feedback — blind pass through the gate

## Key attributes

| Attribute | Value | Purpose |
|-----------|-------|---------|
| `offset` | 10 px | Horizontal centering bias (accounts for camera off-center mount) |
| `alt` | ±1 | Sign flips on each gate-lost event to alternate search direction |
| `sideways_velocity_search` | 0.2 m/s | Speed during SIDE_FLY scan |

## `update_frame()`

Helper called inside every state loop:

```python
def update_frame(self):
    rclpy.spin_once(self.mav, timeout_sec=0)
    rclpy.spin_once(self.zed_node, timeout_sec=0)
    self.cv_image = self.zed_node.frame
    self.cv_depth_image = self.zed_node.depth_frame
```

Both nodes are spun to keep MAVROS callbacks alive while the mission loop blocks.

## Older version

`src/imagens/mission_1.py` is an earlier iteration of the same class:
- No `ADJUSTMENT` state (starts immediately at `SIDE_FLY`)
- No depth image — `RectDetection` called with only `(image, color)` (2 args)
- No `offset` bias
- Identical PID parameters and velocity values

## See also

- [RectDetection](gate_detection.md) — vision backend used in every state
- [PID](pid.md) — lateral centering controller
- [Mav](communication.md) — `set_vel_relative`, `set_vel` calls
- [ZedSubscriber](zed_subscriber.md) — source of `frame` and `depth_frame`
- [Mission orchestrator](mission_orchestrator.md) — calls `run()` and handles return values
