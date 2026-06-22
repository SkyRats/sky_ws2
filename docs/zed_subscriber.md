# ZedSubscriber — ZED Camera Frame Ingestion

**Source:** `src/imagens/indoor_2025/mission_base.py`

`ZedSubscriber` is a ROS2 `Node` that subscribes to the ZED2i camera topics and stores the latest RGB and depth frames so mission modules can read them synchronously via `rclpy.spin_once`.

## Class

```python
class ZedSubscriber(Node):
    frame: np.ndarray | None        # latest BGR image (cv2 format)
    depth_frame: np.ndarray | None  # latest float32 depth map (meters)
```

## Subscriptions

| Topic | Type | Stored in |
|-------|------|-----------|
| `/zed/zed_node/left/image_rect_color` | `sensor_msgs/Image` | `self.frame` (BGR, uint8) |
| `zed/zed_node/depth/depth_registered` | `sensor_msgs/Image` | `self.depth_frame` (float32, meters) |

Note the inconsistency: the RGB topic has a leading `/` (absolute), the depth topic does not (relative to node namespace). Both work in practice because MAVROS and ZED nodes run in the root namespace.

## Usage pattern

Mission loops call `rclpy.spin_once(zed_node, timeout_sec=0)` each iteration to trigger the callbacks and refresh `frame` / `depth_frame` before reading them:

```python
rclpy.spin_once(zed_node, timeout_sec=0)
cv_image = zed_node.frame
depth_image = zed_node.depth_frame
```

Both start as `None` — always guard against `None` before passing to OpenCV.

## Encoding

| Frame | `imgmsg_to_cv2` encoding | Shape |
|-------|--------------------------|-------|
| `frame` | `'bgr8'` | `(H, W, 3)` uint8 |
| `depth_frame` | `'32FC1'` | `(H, W)` float32 (meters) |

Depth pixels can be `NaN` or `inf` for invalid readings. All consumers use `np.isfinite()` to filter.

## Initialization

```python
rclpy.init()
zed_node = ZedSubscriber()
```

Must be initialized before any mission starts. The main script creates it alongside `Mav` and passes both into `Mission`.

## See also

- [Gate detection](gate_detection.md) — consumes `frame` + `depth_frame`
- [Mission_1](mission_1.md) — calls `update_frame()` which wraps `spin_once` on this node
- [Mission orchestrator](mission_orchestrator.md) — owns the node lifecycle
- [Launch file](launch.md) — starts the ZED driver that publishes these topics
