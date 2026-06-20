# Launch File — mavros_zed.launch.py

**Source:** `src/indoor_2026/launch/mavros_zed.launch.py`  
**Package:** `indoor_2026` (`src/indoor_2026/`)

Starts the hardware drivers and pose bridge needed before running any mission: MAVROS (flight controller link), the ZED camera wrapper, and the pose relay node.

## Usage

```bash
# After building and sourcing:
ros2 launch indoor_2026 mavros_zed.launch.py
```

## What it launches

### 1. MAVROS — `apm.launch`

Includes `mavros/launch/apm.launch` (the ArduPilot-specific MAVROS launch). This sets up all MAVLink-to-ROS2 bridges:

- `/mavros/local_position/pose` — EKF-fused local position
- `/mavros/vision_pose/pose` — external vision pose input (for ZED odometry)
- `/mavros/setpoint_position/local` — position setpoint subscriber
- `/mavros/setpoint_raw/local` — raw setpoint subscriber
- `/mavros/setpoint_velocity/cmd_vel_unstamped` — velocity setpoint subscriber
- `/mavros/set_mode`, `/mavros/cmd/arming`, `/mavros/cmd/takeoff` — services

The `apm.launch` file itself is in the installed `mavros` package. Connection is configured to `/dev/ttyTHS1:921600` (Jetson UART Telem2 at 921600 baud).

### 2. ZED Wrapper — `zed_camera.launch.py`

Includes `zed_wrapper/launch/zed_camera.launch.py` with:

```python
launch_arguments={'camera_model': 'zed2i'}
```

Publishes:
- `/zed/zed_node/left/image_rect_color` — rectified RGB (consumed by [ZedSubscriber](zed_subscriber.md))
- `/zed/zed_node/depth/depth_registered` — registered depth map
- `/zed/zed_node/odom` / `/zed/zed_node/pose` — visual odometry

> **Note:** The comment in the file says to switch `camera_model` to `zedm` for the ZED Mini. Current hardware is ZED2i.

### 3. Pose relay — `pose_relay`

Runs the `indoor_2026/pose_relay.py` node, which bridges ZED pose to MAVROS external vision:

```
/mavros/zed/pose  →  [pose_relay]  →  /mavros/vision_pose/pose
```

Without this node, MAVROS has no publisher on `/mavros/vision_pose/pose` and ArduPilot receives no external position estimate. See [pose_relay.md](pose_relay.md) for details on the coordinate frame correction applied.

## Build

```bash
cd ~/imav_2026_ws
colcon build --packages-select indoor_2026
source install/setup.bash
```

The launch file is installed via `setup.py`:

```python
(os.path.join('share', 'indoor_2026', 'launch'), glob('launch/*.launch.py'))
```

## See also

- [pose_relay.md](pose_relay.md) — the vision pose bridge node
- [ZedSubscriber](zed_subscriber.md) — consumes ZED topics
- [Mav](communication.md) — consumes MAVROS topics
- [README](README.md) — full startup sequence
