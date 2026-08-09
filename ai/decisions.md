# Decisions

Architectural decisions with rationale. A decision belongs here, never in a
journal. Newest last. Never edit a past entry's decision — supersede it with a
new entry that links back.

---

## Open items — carried forward from 2026-08-08

Six things were deliberately left undone. None is forgotten; none is safe to
assume resolved. Check this list before planning work in this tree.

| # | Item | Owner | Blocks |
|---|---|---|---|
| 1 | `ai/retire-submodules.sh` written but **unrun** | needs #2 first | the vcstool migration in entry #1 below |
| 2 | `src/outdoor_2025` has 5 uncommitted files, now **invisible** to main's `git status` because `/src/*` is gitignored | Eduardo commits + pushes | #1 |
| 3 | `src/sky_sim2` at detached HEAD, 1 commit behind `origin/main`; pinned by SHA in `sky_ws2.repos` | Eduardo fixes HEAD, then the pin becomes `main` | nothing |
| 4 | **SD card presence in the Pixhawk 6C is unverified.** Written as *unverified* in 4 places rather than guessed | Eduardo checks the FC physically | arming — no card means no Lua, no home-set, no arm |
| 5 | `DroneMotion` broken import — entry #2 below | undecided | **every mission, on the next clean build** |
| 6 | `sky_mavlink` component 191 collision — entry #3 below | out of writable scope | any mission run from that checkout |

Item 4 is the one most likely to waste a field session. Items 5 and 6 are the two
that can bite in the air.

---

## 1. Workspace reproducibility: vcstool manifest for every nested repo; git submodules retired

**Date:** 2026-08-08
**Status:** decided, not yet executed
**Scope:** `sky_ws2` root — how the 14 nested repositories are pinned and restored

### Context

The workspace root tracks 14 nested git repositories. Only 3 of them
(`src/sky_vision2`, `src/indoor_2026`, `src/sky_navigation`) are git submodules;
the other 11 are untracked working clones that appear in `git status` as `??`
entries. A fresh machine cannot reconstruct the workspace: 11 of 14 repos exist
nowhere in main's history.

Both stale gitlinks confirm the submodule mechanism is not being maintained:

| Submodule | Pointer in main's index | Actual worktree HEAD |
|---|---|---|
| `src/indoor_2026` | `0fa856cc` | `4458e661` |
| `src/sky_navigation` | `f41532e1` | `f41532e1` (in sync) |
| `src/sky_vision2` | `5c226bfd` | `d1ba5d6a` |

Two of three pointers have drifted. Nobody has been running
`git add src/<repo> && git commit` after work in a submodule.

### Decision

One mechanism for all 14: a `sky_ws2.repos` vcstool manifest at the repo root.
Git submodules are retired — the 3 gitlinks are removed from main's index and
`.gitmodules` is deleted.

Pinning strategy:

- **Ours (6 nested SkyRats repos):** `version:` is the **branch name**. Daily work
  is on these; a branch name means `vcs pull` gets teammates' work without a
  pointer-bump commit in main.
- **Vendored (8 upstream repos):** `version:` is an **exact SHA**, or an upstream
  tag when the current SHA is exactly on one. These must not move under us.
- **Milestones:** `vcs export --exact` writes a lock snapshot pinning all 14 to
  SHAs, committed as `ai/locks/<milestone>.repos`.

### Rejected alternatives

**All 14 as git submodules.** Rejected for two reasons. First, it multiplies
pointer-bump commits in main by roughly 6× — every commit in any of the 6 active
SkyRats repos needs a follow-up commit in main to move its gitlink, and the table
above shows the team already does not do this for 3. Second, `src/ardupilot`
declares 15 recursive submodules of its own; making it a submodule of main makes
`git clone --recursive` the workspace's setup command and drags all 15 into
main's clone story, including ChibiOS and the DroneCAN tree.

**3 submodules kept + 17 in a manifest (status quo, extended).** Rejected because
it leaves two update commands and two answers to "how do I pin this". The split is
not principled — the 3 submodules are submodules for historical reasons, not
because they differ in kind from `src/sky_mavlink` or `src/outdoor_2025`.

### Known consequences

- Removing a gitlink from main's index is a commit that changes what main tracks.
  The nested worktrees are untouched — `git rm --cached` only.
- `Micro-XRCE-DDS-Gen` declares 2 submodules of its own. vcstool does **not**
  recurse; they must be initialised with a separate `git submodule update --init`
  after `vcs import`. Same for `src/ardupilot`'s 15.
- `src/sky_sim2` is at a detached HEAD (`125c71ac`) with no branch. It cannot get
  a branch-name pin until that is resolved.

### Blocking prerequisite

`src/outdoor_2025` has 5 uncommitted changes (`TASK3/scripts/PID_controller.py`,
`TASK3/scripts/enu_utils.py`, `TASK3/scripts/follower.py`, deleted
`outdoor/__init__.py`, `setup.py`). Once `/src/*` is gitignored these become
invisible to main's `git status`, so they must be committed and pushed in
`outdoor_2025` **before** the manifest is adopted.

---

## 2. `indoor_2026` missions depend on a module that no longer exists in source

**Date:** 2026-08-08
**Status:** OPEN — fix undecided. Read this before touching any mission.
**Scope:** `src/indoor_2026`, `src/sky_navigation`

### Symptom

`src/indoor_2026/indoor_2026/auxiliary.py:32`:

```python
from sky_navigation.drone_motion import DroneMotion
```

`src/sky_navigation/` contains only `pyproject.toml`, `README.md`,
`requirements.txt`, `skymavlink/`, `tests/`. There is **no `sky_navigation` Python
package and no `drone_motion.py` in source anywhere in this workspace.**

The import resolves today only because stale build output is still on the path:

```
install/sky_navigation/lib/python3.10/site-packages/sky_navigation/drone_motion.py
install/indoor_2026/lib/python3.10/site-packages/indoor_2026/drone_motion.py
```

`ros2 run indoor_2026 square_test` therefore works from a sourced `install/` tree and
**breaks the moment anyone deletes `install/` or builds on a fresh machine.** It will
not survive the vcstool reconstruction in entry #1.

### Why it is open

`sky_navigation` was rewritten around `SkyMAVLink` (pure pymavlink, NED/FRD, no
rclpy). `DroneMotion` was the old MAVROS-setpoint API (ENU/FLU, `setpoint_position/local`
and `setpoint_velocity/cmd_vel`). Missions were never ported. The candidate fixes are
not equivalent and none has been chosen:

- port `Auxiliary`/`square_test` to `SkyMAVLink` — matches the current architecture,
  but flips the mission's frame conventions from ENU/FLU to NED/FRD and means MAVROS
  stops carrying commands the way `flight_stack.md` describes;
- restore `drone_motion.py` into `sky_navigation` — smallest change, but re-adds a
  second command path alongside `SkyMAVLink` and contradicts the split documented in
  the root `CLAUDE.md`;
- vendor `DroneMotion` into `indoor_2026` — unblocks missions without touching
  `sky_navigation`, at the cost of a fork.

Recovering the deleted file: `git -C src/sky_navigation log --diff-filter=D --  '*drone_motion*'`,
or copy it out of `install/` before that tree is cleaned.

### Do not

Do not run `rm -rf install/` or `colcon build --cmake-clean-cache` on a machine that
needs to fly before this is resolved. That is currently the only thing keeping
missions runnable.

---

## 3. `sky_mavlink` transmits as MAVLink component 191 — collides with MAVROS

**Date:** 2026-08-08
**Status:** OPEN — flight hazard, out of writable scope, left live deliberately
**Scope:** `src/sky_mavlink` (and its divergence from `src/sky_navigation`)

### The collision

Two checkouts of the same library disagree on their MAVLink identity:

```
src/sky_mavlink/skymavlink/core.py:54     endpoint, source_system=1, source_component=191
src/sky_navigation/skymavlink/core.py:24  _SRC_COMPONENT = 192  # MAV_COMP_ID_ONBOARD_COMPUTER2
```

MAVROS itself transmits as `(sysid 1, compid 191)` — `MAV_COMP_ID_ONBOARD_COMPUTER`.
Since MAVROS now owns the FC serial port and relays the raw stream to mission code
over its `gcs_url` endpoint (see the root `CLAUDE.md`), a mission run from the
`sky_mavlink` checkout puts **two endpoints with the same MAVLink address on one
link**. Targeted FC replies — `COMMAND_ACK` above all — become ambiguous to the
MAVROS router. `sky_navigation` was moved to 192 to fix exactly this; `sky_mavlink`
was not.

### Why it is still live

`src/sky_mavlink` and `src/sky_navigation` are both outside the writable scope set
for this restructure (`sky_ws2`, `sky_vision2` @ `imav_2026`, `indoor_2026` @ `main`).
Neither the code nor its `.claude/rules/skymavlink.md` — which still documents an
`mavp2p` fan-out that is not installed — could be corrected here.

### Operational rule until it is fixed

**Run missions from `src/sky_navigation`, not `src/sky_mavlink`.** Confirm which one
is installed before flying:

```bash
python3 -c "import skymavlink, inspect; print(inspect.getsourcefile(skymavlink))"
```

If that path contains `sky_mavlink`, the component id is 191 and the link is
ambiguous. The two repos also disagree on their `.claude/rules/skymavlink.md`
Transport section by ~35 lines, describing different transports.
