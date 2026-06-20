import rclpy
from rclpy.node import Node
from geometry_msgs.msg import PoseStamped


class PoseRelay(Node):
    def __init__(self):
        super().__init__('pose_relay')
        self.pub = self.create_publisher(PoseStamped, '/mavros/vision_pose/pose', 10)
        self.create_subscription(PoseStamped, '/mavros/zed/pose', self._cb, 10)

    def _cb(self, msg):
        out = PoseStamped()
        out.header = msg.header

        # ZED X and Y axes are inverted relative to MAVROS ENU frame
        out.pose.position.x = -msg.pose.position.x
        out.pose.position.y = -msg.pose.position.y
        out.pose.position.z = msg.pose.position.z

        # Rotate orientation 180° around Z to match the position flip
        # q_rot = (0, 0, 1, 0) — 180° around Z
        # q_result = q_rot * q_orig
        qx = msg.pose.orientation.x
        qy = msg.pose.orientation.y
        qz = msg.pose.orientation.z
        qw = msg.pose.orientation.w
        out.pose.orientation.x = -qy
        out.pose.orientation.y = qx
        out.pose.orientation.z = qw
        out.pose.orientation.w = -qz

        self.pub.publish(out)


def main():
    rclpy.init()
    node = PoseRelay()
    rclpy.spin(node)
    node.destroy_node()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
