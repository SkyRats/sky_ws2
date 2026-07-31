# Session status — 2026-07-14

Handoff notes. Where things stand after pulling all repos and chasing down why the
drone could not take off.

---

## TL;DR

The **EKF origin bug is found, fixed, and verified on hardware**. It is not the last
blocker. Vision is currently dead (ZED publishes nothing), so the EKF has no position
source and `LOCAL_POSITION_NED` still does not flow.

Blocking flight right now:

1. **ZED camera not publishing** — `/zed/zed_node/odom` has `Publisher count: 0`.
2. **`PreArm: RC not found`** — blocks arming on its own.
3. **UART corruption at 921600** — lossy link, not yet understood.

---

## What was done

### Repos pulled

`sky_ws2` fast-forwarded 8 commits on `imav_2026`; submodules synced.

Upstream turned out to be a **rewrite, not an update**:

- `sky_navigation/drone.py` is **gone**. Replaced by `skymavlink` — pure pymavlink,
  NED-native, no rclpy.
- `sky_navigation` is **no longer a colcon package** (no `package.xml`). It is now
  pip-installed: `pip install -e src/sky_navigation`.
  The `colcon build --packages-select ... sky_navigation` line in CLAUDE.md is stale.
- `indoor_2026` migrated to the new NED API.

Builds clean; all 7 mission modules import.

### mavp2p installed

`mavp2p` was never installed — it is the router that owns the UART and fans it to
**14551 (MAVROS)** and **14552 (skymavlink)**. Without it nothing listens on 14552, so
`square_test` just hangs.

Installed v1.3.3 (arm64) to `~/.local/bin` (already on PATH). The shipped
`config/mavp2p.service` expects `/usr/local/bin/mavp2p` — needs sudo to place there.

Correct launch for missions:

```bash
ros2 launch sky_vision2 mavros_mavp2p_fc.launch.py \
    mavp2p_source:=serial:/dev/ttyTHS1:921600
```

`zed_mavros_fc.launch.py` is the **direct-serial** variant — MAVROS owns the UART, no
14552, missions cannot connect. Do not use it for missions.

### Submodules moved to branch tips

The superproject pinned `sky_navigation` and `indoor_2026` **behind** their own fixes
(notably `feat: auto-request LOCAL_POSITION_NED + ATTITUDE streams on connect`).
Both are now checked out at their `main` tips. **Superproject pointers are not yet
committed.**

---

## The EKF origin bug (FIXED)

### Root cause

Home and origin are **separate state** in ArduPilot:

| | gates |
|---|---|
| **home** | arming |
| **origin** | GUIDED takeoff |

EKF3 only self-sets the origin from **GPS or range beacons — never from ExternalNav**.
On a vision-only indoor drone, *nothing* set it. The old `ekf_set_home.lua` called
`ahrs:set_home()` only.

Result: the drone **arms fine**, then `MAV_CMD_NAV_TAKEOFF` returns
`MAV_RESULT_FAILED` — and because upstream `skymavlink.takeoff()` has **no
`COMMAND_ACK` check**, it swallows the rejection, spins out its timeout, logs
`reached 0.00 m`, and the mission flies its whole profile **on the ground**.

Confirmed on hardware: `HOME: SET`, `ORIGIN: NOT SET`, zero `LOCAL_POSITION_NED`.

### Fix

`src/indoor_2026/fc_scripts/ekf_set_home.lua` now calls `ahrs:set_origin()` as well as
`ahrs:set_home()`. Pushed to `indoor_2026` main as **`687d0f8`**.

Two earlier attempts were themselves broken — an `ahrs:get_origin()` pre-check
short-circuited `set_origin` entirely, then reported success and went silent, which
looked identical to "the file never got copied." The shipped version therefore:

- calls `set_origin` / `set_home` **unconditionally**, trusting only their return value
- retries them **independently** (a failing origin must not skip home)
- logs a **versioned heartbeat every 2 s that never stops** — so silence unambiguously
  means *this script is not the one running on the FC*

### Verified working

```
ORIGIN: SET  lat=10000000 lon=10000000
HOME  : SET  lat=10000000 lon=10000000
ekf_home v3: origin=true home=true
```

> **The FC runs the copy on its SD card, not the repo.** Any change needs copying to
> `APM/scripts/` and an FC reboot. Check with `grep set_origin` on the card's copy.

---

## Open blockers

### 1. ZED not publishing (current blocker)

```
ros2 topic info /zed/zed_node/odom
  →  Publisher count: 0     Subscription count: 1
```

The bridge is subscribed and waiting; nothing publishes. No ZED node in `ros2 node list`
— it never came up, rather than came up and went quiet. **Check the `zed.launch.py`
terminal for the startup error.**

Chain:

```
ZED publishing nothing
  → bridge forwards no odom
    → MAVROS sends no VISION_POSITION_ESTIMATE
      → EKF has no horizontal position source  →  CONST_POS_MODE
        → no LOCAL_POSITION_NED
```

EKF flags = **167**: `ATTITUDE`, `VELOCITY_HORIZ/VERT`, `POS_VERT_ABS`, **`CONST_POS_MODE`**.
`POS_HORIZ_REL` and `POS_HORIZ_ABS` are both **no** — confirming no vision reaches the EKF.

`mavros_mavp2p_fc.launch.py` does **not** start the camera. It must be launched separately:

```bash
export ROS_DOMAIN_ID=42
ros2 launch sky_vision2 zed.launch.py
```

Expected once healthy: `CONST_POS_MODE` clears, `POS_HORIZ_REL` → YES,
`LOCAL_POSITION_NED` starts flowing.

### 2. `PreArm: RC not found`

Repeating on the FC. Blocks arming outright, independent of origin/home. Either bind a
receiver or handle that prearm check on the FC.

### 3. UART corruption at 921600

mavp2p logs a steady flood of `invalid magic byte` — starting the moment the FC begins
streaming, not at heartbeat. Baud is correct (heartbeat parses), so the port is
**dropping bytes under load**. Data gets through (~1270 msgs/15 s) but lossy. Best guess
for why MAVLink FTP would never complete. Worth understanding before a real flight.

---

## Recommended next

**Port the `COMMAND_ACK` guard into `skymavlink/flight.py`.** Upstream `takeoff()` fires
`MAV_CMD_NAV_TAKEOFF` and spins on altitude until timeout — it never checks the ack. That
is *why this whole class of bug was invisible*: a refused takeoff logs `reached 0.00 m`
and the mission carries on. The guard turns it into a loud exception.

Reference implementation is preserved in the old `drone.py` (see backup below).

---

## Uncommitted / loose ends

- `sky_ws2` superproject: submodule pointers moved to branch tips, **not committed**.
- Backups of the pre-pull local work (dropped on request) are in the session scratchpad:
  `local_work_backup/` — `ekf_set_home.lua`, `drone.py` (has the `COMMAND_ACK` guard),
  and `.patch` files. **Scratchpad is session-scoped — copy anything worth keeping.**

### Gotchas worth remembering

- ZED topics are **BEST_EFFORT**. `ros2 topic echo` defaults to RELIABLE and silently
  receives nothing. Use `--qos-reliability best_effort`.
- If `ros2 node list` shows nothing, the CLI daemon is stale:
  `ros2 daemon stop && ros2 daemon start`.
- `pgrep -f zed` matches `zed_mavros_bridge` — it is **not** proof the camera is running.
  Use `ros2 topic info /zed/zed_node/odom` and read the publisher count.
