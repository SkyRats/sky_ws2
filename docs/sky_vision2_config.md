# sky_vision2 Configuration Files

**Package:** `sky_vision2` (`src/sky_vision2/`)  
**Config directory:** `src/sky_vision2/config/`

Two configuration files control the DDS transport layer and the MAVROS plugin set. Neither contains application logic — they tune the middleware that the [`ZedMavrosBridge`](zed_mavros_bridge.md) and MAVROS nodes run on top of.

## Files

| File | Used by | Purpose |
|---|---|---|
| `fastdds_no_shm.xml` | `mavros_fc.launch.py` via `FASTRTPS_DEFAULT_PROFILES_FILE` | Forces DDS to use UDPv4 only; disables shared-memory transport |
| `apm_pluginlists_vision.yaml` | MAVROS via `pluginlists_yaml` parameter | Restricts MAVROS to only the plugins needed for vision-based flight |

Both files are installed to the package share directory by `setup.py` and resolved at launch time via `FindPackageShare('sky_vision2')`.

---

## fastdds_no_shm.xml

### Full content

```xml
<profiles xmlns="http://www.eprosima.com/XMLSchemas/fastRTPS_Profiles">
  <transport_descriptors>
    <transport_descriptor>
      <transport_id>udpv4</transport_id>
      <type>UDPv4</type>
    </transport_descriptor>
  </transport_descriptors>
  <participant is_default_profile="true">
    <rtps>
      <userTransports>
        <transport_id>udpv4</transport_id>
      </userTransports>
      <useBuiltinTransports>false</useBuiltinTransports>
    </rtps>
  </participant>
</profiles>
```

### What the two key settings do

| Setting | Effect |
|---|---|
| `useBuiltinTransports>false` | Disables FastDDS's default transport stack, which includes both shared-memory (SHM) and UDP |
| `userTransports` with `udpv4` | Re-enables only UDPv4, replacing the built-in stack |

The net result is that FastDDS behaves as it did before shared-memory transport was added (FastDDS 2.x and later): all inter-process communication goes over loopback UDP, never through `/dev/shm`.

### Why shared-memory transport causes problems with MAVROS

FastDDS shared-memory transport works by writing a type hash into a segment file under `/dev/shm` the first time a publisher or subscriber is created. If the MAVROS process is killed (e.g., `Ctrl+C`) and restarted, FastDDS creates a new segment entry. However, the old entry remains in `/dev/shm` until explicitly cleared or the machine reboots.

When MAVROS restarts and tries to match with the ZED driver (or any other running node), FastDDS reads both the new entry and the stale old entry. If the type hash from the old run differs from the new run (which can happen after a `colcon build` that changed a message type), DDS logs a type mismatch warning and refuses to connect the topics. The symptom is indistinguishable from a genuine type incompatibility: topics exist, nodes are running, but no messages flow.

```
# Symptom: silent no-message failure despite nodes running
ros2 topic hz /mavros/vision_pose/pose
# → no data
```

The stale-SHM problem is especially common during development when MAVROS is restarted frequently. UDPv4-only avoids it entirely because there is no persistent shared state between runs.

### How to activate

The environment variable `FASTRTPS_DEFAULT_PROFILES_FILE` must point to this XML file before any FastDDS participant is created. In practice this means setting it in the launch process environment, not after nodes have started.

`mavros_fc.launch.py` sets it automatically:

```python
env = {'FASTRTPS_DEFAULT_PROFILES_FILE': str(fastdds_profile_path)}
```

For manual invocation:

```bash
export FASTRTPS_DEFAULT_PROFILES_FILE=~/sky_ws2/install/sky_vision2/share/sky_vision2/config/fastdds_no_shm.xml
ros2 run mavros mavros_node ...
```

### Performance trade-off

Shared-memory transport is faster than loopback UDP for large messages (images, point clouds) because it avoids a kernel copy. For the odometry use case (small `Odometry` messages at 30 Hz), the difference is negligible — well under 1 ms of additional latency. The stability benefit far outweighs the cost.

| Transport | Latency | Stability | `/dev/shm` dependency |
|---|---|---|---|
| SHM (default) | Lowest (sub-ms) | Poor on MAVROS restart | Yes |
| UDPv4 only (this config) | Low (1–3 ms loopback) | Robust | No |

For high-bandwidth topics like camera images, consider keeping SHM enabled in a separate DDS profile scoped to the vision processing nodes only.

### Clearing stale SHM manually

If SHM is not disabled and a stale-segment problem is suspected:

```bash
rm -f /dev/shm/fastrtps_*
```

Then restart all ROS2 nodes. This is the workaround; the XML file is the permanent solution.

---

## apm_pluginlists_vision.yaml

### Full content

```yaml
/**:
  ros__parameters:
    plugin_allowlist:
      - sys_status
      - sys_time
      - command
      - local_position
      - global_position
      - home_position
      - imu
      - vision_pose
```

`vision_speed` was removed from this allowlist 2026-07-01 — the bridge no longer publishes vision_speed at all (the ZED wrapper's `publishOdom()` never fills `Odometry.twist`, so it would only ever forward a false zero-velocity measurement).

### Why this file exists — the cost of the default plugin set

MAVROS ships with over 50 plugins. By default, all of them load at startup. Each plugin:

- Subscribes to one or more MAVLink message streams, causing the FCU to send data the system does not use.
- Creates one or more ROS2 topics, polluting the topic graph.
- Runs one or more threads, consuming CPU on the Jetson (which is already busy with ZED SDK, computer vision, and the bridge node).

On the Jetson Orin NX, the difference in startup time between full plugins and this allowlist is approximately 4–8 seconds. The reduction in background CPU load is measurable during flight when the vision pipeline is under load.

### Per-plugin purpose table

| Plugin | ROS2 topic(s) / service(s) | Why included |
|---|---|---|
| `sys_status` | `/mavros/state`, `/mavros/battery_state` | Heartbeat monitoring; without this, no feedback that MAVROS is connected to FCU |
| `sys_time` | Clock sync (internal) | Synchronizes the ROS2 clock with the FCU clock; critical for timestamp alignment between ZED odom and IMU |
| `command` | `/mavros/cmd/arming`, `/mavros/cmd/takeoff`, `/mavros/mavros/set_home` | Arm, disarm, takeoff services, and `set_home` — called by `ekf_home_watchdog` (package `sky_vision2`, not the bridge itself) once vision is stable. See `.claude/rules/ekf_home_watchdog.md`. |
| `local_position` | `/mavros/mavros/pose`, `/mavros/mavros/odom`, etc. (not `/mavros/local_position/pose` — same namespace collapse as `vision_pose`, see `bridge_node.md`) | Intended as EKF output position for `ekf_home_watchdog`'s stability gating; in practice not actually streaming on this hardware (`SR2_POSITION` likely `0` on Telem2) — the watchdog ends up watching the bridge's own outgoing pose instead. See `.claude/rules/ekf_home_watchdog.md` |
| `global_position` | `/mavros/global_position/global` | GPS global position — **not required** for `set_home` with `current_gps=True`: ArduPilot's `handle_command_do_set_home` (`GCS_Common.cpp`) resolves "current location" via `ahrs.get_location()`, which reflects the ExternalNav/EKF3 position estimate even with no real GPS fix. Kept in the allowlist for `/mavros/home_position/home` debugging visibility and general telemetry. |
| `home_position` | `/mavros/home_position/home` | Publishes current home position; useful for debugging whether auto-set home succeeded |
| `imu` | `/mavros/imu/data` | FCU IMU data; needed for any mission that uses attitude information |
| `vision_pose` | `/mavros/mavros/pose` (subscriber — see `sky_vision2`'s `bridge_node.md` for why not `/mavros/vision_pose/pose`) | **Core input:** receives position from bridge, forwards to FCU via `VISION_POSITION_ESTIMATE` |

### What happens when a plugin is missing

Missing the wrong plugin causes silent, hard-to-diagnose failures:

| Missing plugin | Symptom |
|---|---|
| `vision_pose` | Bridge publishes but FCU never receives position. EKF uses only IMU + baro. Drone drifts immediately in GUIDED. |
| `command` | `arm()`, `takeoff()`, and `ekf_home_watchdog`'s `set_home` service calls return "service not available". |
| `sys_status` | `/mavros/state` has no publisher. Code that waits for `state.connected == True` hangs forever. |
| `sys_time` | ZED odometry timestamps drift relative to FCU timestamps. EKF may reject measurements as "too old" or "from the future". |
| `home_position` | No way to confirm `set_home` actually took effect via `/mavros/home_position/home` (the call itself is unaffected — see `global_position` row above). |

### How MAVROS loads this file

The `pluginlists_yaml` parameter is passed to the MAVROS node at launch:

```python
Node(
    package='mavros',
    executable='mavros_node',
    parameters=[
        {'pluginlists_yaml': str(pluginlists_path)},
        ...
    ]
)
```

MAVROS reads the file at node startup and builds the plugin set before processing any MAVLink messages. Adding or removing plugins requires restarting the MAVROS node — it does not support hot reload.

### Extending the allowlist

If a new mission requires a MAVROS capability not currently in the list, add the plugin name to `plugin_allowlist` and rebuild:

```bash
colcon build --packages-select sky_vision2
source install/setup.bash
```

Find available plugin names by listing the MAVROS plugin library directory or checking the [MAVROS plugin documentation](http://wiki.ros.org/mavros/Plugins). Plugin names in the YAML correspond to the plugin's registered name, not the file name.

---

## Config file install path

Both files must be installed to the package share directory. In `setup.py`:

```python
(os.path.join('share', package_name, 'config'), glob('config/*'))
```

After `colcon build`, the files are at:

```
install/sky_vision2/share/sky_vision2/config/fastdds_no_shm.xml
install/sky_vision2/share/sky_vision2/config/apm_pluginlists_vision.yaml
```

The launch files use `FindPackageShare('sky_vision2') / 'config' / 'filename'` to resolve these paths. Editing the source files under `src/sky_vision2/config/` has no effect until a rebuild copies them to the install tree.

## See also

- [ZedMavrosBridge](zed_mavros_bridge.md) — the node that depends on both config files being correct
- [sky_vision2 launch files](sky_vision2_launch.md) — how the config files are loaded at startup (and the FastDDS inconsistency between launch files)
- [launch](launch.md) — the older indoor_2026 launch file, which does not use these configs
