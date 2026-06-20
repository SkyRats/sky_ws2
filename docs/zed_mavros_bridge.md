# ZedMavrosBridge — ZED Odometry → MAVROS External Vision Bridge

**Source:** `src/sky_vision2/sky_vision2/zed_mavros_bridge.py`  
**Executable:** `zed_mavros_bridge` (registered in `setup.py`)  
**Launched by:** `mavros_fc.launch.py`, `zed_mavros_fc.launch.py`, `zed_mavros_sitl.launch.py`

Subscribes to the ZED camera's odometry topic, converts the frame convention, and republishes both position and velocity on the MAVROS external vision inputs so ArduPilot's EKF3 can fuse them. Also monitors EKF health and automatically sets the home position once the estimate is stable.

## Why this node exists

MAVROS exposes two external-vision input topics:

| MAVROS topic | MAVLink message | EKF3 role |
|---|---|---|
| `/mavros/vision_pose/pose` | `VISION_POSITION_ESTIMATE` | Absolute position correction |
| `/mavros/vision_speed/speed_twist` | `VISION_SPEED_ESTIMATE` | Velocity correction |

The ZED ROS2 wrapper publishes both position and velocity together in a single `nav_msgs/Odometry` message on `/zed/zed_node/odom`, but nothing in the stack automatically routes that to the two MAVROS inputs. Without this bridge:

- `/mavros/vision_pose/pose` has zero publishers → ArduPilot has no external position.
- `/mavros/vision_speed/speed_twist` has zero publishers → the EKF must dead-reckon velocity from IMU only, degrading position accuracy.

Additionally, the ArduPilot EKF needs a **home position** to be set before GUIDED mode position hold works correctly. This bridge detects when the EKF has a valid estimate and calls `set_home` automatically, removing a manual step that was easy to forget.

## Comparison with pose_relay

Both `ZedMavrosBridge` and [`pose_relay`](pose_relay.md) solve the same top-level problem (get ZED data into MAVROS), but they are distinct implementations targeting different stages of the project:

| Aspect | `pose_relay` (indoor_2026) | `ZedMavrosBridge` (sky_vision2) |
|---|---|---|
| Package | `indoor_2026` | `sky_vision2` |
| Input topic | `/mavros/zed/pose` (`PoseStamped`) | `/zed/zed_node/odom` (`Odometry`) |
| Input data | Position only | Position **and** velocity |
| Publishes velocity | No | Yes (`/mavros/vision_speed/speed_twist`) |
| Frame correction | 180° Z rotation: negate X and Y, rotate quaternion | X-only negation |
| Sets home | No | Yes (EKF health watchdog) |
| Production role | Earlier simpler version | Current production node |

The input topic difference is the key reason the frame corrections differ. `pose_relay` subscribes to the ZED **pose** topic, which is in the ZED map frame (X=forward, Y=left). `ZedMavrosBridge` subscribes to the ZED **odom** topic, which is in the odometry frame where only the X axis is inverted relative to MAVROS ENU. Applying the `pose_relay` rotation to odom data would produce incorrect results.

**Running both nodes simultaneously will produce duplicate messages on `/mavros/vision_pose/pose`**, which confuses the EKF. Only one should be active at a time. On the sky_vision2 stack, `pose_relay` is not launched.

## Topics and services

| Direction | Topic / Service | Type | Description |
|---|---|---|---|
| Subscribes | `/zed/zed_node/odom` (configurable) | `nav_msgs/Odometry` | ZED visual odometry at ~30 Hz |
| Subscribes | `/mavros/estimator_status` | `mavros_msgs/EstimatorStatus` | EKF health flags |
| Publishes | `/mavros/vision_pose/pose` (configurable) | `geometry_msgs/PoseStamped` | Position for EKF external vision |
| Publishes | `/mavros/vision_speed/speed_twist` (configurable) | `geometry_msgs/TwistStamped` | Velocity for EKF external vision |
| Calls | `/mavros/cmd/set_home` | `mavros_msgs/CommandHome` | Sets ArduPilot home position |

## ROS2 parameters

| Parameter | Default | Description |
|---|---|---|
| `zed_odom_topic` | `/zed/zed_node/odom` | ZED odometry input topic |
| `mavros_vision_pose_topic` | `/mavros/vision_pose/pose` | MAVROS position output topic |
| `mavros_vision_speed_topic` | `/mavros/vision_speed/speed_twist` | MAVROS velocity output topic |

Override at launch time with `--ros-args -p zed_odom_topic:=/my/custom/odom` or via the launch file arguments.

## QoS profile — why BEST_EFFORT

The ZED wrapper publishes the odometry topic with `BEST_EFFORT` reliability. DDS requires that a subscription's QoS is **compatible** with the publisher's QoS before it will match them and deliver messages. The compatibility rule for reliability is:

```
subscriber RELIABLE + publisher BEST_EFFORT  →  INCOMPATIBLE (no connection)
subscriber BEST_EFFORT + publisher BEST_EFFORT  →  compatible (messages flow)
```

If the bridge used the default `RELIABLE` QoS, the DDS middleware would silently refuse to connect the subscription to the ZED publisher. No error is printed; the subscriber simply receives nothing. This is one of the most common silent failures when integrating third-party ROS2 sensor drivers.

The bridge uses:

```python
sensor_qos = QoSProfile(
    reliability=QoSReliabilityPolicy.BEST_EFFORT,
    history=QoSHistoryPolicy.KEEP_LAST,
    durability=QoSDurabilityPolicy.VOLATILE,
    depth=10,
)
```

This profile matches the ZED driver's sensor QoS exactly.

## Coordinate frame correction — X-only negation

The ZED odometry frame has its X axis inverted relative to the ENU (East-North-Up) frame that MAVROS and ArduPilot expect. Only X is negated; Y and Z are passed through unchanged:

```
ZED odom frame → MAVROS ENU frame

position.x  →  -position.x
position.y  →   position.y   (unchanged)
position.z  →   position.z   (unchanged)

twist.linear.x  →  -twist.linear.x
twist.linear.y  →   twist.linear.y   (unchanged)
twist.linear.z  →   twist.linear.z   (unchanged)
```

The quaternion is **not** rotated. This is correct for the odom frame; only a single axis flip is required, not a full 180° rotation around Z. Compare with [`pose_relay`](pose_relay.md), which used the ZED **pose** frame and needed both X and Y negated plus a full quaternion rotation — that is a different frame with a different convention.

The correction is applied in the callback before publishing:

```python
pose_msg.pose.position.x = -msg.pose.pose.position.x
speed_msg.twist.linear.x = -msg.twist.twist.linear.x
```

## EKF health watchdog and auto-set home

### Why set_home is needed

ArduPilot's EKF3 computes position in a local frame relative to a **home position** origin. Without a home position, GUIDED mode position hold does not work: the EKF has no reference point to compare the vision estimate against. `set_home` instructs ArduPilot to record the current location as the origin. With `current_gps=True`, it uses whatever position the EKF currently reports as home — this works even without GPS when the EKF is being fed by external vision.

In manual pre-bridge workflows, operators had to call `set_home` via GCS before arming. Forgetting it caused position hold to drift or refuse to engage. The bridge automates this.

### Why wait for EKF stability

Calling `set_home` too early — before the EKF has converged — would set an inaccurate origin, causing all subsequent position commands to be offset. The bridge waits for `pos_horiz_rel` (horizontal position relative to home is valid) to be `True` for `STABLE_SECS = 5.0` continuous seconds before sending the request.

The 5-second window is long enough to filter out transient EKF convergence spikes that can appear during the first few seconds of visual odometry. If the EKF health flag drops at any point during the countdown, the timer resets to zero (conservative safety design: any wobble restarts the wait).

### State machine

```
         EKF reports pos_horiz_rel=True
                      │
                      ▼
            [_healthy_since = now]
                      │
             elapsed < 5.0 s?
            /                  \
          Yes                   No (5 s elapsed)
           │                        │
  keep waiting             [_send_set_home()]
  (EKF still healthy)              │
           │               service available?
  pos_horiz_rel drops?      /              \
           │              No               Yes
           ▼               │                │
  [_healthy_since = None]  reset timer   call set_home
  (restart countdown)                       │
                                     success?
                                    /        \
                                  No          Yes
                                   │            │
                              reset timer  [_home_set = True]
                              (retry)      (watchdog exits)
```

Once `_home_set` is `True`, the EKF callback returns immediately and the watchdog is permanently disabled. This prevents re-issuing `set_home` during flight if the EKF temporarily reports unhealthy.

### EstimatorStatus.pos_horiz_rel

`pos_horiz_rel` is one of ArduPilot's EKF status bitfield flags, exposed by MAVROS on the `EstimatorStatus` message. It means "the EKF has a valid horizontal position estimate relative to the home position." It is distinct from `pos_horiz_abs` (which requires GPS). For indoor vision-only flight, only `pos_horiz_rel` will ever be True.

## Required ArduPilot parameters

These parameters must be set on the flight controller before the bridge can function. Incorrect values are the most common cause of the EKF ignoring the vision input entirely.

| Parameter | Value | Meaning |
|---|---|---|
| `EK3_SRC1_POSXY` | `6` | Horizontal position source: ExternalNav (vision) |
| `EK3_SRC1_VELXY` | `6` | Horizontal velocity source: ExternalNav (vision) |
| `EK3_SRC1_POSZ` | `1` | Vertical position source: Barometer |
| `EK3_SRC1_VELZ` | `0` | Vertical velocity source: None |
| `EK3_SRC1_YAW` | `6` | Yaw source: ExternalNav (vision) |
| `VISO_TYPE` | `1` | Enable visual odometry processing in ArduPilot |

`EK3_SRC1_POSZ = 1` (Baro) rather than ExternalNav because the ZED odometry Z estimate can drift over time, while the barometer provides a stable absolute altitude reference for indoor environments. Using baro for Z and vision for XY is the standard indoor ArduPilot configuration.

`VISO_TYPE = 1` tells ArduPilot to process incoming `VISION_POSITION_ESTIMATE` and `VISION_SPEED_ESTIMATE` MAVLink messages. Without this, MAVROS publishes the messages but ArduPilot silently discards them.

## Diagnostic logging

Every 100 messages (`_msg_count % 100 == 0`), the bridge logs the current position and quaternion at INFO level. At 30 Hz, this gives a log line roughly every 3.3 seconds — enough to confirm data flow without flooding the terminal.

## See also

- [pose_relay](pose_relay.md) — earlier simpler bridge (indoor_2026 package, no velocity, no auto-home)
- [sky_vision2 launch files](sky_vision2_launch.md) — how to start this node alongside MAVROS and ZED
- [test_zed_odom](test_zed_odom.md) — synthetic odometry tool for testing this bridge without hardware
- [sky_vision2 config](sky_vision2_config.md) — FastDDS and plugin allowlist that this bridge depends on
- [communication](communication.md) — `Mav` node that consumes the MAVROS output this bridge feeds
