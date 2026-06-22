# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this workspace is

`sky_ws2` is the **only ROS2 workspace** for the SkyRats IMAV 2026 drone project. It is used for both hardware flights and SITL/Gazebo development.

## Packages

| Package | Role |
|---------|------|
| `src/sky_vision2/` | ZED→MAVROS vision bridge + launch files — production hardware stack |
| `src/indoor_2026/` | Full indoor flight stack: MAVROS + ZED + bridge + flight controller + motion |
| `src/sky_sim2/` | Gazebo simulation models and worlds (placeholder, minimal content currently) |
| `src/ardupilot/` | ArduPilot firmware submodule |
| `src/zed-ros2-wrapper-humble-v5.0.0/` | ZED SDK ROS2 driver |

All three ROS2 packages (`sky_vision2`, `indoor_2026`, `sky_sim2`) are git submodules.

## Build

```bash
cd ~/sky_ws2
colcon build --packages-select sky_vision2 indoor_2026
source install/setup.bash

# Full build including ArduPilot DDS (first-time or after submodule updates):
colcon build --packages-up-to ardupilot_sitl
```

## Run tests

```bash
colcon test --packages-select sky_vision2 indoor_2026
colcon test-result --verbose
```

## Launch

```bash
source install/setup.bash
export ROS_DOMAIN_ID=42

# Full hardware stack (ZED + MAVROS + bridge) — production
ros2 launch sky_vision2 zed_mavros_fc.launch.py

# MAVROS + bridge only (ZED already running separately)
ros2 launch sky_vision2 mavros_fc.launch.py

# Full autonomous indoor stack (bridge + flight controller + motion)
ros2 launch indoor_2026 full_flight_test.py

# SITL — synthetic odom, no hardware
ros2 run sky_vision2 test_zed_odom                                          # terminal 1
ros2 launch sky_vision2 mavros_fc.launch.py fcu_url:=tcp://127.0.0.1:5760  # terminal 2
```

## Known issues

### `zed_mavros_sitl.launch.py` missing FastDDS no-SHM

`src/sky_vision2/launch/zed_mavros_sitl.launch.py` does not set `FASTRTPS_DEFAULT_PROFILES_FILE`. Export it manually before launching:
```bash
export ROS_DOMAIN_ID=42
export FASTRTPS_DEFAULT_PROFILES_FILE=$(ros2 pkg prefix sky_vision2)/share/sky_vision2/config/fastdds_no_shm.xml
ros2 launch sky_vision2 zed_mavros_sitl.launch.py fcu_url:=tcp://127.0.0.1:5760
```

Or use the practical SITL workaround (no ZED hardware needed):
```bash
# Terminal 1 — synthetic ZED odom:
ros2 run sky_vision2 test_zed_odom

# Terminal 2 — MAVROS + bridge against SITL FCU:
ros2 launch sky_vision2 mavros_fc.launch.py fcu_url:=tcp://127.0.0.1:5760
```

## SITL workflow (ArduPilot + MAVProxy)

```bash
# Terminal 1 — ArduCopter SITL (standalone, no ROS)
cd ~/ardupilot/ArduCopter
sim_vehicle.py --console --map -w

# Verify with MAVProxy
mavproxy.py --console --map --aircraft test --master=:14550
```

## Gazebo + SITL

```bash
cd ~/sky_ws2
source install/setup.bash
ros2 launch ardupilot_gz_bringup iris_runway.launch.py
```

Requires Gazebo Harmonic. Set `export GZ_VERSION=harmonic` in `.bashrc`.
