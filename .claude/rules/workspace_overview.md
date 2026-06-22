# sky_ws2 — Only Workspace

## Role

`sky_ws2` is the **only ROS2 workspace** for the SkyRats IMAV 2026 project. It covers both hardware flights and SITL/Gazebo development. There is no separate production workspace.

## Package map

| Package | Git status | Role |
|---------|-----------|------|
| `src/sky_vision2/` | Submodule — `github.com/SkyRats/sky_vision2` `imav_2026` branch | ZED→MAVROS bridge + launch files |
| `src/indoor_2026/` | Submodule — `github.com/SkyRats/indoor_2026` | Full autonomous indoor stack: bridge + flight controller + motion |
| `src/sky_sim2/` | Submodule — `github.com/SkyRats/sky_sim2` | Gazebo simulation (placeholder) |
| `src/ardupilot/` | Submodule | ArduPilot firmware — not built via colcon |
| `src/zed-ros2-wrapper-humble-v5.0.0/` | Submodule | ZED SDK ROS2 driver |

## Build

```bash
cd ~/sky_ws2

# Build only the custom packages (fast, daily use)
colcon build --packages-select sky_vision2 indoor_2026
source install/setup.bash

# Full build including ArduPilot DDS (first-time or after submodule update)
colcon build --packages-up-to ardupilot_sitl
source install/setup.bash
```

Never run bare `colcon build` — it rebuilds the ZED wrapper and ArduPilot from source (takes 10+ minutes).

## Run tests

```bash
colcon test --packages-select sky_vision2 indoor_2026
colcon test-result --verbose
```

## Domain ID

```bash
export ROS_DOMAIN_ID=42
```

Required in every terminal before any `ros2` command.

## Submodule workflow

```bash
# Update submodules after a git pull
git submodule update --init --recursive

# Work inside a submodule (e.g. sky_vision2)
cd src/sky_vision2
git checkout imav_2026
# ... make changes, commit, push ...
cd ../..
git add src/sky_vision2
git commit -m "chore: bump sky_vision2 submodule"
```
