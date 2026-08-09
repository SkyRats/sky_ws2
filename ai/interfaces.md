# Interfaces

Contracts that span repositories. If a topic, frame, or MAVLink identity appears in
more than one repo, its definition lives here and the repos point at it.

## The split: ROS carries positioning, SkyMAVLink carries commands

Two paths share one FC link. MAVROS is the only process on the serial port and routes
for both.

```
ZED2i → /zed/zed_node/odom (nav_msgs/Odometry, ~30 Hz, BEST_EFFORT)
      → sky_vision2/zed_mavros_bridge
          └─ /mavros/mavros/pose → MAVROS vision_pose plugin (ENU→NED)
               → VISION_POSITION_ESTIMATE → ArduPilot EKF3

mission → skymavlink.SkyMAVLink (pymavlink, udpout:127.0.0.1:14552)
      → MAVROS gcs_url relay (udp://:14552@) → FC serial
          └─ mode / arm / takeoff / SET_POSITION_TARGET_LOCAL_NED → ArduPilot
          ← HEARTBEAT / LOCAL_POSITION_NED / ATTITUDE
```

Four invariants keep the halves from fighting. Breaking any one is a flight hazard.

- **MAVROS never commands.** The plugin allowlists load no `setpoint_*` plugins.
  Never add one — two GUIDED sources give the EKF contradictory targets.
- **SkyMAVLink never publishes vision.** It parses only `HEARTBEAT`,
  `LOCAL_POSITION_NED`, `ATTITUDE`.
- **Distinct MAVLink component ids.** MAVROS transmits as `(1, 191)`; SkyMAVLink as
  `(1, 192)`. Same address on one link makes `COMMAND_ACK` routing ambiguous.
  `src/sky_mavlink` still uses 191 — see `ai/decisions.md` #3.
- **Opposite frames.** The vision half is ENU/FLU; SkyMAVLink is NED/FRD. Never copy
  a frame snippet between them.

MAVROS is therefore on the critical path for commands, not just vision. If it dies
mid-flight, setpoints stop and ArduPilot's `GUID_TIMEOUT` (~3 s) brakes the drone.
Pass `gcs_url:=''` to any launch file to disable the relay.

## Topic names

| Topic | Direction | QoS | Notes |
|---|---|---|---|
| `/zed/zed_node/odom` | ZED → bridge | **BEST_EFFORT** | A RELIABLE subscriber silently receives nothing |
| `/mavros/mavros/pose` | bridge → MAVROS | RELIABLE | Vision in. **Not** `/mavros/vision_pose/pose` |
| `/mavros/mavros/local_position/pose` | MAVROS → missions | RELIABLE | EKF output, ~10 Hz after convergence |
| `/mavros/state` | MAVROS → missions | — | `connected`, `armed`, `mode` |

### Why the vision topic is `/mavros/mavros/pose`

The MAVROS `vision_pose` plugin subscribes to a **relative** topic (`~pose`). The
launch files run `mavros_node` with `name='mavros'` and no `namespace:=` override, so
its effective namespace is `/mavros/mavros` and the relative subscription resolves to
`/mavros/mavros/pose` — not the `/mavros/vision_pose/pose` in generic MAVROS docs.

Re-check with `ros2 node info /mavros/mavros` after any MAVROS or launch-file bump.

> **Open issue — vision topic collision (found 2026-08-07, not yet fixed).**
> `Node(name='mavros')` flattens every plugin sub-node into one node, so
> plugin-relative topics lose their per-plugin namespace. `local_position` publishes
> `~/pose` and `vision_pose` subscribes `~/pose` — both resolve to
> `/mavros/mavros/pose`. Measured on a single clean instance: 1 publisher +
> 1 subscriber on that topic with no bridge running. The EKF's own local position is
> fed back in as `VISION_POSITION_ESTIMATE`, interleaved with the ZED bridge's pose.
> Fix is to drop `name='mavros'` and point the bridge at `/mavros/vision_pose/pose`.

## Frames

### The vision half publishes ENU. MAVROS converts to NED.

`mavros_extras`'s `vision_pose_estimate` plugin calls `ftf::transform_frame_enu_ned()`
on position and
`transform_orientation_enu_ned(transform_orientation_baselink_aircraft(q))` on
orientation. There is **no APM/PX4 branch** in that plugin — it always converts.

**Publish ENU to the vision pose topic. Never convert to NED in the bridge** — doing
it twice is silent and produces a plausible-looking wrong pose.

The bridge's only geometric action is a yaw alignment *within* ENU:

```python
# position:    (x, y, z) -> (-y, x, z)   for the +90 deg case; z ALWAYS untouched
# orientation: q_out = q_corr * q_in     # pure-Z rotation, same angle
```

The `z` pass-through at `zed_mavros_bridge.py:118` is the load-bearing evidence that
the output is ENU: a bridge emitting NED would have to negate it.

### The yaw alignment is computed at runtime

On the **first** odom message (`zed_mavros_bridge.py:81`):

```python
offset = math.pi / 2.0 - yaw_zed
```

so ArduPilot reads NED yaw = 0 at boot whatever direction the drone faces. **The
value depends on boot heading and differs run to run.** It is not a constant and
there is no parameter or launch argument for it. Only when `yaw_zed == 0` does it
reduce to a fixed +π/2 about Z — older docs mistook that special case for the rule.

### The command half is NED/FRD

| `SkyMAVLink` method | Frame |
|---|---|
| `set_local_pose(n, e, d, yaw_deg=0)` | NED (North-East-Down); altitude = −down |
| `set_body_pose(f, r, d, yaw_deg=0)` | FRD offset from current pose, sent as absolute NED |
| `set_body_velocity(f, r, d, yaw_rate_dps=0)` | FRD body frame, re-sent at 20 Hz |
| `set_global_pose(lat, lon, alt)` | Global |
| `stop()` | Stops *sending* — ArduPilot coasts until `GUID_TIMEOUT` (~3 s) |

Full reference: `src/sky_navigation/README.md`.

## Required ArduPilot FCU parameters

Set once via `bash src/indoor_2026/fc_scripts/set_ekf3_vision_params.sh` (requires
MAVROS connected). Reboot the FC afterwards.

| Parameter | Value | Purpose |
|---|---|---|
| `EK3_SRC1_POSXY` | `6` | ExternalNav horizontal position |
| `EK3_SRC1_VELXY` | `0` | None — no vision_speed is published |
| `EK3_SRC1_POSZ` | `1` | Barometer |
| `EK3_SRC1_VELZ` | `0` | None |
| `EK3_SRC1_YAW` | `6` | ExternalNav yaw |
| `VISO_TYPE` | `1` | Enable visual odometry |
| `SCR_ENABLE` | `1` | Enable Lua scripting, for `ekf_set_home.lua` |

Without these, MAVROS publishes vision messages and ArduPilot silently ignores them.

**`EK3_SRC1_VELXY` must be `0`, not `6`.** The ZED wrapper's `publishOdom()` never
fills `Odometry.twist`, so velocity is always exactly zero regardless of real motion.
Forwarding that would tell the EKF "velocity = 0" confidently during real motion —
worse than omitting it. The bridge publishes no vision_speed at all.

## Home-setting happens on the FC, in Lua

`src/indoor_2026/fc_scripts/ekf_set_home.lua`, copied to `APM/scripts/` on the
Pixhawk SD card. It watches EKF3 health and sets home once vision has been stable
~5 s, printing to the GCS Messages tab:

```
ekf_home: HOME SET from vision EKF — ready to arm
```

**Do not arm before that line.** Keep the drone stationary for the first ~20 s after
launch so the EKF converges before the stability window starts counting.

Requires an SD card in the Pixhawk 6C — no card → no scripting → no home-set → the
drone will not arm. *Whether a card is currently installed is unverified.*

`/mavros/estimator_status` is **not** a usable gate: it is fed by `EKF_STATUS_REPORT`
at whatever rate `SR2_EXTRA3` specifies, which defaults to `0` on Telem2, so the topic
never publishes. A ROS-side `ekf_home_watchdog` node held this logic between
2026-07-01 and 2026-07-08 and was removed.

## Bridge exclusivity

`sky_vision2` is the only package that runs `zed_mavros_bridge`. **Never run two
instances** — duplicate messages on `/mavros/mavros/pose` corrupt the EKF.

```bash
ros2 node list | grep zed_mavros_bridge   # must show exactly one
```

## What to check when the drone drifts

1. Confirm `ros2 topic hz /mavros/mavros/pose` is ~30 Hz.
2. Echo `/mavros/mavros/pose` — those values are **ENU**, before MAVROS converts.
   Move the drone toward its boot heading (which becomes NED North): `position.y`
   increases, because boot heading maps to ENU +Y after the yaw alignment.
3. Check `EK3_SRC1_POSXY=6` and `VISO_TYPE=1` are set on the FCU.
4. Confirm exactly one bridge node is running (above).
5. Confirm nothing else is publishing to `/mavros/mavros/pose` — see the open topic
   collision issue above; MAVROS's own `local_position` plugin publishes there too.
