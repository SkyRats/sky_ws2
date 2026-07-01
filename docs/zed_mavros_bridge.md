# ZedMavrosBridge — ZED Odometry → MAVROS External Vision Bridge

**Source:** `src/sky_vision2/sky_vision2/zed_mavros_bridge.py`  
**Executable:** `zed_mavros_bridge` (registered in `setup.py`)  
**Launched by:** `mavros_fc.launch.py`, `zed_mavros_fc.launch.py`

Subscribes to ZED odometry, converts the frame convention to NED, and republishes position (only) on the MAVROS external vision input so ArduPilot's EKF3 can fuse it. Does **not** publish vision_speed — see "No vision_speed" below.

## Topics

| Direction | Topic | Type | Notes |
|---|---|---|---|
| Subscribes | `/zed/zed_node/odom` (configurable) | `nav_msgs/Odometry` | BEST_EFFORT QoS — must match ZED driver |
| Publishes | `/mavros/mavros/pose` (configurable, default) | `geometry_msgs/PoseStamped` | Position for EKF3 ExternalNav |

**Note:** the default topic is `/mavros/mavros/pose`, not `/mavros/vision_pose/pose` as generic MAVROS docs show — the `vision_pose` plugin subscribes to a relative `~/pose` topic, and this launch runs `mavros_node` with `name='mavros'` (no separate namespace), so its effective namespace is `/mavros/mavros`.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `zed_odom_topic` | `/zed/zed_node/odom` | ZED odometry input |
| `mavros_vision_pose_topic` | `/mavros/mavros/pose` | MAVROS position output |
| `yaw_offset_rad` | `0.0` (source) / `-1.5708` (launch file) | Zeroes ZED's initial heading — pure-Z quaternion rotation applied after the axis remap below |

## No vision_speed (2026-07-01)

`zed_camera_component_main.cpp`'s `publishOdom()` in the ZED ROS2 wrapper only fills `pose` — `twist` is never touched, so `msg.twist.twist.linear` is always exactly `(0,0,0)` regardless of real motion. Forwarding that as `VISION_SPEED_ESTIMATE` would tell the EKF "velocity = 0" with confidence even while actually moving — worse than not sending velocity at all. The bridge no longer has a speed publisher, `vision_speed` was removed from `config/apm_pluginlists_vision.yaml`'s allowlist, and `EK3_SRC1_VELXY` must be `0` (None) on the FC, not `6` — see the parameters table below.

If accurate vision velocity is ever needed, it would have to be derived in the bridge by finite-differencing consecutive `pose.position` samples (ZED position tracking is accurate; only `twist` is unpopulated).

## QoS — BEST_EFFORT required

ZED publishes odom with `BEST_EFFORT`. The bridge subscription must match or DDS silently drops all messages (no error is printed). The pose publisher uses default `RELIABLE` which is compatible with MAVROS's subscription.

## Coordinate frame correction (verified against running code, 2026-07-01)

`_odom_cb` does its own axis remap — it does not rely on MAVROS auto-converting ENU→NED:

```
position.x  →  -position.y    (North = -Y_zed)
position.y  →   position.x    (East  =  X_zed)
position.z  →   position.z    (unchanged)

orientation: qx,qy,qz,qw passed through unchanged, then rotated by yaw_offset_rad
             (q_out = q_corr * q_in, q_corr = pure Z rotation of yaw_offset_rad)
```

**MAVROS with ArduPilot does NOT auto-convert ENU→NED.** The bridge must publish NED directly.

Confirmed correct in a live hardware run (EKF3 yaw-aligned, using external nav data, position held near zero while stationary). The module docstring/startup log were previously out of sync with this transform (described "negate Y; flip qy,qz" instead) — fixed 2026-07-01 alongside the vision_speed removal, so docstring/log and `_odom_cb` now agree.

### Verification

Move the drone physically after launch and echo `/mavros/mavros/pose`:

| Movement | Field | Expected |
|---|---|---|
| Move North | `position.x` | Increases |
| Move East | `position.y` | Increases |
| Move Up | `position.z` | Decreases |

## set_home — NOT needed

ArduPilot sets the EKF origin automatically when it begins accepting vision data. Do not call `/mavros/cmd/set_home` from the bridge — the service is unreliable at startup (MAVROS command plugin isn't ready) and ArduPilot doesn't require it for ExternalNav operation.

If you need to set home manually: use QGroundControl or Mission Planner "Set Home Here" button after the EKF converges.

## estimator_status — may not publish

`/mavros/estimator_status` depends on ArduPilot sending `EKF_STATUS_REPORT` (MAVLink stream `EXTRA3`). This stream is often rate=0 by default on Telem2. If the topic never appears, check `SR2_EXTRA3` on the Pixhawk (set to ≥1 Hz via GCS). The bridge does not depend on this topic.

## Required ArduPilot parameters

| Parameter | Value | Meaning |
|---|---|---|
| `EK3_SRC1_POSXY` | `6` | ExternalNav horizontal position |
| `EK3_SRC1_VELXY` | `0` | None — no vision_speed is published |
| `EK3_SRC1_POSZ` | `1` | Barometer vertical (ZED Z drifts) |
| `EK3_SRC1_VELZ` | `0` | None |
| `EK3_SRC1_YAW` | `6` | ExternalNav yaw |
| `VISO_TYPE` | `1` | Enable vision processing in ArduPilot |

Without `VISO_TYPE=1`, ArduPilot silently discards all vision messages even though MAVROS is sending them.

## Build note

`colcon build --packages-select sky_vision2` fails with `error: option --uninstall not recognized` (setuptools compatibility issue). Instead, copy the Python module directly:

```bash
cp src/sky_vision2/sky_vision2/zed_mavros_bridge.py \
   install/sky_vision2/lib/sky_vision2/zed_mavros_bridge.py
```

The package uses an editable install — `src/sky_vision2/sky_vision2/zed_mavros_bridge.py` is what actually runs.

## See also

- [launch.md](launch.md) — how to start the full stack
- [sky_vision2_config.md](sky_vision2_config.md) — FastDDS and plugin allowlist
- [test_zed_odom.md](test_zed_odom.md) — synthetic odom for testing without hardware
