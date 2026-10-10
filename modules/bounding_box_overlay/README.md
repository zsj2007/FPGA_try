# bounding_box_overlay — 检测框叠加

## 功能

将 CCL 检测到的目标外接矩形以黑框形式画在灰度视频流上。使用 1 帧缓冲实现 read-before-write：当前帧的灰度图与上一帧的检测结果对齐后输出。

## 工作原理

1. 灰度像素流写入帧缓冲（BRAM），同时读出上一帧同位置的像素值
2. 读出值延迟 1 拍后进入 overlay 逻辑
3. 当像素坐标落在 bbox 边界时，输出 `BOX_VALUE`（默认为 0，即黑色），否则输出灰度值

## 接口

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| pixel_data / pixel_valid | input | 10 | 灰度像素流 |
| pixel_x / pixel_y | input | 16 | 像素坐标 |
| result_valid / target_found | input | 1 | CCL 检测结果 |
| bbox_left / right / top / bottom | input | 16 | 外接矩形 |
| boxed_data | output | 10 | 叠加后的像素 |
| box_valid | output | 1 | 输出有效 |
| box_active | output | 1 | 当前像素在框上为 1 |

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| BOX_THICKNESS | 2 | 线宽（像素） |
| BOX_VALUE | 0 | 框的颜色（0=黑） |
