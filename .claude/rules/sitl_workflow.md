# SITL Workflow

## ArduPilot SITL (standalone, no ROS)

```bash
# Terminal 1 — ArduCopter SITL
cd ~/ardupilot/ArduCopter
sim_vehicle.py --console --map -w

# Verify with MAVProxy (separate terminal)
mavproxy.py --console --map --aircraft test --master=:14550
```

SITL FCU URL for MAVROS: `tcp://127.0.0.1:5760`

## SITL + synthetic ZED odom (no hardware needed)

The practical way to test the full vision→EKF pipeline in simulation:

```bash
# Terminal 1 — ArduCopter SITL
cd ~/ardupilot/ArduCopter && sim_vehicle.py -w

# Terminal 2 — MAVROS + bridge against SITL FCU
export ROS_DOMAIN_ID=42
cd ~/sky_ws2 && source install/setup.bash
ros2 launch sky_vision2 mavros_fc.launch.py fcu_url:=tcp://127.0.0.1:5760

# Terminal 3 — synthetic ZED odometry
export ROS_DOMAIN_ID=42
ros2 run sky_vision2 test_zed_odom
```

`test_zed_odom` publishes circular odom at 30 Hz on `/zed/zed_node/odom` (BEST_EFFORT). The bridge will pick it up and forward transformed poses and velocities to MAVROS.

## SITL + Gazebo

```bash
cd ~/sky_ws2
source install/setup.bash
ros2 launch ardupilot_gz_bringup iris_runway.launch.py
```

Requires Gazebo Harmonic: `export GZ_VERSION=harmonic` in `.bashrc`.

## zed_mavros_sitl.launch.py FastDDS workaround

`src/sky_vision2/launch/zed_mavros_sitl.launch.py` does not set `FASTRTPS_DEFAULT_PROFILES_FILE`. Clear stale SHM before using it:

```bash
rm -f /dev/shm/fastrtps_*
export ROS_DOMAIN_ID=42
export FASTRTPS_DEFAULT_PROFILES_FILE=$(ros2 pkg prefix sky_vision2)/share/sky_vision2/config/fastdds_no_shm.xml
ros2 launch sky_vision2 zed_mavros_sitl.launch.py fcu_url:=tcp://127.0.0.1:5760
```

Or just use `mavros_fc.launch.py` with a SITL `fcu_url` — it has the SHM fix built in.

## Kill everything

```bash
pkill -9 -f "mavros|zed|ros2 launch|sim_vehicle"
rm -f /dev/shm/fastrtps_*
```
