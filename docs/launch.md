# How to start MAVROS and ZED

Step-by-step guide for starting the drone's software stack on the Jetson.

---

## Before you start

Every terminal you open needs these two lines:

```bash
source ~/sky_ws2/install/setup.bash
export ROS_DOMAIN_ID=42
```

If you added them to your `.bashrc`, they run automatically on every new terminal.

---

## Option 1 — Everything in one command (recommended)

This starts the ZED camera, MAVROS, and the vision bridge all at once:

```bash
ros2 launch sky_vision2 zed_mavros_fc.launch.py
```

**Wait for this line in the logs:**
```
HOME SET from vision EKF — ready to arm
```

That means ArduPilot has a stable position estimate and you can arm the drone.

> This takes about 20–30 seconds from launch. Keep the drone still during that time.

---

## Option 2 — Start ZED and MAVROS in separate terminals

Use this if you need to restart MAVROS without restarting the ZED camera (ZED takes ~15 s to warm up).

**Terminal 1 — ZED camera:**
```bash
ros2 launch sky_vision2 zed.launch.py
```

Wait until you see ZED publishing (takes ~15 s):
```bash
# In a new terminal:
ros2 topic hz /zed/zed_node/odom   # should show ~30 Hz
```

**Terminal 2 — MAVROS + bridge:**
```bash
ros2 launch sky_vision2 mavros_fc.launch.py
```

Again, wait for:
```
HOME SET from vision EKF — ready to arm
```

---

## Option 3 — Full autonomous flight (competition)

This starts everything **and** automatically arms and takes off:

```bash
ros2 launch indoor_2026 full_flight_test.py
```

> Default takeoff altitude is 1.5 m. Change it with `takeoff_altitude:=2.0`.

Expected log sequence:
```
HOME SET from vision EKF — ready to arm
FCU conectado.
Modo GUIDED ativo.
Drone ARMADO.
Comando takeoff enviado para 1.5 m.
```

---

## Connecting to SITL instead of real hardware

Replace the default serial port with the SITL TCP address:

```bash
# Start ArduPilot SITL first (separate terminal):
cd ~/ardupilot/ArduCopter && sim_vehicle.py --console --map -w

# Then start MAVROS + bridge pointed at SITL:
ros2 launch sky_vision2 mavros_fc.launch.py fcu_url:=tcp://127.0.0.1:5760

# And inject fake ZED odometry (no real camera needed):
ros2 run sky_vision2 test_zed_odom
```

---

## Verify everything is working

Run these checks in a new terminal after launch:

```bash
# Is MAVROS connected to the flight controller?
ros2 topic echo /mavros/state --once
# Look for: connected: True

# Is the ZED publishing?
ros2 topic hz /zed/zed_node/odom
# Should be ~30 Hz

# Is the bridge forwarding data to ArduPilot?
ros2 topic hz /mavros/mavros/pose
# Should be ~30 Hz (no vision_speed — bridge doesn't publish it, see zed_mavros_bridge.md)
```

---

## Something's wrong — common fixes

**Topics exist but no data arrives after MAVROS restart:**
```bash
# Clear stale DDS shared memory and relaunch
rm -f /dev/shm/fastrtps_*
ros2 launch sky_vision2 mavros_fc.launch.py
```

**ZED odom topic not appearing:**
- ZED takes ~15 s to initialize. Wait and re-check.
- Make sure the ZED cable (USB-C) is plugged in.

**HOME SET never appears:**
- The EKF needs the drone to be still and the ZED to have good tracking. Check there's enough light and texture in the environment.
- Don't check `/mavros/estimator_status` — it never publishes on this hardware (`SR2_EXTRA3=0` on Telem2). Instead check `ros2 topic echo /mavros/mavros/pose` is moving and non-zero, and `ekf_home_watchdog`'s own log for "vision active" / "EKF stable" progress messages.

**MAVROS won't connect to Pixhawk:**
- Check the UART cable between Jetson and Pixhawk.
- Confirm your user is in the `dialout` group: `groups $USER | grep dialout`
- If not: `sudo usermod -aG dialout $USER` then log out and back in.

---

## Kill everything

```bash
pkill -9 -f "mavros|zed|ros2 launch"
rm -f /dev/shm/fastrtps_*
```

---

## Known issues

**Yaw is currently wrong.** Position (X, Y, Z) and velocity are verified correct on hardware, but the heading estimate from the vision EKF does not match physical orientation. Do not rely on yaw until this is fixed. Tracked in `sky_vision2/zed_mavros_bridge.py`.
