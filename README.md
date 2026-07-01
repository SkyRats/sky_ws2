# sky_ws2 — SkyRats IMAV 2026 Drone Workspace

This is the ROS2 workspace for the SkyRats IMAV 2026 indoor autonomous drone. Everything lives here — hardware flights, simulation, and testing.

## What the drone does

The drone flies indoors without GPS. It uses the **ZED2i stereo camera** to know where it is (visual odometry), feeds that position data to the **Pixhawk flight controller** (ArduPilot), and then autonomously navigates through the course.

```
ZED2i camera
    → visual odometry (position + velocity)
        → ZED-MAVROS bridge (ROS2 node)
            → MAVROS
                → Pixhawk (ArduPilot EKF3)
                    → stabilized, position-aware flight
```

## Hardware

| Component | Detail |
|-----------|--------|
| Computer | NVIDIA Jetson (runs all ROS2 nodes) |
| Camera | ZED2i stereo (USB-C) |
| Flight controller | Pixhawk 6C running ArduPilot |
| Connection | Jetson ↔ Pixhawk via UART `/dev/ttyTHS1` at 921600 baud |

## Packages

| Package | What it does |
|---------|-------------|
| `src/sky_vision2/` | Reads ZED odometry, converts it to the right format, sends it to ArduPilot. Also has launch files for the hardware stack. |
| `src/indoor_2026/` | Full autonomous flight: bridge + arming + takeoff + motion control. This is the competition stack. |
| `src/sky_sim2/` | Gazebo simulation worlds (placeholder, minimal content). |
| `src/zed-ros2-wrapper-humble-v5.0.0/` | ZED camera ROS2 driver (third-party). |
| `src/ardupilot/` | ArduPilot firmware source (not built via colcon). |

## First-time setup

### Clone

```bash
git clone --recursive git@github.com:SkyRats/sky_ws2.git ~/sky_ws2
```

### Install dependencies

```bash
sudo apt install ros-humble-mavros ros-humble-mavros-extras
wget https://raw.githubusercontent.com/mavlink/mavros/ros2/mavros/scripts/install_geographiclib_datasets.sh
chmod +x install_geographiclib_datasets.sh && ./install_geographiclib_datasets.sh
rm install_geographiclib_datasets.sh
```

### Build

```bash
cd ~/sky_ws2
colcon build --packages-select sky_vision2 indoor_2026
source install/setup.bash
```

> Never run bare `colcon build` — it rebuilds the ZED driver and ArduPilot from scratch (10+ minutes).

### `.bashrc` additions

```bash
source /opt/ros/humble/setup.bash
source ~/sky_ws2/install/setup.bash
export ROS_DOMAIN_ID=42
```

## Running the drone (hardware)

Every terminal must have `export ROS_DOMAIN_ID=42` — or source your `.bashrc`.

### Option A — Full stack in one command (ZED + MAVROS + bridge)

```bash
ros2 launch sky_vision2 zed_mavros_fc.launch.py
```

Wait for the log line: `HOME SET from vision EKF — ready to arm`  
Then the drone is ready to arm and fly.

### Option B — Full autonomous flight (arm + takeoff + motion)

```bash
ros2 launch indoor_2026 full_flight_test.py
```

This starts everything including automatic arming and takeoff. See `src/indoor_2026/` for details.

## Testing without hardware (SITL)

**Terminal 1** — Start the ArduPilot software simulator:
```bash
cd ~/ardupilot/ArduCopter
sim_vehicle.py --console --map -w
```

**Terminal 2** — Start MAVROS pointed at the simulator:
```bash
export ROS_DOMAIN_ID=42
source ~/sky_ws2/install/setup.bash
ros2 launch sky_vision2 mavros_fc.launch.py fcu_url:=tcp://127.0.0.1:5760
```

**Terminal 3** — Feed fake ZED odometry:
```bash
export ROS_DOMAIN_ID=42
ros2 run sky_vision2 test_zed_odom
```

## Kill everything

```bash
pkill -9 -f "mavros|zed|ros2 launch|sim_vehicle"
rm -f /dev/shm/fastrtps_*
```

## Required Pixhawk parameters

Set these once on the Pixhawk before any flight that uses the ZED camera:

| Parameter | Value | Why |
|-----------|-------|-----|
| `EK3_SRC1_POSXY` | 6 | Use visual odometry for horizontal position |
| `EK3_SRC1_VELXY` | 0 | None — bridge doesn't publish vision_speed (ZED wrapper never populates twist) |
| `EK3_SRC1_POSZ` | 1 | Use barometer for altitude |
| `EK3_SRC1_VELZ` | 0 | No vertical velocity source |
| `EK3_SRC1_YAW` | 6 | Use visual odometry for heading |
| `VISO_TYPE` | 1 | Enable visual odometry input |

To set them automatically (with MAVROS running):
```bash
bash ~/sky_ws2/src/indoor_2026/fc_scripts/set_ekf3_vision_params.sh
```

## Verify everything is working

```bash
export ROS_DOMAIN_ID=42
ros2 topic echo /mavros/state --once           # look for: connected: True
ros2 topic hz /zed/zed_node/odom              # should be ~30 Hz
ros2 topic hz /mavros/mavros/pose             # should be ~30 Hz (no vision_speed — bridge doesn't publish it)
```

## Submodule workflow

`sky_vision2`, `indoor_2026`, and `sky_sim2` are git submodules. To update after pulling:

```bash
git submodule update --init --recursive
```

To make changes to a package:
```bash
cd src/sky_vision2
git checkout imav_2026
# ... make changes, commit, push ...
cd ../..
git add src/sky_vision2
git commit -m "bump sky_vision2"
```
