# Install and setup

## Cloning this Repository

To clone this repository, and all of its submodules, use the following command:
```
git clone --recursive git@github.com:SkyRats/sky_ws2.git
```

# WARNING: DO NOT use sudo unless the instructions specify it's usage.

## ROS2 install
This repo uses ROS2 humble. Follow the instructions to install in: https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html

### Desktop install
Recomended desktop and dev-tools install.

### SBC install
Recomended ros-base and dev-tools install.

Set up on your .bashrc (or .zshrc):
```
source /opt/ros/humble/setup.zsh
```

## Ardupilot

This is based on ardupilot's documentations, available in: https://ardupilot.org/dev/docs/ros.html

## Setting up the build environment
For more details, see: https://ardupilot.org/dev/docs/building-setup-linux.html#building-setup-linux

First we setup the build environment that contains simulation code (and more) from Ardupilot:

```
git clone --recurse-submodules https://github.com/ArduPilot/ardupilot.git
cd ardupilot

Tools/environment_install/install-prereqs-ubuntu.sh -y
. ~/.profile
```

## ROS2 + Ardupilot
For more details, see: https://ardupilot.org/dev/docs/ros2.html

Go to sky_ws2 and clone the repos necessary using vcs:
```
source ~/.bashrc
cd ~/sky_ws2
vcs import --recursive --input  https://raw.githubusercontent.com/ArduPilot/ardupilot/master/Tools/ros2/ros2.repos src
```

Update dependencies:
```
sudo apt update
rosdep update
source /opt/ros/humble/setup.bash
rosdep install --from-paths src --ignore-src -r -y
```

We have another dependency that (may) be useful in the future if we decide to not use MAVROS2 for communication with the drone. In that case we need to install MicroXRCEDDSGen:

```
sudo apt install default-jre
cd ~/sky_ws2
git clone --recurse-submodules https://github.com/ardupilot/Micro-XRCE-DDS-Gen.git
cd Micro-XRCE-DDS-Gen
./gradlew assemble
echo "export PATH=\$PATH:$PWD/scripts" >> ~/.bashrc
```

Finally, lets build the workspace using colcon:
```
cd ~/sky_ws2
colcon build --packages-up-to ardupilot_dds_tests
```

We now have all that is necessary to start configuring SITL.

## Simulation (SITL)

This simulation is based on gazebo harmonic (or garden, but not recommended). 

### Ardupilot software in the loop
See https://ardupilot.org/dev/docs/setting-up-sitl-on-linux.html for more details

When we built our ardupilot environment we also built the SITL provided. Now make sure you have mavproxy (a byte-sized ground control station):
```
pip install --upgrade pymavlink MAVProxy --user
```

At this point you should be able to run a simulation (after a compiling period) using:
```
cd ~/ardupilot/ArduCopter
sim_vehicle.py --console --map -w
```

If all is good, go ahead to the next session and install the gazebo harmonic version used in sky_sim2 

### SITL + ROS2
For more details, see: https://ardupilot.org/dev/docs/ros2-sitl.html#

We now need to integrate our new SITl system with ROS2. To do that we will need to:

```
source /opt/ros/humble/setup.bash
cd ~/sky_ws2
colcon build --packages-up-to ardupilot_sitl
source install/setup.bash
ros2 launch ardupilot_sitl sitl_dds_udp.launch.py transport:=udp4 refs:=$(ros2 pkg prefix ardupilot_sitl)/share/ardupilot_sitl/config/dds_xrce_profile.xml synthetic_clock:=True wipe:=False model:=quad speedup:=1 slave:=0 instance:=0 defaults:=$(ros2 pkg prefix ardupilot_sitl)/share/ardupilot_sitl/config/default_params/copter.parm,$(ros2 pkg prefix ardupilot_sitl)/share/ardupilot_sitl/config/default_params/dds_udp.parm sim_address:=127.0.0.1 master:=tcp:127.0.0.1:5760 sitl:=127.0.0.1:5501
```

Lets see if it worked using:
```
mavproxy.py --console --map --aircraft test --master=:14550
```

We are almost done! We now need to install and configure gazebo harmonic.

### Gazebo harmonic and SITL
For more details, see: https://ardupilot.org/dev/docs/ros2-gazebo.html#ros2-gazebo

Lets first ensure you have gazebo installed:

```
sudo apt-get update
sudo apt-get install curl lsb-release gnupg

sudo curl https://packages.osrfoundation.org/gazebo.gpg --output /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] https://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null
sudo apt-get update
sudo apt-get install gz-harmonic
```

A common error when compiling is that some dependencies may not be installed. Install them using:
```
sudo apt update
sudo apt-get install libgflags-dev
sudo apt install ros-humble-actuator-msgs
sudo apt install ros-humble-gps-msgs
sudo apt install ros-humble-vision-msgs
sudo apt install libgz-sim8-dev rapidjson-dev
sudo apt install libopencv-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl
```

You should also set the gazebo version to harmonic in your ~/.bashrc file
```
export GZ_VERSION=harmonic
```

Enter our repo and then: 
```
cd ~/sky_ws2
vcs import --input https://raw.githubusercontent.com/ArduPilot/ardupilot_gz/main/ros2_gz.repos --recursive src
```


You should then add the Gazebo APT sources:
```
sudo apt install wget
wget https://packages.osrfoundation.org/gazebo.gpg -O /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null
sudo apt update

```


And add it to rosdep (as ROS2 humble and Gazebo Harmonic are not the default pairing)
```
sudo wget https://raw.githubusercontent.com/osrf/osrf-rosdep/master/gz/00-gazebo.list -O /etc/ros/rosdep/sources.list.d/00-gazebo.list
rosdep update
```

Update the dependencies:
```
cd ~/sky_ws2
source /opt/ros/humble/setup.bash
sudo apt update
rosdep update
rosdep install --from-paths src --ignore-src -y
```

Finally you can build sky_ws2 and then run a sample simulation:
```
cd ~/sky_ws2
source install/setup.bash
colcon test --packages-select ardupilot_sitl ardupilot_dds_tests ardupilot_gazebo ardupilot_gz_applications ardupilot_gz_description ardupilot_gz_gazebo ardupilot_gz_bringup
colcon test-result --all --verbose

source install/setup.bash
ros2 launch ardupilot_gz_bringup iris_runway.launch.py
```

### MAVROS2 install

Mavros is part of rosdep, and can be installed using:
```
sudo apt install ros-humble-mavros
sudo apt install ros-humble-mavros-extras
```

Then download the geographiclib_datasets:
```
wget https://raw.githubusercontent.com/mavlink/mavros/ros2/mavros/scripts/install_geographiclib_datasets.sh
chmod a+x install_geographiclib_datasets.sh
./install_geographiclib_datasets.sh
rm install_geographiclib_datasets.sh
```

You should now be able to develop using Ardupilot SITL + ROS2. Go ahead and visit sky_sim2 for simulation models and worlds, or sky_vision2 for general-use camera related code. Drones are fun!