# CLAUDE.md

ROS 2 Humble workspace for the **SkyRats IMAV 2026 indoor autonomous drone**. A ZED2i
stereo camera feeds visual odometry to ArduPilot's EKF3 through MAVROS for GPS-denied
indoor flight; missions command the FC over a separate pymavlink path.

@ai/interfaces.md
@ai/conventions.md

Also in `ai/`, not auto-loaded — read when relevant:

- `ai/decisions.md` — architectural decisions and their rationale. **Entries #2 and #3
  are open flight/build hazards; read them before touching missions or flying.**
- `ai/repos.md` — the 14 nested repos, how each is pinned, reproducibility gaps.
- `ai/stack.md` — hardware, versions, entry points, startup verification.

## Quick start

```bash
export ROS_DOMAIN_ID=42                            # required in every terminal
cd ~/sky_ws2
colcon build --packages-select sky_vision2 indoor_2026
source install/setup.bash
pip install -e src/sky_navigation                  # pip-only, once

ros2 launch sky_vision2 zed_mavros_fc.launch.py    # full stack
ros2 run indoor_2026 square_test                   # a mission
```

Tests:

```bash
colcon test --packages-select sky_vision2 indoor_2026 && colcon test-result --verbose
python3 src/sky_navigation/tests/square_test.py --endpoint tcp:127.0.0.1:5760
```

## Where things live

| Repo | Role |
|---|---|
| `src/sky_vision2` | ZED→MAVROS bridge, launch files, DDS/plugin config |
| `src/indoor_2026` | competition missions |
| `src/sky_navigation` | `SkyMAVLink` flight API (pip package, **not** colcon) |

Each has its own `CLAUDE.md` and `.claude/rules/`, loaded on demand when you open a
file in it. Anything spanning two repos belongs in `ai/interfaces.md` instead.

Key source files:

- `src/sky_vision2/sky_vision2/zed_mavros_bridge.py` — the production bridge
- `src/sky_navigation/skymavlink/{core,flight,motion}.py` — connection, commands, setpoints
- `src/indoor_2026/indoor_2026/square_test.py` — reference mission
- `src/indoor_2026/fc_scripts/` — FC parameter script and the home-setting Lua
