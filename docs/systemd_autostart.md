# Boot Autostart — `skyrats-vision.service`

**Source:** `scripts/skyrats-vision.service` (installed to `/etc/systemd/system/`), `scripts/start_vision_stack.sh`
**Installs to:** `/etc/systemd/system/skyrats-vision.service`, enabled via `systemctl enable --now`

Starts the full production vision stack (ZED + MAVROS + `zed_mavros_bridge`) automatically every time the Jetson boots, so the drone doesn't need a manual `ros2 launch` after power-on.

## Unit file

```ini
[Unit]
Description=SkyRats ZED + MAVROS vision bridge (sky_vision2)
After=network.target multi-user.target
Wants=network.target

[Service]
Type=simple
User=skyrats
Group=skyrats
Environment=HOME=/home/skyrats
Environment=ROS_DOMAIN_ID=42
ExecStart=/home/skyrats/sky_ws2/scripts/start_vision_stack.sh
Restart=on-failure
RestartSec=5
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
```

`ROS_DOMAIN_ID=42` is set in **two** places — the unit's `Environment=` line and inside `start_vision_stack.sh` itself (`export ROS_DOMAIN_ID=42` before the `ros2 launch`). The script's export is what actually matters at runtime; the unit-level one is redundant but keeps the domain ID visible via `systemctl cat skyrats-vision.service` without having to open the script.

## start_vision_stack.sh

```bash
#!/bin/bash
set -e
rm -f /dev/shm/fastrtps_*          # clear stale FastDDS entries from a prior crashed run
source /opt/ros/humble/setup.bash
source /home/skyrats/sky_ws2/install/setup.bash
export ROS_DOMAIN_ID=42
exec ros2 launch sky_vision2 zed_mavros_fc.launch.py
```

`/dev/shm` is tmpfs and clears on a real reboot, but a `Restart=on-failure` retry (without a full reboot) can leave stale FastDDS type-signature entries from the crashed run — clearing them before every start avoids topics that appear alive but carry no data (same class of bug as the FastDDS SHM issue described in `sky_vision2_config.md`).

## Deploying changes

The unit file is version-controlled at `scripts/skyrats-vision.service`. `sudo` has no passwordless helper on this Jetson, so applying it requires manual steps (Claude Code running here cannot run `sudo` itself):

```bash
sudo cp /home/skyrats/sky_ws2/scripts/skyrats-vision.service /etc/systemd/system/skyrats-vision.service
sudo systemctl daemon-reload
sudo systemctl restart skyrats-vision.service   # or `enable --now` if not yet enabled
```

## Verifying it actually autostarts

`enabled` in `systemctl is-enabled` only means the symlink exists in `multi-user.target.wants/` — it does **not** confirm the service survives a real reboot. Compare boot time against the service's start time:

```bash
uptime -s                                                            # system boot time
systemctl show skyrats-vision.service -p ActiveEnterTimestamp        # service start time
```

If the service's start time is more than a few seconds after boot, either it failed and got restarted later (`journalctl -u skyrats-vision.service -b`), or it was `enable --now`'d manually after boot rather than actually starting from systemd — confirmed this workspace's first deploy (2026-07-01) was exactly that: five rounds of `cp` + `enable --now` while iterating on the unit file, on a system that had already booted 80+ minutes earlier. It was verified to genuinely autostart only after an actual `sudo reboot` test.

## Runtime checks

```bash
systemctl status skyrats-vision.service --no-pager -l
journalctl -u skyrats-vision.service -b --no-pager   # this boot's logs only
```

Healthy startup shows, in order: ZED node loading configs → `robot_state_publisher`/`component_container_isolated`/`mavros_node`/`zed_mavros_bridge` processes starting → mavros `FCU: EKF3 IMU0 is using external nav data` → bridge's `Vision data flowing — ready to arm once EKF converges`. `FCU: PreArm: RC not found` is expected noise with no RC transmitter bound and is not a failure.

## Checking from another terminal (or another machine)

`ROS_DOMAIN_ID` is per-shell, not global — the service having it set does not make it visible in a terminal that hasn't exported it too:

```bash
export ROS_DOMAIN_ID=42
ros2 topic list
```

If this comes back with only `/parameter_events` and `/rosout` (the two topics that always exist), the domain ID isn't exported in *that* shell — it's not a sign the service is broken.

## Visualizing live pose in rviz2

No drone-body URDF/mesh exists in this workspace (only the ZED camera's own housing, via `zed_wrapper`'s URDF). Visualization means watching the camera's TF frame move, not a rendered quadcopter.

The ZED wrapper publishes a fully world-anchored, live-updating TF tree by itself (`publish_tf: true`, `publish_map_tf: true` in `zed_wrapper`'s `common_stereo.yaml`):

```
map → odom → zed_camera_link (moving live) → zed_camera_center → left/right camera frames
```

From a laptop on the same LAN as the Jetson (same subnet — default DDS multicast discovery works, no extra config needed), with ROS2 Humble installed and `ROS_DOMAIN_ID=42` exported:

```bash
rviz2
```

- **Fixed Frame** → `map`
- **Add → TF** — shows `zed_camera_link` moving live
- **Add → Odometry**, topic `/zed/zed_node/odom`, Keep: 100 — draws a breadcrumb trail
- **Add → Path**, topic `/zed/zed_node/path_odom` — full trajectory line instead of individual arrows

Building an actual drone-shaped model (URDF + a transform chain down to it) is possible but doesn't exist yet — the axes/arrow view is what's available today.
