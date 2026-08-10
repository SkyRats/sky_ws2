# Repositories

The workspace root plus 14 nested repositories. Pinning mechanism and rationale:
`ai/decisions.md` entry #1.

## Ours

| Path | Remote | Branch | Role |
|---|---|---|---|
| `.` | `SkyRats/sky_ws2` | `imav_2026` | workspace root — shared docs, `.repos` manifest |
| `src/sky_vision2` | `SkyRats/sky_vision2` | `imav_2026` | ZED→MAVROS bridge, launch files, DDS/plugin config |
| `src/indoor_2026` | `SkyRats/indoor_2026` | `main` | IMAV 2026 competition missions |
| `src/sky_navigation` | **`SkyRats/sky_mavlink`** | `main` | `SkyMAVLink` — pip package, **not** colcon. Repo was renamed; directory name still says `sky_navigation`. |
| `src/outdoor_2025` | `SkyRats/outdoor_2025` | `dev_swarm` | previous season; not part of the indoor stack |
| `src/sky_sim2` | `SkyRats/sky_sim2` | *(detached `125c71ac`)* | simulation assets |

Only three of these are on the IMAV 2026 critical path: `sky_vision2`,
`indoor_2026`, `sky_navigation`.

> `src/sky_mavlink/` is a **redundant checkout of the same repository** on an
> already-merged branch — not a separate project. See `ai/decisions.md` #6. It should
> be removed; nothing in it is unpushed.

## Vendored

Upstream code, pinned to exact SHAs (or tags where HEAD sits on one). Do not commit
into these; do not add `CLAUDE.md`, journals, or settings to them.

| Path | Upstream | Pin |
|---|---|---|
| `src/ardupilot` | `ArduPilot/ardupilot` | SHA `f04add8b` (`ArduPilot-4.6.0-beta1-4037-g…`) |
| `src/ardupilot_gazebo` | `ArduPilot/ardupilot_gazebo` | SHA `37915925` (repo has no tags) |
| `src/ardupilot_gz` | `ArduPilot/ardupilot_gz` | SHA `58f47263` (repo has no tags) |
| `src/ros_gz` | `gazebosim/ros_gz` | tag `0.244.20` |
| `src/sdformat_urdf` | `ros/sdformat_urdf` | SHA `4be22a54` (`1.0.1-8-g…`) |
| `src/micro_ros_agent` | `micro-ROS/micro-ROS-Agent` | SHA `4f363a79` (`3.0.6-3-g…`) |
| `src/zed-ros2-wrapper` | `stereolabs/zed-ros2-wrapper` | SHA `74f4813d` (`humble-v5.0.0-1-g…`) |
| `Micro-XRCE-DDS-Gen` | `ardupilot/Micro-XRCE-DDS-Gen` | tag `v4.7.1` |

Two of these carry their own submodules, which **vcstool does not restore**:

```bash
git -C Micro-XRCE-DDS-Gen submodule update --init --recursive   # 2
git -C src/ardupilot      submodule update --init --recursive   # 15
```

## Reproducibility gaps

Present in the working tree, reachable from no manifest and no recorded upstream.
A fresh machine does not get these.

| Path | What it is | Status |
|---|---|---|
| `src/ardupilot_sitl_models` | **empty directory** | No upstream recorded anywhere in the tree. A rosdep key of this name fails to resolve during the Gazebo build (`indoor_2026/.claude/rules/gazebo_sim_test.md`). Upstream to be supplied. |
| `terrain/` | SITL terrain data (`S36E149.DAT`) | Generated or downloaded — provenance unrecorded |
| `eeprom.bin` | SITL FC EEPROM image | Run artifact |
| `mav.parm` | dumped FC parameters | Run artifact — but the authoritative param set is `src/indoor_2026/fc_scripts/set_ekf3_vision_params.sh` |
| `mav.tlog`, `mav.tlog.raw` | MAVLink telemetry logs | Run artifacts |
| `logs/` | run logs | Run artifacts |

The run artifacts are gitignore candidates. `src/ardupilot_sitl_models` is the only
one that blocks a clean rebuild.

## Quarantined

`nsrc/` — a clone of `SkyRats/sky_ws2` nested inside itself, with 3 clone-in-clone
children. Moved to `~/attic/nsrc-20260808` on 2026-08-08. All four repos were
verified to have 0 unpushed commits and 0 stashes first. It carried 1,235 lines of
stale instruction text that shadowed the real files.
