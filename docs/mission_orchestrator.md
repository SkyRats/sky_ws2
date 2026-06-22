# Mission — Top-Level State Machine

**Source:** `src/imagens/indoor_2025/mission.py`

`Mission` sequences all competition tasks. It owns the `Mav` and `ZedSubscriber` nodes and drives a state machine from takeoff through each sub-mission to landing.

## States

```
TAKEOFF → MISSION_1 → TRAVELLING → LAND
                                 ↑
               (MISSION_2, MISSION_3, MISSION_4 stubs)
```

| State | `States` value | Description |
|-------|---------------|-------------|
| `TAKEOFF` | 0 | Arms and takes off to `ALTITUDE = 1.25 m` |
| `MISSION_1` | 1 | Gate traversal — delegates to `Mission_1` |
| `MISSION_2` | 2 | Stub (not implemented) |
| `MISSION_3` | 3 | Stub (not implemented) |
| `MISSION_4` | 4 | Landing pad — delegates to `Mission_4` |
| `TRAVELLING` | 5 | Inter-mission navigation (not implemented) |
| `DIVERTING` | 6 | Obstacle avoidance (not implemented) |
| `LAND` | 7 | Commands landing and stops the loop |

## Constructor

```python
Mission(mav: Mav, velocity: int, zed_node: ZedSubscriber)
```

Creates all sub-mission instances at startup. `velocity` is stored but currently unused (sub-missions use hardcoded velocities).

## `state_machine()`

Called repeatedly from the main loop. Each call advances the state machine by one step:

1. **TAKEOFF** — calls `mav.takeoff(height=1.25)`, then spins both nodes for 6 seconds to let the drone stabilize, then transitions to `MISSION_1`.
2. **MISSION_1** — delegates to `mission_1.run()`, which returns `(done, problem)`. If `problem=True` → LAND. If `done=True` → sleeps 5 s → TRAVELLING.
3. **LAND** — calls `mav.land()`, sets `running=False` to exit the loop.

## Entry point

```python
if __name__ == '__main__':
    rclpy.init()
    zed_node = ZedSubscriber()
    mav = Mav(debug=True)
    mission = Mission(mav=mav, velocity=0.25, zed_node=zed_node)
    time.sleep(5)

    while mission.running:
        rclpy.spin_once(mav, timeout_sec=0.01)
        rclpy.spin_once(zed_node, timeout_sec=0.01)
        mission.state_machine()
        time.sleep(0.01)
```

The main loop spins both nodes and calls `state_machine()` every ~10 ms. Position is printed each iteration for debugging.

## Error handling

| Exception | Action |
|-----------|--------|
| `KeyboardInterrupt` | Calls `mav.land()` |
| `RuntimeError` | Prints and exits (e.g. camera failure) |
| `Exception` | Prints unexpected error and exits |
| Finally | Destroys both nodes, shuts down rclpy |

If `takeoff()` fails, the state machine immediately transitions to LAND.

## See also

- [Mav](communication.md) — the MAVROS interface used for all movement
- [ZedSubscriber](zed_subscriber.md) — camera node passed to sub-missions
- [Mission_1](mission_1.md) — gate traversal sub-mission
- [Mission_4](mission_4.md) — landing pad sub-mission (partial)
