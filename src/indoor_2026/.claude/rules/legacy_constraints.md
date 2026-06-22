# indoor_2026 — Legacy Status and Constraints

## This package is reference-only

`indoor_2026` is kept for historical reference. It is not the production bridge. When in doubt about which bridge to use or modify, use `sky_vision2/ZedMavrosBridge`.

Consequences:
- New features (velocity forwarding, EKF watchdog, configurable topics) belong in `sky_vision2`, not here.
- Bug fixes that affect real flights should go in `sky_vision2`.
- `pose_relay` has known limitations (no velocity, no auto-home) that are intentional for a reference implementation — do not add these features to `pose_relay`.

## Never run both bridges simultaneously

`pose_relay` and `ZedMavrosBridge` both publish to `/mavros/vision_pose/pose`. Running both creates duplicate vision measurements that corrupt the EKF. Before launching either:

```bash
ros2 node list | grep -E "pose_relay|zed_mavros_bridge"
# must show only one (or none) before launching the other
```

Kill all drone processes if needed:
```bash
pkill -9 -f "mavros|zed|ros2 launch"
rm -f /dev/shm/fastrtps_*
```

## Build only what you need

```bash
# This package only:
colcon build --packages-select indoor_2026

# Production bridge (preferred):
colcon build --packages-select sky_vision2
```

Never run a bare `colcon build` in the workspace root unless you intend to rebuild every package including the ZED wrapper (takes minutes).

## Workspace context

This package lives in `~/imav_2026_ws/` (production workspace). The dev/sim workspace at `~/sky_ws2/` has a separate `indoor_2026` package that is a convenience launcher (uses sky_vision2's bridge, not pose_relay). Do not confuse the two.
