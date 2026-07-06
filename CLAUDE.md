# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

ROS2 Humble workspace (`imav_2026_ws`) for the **SkyRats IMAV 2026 indoor autonomous drone** competition. The drone uses a ZED2i stereo camera for visual odometry, gate traversal, and precision landing, with ArduPilot (Pixhawk 6C) as the flight controller via MAVROS.

Hardware: NVIDIA Jetson + ZED2i (USB-C) + Pixhawk 6C (Telem2 UART `/dev/ttyTHS1:921600`).

## Build and run

```bash
# Always build before launching — launch files reference installed paths
cd ~/imav_2026_ws
colcon build --packages-select sky_vision2 sky_navigation
source install/setup.bash

# Full hardware stack (ZED + MAVROS + bridge)
ros2 launch sky_vision2 zed_mavros_fc.launch.py

# MAVROS + bridge only (ZED already running in another terminal)
ros2 launch sky_vision2 mavros_fc.launch.py

# ZED camera only
ros2 launch sky_vision2 zed.launch.py

# Test bridge without hardware (synthetic odom)
ros2 run sky_vision2 zed_mavros_bridge   # terminal 1
ros2 run sky_vision2 test_zed_odom       # terminal 2
```

## DDS domain — required in every terminal

All nodes run on `ROS_DOMAIN_ID=42`. Any terminal used to inspect or interact with the stack must export it first:

```bash
export ROS_DOMAIN_ID=42
ros2 topic list   # now sees sky_vision2 topics
```

## Running tests

The packages use the standard ROS2 linting suite (`flake8`, `pep257`, `copyright`):

```bash
cd ~/imav_2026_ws
colcon test --packages-select sky_vision2
colcon test-result --verbose
```

## Architecture

### Packages

| Package | Role |
|---------|------|
| `src/sky_vision2/` | **Production** — ZED→MAVROS bridge, all launch files, DDS/plugin config |
| `src/sky_navigation/` | **Production** — drone movement API (position + velocity setpoints via MAVROS) |
| `src/indoor_2026/` | Full competition stack — flight controller FSM (arm/takeoff/land) |
| `src/ardupilot/` | ArduPilot firmware source (submodule, not built via colcon) |
| `src/zed-ros2-wrapper/` | ZED SDK ROS2 driver (submodule) |

`sky_vision2` is the production bridge. **Never run two bridge instances simultaneously** — duplicate messages on the vision pose topic corrupt the EKF. Verify with `ros2 node list | grep zed_mavros_bridge`.

### Data flow

```
ZED2i → /zed/zed_node/odom (nav_msgs/Odometry, ~30 Hz, BEST_EFFORT)
      → sky_vision2/zed_mavros_bridge
          └─ /mavros/mavros/pose  → VISION_POSITION_ESTIMATE → ArduPilot EKF3

sky_vision2/ekf_home_watchdog → /mavros/mavros/set_home  (once EKF converges)

indoor_2026/flight_controller → set_mode + arming + takeoff → ArduPilot
sky_navigation/drone_motion   → setpoint_position/local or setpoint_velocity/cmd_vel → ArduPilot
```

See `src/sky_vision2/CLAUDE.md` for the full bridge frame-convention details.

### Key source files

- `src/sky_vision2/sky_vision2/zed_mavros_bridge.py` — production bridge node
- `src/sky_vision2/sky_vision2/test_zed_odom.py` — synthetic odom publisher for offline testing
- `src/sky_vision2/launch/` — four launch file variants (see below)
- `src/sky_vision2/config/fastdds_no_shm.xml` — disables DDS shared-memory transport
- `src/sky_vision2/config/apm_pluginlists_vision.yaml` — MAVROS plugin allowlist
- `src/sky_navigation/sky_navigation/drone_motion.py` — DroneMotion node (local pose, body pose, body velocity, yaw)
- `src/indoor_2026/indoor_2026/flight_controller.py` — FSM: arm → takeoff → land/RTL
- `media/imagens/indoor_2025/` — legacy mission scripts (communication2.py, mission.py, mission_1.py, etc.)

### Launch file quick-reference

| File | Starts | Notes |
|------|--------|-------|
| `zed_mavros_fc.launch.py` | ZED + MAVROS + bridge | Standard pre-flight command |
| `mavros_fc.launch.py` | MAVROS + bridge | Use when ZED already running; sets FastDDS no-SHM |
| `zed.launch.py` | ZED only | Camera test |
| `zed_mavros_sitl.launch.py` | Same as fc for now | Not yet adapted for SITL |

## Drone movement (sky_navigation)

`sky_navigation/drone_motion` handles all position and velocity setpoints after takeoff. It does not arm or take off — the `indoor_2026/flight_controller` FSM does that.

```bash
ros2 run sky_navigation drone_motion
```

Movement API (call from your mission node):

| Method | Setpoint type | Frame |
|--------|--------------|-------|
| `local_pose(x, y, z, yaw_deg)` | Position, one-shot | Local ENU (East-North-Up) |
| `body_pose(fwd, left, up, yaw_deg)` | Position, one-shot | Body FLU offset from current pose |
| `body_velocity(fwd, left, up, yaw_rate_deg)` | Velocity, 20 Hz loop | Body FLU |
| `set_yaw(yaw_deg)` | Position, one-shot | Holds position, rotates to heading |
| `stop()` | — | Cancels velocity setpoint |

See `src/sky_navigation/CLAUDE.md` and `src/sky_navigation/.claude/rules/drone_motion.md` for the full reference.

## FastDDS SHM note

Both `zed_mavros_fc.launch.py` and `mavros_fc.launch.py` set `FASTRTPS_DEFAULT_PROFILES_FILE` to disable shared-memory DDS transport. `zed_mavros_sitl.launch.py` does **not** — clear stale entries before restarting MAVROS under that file:

```bash
rm -f /dev/shm/fastrtps_*
```

## Required ArduPilot FCU parameters

These must be set on the Pixhawk before flying with visual odometry:

| Parameter | Value |
|-----------|-------|
| `EK3_SRC1_POSXY` | `6` (ExternalNav) |
| `EK3_SRC1_VELXY` | `6` (ExternalNav) |
| `EK3_SRC1_POSZ` | `1` (Baro) |
| `EK3_SRC1_VELZ` | `0` (None) |
| `EK3_SRC1_YAW` | `6` (ExternalNav) |
| `VISO_TYPE` | `1` |

## Startup verification sequence

```bash
export ROS_DOMAIN_ID=42
ros2 topic echo /mavros/state --once          # connected: True
ros2 topic hz /zed/zed_node/odom             # ~30 Hz (after ~15 s)
ros2 topic hz /mavros/vision_pose/pose       # ~30 Hz
ros2 topic hz /mavros/vision_speed/speed_twist  # ~30 Hz
# Bridge log: "HOME SET from vision EKF — ready to arm"
```

## Documentation

Extended docs for all nodes, launch files, config, and mission scripts are in `docs/`. Start with `docs/README.md`.
