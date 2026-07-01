#!/bin/bash
# start_vision_stack.sh
#
# Launches the production ZED + MAVROS + zed_mavros_bridge stack. Meant to be
# run by the skyrats-vision.service systemd unit at boot, not run manually
# (use `ros2 launch sky_vision2 zed_mavros_fc.launch.py` directly for that).

set -e

# /dev/shm is tmpfs and clears on reboot, but a systemd Restart=on-failure
# retry (without a full reboot) can leave stale FastDDS entries from the
# crashed run — clear them before every start.
rm -f /dev/shm/fastrtps_*

source /opt/ros/humble/setup.bash
source /home/skyrats/sky_ws2/install/setup.bash
export ROS_DOMAIN_ID=42

exec ros2 launch sky_vision2 zed_mavros_fc.launch.py
