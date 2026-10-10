# camera_capture — 相机像素流捕获

## 功能

将并行相机接口（cam_data, cam_href, cam_vsync）转换为内部像素流接口（pixel_valid + frame_start / line_start / line_end + pixel_x / pixel_y）。

## 接口信号

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| pclk | input | 1 | 像素时钟，来自相机 |
| reset_n | input | 1 | 低有效复位 |
| cam_data | input | 10 | 相机并行数据 |
| cam_href | input | 1 | 行有效（高有效） |
| cam_vsync | input | 1 | 帧同步（高有效） |
| pixel_data | output | 10 | 对齐后的像素值 |
| pixel_valid | output | 1 | 像素有效，每个 pclk 一拍 |
| frame_start | output | 1 | 帧首脉冲（首像素同拍为 1） |
| line_start | output | 1 | 行首脉冲 |
| line_end | output | 1 | 行末脉冲 |
| pixel_x | output | 16 | 像素列坐标（0 ~ IMAGE_WIDTH-1） |
| pixel_y | output | 16 | 像素行坐标（0 ~ IMAGE_HEIGHT-1） |

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| IMAGE_WIDTH | 640 | 图像宽度 |
| IMAGE_HEIGHT | 400 | 图像高度 |
| PIXEL_WIDTH | 10 | 像素位宽 |
| HREF_ACTIVE_LEVEL | 1 | href 有效电平 |
| VSYNC_ACTIVE_LEVEL | 1 | vsync 有效电平 |

## 时序

VSYNC 上升沿后 frame_start_pending 置位，等第一个 href 有效像素到来时 pulse frame_start=1。line_start 在 href 上升沿的首个像素为 1，line_end 在每行末像素为 1。
