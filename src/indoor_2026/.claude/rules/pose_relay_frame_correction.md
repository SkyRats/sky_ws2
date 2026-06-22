# pose_relay — Frame Correction Rules

## What pose_relay corrects

`pose_relay` applies a 180° Z rotation: negates both X and Y, plus quaternion rotation.

```python
out.pose.position.x = -msg.pose.position.x
out.pose.position.y = -msg.pose.position.y
out.pose.position.z =  msg.pose.position.z

# 180° Z rotation: q_rot=(0,0,1,0), q_result = q_rot * q_orig
out.pose.orientation.x = -qy
out.pose.orientation.y =  qx
out.pose.orientation.z =  qw
out.pose.orientation.w = -qz
```

## This correction has NOT been hardware-verified

The production bridge `ZedMavrosBridge` has been hardware-verified: ZED odom is X=North, Y=West, Z=Down — only **Y negation** is needed to reach NED. X negation in pose_relay may be wrong.

MAVROS needs **NED output** (X=North, Y=East, Z=Down), not ENU. If pose_relay is ever revived, verify its axes with the same hardware test before use:
- Move North → corrected position.x must increase
- Move East → corrected position.y must increase
- Move Up → corrected position.z must decrease (Z=Down)

## Known bug: wrong subscription topic

`pose_relay` subscribes to `/mavros/zed/pose`. The ZED ROS2 wrapper v5 does not publish on this path — the actual topic is `/zed/zed_node/pose`. If `pose_relay` is ever revived or debugged, add a topic remapping in the launch file:

```python
remappings=[('/mavros/zed/pose', '/zed/zed_node/pose')]
```

Or change the hardcoded topic in `pose_relay.py` directly.

## QoS note

`pose_relay` uses the default RELIABLE QoS. The ZED wrapper publishes odom and pose with BEST_EFFORT. On the pose topic specifically, the QoS compatibility depends on the ZED wrapper version — if it uses BEST_EFFORT for pose as well, the subscription will silently receive nothing. Production bridge `ZedMavrosBridge` avoids this by explicitly using BEST_EFFORT.
