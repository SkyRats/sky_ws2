# sky_vision2 Launch Files

**Package:** `sky_vision2` (`src/sky_vision2/`)  
**Launch directory:** `src/sky_vision2/launch/`

Four launch files cover the different hardware and simulation configurations needed during development. They share common building blocks (ZED camera, MAVROS, bridge node) combined in different ways.

## Quick-reference — which launch file to use

| Scenario | Launch file | Notes |
|---|---|---|
| ZED already running; start MAVROS + bridge only | `mavros_fc.launch.py` | Most common during iterative bridge development |
| Start ZED camera only (no MAVROS) | `zed.launch.py` | Useful when testing vision without flight control |
| Full hardware flight: ZED + MAVROS + bridge | `zed_mavros_fc.launch.py` | Standard pre-flight startup |
| SITL development | `zed_mavros_sitl.launch.py` | Currently a placeholder — not yet adapted for SITL |

## Build and source first

All launch files depend on installed package share paths. They will fail with a `FindPackageShare` error if run against an unbuilt workspace:

```bash
cd ~/imav_2026_ws
colcon build --packages-select sky_vision2
source install/setup.bash
```

## mavros_fc.launch.py

**Purpose:** MAVROS node + ZedMavrosBridge. Does **not** start the ZED camera driver. Use when ZED is already running in a separate terminal or process.

```bash
ros2 launch sky_vision2 mavros_fc.launch.py
# Optional overrides:
ros2 launch sky_vision2 mavros_fc.launch.py fcu_url:=/dev/ttyUSB0:57600
ros2 launch sky_vision2 mavros_fc.launch.py zed_odom_topic:=/zed/zed_node/odom
```

### Launch arguments

| Argument | Default | Description |
|---|---|---|
| `fcu_url` | `/dev/ttyTHS1:921600` | MAVLink connection string (see format table below) |
| `zed_odom_topic` | `/zed/zed_node/odom` | Forwarded to the bridge node as a ROS2 parameter |

### Environment variables set

| Variable | Value | Why |
|---|---|---|
| `ROS_DOMAIN_ID` | `42` | Isolates DDS from other ROS2 nodes (see below) |
| `FASTRTPS_DEFAULT_PROFILES_FILE` | Path to `fastdds_no_shm.xml` | Disables shared-memory transport (see [config](sky_vision2_config.md)) |

### What it starts

1. **MAVROS** — loaded via `mavros/launch/apm.launch` with:
   - `fcu_url` wired to the launch argument
   - `pluginlists_yaml` pointing to `apm_pluginlists_vision.yaml` (allowlist, not the default full list)

2. **ZedMavrosBridge** — the bridge node with `zed_odom_topic` forwarded as a parameter.

### pluginlists_yaml path resolution

The plugin allowlist path is resolved at launch time using `FindPackageShare('sky_vision2')`. This returns the **installed** share directory (`install/sky_vision2/share/sky_vision2/config/`), not the source directory. The file must exist there, which only happens after `colcon build`. Running without building first yields a cryptic `KeyError` from the launch system, not an obvious file-not-found error.

## zed.launch.py

**Purpose:** ZED camera driver only. No MAVROS, no bridge.

```bash
ros2 launch sky_vision2 zed.launch.py
# Override camera model:
ros2 launch sky_vision2 zed.launch.py camera_model:=zedm
```

### Launch arguments

| Argument | Default | Description |
|---|---|---|
| `camera_model` | `zed2i` | Passed to `zed_wrapper/launch/zed_camera.launch.py` |

### Environment variables set

| Variable | Value |
|---|---|
| `ROS_DOMAIN_ID` | `42` |

### What it starts

Includes `zed_wrapper/launch/zed_camera.launch.py` with the camera model argument forwarded. This starts the full ZED SDK ROS2 wrapper, which publishes:

| Topic | Description |
|---|---|
| `/zed/zed_node/odom` | Visual odometry (input to ZedMavrosBridge) |
| `/zed/zed_node/pose` | Absolute pose in the map frame |
| `/zed/zed_node/left/image_rect_color` | Rectified RGB (consumed by vision missions) |
| `/zed/zed_node/depth/depth_registered` | Registered depth map |

### When to use this separately

- Testing gate detection or any vision algorithm without MAVROS overhead.
- Verifying the camera is physically working before connecting the flight controller.
- Running `test_zed_odom` alongside (the test tool replaces this node during pure bridge testing).

## zed_mavros_fc.launch.py

**Purpose:** Full real-hardware stack. Starts ZED camera, MAVROS, and the bridge together.

```bash
ros2 launch sky_vision2 zed_mavros_fc.launch.py
```

### Launch arguments

| Argument | Default | Description |
|---|---|---|
| `fcu_url` | `/dev/ttyTHS1:921600` | MAVLink serial connection |
| `camera_model` | `zed2i` | ZED camera model |
| `zed_odom_topic` | `/zed/zed_node/odom` | ZED odometry topic (bridge parameter) |

### Environment variables set

| Variable | Value |
|---|---|
| `ROS_DOMAIN_ID` | `42` |

**Notable:** `FASTRTPS_DEFAULT_PROFILES_FILE` is **not** set here. This is an inconsistency with `mavros_fc.launch.py` — see the Gotcha section below.

### What it starts

1. Includes `zed.launch.py` (ZED camera driver)
2. Includes `mavros/launch/apm.launch` (MAVROS with plugin allowlist)
3. Starts `zed_mavros_bridge` node

### Startup order

The ZED driver takes several seconds to initialize (SDK firmware load, camera self-test). The bridge will attempt to subscribe to the odom topic immediately but will simply receive no messages until the ZED driver is ready. This is handled gracefully — the bridge does not require messages to exist at startup. MAVROS similarly waits for the FCU heartbeat before declaring itself connected.

## zed_mavros_sitl.launch.py

**Purpose:** Intended for SITL (Software In The Loop) testing with ArduPilot in simulation. **Currently a placeholder** — the file is identical to `zed_mavros_fc.launch.py` and has not yet been adapted for SITL.

```bash
# Current behavior: identical to zed_mavros_fc.launch.py
ros2 launch sky_vision2 zed_mavros_sitl.launch.py
```

### What SITL adaptation should include

When this file is properly adapted, it should differ from `zed_mavros_fc.launch.py` in these ways:

| Setting | Real hardware | SITL |
|---|---|---|
| `fcu_url` | `/dev/ttyTHS1:921600` | `tcp://127.0.0.1:5760` or `udp://127.0.0.1:14550` |
| ZED camera | Real ZED2i | Replace with `test_zed_odom` publisher or a bag file |
| `camera_model` arg | Required | Not applicable |

Until that adaptation is done, use `zed_mavros_fc.launch.py` for real hardware and override `fcu_url` manually when testing with SITL.

## fcu_url format reference

| Connection type | Format | Example |
|---|---|---|
| Serial UART | `device:baudrate` | `/dev/ttyTHS1:921600` |
| TCP (SITL default) | `tcp://host:port` | `tcp://127.0.0.1:5760` |
| UDP MAVLink | `udp://host:port` | `udp://127.0.0.1:14550` |
| USB serial | `device:baudrate` | `/dev/ttyUSB0:57600` |

The Jetson uses `/dev/ttyTHS1` which is the hardware UART on the 40-pin header, connected to the Pixhawk 6C Telem2 port. 921600 baud is the maximum reliable rate for that link; using a lower baud rate causes MAVROS to lag behind the FCU message rate and drop messages.

## Why ROS_DOMAIN_ID=42

ROS2 uses DDS for inter-process communication. By default, all ROS2 processes on the same network share DDS domain 0. This causes a subtle but serious problem during integration:

If another ROS2 environment on the same machine or LAN has a different build of `mavros_msgs` (different message version, different field order, or different IDL hash), DDS will detect a type mismatch when both participants try to publish on the same topic name. The middleware may silently refuse to match publisher and subscriber, or in some cases crash.

Setting `ROS_DOMAIN_ID=42` creates a private DDS domain that only processes explicitly started with `ROS_DOMAIN_ID=42` can see. This means:

- The sky_vision2 stack is invisible to any other ROS2 processes on the network.
- No accidental cross-domain message pollution.
- No type-hash conflicts with older or unrelated ROS2 installations.

The value 42 is arbitrary; what matters is that all nodes in the stack use the same value.

**Consequence:** When connecting external tools (e.g., `rqt`, `ros2 topic list`, `rviz2`), you must also set `ROS_DOMAIN_ID=42` in that terminal or they will see an empty graph.

```bash
export ROS_DOMAIN_ID=42
ros2 topic list
```

## Gotcha — FastDDS no-SHM inconsistency

`mavros_fc.launch.py` sets `FASTRTPS_DEFAULT_PROFILES_FILE` to disable shared-memory transport. `zed_mavros_fc.launch.py` does **not** set it.

This inconsistency means:

- When using `mavros_fc.launch.py` (MAVROS only, ZED launched separately): shared-memory transport is disabled; MAVROS restart problems are avoided.
- When using `zed_mavros_fc.launch.py` (full stack): shared-memory transport is active (default DDS behavior); if MAVROS is killed and restarted without clearing `/dev/shm`, stale type signature entries can cause DDS to reject new connections.

**Workaround for the full stack:** Either set the env variable manually before launching, or clear `/dev/shm` after killing MAVROS:

```bash
rm -f /dev/shm/fastrtps_*
ros2 launch sky_vision2 zed_mavros_fc.launch.py
```

See [sky_vision2 config](sky_vision2_config.md) for a full explanation of why shared-memory transport causes these problems.

## See also

- [ZedMavrosBridge](zed_mavros_bridge.md) — the bridge node these launch files start
- [sky_vision2 config](sky_vision2_config.md) — FastDDS profile and plugin allowlist referenced by the launch files
- [test_zed_odom](test_zed_odom.md) — testing the bridge pipeline without real ZED hardware
- [launch](launch.md) — the older `indoor_2026` launch file for comparison
- [pose_relay](pose_relay.md) — the bridge node used in the older stack
