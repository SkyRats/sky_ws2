# ROS2 Conventions for sky_ws2

## MAVROS vision_pose converts ENU→NED for ArduPilot

MAVROS `vision_pose_estimate` plugin automatically applies two chained rotations before sending `VISION_POSITION_ESTIMATE`:
1. Body FLU → FRD (BASELINK_TO_AIRCRAFT)
2. World ENU → NED (ENU_TO_NED)

**Publish ENU to `/mavros/vision_pose/pose`.** Do not manually convert to NED — MAVROS handles it. The bridge only applies a NED alignment offset (+π/2 around Z) to set boot-time yaw=0.

## Domain ID

All nodes run on `ROS_DOMAIN_ID=42`. Every new terminal must export it:
```bash
export ROS_DOMAIN_ID=42
```
Forgetting this is the most common reason commands appear to show no nodes or topics.

## QoS profiles

| Publisher | Required subscriber QoS | Why |
|-----------|------------------------|-----|
| ZED odom `/zed/zed_node/odom` | BEST_EFFORT | ZED driver publishes BEST_EFFORT; a RELIABLE subscriber gets no data |
| All other MAVROS topics | RELIABLE (default) | Standard ROS2 default is fine |

Always use `QoSReliabilityPolicy.BEST_EFFORT` when subscribing to any ZED camera topic. Using the default RELIABLE profile will silently receive nothing.

## FastDDS shared memory

The `fastdds_no_shm.xml` config disables DDS SHM transport. It must be active when starting MAVROS, otherwise stale entries in `/dev/shm` from prior runs cause type mismatches that look like topics existing but carrying no data.

Both `zed_mavros_fc.launch.py` and `mavros_fc.launch.py` set this automatically. `zed_mavros_sitl.launch.py` does **not** — clear SHM before restarting:
```bash
rm -f /dev/shm/fastrtps_*
```

## Bridge exclusivity

Only `sky_vision2` runs `zed_mavros_bridge`. **Never run two instances simultaneously** — duplicate messages on `/mavros/vision_pose/pose` corrupt the EKF:
```bash
ros2 node list | grep zed_mavros_bridge   # must show exactly one
```

## Build and source sequence

Always build before launching — launch files use `FindPackageShare` which resolves installed paths:
```bash
colcon build --packages-select sky_vision2 indoor_2026
source install/setup.bash   # must re-source after every build
```

## ROS2 node callbacks must be non-blocking

Timer and subscription callbacks run on the executor thread. Never call `time.sleep()`, blocking service calls (use `call_async`), or heavy CV processing inside a ROS2 callback. Blocking the executor degrades all message rates in the node.
