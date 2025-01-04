xhost +

sudo docker start sky_ws2

sudo docker exec -it \
    --env="DISPLAY=$DISPLAY" \
    --env="QT_X11_NO_MITSHM=1" \
    --privileged \
    sky_ws2 \
    bash 
