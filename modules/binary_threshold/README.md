# binary_threshold — 灰度二值化

## 功能

将 10-bit 灰度像素流转换为 1-bit 二值流。当 `pixel_data >= THRESHOLD` 时输出 1（白），否则输出 0（黑）。控制信号（valid, frame_start, line_start, line_end, x, y）打一拍延迟后透传。

## 接口

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| clk | input | 1 | 时钟 |
| reset_n | input | 1 | 低有效复位 |
| pixel_data | input | PIXEL_WIDTH | 灰度输入 |
| pixel_valid | input | 1 | 像素有效 |
| frame_start / line_start / line_end | input | 1 | 帧/行同步 |
| pixel_x / pixel_y | input | 16 | 像素坐标 |
| binary_data | output | 1 | 二值输出（0 或 1） |
| binary_valid / binary_frame_start / ... | output | - | 延迟一拍的控制信号 |

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| PIXEL_WIDTH | 10 | 输入像素位宽 |
| THRESHOLD | 1000 | 二值化阈值（10-bit），当前用 10'd1000 |

## 时序

1 周期延迟。输入 valid 和 data 在同一拍，输出 binary_* 在下一拍有效。
