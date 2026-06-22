# Coordinate Frame Conventions

## Frame chain

```
ZED odom (X=North, Y=West, Z=Down) → ZedMavrosBridge (negate Y, negate qy/qz) → NED → MAVROS passthrough → VISION_POSITION_ESTIMATE → ArduPilot EKF3
```

## MAVROS does NOT convert frames for ArduPilot

MAVROS `vision_pose` plugin with ArduPilot passes data directly as `VISION_POSITION_ESTIMATE` without any ENU→NED conversion. The bridge must publish **NED** (X=North, Y=East, Z=Down) directly. Do not publish ENU and expect MAVROS to convert.

## Frames in use

| Frame | Axes | Used by |
|-------|------|---------|
| **ZED odom** (hardware-observed) | X=North, Y=West, Z=Down | `/zed/zed_node/odom` |
| **NED** | X=North, Y=East, Z=Down | ArduPilot EKF3 / MAVLink / MAVROS input |

## The Y-axis correction

The ZED odom Y axis points West. NED Y must point East. Only Y is inverted — X (North) and Z (Down) are already NED-aligned.

```python
position.x =  zed.position.x   # North, unchanged
position.y = -zed.position.y   # West → East
position.z =  zed.position.z   # Down, unchanged

velocity.x =  zed.twist.linear.x
velocity.y = -zed.twist.linear.y
velocity.z =  zed.twist.linear.z

# Quaternion: flipping Y reverses rotations around Y (pitch) and Z (yaw)
q.x =  qx   # roll (around North), unchanged
q.y = -qy   # pitch sign flips
q.z = -qz   # yaw sign flips
q.w =  qw
```

## The 180° Z-axis correction

The ZED2i odom frame has both X and Y axes inverted relative to ENU in our mounting configuration (X points West, Y points South). This is equivalent to a 180° rotation around Z. `ZedMavrosBridge` corrects this:

```python
pose_msg.pose.position.x = -msg.pose.pose.position.x   # negate X
pose_msg.pose.position.y = -msg.pose.pose.position.y   # negate Y
speed_msg.twist.linear.x = -msg.twist.twist.linear.x   # negate Vx
speed_msg.twist.linear.y = -msg.twist.twist.linear.y   # negate Vy
# quaternion: q_result = q_z180 * q_orig, q_z180 = (0, 0, 1, 0)
pose_msg.pose.orientation.x = -qy
pose_msg.pose.orientation.y =  qx
pose_msg.pose.orientation.z =  qw
pose_msg.pose.orientation.w = -qz
```

Both X and Y are negated and the quaternion is rotated 180° around Z for consistency. This applies to `/zed/zed_node/odom` (Odometry). The legacy `pose_relay` node applies the same rotation but to `/zed/zed_node/pose` (PoseStamped), which has the same frame convention in our setup.

## What to check when the drone drifts

If the drone drifts in a specific axis after arming:
1. Confirm `ros2 topic hz /mavros/vision_pose/pose` is ~30 Hz.
2. Echo `/mavros/vision_pose/pose` and move the drone in known directions:
   - Move North → `position.x` must increase
   - Move East  → `position.y` must increase
   - Move Up    → `position.z` must decrease (Z=Down, up is negative)
3. Check `EK3_SRC1_POSXY=6` and `VISO_TYPE=1` are set on the FCU.
4. Confirm only one bridge node is running (`ros2 node list | grep -E "bridge|relay"`).
