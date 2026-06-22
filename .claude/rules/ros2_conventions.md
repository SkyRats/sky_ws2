# ROS2 Conventions for imav_2026_ws

## MAVROS vision_pose expects NED for ArduPilot

MAVROS `vision_pose` plugin with ArduPilot (`apm.launch`) does NOT perform ENU→NED conversion. It passes the `PoseStamped` data directly as `VISION_POSITION_ESTIMATE`, which ArduPilot EKF3 expects in NED (X=North, Y=East, Z=Down).

**Always publish NED to `/mavros/vision_pose/pose` and `/mavros/vision_speed/speed_twist`.** Never publish ENU and assume MAVROS will convert — it will not.

## Domain ID

All nodes run on `ROS_DOMAIN_ID=42`. Every new terminal must export it:
```bash
export ROS_DOMAIN_ID=42
```
Set it in the terminal before calling `ros2 topic`, `ros2 node`, `ros2 run`, or `ros2 launch`. Forgetting this is the most common reason commands appear to show no nodes or topics.

## QoS profiles

| Publisher | Required subscriber QoS | Why |
|-----------|------------------------|-----|
| ZED odom `/zed/zed_node/odom` | BEST_EFFORT | ZED driver publishes BEST_EFFORT; a RELIABLE subscriber gets no data |
| All other MAVROS topics | RELIABLE (default) | Standard ROS2 default is fine |

Always use `QoSReliabilityPolicy.BEST_EFFORT` when subscribing to any ZED camera topic. Using the default RELIABLE profile will silently receive nothing.

## FastDDS shared memory

The `fastdds_no_shm.xml` config disables DDS SHM transport. It must be active when starting MAVROS, otherwise stale entries in `/dev/shm` from prior runs cause type mismatches that look like topics existing but carrying no data.

`mavros_fc.launch.py` sets this automatically. `zed_mavros_fc.launch.py` does not — clear SHM before restarting:
```bash
rm -f /dev/shm/fastrtps_*
```

## Bridge exclusivity

`ZedMavrosBridge` (sky_vision2) and `pose_relay` (indoor_2026) both publish to `/mavros/vision_pose/pose`. **Never run both simultaneously.** Check with `ros2 node list | grep -E "bridge|relay"` before launching.

## Build and source sequence

Always build before launching — launch files use `FindPackageShare` which resolves installed paths:
```bash
colcon build --packages-select sky_vision2   # or indoor_2026
source install/setup.bash                     # must re-source after every build
```

## ROS2 node callbacks must be non-blocking

Timer and subscription callbacks run on the executor thread. Never call `time.sleep()`, blocking service calls (use `call_async`), or heavy CV processing inside a ROS2 callback. Blocking the executor degrades all message rates in the node.
