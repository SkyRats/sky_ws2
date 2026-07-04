# imav_2026_ws — Documentation Index

ROS2 workspace for the SkyRats IMAV 2026 indoor autonomous drone competition. The drone uses a ZED2i stereo camera for visual odometry, gate traversal, and precision landing with ArduPilot via MAVROS.

## Workspace layout

```
imav_2026_ws/
├── src/
│   ├── indoor_2026/          # ROS2 package: pose relay node + master launch file
│   ├── sky_vision2/          # ROS2 package: ZED-MAVROS bridge, launch files, DDS/plugin config
│   │   ├── sky_vision2/
│   │   │   ├── zed_mavros_bridge.py   # Production vision bridge node
│   │   │   └── test_zed_odom.py       # Synthetic odom publisher for offline testing
│   │   ├── launch/                    # Four launch file variants
│   │   └── config/                    # FastDDS profile + MAVROS plugin allowlist
│   ├── ardupilot/            # ArduPilot firmware source (submodule)
│   └── zed-ros2-wrapper/     # ZED SDK ROS2 driver (submodule)
├── media/imagens/            # Captured test images and legacy indoor_2025 scripts
└── docs/                     # ← you are here
```

## Components

### sky_vision2 — production vision stack

| Doc | What it covers | Source path |
|-----|---------------|-------------|
| [zed_mavros_bridge.md](zed_mavros_bridge.md) | `ZedMavrosBridge` — ZED odom → MAVROS pose+velocity, EKF health watchdog, auto set_home | `src/sky_vision2/sky_vision2/zed_mavros_bridge.py` |
| [test_zed_odom.md](test_zed_odom.md) | `ZedOdomPublisher` + `BridgeVerifier` — offline bridge testing with synthetic odometry | `src/sky_vision2/sky_vision2/test_zed_odom.py` |
| [sky_vision2_launch.md](sky_vision2_launch.md) | Four launch file variants: ZED only, MAVROS+bridge only, full stack FC, full stack SITL | `src/sky_vision2/launch/` |
| [sky_vision2_config.md](sky_vision2_config.md) | `fastdds_no_shm.xml` — DDS SHM fix; `apm_pluginlists_vision.yaml` — MAVROS plugin allowlist | `src/sky_vision2/config/` |
| [mavros_patched.md](mavros_patched.md) | Optional overlay build of MAVROS (`odraudE31/mavros`, `fix/vision-pose-yaw-clamping`) fixing the `vision_pose_estimate` Eigen yaw-clamping bug | `~/sky_ws2/src/mavros_patched` (symlink, not tracked in this repo) |

### indoor_2026 — mission package and legacy bridge

| Doc | What it covers | Source path |
|-----|---------------|-------------|
| [pose_relay.md](pose_relay.md) | `pose_relay` — earlier ZED pose → MAVROS bridge (position only, no velocity, no auto-home) | `src/indoor_2026/indoor_2026/pose_relay.py` |
| [launch.md](launch.md) | `mavros_zed.launch.py` — starts MAVROS + ZED + pose relay (indoor_2026 stack) | `src/indoor_2026/launch/mavros_zed.launch.py` |

### Mission and vision scripts (media/imagens/indoor_2025/)

| Doc | What it covers | Source path |
|-----|---------------|-------------|
| [communication.md](communication.md) | `Mav` — MAVROS interface: arm/takeoff/goto/land/velocity | `media/imagens/indoor_2025/communication2.py` |
| [zed_subscriber.md](zed_subscriber.md) | `ZedSubscriber` — RGB + depth frame ingestion from ZED topics | `media/imagens/indoor_2025/mission_base.py` |
| [gate_detection.md](gate_detection.md) | `RectDetection` — green gate detection with depth isolation | `media/imagens/indoor_2025/rect_detection.py` |
| [pid.md](pid.md) | `PID` — proportional-integral-derivative controller (pixel error → velocity) | `media/imagens/indoor_2025/mission_1.py` |
| [mission_orchestrator.md](mission_orchestrator.md) | `Mission` — top-level state machine (takeoff → missions → land) | `media/imagens/indoor_2025/mission.py` |
| [mission_1.md](mission_1.md) | `Mission_1` — gate traversal: adjust → search → center → pass | `media/imagens/indoor_2025/mission_1.py` |
| [mission_4.md](mission_4.md) | `Mission_4` — landing pad detection (partial, H-circle shape) | `media/imagens/indoor_2025/mission_4.py` |
| [precision_landing.md](precision_landing.md) | Standalone color-blob precision landing script | `media/imagens/indoor_2025/imav_pid_mavros.py` |

## Quick start

### Production stack (sky_vision2)

```bash
# 1. Build
cd ~/imav_2026_ws
colcon build --packages-select sky_vision2
source install/setup.bash

# 2. Full hardware stack: ZED camera + MAVROS + vision bridge
ros2 launch sky_vision2 zed_mavros_fc.launch.py

# 3. Verify data is flowing
ros2 topic hz /mavros/vision_pose/pose
ros2 topic echo /mavros/state
```

> See [sky_vision2_launch.md](sky_vision2_launch.md) for all launch options (ZED only, MAVROS only, SITL).

### Mission scripts (legacy indoor_2025)

```bash
# Requires sky_vision2 or indoor_2026 stack already running

cd ~/imav_2026_ws/media/imagens/indoor_2025
python3 mission.py
```

### Testing the bridge without hardware

```bash
# Terminal 1 — bridge node alone
ros2 run sky_vision2 zed_mavros_bridge

# Terminal 2 — synthetic odometry publisher + verifier
ros2 run sky_vision2 test_zed_odom
```

> See [test_zed_odom.md](test_zed_odom.md) for expected output and how to verify X-negation.

## Data flow

```
ZED2i camera
    │
    │  /zed/zed_node/odom (Odometry, ~30 Hz, BEST_EFFORT QoS)
    ▼
ZedMavrosBridge (sky_vision2)
    ├─ negates position.y and twist.linear.y (ZED Y=West → NED Y=East)
    ├─ negates quaternion qy and qz (pitch/yaw sign flip)
    ├─ publishes /mavros/vision_pose/pose    (PoseStamped)
    ├─ publishes /mavros/vision_speed/speed_twist (TwistStamped)
    │
    │  also subscribes to /mavros/estimator_status
    │  → waits 5 s of EKF pos_horiz_rel=True
    │  → calls /mavros/cmd/set_home once
    │
    ▼
MAVROS
    ├─ VISION_POSITION_ESTIMATE → ArduPilot EKF3 (XY position source)
    └─ VISION_SPEED_ESTIMATE    → ArduPilot EKF3 (XY velocity source)
    │
    ▼
ArduPilot EKF3 (EK3_SRC1_POSXY=6, EK3_SRC1_VELXY=6)
    └─ fused local position estimate
    │
    ▼
/mavros/local_position/pose
    │
    ▼
Mav (communication2.py) ──── Mission_1 / Mission_4
    │                              │
    │  /mavros/setpoint_*/...      │  ZedSubscriber → RectDetection / Detection
    ▼                              │  (gate + pad detection via ZED RGB+depth)
ArduPilot flight controller ───────┘
```

### Vision bridge path: sky_vision2 vs indoor_2026

Two bridge implementations exist. Only one should be running at a time:

| Stack | Bridge node | Input | Frame correction (→ NED) | Velocity to EKF | Auto home |
|-------|-------------|-------|--------------------------|-----------------|-----------|
| `sky_vision2` | `ZedMavrosBridge` | `/zed/zed_node/odom` (Odometry) | negate Y, negate qy/qz | Yes | Yes |
| `indoor_2026` | `pose_relay` | `/mavros/zed/pose` (PoseStamped) | negate X and Y, rotate quat 180° Z (needs review) | No | No |

`sky_vision2` is the current production stack. `indoor_2026/pose_relay` is kept for reference.

## Required ArduPilot parameters

These must be set on the FCU before flying with visual odometry:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `EK3_SRC1_POSXY` | `6` | Horizontal position: ExternalNav (vision) |
| `EK3_SRC1_VELXY` | `6` | Horizontal velocity: ExternalNav (vision) |
| `EK3_SRC1_POSZ`  | `1` | Vertical position: Barometer |
| `EK3_SRC1_VELZ`  | `0` | Vertical velocity: None |
| `EK3_SRC1_YAW`   | `6` | Yaw: ExternalNav (vision) |
| `VISO_TYPE`      | `1` | Enable visual odometry processing |

## Dependencies

- ROS2 Humble
- `mavros` + `mavros_msgs` — apt by default; optionally overridden by a patched `mavros` overlay build, see [mavros_patched.md](mavros_patched.md)
- `zed_wrapper` (ZED ROS2 wrapper v5, `src/zed-ros2-wrapper/`)
- `nav_msgs`, `geometry_msgs`, `sensor_msgs`
- Python: `opencv-python`, `numpy`
- FastDDS (eProsima) — configured via `src/sky_vision2/config/fastdds_no_shm.xml`
