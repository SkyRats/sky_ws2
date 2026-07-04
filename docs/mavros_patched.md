# Patched MAVROS overlay — vision_pose yaw-clamping fix

## Why

MAVROS's `vision_pose_estimate` plugin extracts roll/pitch/yaw from the incoming quaternion with
`Eigen::eulerAngles(2,1,0)` before sending `VISION_POSITION_ESTIMATE`. That Eigen call **clamps yaw
to `[0, π]`** — for NED headings in `(π, 2π)` it silently returns an alternate (but equivalent)
decomposition instead of the natural one. Symptom on hardware: yaw appears to freeze near `3.14 rad`
as the drone rotates through the south/west half of the compass. See
`src/sky_vision2/.claude/rules/yaw_frame_research.md` for the full derivation, and
[MAVROS #444](https://github.com/mavlink/mavros/issues/444) / [#1472](https://github.com/mavlink/mavros/issues/1472)
for upstream history — never fixed in `vision_pose_estimate` upstream.

Fork: **`git@github.com:odraudE31/mavros.git`**, branch **`fix/vision-pose-yaw-clamping`**
(1 commit ahead of upstream `ros2`) — replaces the Eigen decomposition in `quaternion_to_rpy` with an
atan2-based ZYX decomposition that doesn't clamp.

This lets the bridge keep using the plain `vision_pose` pipeline (see `bridge_node.md`) without
needing the `mocap_pose_estimate` workaround that was used at one point to sidestep this bug.

## How it's wired into `sky_ws2`

Only the `mavros` package (where `libmavros.so` and `quaternion_to_rpy` live) is overridden — `libmavconn`
and `mavros_msgs` still come from the apt install (`/opt/ros/humble`), since they're unaffected by the fix.

```bash
# One-time: clone the fork and symlink the mavros package into the workspace
mkdir -p ~/Repositories
git clone git@github.com:odraudE31/mavros.git ~/Repositories/mavros
cd ~/Repositories/mavros
git checkout fix/vision-pose-yaw-clamping

ln -s ~/Repositories/mavros/mavros ~/sky_ws2/src/mavros_patched

# Build just the overridden package
export ROS_DOMAIN_ID=42
cd ~/sky_ws2
colcon build --packages-select mavros
```

## Verify the overlay is active

```bash
source ~/sky_ws2/install/setup.bash
ros2 pkg prefix mavros
# must print ~/sky_ws2/install/mavros — NOT /opt/ros/humble
```

Any terminal that launches MAVROS (`mavros_fc.launch.py`, `zed_mavros_fc.launch.py`) must source
`~/sky_ws2/install/setup.bash` (after exporting `ROS_DOMAIN_ID=42`) for the patched `libmavros.so`
to be picked up. Restart MAVROS if it was already running against the apt build.

## Revert to apt MAVROS

```bash
rm ~/sky_ws2/src/mavros_patched
rm -rf ~/sky_ws2/install/mavros ~/sky_ws2/build/mavros
source ~/sky_ws2/install/setup.bash
ros2 pkg prefix mavros   # back to /opt/ros/humble
```
