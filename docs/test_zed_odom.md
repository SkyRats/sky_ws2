# test_zed_odom — Synthetic ZED Odometry Test Tool

**Source:** `src/sky_vision2/sky_vision2/test_zed_odom.py`  
**Executable:** `test_zed_odom` (registered in `setup.py`)  
**Run with:** `ros2 run sky_vision2 test_zed_odom`

A self-contained test harness that publishes synthetic ZED odometry and verifies that [`ZedMavrosBridge`](zed_mavros_bridge.md) correctly forwards it to the MAVROS external vision topics. Allows full pipeline testing without a physical ZED camera.

## Why this tool exists

The [`ZedMavrosBridge`](zed_mavros_bridge.md) pipeline involves three moving parts — the ZED driver, the bridge node, and MAVROS — any of which can be down during development or integration. Diagnosing a silent failure (no messages on `/mavros/vision_pose/pose`) is much easier when the ZED input side can be ruled out by replacing it with a known-good synthetic source.

This tool lets a developer:

1. Confirm the bridge is running and receiving messages even without ZED hardware.
2. Verify the X-axis negation is applied correctly (publisher sends `x=2.0`, vision topic receives `x=-2.0`).
3. Confirm velocity is forwarded as well as position (the bridge publishes to both topics; this verifier reads both).
4. Do a quick sanity check after any change to the bridge's coordinate transform logic.

## Nodes

### ZedOdomPublisher

Publishes synthetic `nav_msgs/Odometry` messages at 30 Hz on the configurable topic (default `/zed/zed_node/odom`, matching the bridge's default input topic).

**Trajectory:** A circular path in the XY plane with a slow upward climb.

| Parameter | Value | Why |
|---|---|---|
| Radius | 2.0 m | Large enough to produce clearly non-zero X and Y |
| Angular velocity (ω) | 0.2 rad/s | Slow enough to resolve clearly in 30 Hz data |
| Z climb rate | 0.5 m/s | Exercises the Z channel without hitting ceiling limits quickly |
| Publish rate | 30 Hz | Matches actual ZED odometry rate |

**Kinematic equations:**

```
t  = elapsed time (seconds)

position.x = radius * cos(ω * t)        = 2.0 * cos(0.2t)
position.y = radius * sin(ω * t)        = 2.0 * sin(0.2t)
position.z = 0.5 * t

yaw        = ω * t                       (tangent to circle)

velocity.x = -radius * ω * sin(ω * t)  = -0.4 * sin(0.2t)
velocity.y =  radius * ω * cos(ω * t)  =  0.4 * cos(0.2t)
velocity.z = 0.5
```

The velocity is the analytic derivative of the position trajectory, so it is always tangent to the circle. **Note (2026-07-01): the bridge no longer forwards velocity at all** — the real ZED wrapper never populates `Odometry.twist`, so publishing a synthetic one here would test something the bridge intentionally discards. This synthetic `twist` field is unused by `BridgeVerifier` now; kept only in case velocity is derived from position in the bridge in the future.

**Quaternion:** Built from the instantaneous yaw using `_yaw_to_quaternion(yaw)`, a local helper that computes `(x=0, y=0, z=sin(yaw/2), w=cos(yaw/2))` — the standard quaternion for a pure Z rotation.

### BridgeVerifier

Subscribes to the bridge's pose output topic and reports statistics. No velocity subscription — the bridge doesn't publish vision_speed (removed 2026-07-01).

| Subscription | Type | What it checks |
|---|---|---|
| `/mavros/mavros/pose` (verified 2026-07-01 — not `/mavros/vision_pose/pose`, see `sky_vision2`'s `bridge_node.md` for why) | `geometry_msgs/PoseStamped` | Position is flowing |

**Per-message logging (every 30 pose messages):** Logs current position (x, y, z) from the vision topic. At 30 Hz this produces one log line per second — readable without being overwhelming.

**5-second summary:** Every 5 seconds, logs the total message count:

```
[BridgeVerifier] 5s summary: pose_msgs=150
```

The counter should increase at approximately 30 messages per 5 seconds. Stuck at zero indicates the bridge is not forwarding pose.

**No-message warning:** If the pose counter is still zero when the first summary fires (5 seconds after start), a warning is logged:

```
[BridgeVerifier] WARNING: no pose messages received — is the bridge running?
```

This catches the two most common failure modes: bridge node not started, or QoS mismatch between publisher and verifier.

## SingleThreadedExecutor choice

Both `ZedOdomPublisher` and `BridgeVerifier` run on a single `SingleThreadedExecutor` in `main()`. The cooperative scheduling is intentional:

- The publisher fires at 30 Hz via a timer callback.
- The verifier callbacks fire when messages arrive from the bridge (which in turn fires when the publisher's messages are processed by the bridge).
- There is no shared mutable state between the two nodes.

A `MultiThreadedExecutor` would also work but adds unnecessary complexity. The publish → bridge → verify latency chain is fully within the same process only if the bridge is embedded in the same executor, which it is not — the bridge is a separate process. The single-threaded executor is sufficient because neither node does blocking work.

## Three-terminal test workflow

```
Terminal 1 — start the bridge (if MAVROS is not running, start just the bridge):
    ros2 run sky_vision2 zed_mavros_bridge

Terminal 2 — start the test tool:
    ros2 run sky_vision2 test_zed_odom

Terminal 3 — optional, inspect raw topic values:
    ros2 topic echo /mavros/mavros/pose
```

Expected output in Terminal 2 after 5 seconds:

```
[ZedOdomPublisher] Publishing odom: x=2.000, y=0.000, z=0.000
[BridgeVerifier] pose x=-2.000  y=0.000  z=0.000
[BridgeVerifier] 5s summary: pose_msgs=150
```

## Verifying X-negation

The published odometry starts at `(x=2.0, y=0.0, z=0.0)` (cos(0)=1, sin(0)=0). After the bridge applies X negation, the vision_pose topic should show `x=-2.0`. Check the first BridgeVerifier log line:

```
[BridgeVerifier] pose x=-2.000  y=0.000  z=0.000
```

If `x=+2.000` appears (positive), the bridge is forwarding without negating — check whether the negation line in `_odom_cb` is present and not commented out.

As the trajectory progresses, the position rotates around the circle. The Y values will increase while X decreases (as `sin(ω*t)` grows and `cos(ω*t)` falls from 1). Because only X is negated, Y tracks identically between publisher and verifier:

```
Published:     x=+2.0 * cos(t)    y=+2.0 * sin(t)
Vision topic:  x=-2.0 * cos(t)    y=+2.0 * sin(t)
```

## What this tool does NOT test

| Gap | How to cover it |
|---|---|
| `ekf_home_watchdog`'s `set_home` gating and service call | Not exercised by this tool directly — run `ekf_home_watchdog` alongside this tool against SITL (`ros2 launch sky_vision2 mavros_fc.launch.py fcu_url:=tcp://127.0.0.1:5760`) and watch its log / `ros2 topic echo /mavros/home_position/home` |
| Actual QoS match with ZED driver | Requires the real ZED driver or a publisher with BEST_EFFORT QoS |
| Bridge restart after MAVROS restart | Manual test — restart both nodes, verify topic resumes |

## See also

- [ZedMavrosBridge](zed_mavros_bridge.md) — the node this tool tests
- [sky_vision2 launch files](sky_vision2_launch.md) — how to start the full stack for hardware testing
- [sky_vision2 config](sky_vision2_config.md) — FastDDS profile that may affect topic delivery during testing
