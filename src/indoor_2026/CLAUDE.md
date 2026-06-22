# CLAUDE.md

This file provides guidance to Claude Code when working with the `indoor_2026` package.

## What this package is

`indoor_2026` is the **legacy reference bridge** for the SkyRats IMAV 2026 drone. It contains the original ZED→MAVROS pose relay and a launch file that predates the production `sky_vision2` stack.

**Status: kept for reference only.** All production work uses `sky_vision2/ZedMavrosBridge`. Do not use `pose_relay` for real flights — it lacks velocity forwarding, auto-home, and BEST_EFFORT QoS.

## Package contents

| File | Role |
|------|------|
| `indoor_2026/pose_relay.py` | Legacy bridge: ZED pose → MAVROS vision_pose (position only) |
| `launch/mavros_zed.launch.py` | Starts MAVROS + ZED + pose_relay in one command |

## pose_relay node

### Topics

| Direction | Topic | Type |
|-----------|-------|------|
| Subscribes | `/mavros/zed/pose` | `geometry_msgs/PoseStamped` |
| Publishes | `/mavros/vision_pose/pose` | `geometry_msgs/PoseStamped` |

**Known issue:** `/mavros/zed/pose` is not published by the ZED ROS2 wrapper v5. The wrapper publishes on `/zed/zed_node/pose` (PoseStamped). `pose_relay` will receive no messages unless the topic is remapped at launch.

### Frame correction

`pose_relay` applies a 180° Z rotation: negates both X and Y, plus quaternion rotation. The ZED pose topic convention may differ from the odom topic — this has **not been hardware-verified** for the pose topic. `ZedMavrosBridge` (the production bridge) has been verified: ZED odom is X=North, Y=West, Z=Down, so only Y needs negating.

If `pose_relay` is ever revived, verify its frame correction against hardware before use. See `.claude/rules/pose_relay_frame_correction.md`.

### Limitations vs ZedMavrosBridge

| Feature | `pose_relay` | `ZedMavrosBridge` (sky_vision2) |
|---------|:---:|:---:|
| Frame correction (180° Z rotation) | Yes | Yes |
| Position to EKF | Yes | Yes |
| Velocity to EKF | **No** | Yes |
| Auto set_home | **No** | Yes |
| BEST_EFFORT QoS | **No** | Yes |
| Configurable topics | **No** | Yes |

## Build and run

```bash
cd ~/imav_2026_ws
colcon build --packages-select indoor_2026
source install/setup.bash
ros2 launch indoor_2026 mavros_zed.launch.py
```

**Do not run alongside `sky_vision2` bridge** — both publish to `/mavros/vision_pose/pose` and will confuse the EKF. Check with `ros2 node list | grep -E "pose_relay|zed_mavros_bridge"`.

## See also

- `src/sky_vision2/` — production bridge (use this for all flights)
- `docs/pose_relay.md` — detailed frame correction walkthrough
- `docs/launch.md` — `mavros_zed.launch.py` internals
- `docs/zed_mavros_bridge.md` — comparison table between both bridges
