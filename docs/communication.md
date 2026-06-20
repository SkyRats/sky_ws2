# Mav — MAVROS Communication Interface

**Source:** `src/imagens/indoor_2025/communication2.py`

`Mav` is a ROS2 `Node` that wraps all MAVROS interactions needed for autonomous flight. Every mission module receives a `Mav` instance and calls its methods instead of touching MAVROS topics directly.

## Constructor

```python
Mav(debug=False, simulation=False, lidar_min=0.3, indoor=False, zed=True)
```

| Param | Default | Effect |
|-------|---------|--------|
| `debug` | `False` | Enables verbose ROS logger output |
| `simulation` | `False` | Switches pose source to `/mavros/local_position/pose` |
| `indoor` | `False` | Same effect as `simulation` for pose source |
| `zed` | `True` | Inverts Y axis sign (`const = -1`) to match ZED frame convention |
| `lidar_min` | `0.3` | Offset added to Z from pose callbacks (physical lidar mount offset) |

### Subscriptions

| Topic | Type | Used when |
|-------|------|-----------|
| `/mavros/local_position/pose` | `PoseStamped` | `simulation=True` or `indoor=True` |
| `/mavros/vision_pose/pose` | `PoseStamped` | Default (outdoor/real hardware) |

### Publishers

| Topic | Type | Purpose |
|-------|------|---------|
| `/mavros/setpoint_position/local` | `PoseStamped` | Absolute position setpoints |
| `/mavros/setpoint_raw/local` | `PositionTarget` | Raw setpoints (relative pos or velocity) |
| `/mavros/setpoint_velocity/cmd_vel_unstamped` | `Twist` | Velocity commands |

### Services called

| Service | Type | Purpose |
|---------|------|---------|
| `/mavros/set_mode` | `SetMode` | Change flight mode |
| `/mavros/cmd/arming` | `CommandBool` | Arm / disarm |
| `/mavros/cmd/takeoff` | `CommandTOL` | Takeoff command |

## Key attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `pose` | `Pose` | Current vehicle pose, updated by subscriber |
| `goal_pose` | `Pose` | Last commanded target pose |
| `mode` | `int` | Current mode (not actively updated) |

## Methods

### Movement

#### `goto(x, y, z, yaw, send_time)`
Sends an absolute position setpoint in the local NED frame.  
- Omitted axes default to current position.  
- `yaw` is offset by π/2 internally to match ArduPilot convention.  
- If `send_time` is given, keeps publishing for that many seconds (blocks).

#### `goto_relative(x, y, z, yaw, send_time)`
Sends a body-frame offset via `PositionTarget.FRAME_BODY_OFFSET_NED`.  
- `x` = forward, `y` = sideways (sign-corrected by `const`), `z` = upward.

#### `set_vel(vel_x, vel_y, vel_z, ang_x, ang_y, ang_z)`
Publishes a `Twist` velocity command (world frame).  
- `vel_y` is sign-corrected by `const`.

#### `set_vel_relative(forward, sideways, upward)`
Publishes a `PositionTarget` in body frame with only velocity bits unmasked.  
- Calls `rclpy.spin_once` after publishing.

#### `rotate(yaw)` / `rotate_relative(yaw)` / `rotate_control_yaw(yaw, yaw_rate)`
Three yaw control methods:
- `rotate` — absolute yaw via `goto`
- `rotate_relative` — relative yaw offset from current heading
- `rotate_control_yaw` — raw `PositionTarget` with yaw rate

#### `distance_to_goal() → float`
Euclidean distance between `pose` and `goal_pose`.

### Arming / mode

#### `arm() → bool` / `disarm() → bool`
Calls `/mavros/cmd/arming`. Returns `True` on success.

#### `change_mode(mode: str) → bool`
Calls `/mavros/set_mode`. Mode strings: `"4"` = GUIDED, `"9"` = LAND, `"0"` = STABILIZE.

#### `takeoff(height=1.0) → bool`
1. Checks if already at target height (within 0.1 m).  
2. Sets mode to GUIDED (`"4"`).  
3. Arms the drone.  
4. Sends `CommandTOL` with `altitude=height`.  
Returns `True` if command was sent without error.

#### `land() → bool`
Sets mode to LAND (`"9"`) and disarms.

### Utilities

#### `euler_from_quaternion(quaternion) → (roll, pitch, yaw)`
Manual quaternion-to-Euler conversion (no tf2 dependency).

#### `quaternion_from_euler(yaw, pitch, roll) → [qx, qy, qz, qw]`

#### `in_between(check, center, margin) → bool`
Returns `True` if `check` is within `margin` of `center`.

## Y-axis sign convention

ZED2i outputs poses in a right-handed coordinate system where Y points left, while ArduPilot uses Y pointing right. The `const = -1` flag (set when `zed=True`) flips the Y sign in all movement commands so callers can use an intuitive "positive Y = right" convention.

## See also

- [ZedSubscriber](zed_subscriber.md) — provides camera frames consumed by missions
- [Mission_1](mission_1.md) — primary consumer of `Mav`
- [Mission orchestrator](mission_orchestrator.md) — manages `Mav` lifecycle
