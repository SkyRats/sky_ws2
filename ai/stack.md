# Stack

Hardware and software the workspace targets. Read `ai/interfaces.md` for how the
pieces talk to each other.

## Vehicle

SkyRats IMAV 2026 indoor autonomous drone. GPS-denied: visual odometry, gate
traversal, precision landing.

| Component | Part | Connection |
|---|---|---|
| Companion computer | NVIDIA Jetson | — |
| Stereo camera | ZED2i | USB-C |
| Flight controller | Pixhawk 6C | Telem2 UART, `/dev/ttyTHS1:921600` |
| Firmware | ArduPilot (ArduCopter) | EKF3 with ExternalNav |

The Pixhawk needs an **SD card** for Lua scripting (`APM/scripts/`), which is how home
gets set. *Whether one is currently installed is unverified.*

## Software

| Layer | Version |
|---|---|
| ROS | ROS 2 Humble |
| DDS | Fast DDS, shared memory **disabled** (`fastdds_no_shm.xml`) |
| FC bridge | MAVROS 2, APM dialect |
| Mission API | `skymavlink` — pure pymavlink, pip-installed |
| Simulation | Gazebo Harmonic + `ardupilot_gz` (GPS-based EKF, not vision) |

MAVROS runs with a plugin **allowlist**, not the default set — `apm_pluginlists_vision.yaml`.
Loading the full set crashes on duplicate topic registration under the flattened
`/mavros/mavros` namespace.

### MAVROS overlay (optional)

`git@github.com:odraudE31/mavros.git`, branch `fix/vision-pose-yaw-clamping`, commit
`d61db77e` — replaces the Eigen `eulerAngles(2,1,0)` decomposition in
`quaternion_to_rpy` with an atan2-based ZYX decomposition, fixing yaw clamping to
`[0, π]` (MAVROS issue #444). Built as an opt-in overlay; apt MAVROS is untouched by
default. See `docs/mavros_patched.md`.

Without the overlay, NED headings in the south-to-west half fold back toward 0. With
it, full `[-π, π]` works.

## Entry points

| Command | Starts |
|---|---|
| `ros2 launch sky_vision2 zed_mavros_fc.launch.py` | ZED + MAVROS + bridge — standard pre-flight |
| `ros2 launch sky_vision2 mavros_fc.launch.py` | MAVROS + bridge (ZED already running) |
| `ros2 launch sky_vision2 zed.launch.py` | ZED only |
| `ros2 launch indoor_2026 full_flight_test.py` | MAVROS + bridge + `square_test` — auto-arms and flies |
| `ros2 run indoor_2026 square_test` | the mission alone |
| `ros2 run sky_vision2 test_zed_odom` | synthetic odom, no hardware |

The `*_sitl.launch.py` variants do not set the FastDDS profile — clear
`/dev/shm/fastrtps_*` before using them.

## Startup verification

```bash
export ROS_DOMAIN_ID=42
ros2 topic echo /mavros/state --once                # connected: True
ros2 topic hz /zed/zed_node/odom                    # ~30 Hz after ~15 s
ros2 topic hz /mavros/mavros/pose                   # ~30 Hz — vision in
ros2 topic hz /mavros/mavros/local_position/pose    # ~10 Hz once EKF converges
```

Then confirm the command relay before running a mission:

```bash
python3 -c "
from skymavlink import SkyMAVLink
m = SkyMAVLink(); m.wait_for_connection(); print('position:', m.wait_for_position())"
```

Wait for `FCU: EKF3 IMU0 is using external nav data` in the MAVROS log and
`ekf_home: HOME SET from vision EKF — ready to arm` on the GCS before arming.
