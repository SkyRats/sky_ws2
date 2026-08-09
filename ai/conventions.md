# Conventions

Workspace-wide rules. Per-repo specifics live in that repo's `CLAUDE.md`.

## DDS domain — required in every terminal

```bash
export ROS_DOMAIN_ID=42
```

Forgetting this is the most common reason `ros2 node list` and `ros2 topic list`
come back empty. Nothing is broken; you are on a different domain.

## QoS

| Publisher | Required subscriber QoS | Why |
|---|---|---|
| ZED topics (`/zed/zed_node/*`) | **BEST_EFFORT** | The ZED driver publishes BEST_EFFORT; a RELIABLE subscriber gets no data, silently |
| MAVROS topics | RELIABLE (default) | Standard default is fine |

ROS 2 does not warn on a QoS mismatch. It just never connects.

## ROS 2 callbacks must not block

Timer and subscription callbacks run on the executor thread. No `time.sleep()`, no
blocking service calls (use `call_async`), no heavy CV work inside a callback —
blocking the executor degrades every message rate in the node.

Missions are the deliberate exception and they handle it correctly:
`indoor_2026`'s `Auxiliary` spins its nodes on a `SingleThreadedExecutor` in a
background daemon thread, so the mission's own blocking calls and sleeps run on the
main thread and never sit inside a callback.

In `SkyMAVLink` missions the equivalent rule is: **never `time.sleep()`** — call
`mav.sleep()`, which keeps the 20 Hz setpoint tick loop running. A bare `time.sleep()`
stops setpoints and `GUID_TIMEOUT` brakes the drone mid-manoeuvre.

## Build and source sequence

```bash
cd ~/sky_ws2
colcon build --packages-select sky_vision2 indoor_2026
source install/setup.bash        # re-source after EVERY build
```

Launch files resolve installed paths via `FindPackageShare`, so an unbuilt or
unsourced package fails at launch, not at build.

`sky_navigation` is **not** a colcon package — no `package.xml`, no `setup.py`.
Including it in `--packages-select` fails. Install it once with pip:

```bash
pip install -e ~/sky_ws2/src/sky_navigation
```

> Before deleting or rebuilding `install/`, read `ai/decisions.md` entry #2. Mission
> code currently depends on a module that survives only there.

## FastDDS shared memory

`config/fastdds_no_shm.xml` disables the DDS shared-memory transport. It must be
active when MAVROS starts, or stale `/dev/shm` entries from prior runs cause type
mismatches that look exactly like "the topic exists but carries no data".

`zed_mavros_fc.launch.py` and `mavros_fc.launch.py` set it automatically. The `sitl`
variants do **not** — clear SHM first:

```bash
rm -f /dev/shm/fastrtps_*
```

## Documentation rules

- **Verify before you write.** A claim about a topic, parameter, frame, or device goes
  in only after grepping current source for it. Most of the staleness cleared on
  2026-08-08 was confidently-worded text describing code that had been deleted.
- **Hardware-adjacent content is quoted, never paraphrased.** Parameter values, wiring,
  ESC config, frame conventions, clearance figures. Paraphrasing a param value is how
  a vehicle gets damaged.
- **Cross-repo facts go in `ai/interfaces.md`**, not in two repos' `CLAUDE.md`. Four
  duplicated rule files drifted into mutual contradiction before this was a rule.
- **Decisions with a rationale go in `ai/decisions.md`**, never in a journal. Journals
  record what happened; decisions record why, and supersede rather than get edited.
- **Superseded docs get a header, not a deletion**, when they hold research worth
  keeping — say plainly what is no longer true and point at the current reference.
- **If a fact is not written down anywhere and it matters, say so and ask.** Never
  infer pin assignments, frame conventions, or parameter values.

## Git

The nested repositories are pinned by `sky_ws2.repos` (vcstool), not submodules — see
`ai/decisions.md` entry #1. Consequences for everyday work:

- Commit inside the repo you changed. The root does not track a pointer to it.
- Never `git add` a path in the root that contains a nested repo. Stage explicit
  individual file paths.
- If git prints "adding embedded git repository", stop — something is misconfigured.
