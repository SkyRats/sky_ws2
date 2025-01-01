xhost +
sudo docker run -it \
    --name=sky_ws2\
    --env="DISPLAY=$DISPLAY" \
    --volume="/tmp/.x11-unix:/tmp/.x11-unix:rw" \
    --volume="<absolute/path/to/sky_ws>:/home/sky/sky_ws2" \
    --volume="/dev:/dev"\
    --net=host \
    --privileged \
    ardupilot/ardupilot-dev-ros:latest\
    bash
