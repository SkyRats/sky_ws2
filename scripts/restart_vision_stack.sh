#!/bin/bash
# restart_vision_stack.sh
#
# Restarts the production ZED + MAVROS + zed_mavros_bridge stack
# (skyrats-vision.service). Requires sudo — run manually, not from Claude.

sudo systemctl restart skyrats-vision.service
