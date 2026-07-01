# sky_vision2 Launch Files

**Package:** `sky_vision2` (`src/sky_vision2/`)  
**Launch directory:** `src/sky_vision2/launch/`  
**Installed to:** `install/sky_vision2/share/sky_vision2/launch/`

Four launch files cover the hardware and simulation configurations. They share common building blocks (ZED camera, MAVROS, bridge node) combined in different ways. Every launch file is a Python `LaunchDescription` that the ROS2 launch system interprets — understanding how that system works is prerequisite to understanding why each file is structured the way it is.

## Build and source — always required first

All launch files reference installed paths. `FindPackageShare('sky_vision2')` resolves to `install/sky_vision2/share/sky_vision2/`, which only exists after a build. Without building first, the launch system raises a `KeyError` on the path substitution, not a readable file-not-found message.

```bash
cd ~/sky_ws2
colcon build --packages-select sky_vision2
source install/setup.bash
```

The `source install/setup.bash` step registers the `sky_vision2` package in the current shell's `AMENT_PREFIX_PATH`, which is what `FindPackageShare` searches.

---

## Quick-reference — which file to use

| Scenario | Launch file | Starts |
|---|---|---|
| ZED already running; add MAVROS + bridge | `mavros_fc.launch.py` | MAVROS + bridge |
| Camera test, no flight control | `zed.launch.py` | ZED only |
| Full real-hardware flight | `zed_mavros_fc.launch.py` | ZED + MAVROS + bridge |
| SITL (not yet adapted) | `zed_mavros_sitl.launch.py` | Same as fc for now |

---

## How ROS2 launch actions work

Every launch file uses a combination of three action types. Understanding them is necessary to read the files:

| Action | Class | Effect |
|---|---|---|
| `SetEnvironmentVariable` | Env action | Sets an environment variable for **all child nodes** launched after this action in the same `LaunchDescription`. Does not affect the shell that called `ros2 launch`. |
| `DeclareLaunchArgument` | Configuration | Declares a named argument that can be overridden on the command line (`key:=value`). Does nothing by itself — the argument value is consumed by `LaunchConfiguration`. |
| `Node` | Process action | Spawns a new process running a specific ROS2 executable. Receives parameters, arguments, and inherits the environment set by preceding `SetEnvironmentVariable` actions. |
| `IncludeLaunchDescription` | Composition | Inlines another launch file. The included file's actions run as if copied into the current `LaunchDescription`. Environment variables set before the include are visible inside it. |

The order of actions in the returned `LaunchDescription` list matters: `SetEnvironmentVariable` must appear before any `Node` that depends on that variable.

---

## Common MAVROS node parameters

Every launch file that starts MAVROS uses the same `Node` configuration. These parameters are documented once here and referenced per-file below.

### Two YAML files — not the same thing

MAVROS receives two separate YAML files:

| File | Source | Controls |
|---|---|---|
| `apm_pluginlists_vision.yaml` | `sky_vision2/config/` | Which **ROS2 plugins** load (topics/services the ROS2 side exposes). See [sky_vision2 config](sky_vision2_config.md#apm_pluginlists_vision-yaml). |
| `apm_config.yaml` | `mavros` package (`install/mavros/share/mavros/launch/`) | Which **MAVLink message streams** to request from the FCU, rate overrides, and plugin-specific configuration (e.g., local frame origins). |

These are independent. A plugin must be in the allowlist to load, and separately, the FCU must be configured to send the corresponding MAVLink messages (controlled by `apm_config.yaml`). If a plugin is in the allowlist but the FCU never sends its MAVLink message, the ROS2 topic simply has no data.

### MAVROS node parameters

```python
Node(
    package='mavros',
    executable='mavros_node',
    name='mavros',
    output='screen',
    parameters=[
        pluginlists_yaml,       # sky_vision2 allowlist
        apm_config_yaml,        # mavros default APM config
        {
            'fcu_url': ...,
            'gcs_url': '',
            'tgt_system': 1,
            'tgt_component': 1,
            'fcu_protocol': 'v2.0',
        },
    ],
)
```

| Parameter | Value | Meaning |
|---|---|---|
| `fcu_url` | `/dev/ttyTHS1:921600` (default) | MAVLink transport URL. Serial format is `device:baud`. See format table below. |
| `gcs_url` | `''` (empty) | Disables GCS forwarding. MAVROS can forward MAVLink to a ground station (Mission Planner, QGC) simultaneously. Empty string disables this. On a Jetson with no network GCS, forwarding is unnecessary overhead. |
| `tgt_system` | `1` | MAVLink `system_id` of the FCU. ArduPilot defaults to 1. Must match `SYSID_THISMAV` in ArduPilot. |
| `tgt_component` | `1` | MAVLink `component_id` of the autopilot. 1 = autopilot component. Must match the FCU; mismatching causes MAVROS to ignore all FCU messages. |
| `fcu_protocol` | `'v2.0'` | Use MAVLink v2 framing. v2 adds message signing support and packet sequence numbers that enable detection of dropped messages. v1 is the legacy protocol — using it with modern ArduPilot is not recommended. |

### fcu_url format reference

| Connection type | Format | Example |
|---|---|---|
| Serial UART (Jetson Telem2) | `device:baudrate` | `/dev/ttyTHS1:921600` |
| USB serial adapter | `device:baudrate` | `/dev/ttyUSB0:57600` |
| TCP (ArduPilot SITL default) | `tcp://host:port` | `tcp://127.0.0.1:5760` |
| UDP (MAVProxy forwarding) | `udp://:port` | `udp://:14550` |

The Jetson uses `/dev/ttyTHS1` — the hardware UART on the 40-pin header — connected to the Pixhawk 6C Telem2 port. 921600 baud is the maximum reliable rate for this link. Lower rates cause MAVROS to fall behind the FCU message rate and drop messages, which degrades EKF update frequency.

If `/dev/ttyTHS1` does not exist or permission is denied:

```bash
ls -l /dev/ttyTHS*          # verify device exists
sudo usermod -aG dialout $USER  # add user to dialout group (requires re-login)
```

---

## mavros_fc.launch.py

**Purpose:** MAVROS + ZedMavrosBridge. Does **not** start the ZED camera. Use when the ZED driver is already running (e.g., in a separate terminal via `zed.launch.py`).

```bash
ros2 launch sky_vision2 mavros_fc.launch.py

# Override UART port and baud:
ros2 launch sky_vision2 mavros_fc.launch.py fcu_url:=/dev/ttyUSB0:57600

# Override ZED odom topic if ZED was launched with a non-default namespace:
ros2 launch sky_vision2 mavros_fc.launch.py zed_odom_topic:=/my_zed/odom
```

### Launch arguments

| Argument | Default | Description |
|---|---|---|
| `fcu_url` | `/dev/ttyTHS1:921600` | MAVLink connection string forwarded to MAVROS |
| `zed_odom_topic` | `/zed/zed_node/odom` | ZED odometry topic forwarded to the bridge as a ROS2 parameter |

### Environment variables set

| Variable | Value | Effect scope |
|---|---|---|
| `ROS_DOMAIN_ID` | `42` | All child nodes (MAVROS, bridge) |
| `FASTRTPS_DEFAULT_PROFILES_FILE` | `install/.../config/fastdds_no_shm.xml` | All child nodes |

This is the only launch file that sets `FASTRTPS_DEFAULT_PROFILES_FILE`. The FastDDS no-SHM profile must be active **before** any DDS participant is created. `SetEnvironmentVariable` in the launch graph propagates the variable to every node process spawned after it in the same launch file. It does not affect the terminal where `ros2 launch` was run, nor other terminals.

### Full launch graph

```
LaunchDescription
  ├── SetEnvironmentVariable: ROS_DOMAIN_ID = 42
  ├── SetEnvironmentVariable: FASTRTPS_DEFAULT_PROFILES_FILE → fastdds_no_shm.xml
  ├── DeclareLaunchArgument: fcu_url (default /dev/ttyTHS1:921600)
  ├── DeclareLaunchArgument: zed_odom_topic (default /zed/zed_node/odom)
  ├── Node: mavros_node
  │     parameters: [apm_pluginlists_vision.yaml, apm_config.yaml, {fcu_url, gcs_url='', ...}]
  └── Node: zed_mavros_bridge
        parameters: [{zed_odom_topic: <arg>}]
```

### Startup verification

After launch, check in order:

```bash
# 1. MAVROS connected to FCU (wait ~5 s for serial handshake):
ros2 topic echo /mavros/state --once
# → connected: True, armed: False, mode: "STABILIZE"

# 2. ZED odom is arriving (ZED must already be running):
ros2 topic hz /zed/zed_node/odom
# → average rate: ~30 Hz

# 3. Bridge is publishing to MAVROS:
ros2 topic hz /mavros/mavros/pose
# → average rate: ~30 Hz (no vision_speed — bridge doesn't publish it; topic name
#   is /mavros/mavros/pose, not /mavros/vision_pose/pose — see bridge_node.md)

# 4. EKF receiving vision data — /mavros/estimator_status often never publishes
# (SR2_EXTRA3 defaults to 0 Hz on Telem2). Check ArduPilot/Mission Planner logs
# for "EKF3 IMU0 is using external nav data" instead.
```

### Common failures

| Symptom | Cause | Fix |
|---|---|---|
| `mavros/state` `connected: False` | Serial port wrong or Pixhawk not powered | Check `/dev/ttyTHS1` exists and baud matches Telem2 config |
| `vision_pose` 0 Hz | ZED not running or topic name mismatch | Launch ZED first; verify `zed_odom_topic` matches ZED's actual output topic |
| `vision_pose` present but FCU ignores it | `VISO_TYPE` not set or EK3_SRC parameters wrong | Set ArduPilot params per [README](README.md#required-ardupilot-parameters) |
| DDS type error in log | Stale SHM from previous run | `rm -f /dev/shm/fastrtps_*` then relaunch (this file sets no-SHM, but ZED launched in another terminal may not) |

---

## zed.launch.py

**Purpose:** ZED camera driver only. No MAVROS, no bridge. Use for standalone camera testing or as the first step of a split-terminal workflow.

```bash
ros2 launch sky_vision2 zed.launch.py

# For ZED Mini instead of ZED2i:
ros2 launch sky_vision2 zed.launch.py camera_model:=zedm

# For ZED-X (newer model):
ros2 launch sky_vision2 zed.launch.py camera_model:=zedx
```

### Launch arguments

| Argument | Default | Description |
|---|---|---|
| `camera_model` | `zed2i` | ZED camera model string, passed directly to `zed_camera.launch.py` |

Valid model strings: `zed`, `zed2`, `zed2i`, `zedm`, `zedx`, `zedxm`. Using the wrong model string causes the ZED SDK to fail at initialization with a model mismatch error.

### Environment variables set

| Variable | Value |
|---|---|
| `ROS_DOMAIN_ID` | `42` |

### Full launch graph

```
LaunchDescription
  ├── SetEnvironmentVariable: ROS_DOMAIN_ID = 42
  ├── DeclareLaunchArgument: camera_model (default zed2i)
  └── IncludeLaunchDescription: zed_wrapper/launch/zed_camera.launch.py
        launch_arguments: {camera_model: <arg>}
```

The `IncludeLaunchDescription` pulls in `zed_camera.launch.py` from the installed `zed_wrapper` package. This is the Stereolabs-provided launch file; it handles camera serial number detection, GPU allocation, ZED SDK parameter loading, and starts the `zed_node` component inside a `ZedCamera` container.

### Topics published by the ZED driver

| Topic | Type | Rate | Consumers |
|---|---|---|---|
| `/zed/zed_node/odom` | `nav_msgs/Odometry` | ~30 Hz | `ZedMavrosBridge` |
| `/zed/zed_node/pose` | `geometry_msgs/PoseStamped` | ~30 Hz | `pose_relay` (legacy) |
| `/zed/zed_node/left/image_rect_color` | `sensor_msgs/Image` | ~30 Hz | `ZedSubscriber` (mission vision) |
| `/zed/zed_node/depth/depth_registered` | `sensor_msgs/Image` | ~30 Hz | `ZedSubscriber` (mission vision) |
| `/zed/zed_node/imu/data` | `sensor_msgs/Imu` | ~400 Hz | (unused currently) |

The odom and pose topics use BEST_EFFORT QoS — this is why the bridge must also subscribe with BEST_EFFORT (see [ZedMavrosBridge](zed_mavros_bridge.md#qos-profile--why-best_effort)).

### ZED SDK startup time

The ZED driver takes 10–15 seconds from launch to publishing its first odom message. During this time:
- The camera LED blinks orange (firmware loading).
- No topics are published yet.
- `ros2 topic hz /zed/zed_node/odom` shows no data.

This is normal. The bridge will receive no odom messages during this window and will begin bridging automatically once the ZED driver is ready.

### Startup verification

```bash
# ZED publishes after ~15 s of startup:
ros2 topic hz /zed/zed_node/odom
# → average rate: ~30 Hz

# Check image is available (not NaN frames):
ros2 topic echo /zed/zed_node/left/image_rect_color --field header --once
# → stamp.sec should be close to current time
```

---

## zed_mavros_fc.launch.py

**Purpose:** Full real-hardware stack. Starts ZED camera, MAVROS, and the bridge in a single launch. Standard pre-flight startup command.

```bash
ros2 launch sky_vision2 zed_mavros_fc.launch.py

# Override UART:
ros2 launch sky_vision2 zed_mavros_fc.launch.py fcu_url:=/dev/ttyTHS0:921600

# Override ZED odom topic:
ros2 launch sky_vision2 zed_mavros_fc.launch.py zed_odom_topic:=/zed/zed_node/odom
```

### Launch arguments

| Argument | Default | Description |
|---|---|---|
| `fcu_url` | `/dev/ttyTHS1:921600` | MAVLink serial connection |
| `camera_model` | `zed2i` | ZED camera model |
| `zed_odom_topic` | `/zed/zed_node/odom` | ZED odometry topic for the bridge |

### Environment variables set

| Variable | Value |
|---|---|
| `ROS_DOMAIN_ID` | `42` |
| `FASTRTPS_DEFAULT_PROFILES_FILE` | `install/.../config/fastdds_no_shm.xml` |

### Full launch graph

```
LaunchDescription
  ├── SetEnvironmentVariable: ROS_DOMAIN_ID = 42
  ├── SetEnvironmentVariable: FASTRTPS_DEFAULT_PROFILES_FILE → fastdds_no_shm.xml
  ├── DeclareLaunchArgument: fcu_url
  ├── DeclareLaunchArgument: camera_model
  ├── DeclareLaunchArgument: zed_odom_topic
  ├── IncludeLaunchDescription: zed_wrapper/launch/zed_camera.launch.py
  │     launch_arguments: {camera_model: <arg>}
  ├── Node: mavros_node
  │     parameters: [apm_pluginlists_vision.yaml, apm_config.yaml, {fcu_url, ...}]
  └── Node: zed_mavros_bridge
        parameters: [{zed_odom_topic: <arg>}]
```

All three processes start roughly simultaneously. The launch system does not enforce startup ordering between them — they race to initialize and each tolerates the others being absent at first:

- MAVROS waits for a FCU heartbeat over the serial link.
- The ZED driver takes 10–15 s to initialize; the bridge receives no odom until then.
- The bridge subscribes to topics that may not exist yet; ROS2 subscriptions are valid before publishers appear.

This means launching one command starts everything and the system converges to a working state without manual sequencing.

### Startup sequence (what actually happens)

```
t=0 s    ros2 launch ... starts
t=0 s    ROS_DOMAIN_ID=42 applied to all child processes
t=0 s    ZED driver starts — SDK initializing, no topics yet
t=0 s    MAVROS starts — waiting for FCU heartbeat on ttyTHS1
t=0 s    Bridge starts — waiting for /zed/zed_node/odom messages
t=2-5 s  MAVROS receives first FCU heartbeat → /mavros/state connected: True
t=10-15 s ZED SDK ready → /zed/zed_node/odom starts at ~30 Hz
t=10-15 s Bridge receives first odom → starts publishing vision_pose (no vision_speed)
t=10-15 s EKF begins fusing vision data → "EKF3 IMU0 is using external nav data" in FCU log
t=15-20 s  No explicit set_home call — ArduPilot sets EKF origin automatically once
           vision data arrives; keep the drone stationary ~20 s for a clean converge
```

### Startup verification

```bash
# In a second terminal (must export domain first):
export ROS_DOMAIN_ID=42

# 1. MAVROS connected:
ros2 topic echo /mavros/state --once
# connected: True

# 2. ZED producing odom:
ros2 topic hz /zed/zed_node/odom
# ~30 Hz

# 3. Bridge forwarding to MAVROS:
ros2 topic hz /mavros/vision_pose/pose
# ~30 Hz

# 4. Home set (check bridge log output):
# Log line: "HOME SET from vision EKF — ready to arm"

# 5. Arm:
ros2 service call /mavros/cmd/arming mavros_msgs/srv/CommandBool "{value: true}"
```

### Common failures

| Symptom | Cause | Fix |
|---|---|---|
| ZED log shows "Camera not found" | USB or power issue | Check USB-C connection; Jetson must provide enough current |
| `vision_pose` 0 Hz | ZED still initializing | Wait 15 s; if still 0 Hz, check bridge log for subscription errors |
| EKF never sets `pos_horiz_rel` | ArduPilot parameters wrong or `VISO_TYPE=0` | Verify EK3_SRC1_POSXY=6 and VISO_TYPE=1 via Mission Planner |
| "HOME SET" never logged | EKF health unstable (camera moving on startup, bad lighting) | Keep drone stationary for first 20 s after launch |
| DDS type mismatch errors | SHM not disabled (this file doesn't set the profile) | See Gotcha section below |

---

## zed_mavros_sitl.launch.py

**Purpose:** Intended for SITL (Software In The Loop) simulation with ArduPilot running in software. **Currently a placeholder** — the file is byte-for-byte identical to `zed_mavros_fc.launch.py` and has the `zed_mavros_fc.launch.py` docstring verbatim. It has not yet been adapted for simulation.

```bash
# Current behavior: starts ZED + MAVROS + bridge against real FC (same as zed_mavros_fc.launch.py)
ros2 launch sky_vision2 zed_mavros_sitl.launch.py
```

### What a proper SITL adaptation requires

For SITL, the launch file must differ from `zed_mavros_fc.launch.py` in at least three ways:

**1. FCU URL must point to the simulation process**

| Setup | fcu_url |
|---|---|
| ArduPilot SITL (default TCP) | `tcp://127.0.0.1:5760` |
| ArduPilot via MAVProxy UDP | `udp://:14550` |
| ArduPilot SITL direct UDP | `udp://127.0.0.1:14550` |

```python
# Change default:
fcu_url_arg = DeclareLaunchArgument(
    'fcu_url',
    default_value='tcp://127.0.0.1:5760',
    ...
)
```

**2. Real ZED camera is not needed — replace with synthetic odom**

In SITL, the drone is simulated and there is no physical ZED. Replace the ZED driver include with the test publisher:

```python
# Instead of IncludeLaunchDescription for zed_camera.launch.py:
Node(
    package='sky_vision2',
    executable='test_zed_odom',
    name='zed_odom_test_publisher',
    output='screen',
)
```

The `test_zed_odom` node publishes synthetic `Odometry` on the same topic the bridge expects, allowing full end-to-end testing without a camera. See [test_zed_odom](test_zed_odom.md) for what trajectory it generates.

**3. FastDDS no-SHM should be enabled**

SITL is a development context where MAVROS is frequently restarted. The no-SHM profile should be set here too:

```python
no_shm = SetEnvironmentVariable('FASTRTPS_DEFAULT_PROFILES_FILE', fastdds_profile)
```

Until the file is updated, override `fcu_url` manually and use `mavros_fc.launch.py` with `test_zed_odom` running in a separate terminal as a practical workaround:

```bash
# Terminal 1 — fake ZED odom:
ros2 run sky_vision2 test_zed_odom

# Terminal 2 — MAVROS + bridge against SITL:
ros2 launch sky_vision2 mavros_fc.launch.py fcu_url:=tcp://127.0.0.1:5760
```

---

## FastDDS no-SHM — which launch files set it

| Launch file | SHM disabled | Safe to restart MAVROS without clearing `/dev/shm` |
|---|---|---|
| `mavros_fc.launch.py` | Yes | Yes |
| `zed_mavros_fc.launch.py` | Yes | Yes |
| `zed_mavros_sitl.launch.py` | **No** | **No** |
| `zed.launch.py` | N/A (ZED only, no MAVROS) | N/A |

`zed_mavros_sitl.launch.py` is the only launch file that does not disable shared-memory DDS transport. Before restarting MAVROS under that file, clear stale SHM entries:

```bash
rm -f /dev/shm/fastrtps_*
ros2 launch sky_vision2 zed_mavros_sitl.launch.py ...
```

Or set the env variable before launching:

```bash
export FASTRTPS_DEFAULT_PROFILES_FILE=$(ros2 pkg prefix sky_vision2)/share/sky_vision2/config/fastdds_no_shm.xml
ros2 launch sky_vision2 zed_mavros_sitl.launch.py fcu_url:=tcp://127.0.0.1:5760
```

For SITL development, the practical workaround is to use `mavros_fc.launch.py` (which does set the profile) with `test_zed_odom` providing synthetic odometry in a second terminal — no real ZED needed. See [test_zed_odom](test_zed_odom.md).

---

## Why ROS_DOMAIN_ID=42

ROS2 DDS communication is domain-scoped: only participants with the same `ROS_DOMAIN_ID` can exchange messages. All four launch files set it to `42`.

### The problem it solves

Without a fixed domain ID, the sky_vision2 stack uses DDS domain `0` (the default). Any other ROS2 process on the same machine or LAN also using domain `0` is a potential source of collisions:

- A ROS2 desktop environment with a different build of `mavros_msgs` publishes on `/mavros/state`. The DDS type hash for its `mavros_msgs/State` message differs from the Jetson's build. When the Jetson's MAVROS tries to match this topic, DDS reports a type mismatch. Depending on the FastDDS version, this either silently drops messages or crashes the MAVROS subscriber.
- The same collision can happen between two workspaces on the same machine if one was built against a different ROS2 underlay.

Domain `42` acts as a namespace fence: only processes explicitly configured with `ROS_DOMAIN_ID=42` participate. Every terminal used to interact with the stack must also export this variable:

```bash
export ROS_DOMAIN_ID=42
ros2 topic list   # now sees sky_vision2 topics
ros2 run rqt_graph rqt_graph  # shows sky_vision2 graph
```

Domain IDs must be in `[0, 101]` on most platforms. `42` is arbitrary; any value in that range works as long as it is not already used by another isolated stack on the system.

---

## See also

- [ZedMavrosBridge](zed_mavros_bridge.md) — the bridge node these launch files start, with full QoS, frame correction, and EKF watchdog documentation
- [sky_vision2 config](sky_vision2_config.md) — `fastdds_no_shm.xml` and `apm_pluginlists_vision.yaml` referenced by the launch files
- [test_zed_odom](test_zed_odom.md) — synthetic ZED odom publisher for testing the bridge without hardware; the practical SITL workaround
- [launch](launch.md) — the older `indoor_2026/launch/mavros_zed.launch.py` launch file, which uses an XML-include approach and the simpler `pose_relay` bridge
- [pose_relay](pose_relay.md) — the bridge started by the `indoor_2026` stack, for comparison with `ZedMavrosBridge`
