from launch import LaunchDescription
from launch.actions import IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource, AnyLaunchDescriptionSource
from launch.substitutions import PathJoinSubstitution
from launch_ros.substitutions import FindPackageShare
from launch_ros.actions import Node

def generate_launch_description():

    # MAVROS (apm) — XML launch file, use AnyLaunchDescriptionSource
    # Jetson UART GPIO pins (Telem2) → /dev/ttyTHS1:921600
    mavros_launch = IncludeLaunchDescription(
        AnyLaunchDescriptionSource(
            PathJoinSubstitution([
                FindPackageShare('mavros'),
                'launch',
                'apm.launch'
            ])
        ),
        launch_arguments={
            'fcu_url': '/dev/ttyTHS1:921600'
        }.items()
    )

    # ZED wrapper com o argumento de qual câmera está sendo usada
    # Posteriormente mudar para zedm, por enquanto zed2i
    zed_launch = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            PathJoinSubstitution([
                FindPackageShare('zed_wrapper'),
                'launch',
                'zed_camera.launch.py'
            ])
        ),
        launch_arguments={
            'camera_model': 'zed2i'
        }.items()
    )

    pose_relay = Node(
        package='indoor_2026',
        executable='pose_relay',
        name='pose_relay',
        output='screen'
    )

    return LaunchDescription([
        mavros_launch,
        zed_launch,
        pose_relay,
    ])
