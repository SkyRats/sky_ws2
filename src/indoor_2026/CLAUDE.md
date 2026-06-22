# CLAUDE.md — indoor_2026 (sky_ws2)

Convenience launcher package. Starts MAVROS + ZED + `sky_vision2/ZedMavrosBridge` in one command. Contains no Python nodes.

This package is **not** the same as `indoor_2026` in `~/imav_2026_ws/`. That one contains the legacy `pose_relay` node. This one is a thin wrapper around `sky_vision2`.

## Build and run

```bash
cd ~/sky_ws2
colcon build --packages-select indoor_2026
source install/setup.bash

export ROS_DOMAIN_ID=42
ros2 launch indoor_2026 mavros_zed.launch.py
```

Prefer `ros2 launch sky_vision2 zed_mavros_fc.launch.py` — it has FastDDS SHM disabled and all overrideable arguments.

## See also

- `.claude/rules/package_role.md` — full role description and context
- `src/sky_vision2/` — the bridge this launch file uses
- `~/imav_2026_ws/src/indoor_2026/` — different package with `pose_relay`
