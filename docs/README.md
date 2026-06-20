# indoor_2026 — Documentation Index

ROS2 workspace for the SkyRats IMAV 2026 indoor autonomous drone competition. The drone uses a ZED2i stereo camera for vision-based navigation through gates and precision landing.

## Workspace layout

```
imav_2026_ws/
├── src/
│   ├── indoor_2026/          # ROS2 package (launch files, package config)
│   ├── imagens/
│   │   ├── indoor_2025/      # All mission and vision scripts
│   │   └── mission_1.py      # Older standalone gate-traversal script
│   ├── ardupilot/            # ArduPilot firmware source
│   └── zed-ros2-wrapper/     # ZED SDK ROS2 driver
└── docs/                     # ← you are here
```

## Components

| Doc | What it covers | Source path |
|-----|---------------|-------------|
| [communication.md](communication.md) | `Mav` — MAVROS interface, arm/takeoff/goto/land | `src/imagens/indoor_2025/communication2.py` |
| [zed_subscriber.md](zed_subscriber.md) | `ZedSubscriber` — RGB + depth frame ingestion | `src/imagens/indoor_2025/mission_base.py` |
| [gate_detection.md](gate_detection.md) | `RectDetection` — green gate detection with depth | `src/imagens/indoor_2025/rect_detection.py` |
| [pid.md](pid.md) | `PID` — generic proportional-integral-derivative controller | `src/imagens/indoor_2025/mission_1.py` |
| [mission_orchestrator.md](mission_orchestrator.md) | `Mission` — top-level state machine | `src/imagens/indoor_2025/mission.py` |
| [mission_1.md](mission_1.md) | `Mission_1` — gate traversal (adjust → search → center → pass) | `src/imagens/indoor_2025/mission_1.py` |
| [mission_4.md](mission_4.md) | `Mission_4` — landing pad detection (partial) | `src/imagens/indoor_2025/mission_4.py` |
| [precision_landing.md](precision_landing.md) | Standalone color-blob precision landing script | `src/imagens/indoor_2025/imav_pid_mavros.py` |
| [pose_relay.md](pose_relay.md) | `pose_relay` — bridges ZED pose to MAVROS vision input with frame correction | `src/indoor_2026/indoor_2026/pose_relay.py` |
| [launch.md](launch.md) | `mavros_zed.launch.py` — starts MAVROS + ZED driver + pose relay | `src/indoor_2026/launch/mavros_zed.launch.py` |

## Quick start

```bash
# 1. Build the workspace
cd ~/imav_2026_ws
colcon build --packages-select indoor_2026
source install/setup.bash

# 2. Launch hardware drivers (MAVROS + ZED)
ros2 launch indoor_2026 mavros_zed.launch.py

# 3. In another terminal, run the main mission
cd src/imagens/indoor_2025
python3 mission.py
```

## Data flow

```
ZED2i camera
    │
    ├─────────────────────────────────────────────────────┐
    ▼                                                     ▼
ZedSubscriber (mission_base.py)               pose_relay (pose_relay.py)
    ├─ /mavros/zed/left/image_rect_color          │
    │     →  frame (BGR)                          │  /mavros/zed/pose
    └─ /mavros/zed/depth/depth_registered         │  (X,Y negated + quaternion rotated)
          →  depth_frame (float32)                │
    │                                             ▼
    ▼                                   /mavros/vision_pose/pose
RectDetection (rect_detection.py)                 │
    └─ detects green gate posts,                  ▼
       returns (gate_found, error_x, error_y)   MAVROS → ArduPilot EKF (position estimate)
    │
    ▼
Mission_1 / Mission_4
    └─ uses PID + Mav to send velocity setpoints
    │
    ▼
Mav (communication2.py)
    ├─ /mavros/setpoint_velocity/cmd_vel_unstamped
    ├─ /mavros/setpoint_raw/local
    └─ /mavros/setpoint_position/local
    │
    ▼
MAVROS → ArduPilot flight controller
```

## Dependencies

- ROS2 Humble
- `mavros` + `mavros_msgs`
- `zed_wrapper` (ZED ROS2 wrapper v5)
- `cv_bridge`, `sensor_msgs`, `geometry_msgs`
- Python: `opencv-python`, `numpy`
