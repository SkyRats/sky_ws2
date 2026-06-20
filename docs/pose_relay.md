# pose_relay — ZED → MAVROS Vision Pose Bridge

**Source:** `src/indoor_2026/indoor_2026/pose_relay.py`  
**Executable:** `pose_relay` (registered in `setup.py`)  
**Launched by:** `mavros_zed.launch.py`

Subscribes to the ZED pose and republishes it on the MAVROS external vision topic so ArduPilot's EKF can use it as a position source.

## Why this node exists

The ZED ROS2 wrapper publishes pose under the `/mavros/zed/` namespace. MAVROS listens for external vision on `/mavros/vision_pose/pose`. Without this relay, `/mavros/vision_pose/pose` has 0 publishers and ArduPilot receives no position estimate from the ZED.

## Topics

| Direction | Topic | Type |
|-----------|-------|------|
| Subscribes | `/mavros/zed/pose` | `geometry_msgs/PoseStamped` |
| Publishes | `/mavros/vision_pose/pose` | `geometry_msgs/PoseStamped` |

Rate: mirrors ZED output (~30 Hz).

## Coordinate frame correction

The ZED map frame has X and Y axes inverted relative to the ENU frame MAVROS expects. The relay applies a **180° rotation around Z** to both position and orientation:

```
position.x  →  -x
position.y  →  -y
position.z  →   z

# Quaternion: q_result = q_z180 * q_orig, where q_z180 = (x=0, y=0, z=1, w=0)
orientation.x  →  -qy
orientation.y  →   qx
orientation.z  →   qw
orientation.w  →  -qz
```

The quaternion is rotated consistently with the position so the heading sent to ArduPilot remains coherent.

## See also

- [Launch file](launch.md) — starts this node alongside MAVROS and ZED
- [Mav](communication.md) — subscribes to `/mavros/vision_pose/pose` to read current drone pose
