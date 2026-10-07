# 灰度视频流接口

早期占位示例采用 AXI4-Stream 风格的单像素流，位于 `modules/axis_video_passthrough/`。

当前第一版摄像头流水线采用不能反压的原生单像素流：

| 信号 | 含义 |
|---|---|
| `pixel_data` | 单通道无符号灰度像素，默认10 bit |
| `pixel_valid` | 当前像素与元数据有效 |
| `frame_start` | 一帧第一个有效像素 |
| `line_start` / `line_end` | 一行第一个/最后一个有效像素 |
| `pixel_x` / `pixel_y` | 从0开始的像素坐标 |

这个接口没有 `ready`，因为物理摄像头不能因下游暂停而停止发送。需要跨时钟域或连接AXI时，在完整流水线外围增加FIFO/适配器。

## AXI直通学习示例

以下接口仍作为AXI握手机制的独立学习示例保留：

| 信号 | 含义 |
|---|---|
| `tdata` | 单通道无符号灰度像素，默认 10 bit |
| `tvalid` | 当前周期的像素与边界信号有效 |
| `tready` | 下游可以接收当前像素 |
| `tuser` | 一帧第一个像素，Start of Frame |
| `tlast` | 一行最后一个像素，End of Line |

一次像素传输只在下面条件成立时发生：

```text
tvalid && tready
```

当下游拉低 `tready` 时，上游必须保持 `tdata`、`tuser`、`tlast` 和 `tvalid` 不变，直到完成传输。

默认图像参数：

```text
宽度：640
高度：400
像素：10 bit 灰度
```

模块必须使用参数，不能在算法内部散落硬编码的 `640` 和 `400`。
