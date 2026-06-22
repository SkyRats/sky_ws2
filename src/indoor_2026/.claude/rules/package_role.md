# indoor_2026 in sky_ws2 — Package Role

## What this package is (sky_ws2 context)

In `sky_ws2`, `indoor_2026` is a **thin convenience launcher** — it starts MAVROS + ZED + `sky_vision2/ZedMavrosBridge` in one command. It contains no Python nodes of its own.

This is **different** from `indoor_2026` in `~/imav_2026_ws/`, which contains the legacy `pose_relay` node.

## What it does

`launch/mavros_zed.launch.py` launches:
1. MAVROS via `apm.launch` (fcu_url: `/dev/ttyTHS1:921600`)
2. ZED wrapper (camera_model: `zed2i`)
3. `sky_vision2/zed_mavros_bridge` node

It is functionally equivalent to `ros2 launch sky_vision2 zed_mavros_fc.launch.py` but without the FastDDS SHM fix and FCU parameter overrides.

## Prefer sky_vision2 launch files

For SITL or hardware testing, prefer the `sky_vision2` launch files directly:

```bash
# Hardware — includes FastDDS SHM fix and all parameters
ros2 launch sky_vision2 zed_mavros_fc.launch.py

# SITL
ros2 launch sky_vision2 mavros_fc.launch.py fcu_url:=tcp://127.0.0.1:5760
```

Use `indoor_2026/mavros_zed.launch.py` only when a single-command launch is needed for convenience and the FastDDS workaround is already in place.

## Build

```bash
cd ~/sky_ws2
colcon build --packages-select indoor_2026
source install/setup.bash
```

## Cross-references

- `src/sky_vision2/` — the bridge this package uses (submodule, `imav_2026` branch)
- `~/imav_2026_ws/src/indoor_2026/` — different package: contains legacy `pose_relay` node
- `.claude/rules/workspace_overview.md` — full sky_ws2 package map
