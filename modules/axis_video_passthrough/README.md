# axis_video_passthrough — AXI4-Stream 视频透传

## 功能

组合逻辑 AXI4-Stream 风格视频接口转换。将帧首（tuser）和行末（tlast）信号转为 frame_start / line_end 脉冲，方便下游模块使用。

## 接口

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| s_axis_tdata | input | DATA_WIDTH | 输入像素 |
| s_axis_tvalid | input | 1 | 输入有效 |
| s_axis_tuser | input | 1 | 帧首标记 |
| s_axis_tlast | input | 1 | 行末标记 |
| m_axis_tdata | output | DATA_WIDTH | 透传像素 |
| m_axis_tvalid | output | 1 | 透传有效 |
| pixel_data | output | DATA_WIDTH | 像素值 |
| pixel_valid | output | 1 | 像素有效 |
| frame_start | output | 1 | 帧首脉冲 |
| line_end | output | 1 | 行末脉冲 |

## 说明

纯组合逻辑，零延迟。用于将 AXI4-Stream 视频源（如 MIPI CSI 接收器）接入内部 pixel-valid 接口。
