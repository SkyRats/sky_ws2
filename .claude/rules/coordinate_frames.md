# Coordinate Frame Conventions

## Frame chain

```
ZED odom (ENU / FLU, REP-105)
    │
    │  bridge applies NED-align offset (+π/2 around Z)
    │    position: (x, y, z) → (−y, x, z)
    │    quaternion: q_sent = q_offset * q_zed
    ▼
MAVROS /mavros/vision_pose/pose  (ENU, offset applied)
    │
    │  vision_pose_estimate plugin converts ENU→NED automatically:
    │    position: x_ned=y_enu, y_ned=x_enu, z_ned=−z_enu
    │    orientation: FLU→FRD + ENU→NED rotations applied
    ▼
VISION_POSITION_ESTIMATE  (NED / FRD)
    │
    ▼
ArduPilot EKF3
```

## MAVROS DOES convert ENU→NED for ArduPilot

The `vision_pose_estimate` plugin applies two chained rotations before sending `VISION_POSITION_ESTIMATE`:
1. `BASELINK_TO_AIRCRAFT` → Rx(π): body FLU → FRD
2. `ENU_TO_NED` → Rz(π/2)·Rx(π): world ENU → world NED

**Do not manually convert to NED before publishing to MAVROS.** Publish ENU — MAVROS handles it.

## NED alignment offset (applied in the bridge)

ZED boots with identity quaternion (ENU yaw=0) → MAVROS converts to NED yaw=π/2 (East). The bridge left-multiplies every pose by `q_offset = (w=√2/2, x=0, y=0, z=√2/2)` (+π/2 around Z) so ArduPilot sees NED yaw=0 at boot.

```python
# Position
pose.position.x, pose.position.y = -pose.position.y, pose.position.x

# Orientation: q_new = q_offset * q_zed
s = sqrt(2)/2
pose.orientation.w = s * (w - qz)
pose.orientation.x = s * (qx - qy)
pose.orientation.y = s * (qx + qy)
pose.orientation.z = s * (w + qz)
```

See `src/sky_vision2/.claude/rules/yaw_frame_research.md` for full derivation and source references.

## What to check when the drone drifts

1. Confirm `ros2 topic hz /mavros/vision_pose/pose` is ~30 Hz.
2. Echo `/mavros/vision_pose/pose` and move the drone in known directions (after NED align):
   - Move toward boot heading (NED North) → `position.y` increases (ENU North = +Y before conversion)
3. Check `EK3_SRC1_POSXY=6` and `VISO_TYPE=1` are set on the FCU.
4. Confirm only one bridge node is running: `ros2 node list | grep zed_mavros_bridge`
