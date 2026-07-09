# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

ROS2 Humble workspace for the **SkyRats IMAV 2026 indoor autonomous drone** competition. The drone uses a ZED2i stereo camera for visual odometry, gate traversal, and precision landing, with ArduPilot (Pixhawk 6C) as the flight controller via MAVROS.

Hardware: NVIDIA Jetson + ZED2i (USB-C) + Pixhawk 6C (Telem2 UART `/dev/ttyTHS1:921600`).

## Build and run

```bash
cd ~/sky_ws2
colcon build --packages-select sky_vision2 sky_navigation indoor_2026
source install/setup.bash

# Full hardware stack (ZED + MAVROS + bridge)
ros2 launch sky_vision2 zed_mavros_fc.launch.py

# MAVROS + bridge only (ZED already running)
ros2 launch sky_vision2 mavros_fc.launch.py

# ZED camera only
ros2 launch sky_vision2 zed.launch.py

# Test bridge without hardware (synthetic odom)
ros2 run sky_vision2 test_zed_odom

# Run a mission
ros2 run indoor_2026 square_test
```

## DDS domain — required in every terminal

```bash
export ROS_DOMAIN_ID=42
```

## Running tests

```bash
cd ~/sky_ws2
colcon test --packages-select sky_vision2 sky_navigation indoor_2026
colcon test-result --verbose
```

## Architecture

### Packages

| Package | Submodule | Role |
|---------|-----------|------|
| `src/sky_vision2/` | `SkyRats/sky_vision2` @ `imav_2026` | ZED→MAVROS bridge, launch files, DDS/plugin config |
| `src/sky_navigation/` | `SkyRats/sky_navigation` | `Drone` class — dronekit-style flight API for missions |
| `src/indoor_2026/` | `SkyRats/indoor_2026` | Competition missions (`square_test`, etc.) |

`sky_vision2` is the production bridge. **Never run two bridge instances simultaneously** — duplicate messages on `/mavros/vision_pose/pose` corrupt the EKF. Verify with `ros2 node list | grep zed_mavros_bridge`.

### Data flow

```
ZED2i → /zed/zed_node/odom (nav_msgs/Odometry, ~30 Hz, BEST_EFFORT)
      → sky_vision2/zed_mavros_bridge
          └─ /mavros/vision_pose/pose → VISION_POSITION_ESTIMATE → ArduPilot EKF3

indoor_2026/square_test → sky_navigation/Drone
    → /mavros/set_mode + /mavros/cmd/arming + /mavros/cmd/takeoff → ArduPilot
    → /mavros/setpoint_position/local or /mavros/setpoint_velocity/cmd_vel → ArduPilot
```

### Key source files

- `src/sky_vision2/sky_vision2/zed_mavros_bridge.py` — production bridge node
- `src/sky_vision2/sky_vision2/test_zed_odom.py` — synthetic odom publisher for offline testing
- `src/sky_vision2/launch/` — launch file variants (see below)
- `src/sky_vision2/config/fastdds_no_shm.xml` — disables DDS shared-memory transport
- `src/sky_vision2/config/apm_pluginlists_vision.yaml` — MAVROS plugin allowlist
- `src/sky_navigation/sky_navigation/drone.py` — `Drone` class (arm, takeoff, land, pose, velocity)
- `src/indoor_2026/indoor_2026/square_test.py` — reference mission using `Drone`

### Launch file quick-reference

| File | Starts | Notes |
|------|--------|-------|
| `zed_mavros_fc.launch.py` | ZED + MAVROS + bridge | Standard pre-flight command |
| `mavros_fc.launch.py` | MAVROS + bridge | Use when ZED already running; FastDDS SHM disabled |
| `zed.launch.py` | ZED only | Camera test |
| `indoor_2026/full_flight_test.py` | MAVROS + bridge + `square_test` | One-command SITL/flight test |

## Mission API (sky_navigation)

Missions import `Drone` from `sky_navigation` and call it top-to-bottom:

```python
from sky_navigation.drone import Drone
drone = Drone()
drone.wait_for_connection()
drone.set_mode('GUIDED')
drone.arm()
drone.takeoff()          # blocks until altitude reached
drone.local_pose(x, y, z)   # ENU position setpoint
drone.local_velocity(vx, vy, vz)  # ENU velocity, 20 Hz
drone.stop()
drone.land()             # blocks until disarmed
drone.shutdown()
```

| Method | Frame |
|--------|-------|
| `local_pose(x, y, z, yaw_deg=0)` | ENU (East-North-Up) |
| `body_pose(fwd, left, up, yaw_deg=0)` | FLU offset from current pose |
| `local_velocity(east, north, up, yaw_rate_deg=0)` | ENU, 20 Hz |
| `body_velocity(fwd, left, up, yaw_rate_deg=0)` | FLU body frame, 20 Hz |
| `set_yaw(yaw_deg)` | Holds position, rotates |
| `stop()` | Cancels velocity setpoint |

See `src/sky_navigation/CLAUDE.md` for the full reference.

## FastDDS SHM note

`zed_mavros_fc.launch.py` and `mavros_fc.launch.py` disable shared-memory DDS transport automatically. After any crash/restart, clear stale entries before relaunching:

```bash
rm -f /dev/shm/fastrtps_*
```

## Required ArduPilot FCU parameters

Set once via `bash src/indoor_2026/fc_scripts/set_ekf3_vision_params.sh` (requires MAVROS connected):

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `EK3_SRC1_POSXY` | `6` | ExternalNav horizontal position |
| `EK3_SRC1_VELXY` | `0` | None (ZED wrapper never populates twist) |
| `EK3_SRC1_POSZ` | `1` | Barometer |
| `EK3_SRC1_VELZ` | `0` | None |
| `EK3_SRC1_YAW` | `6` | ExternalNav yaw |
| `VISO_TYPE` | `1` | Enable visual odometry |

## Startup verification

```bash
export ROS_DOMAIN_ID=42
ros2 topic echo /mavros/state --once          # connected: True
ros2 topic hz /zed/zed_node/odom             # ~30 Hz (after ~15 s)
ros2 topic hz /mavros/vision_pose/pose       # ~30 Hz
ros2 topic hz /mavros/local_position/pose    # ~10 Hz (after EKF converges)
```
