# vision_pipeline — 顶层视觉流水线

## 功能

集成所有子模块的顶层，完整实现：相机输入 → 二值化 → 形态学 → 连通域检测 → 画框 → LOS 解算。

## 数据流

```
camera_capture
     │  pixel_data, pixel_valid, frame_start, line_start, line_end, x, y
     ▼
binary_threshold (THRESHOLD=1000)
     │  binary_data, binary_valid, ...
     ▼
┌──── morphology ──────────────────────────────┐
│  frame < 338: bypass erosion → 3×3 dilate    │
│  frame ≥ 338: 3×3 erode → 3×3 dilate         │
│  总延迟: 4 周期                                 │
└──────────────────────────────────────────────┘
     │  morph_data, morph_valid, ...
     ▼
ccl_analyzer (连通域 + 长宽比筛选)
     │  center_x/y, bbox_l/r/t/b, area, target_found
     ├──────────────────────┐
     ▼                      ▼
bounding_box_overlay    los_guidance
  (画框叠加)              (视线角 + 角速率)
     │                      │
     ▼                      ▼
  output_data            hfov/vfov, omega
  output_valid
```

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| IMAGE_WIDTH / IMAGE_HEIGHT | 640 / 400 | 图像尺寸 |
| PIXEL_WIDTH | 10 | 像素位宽 |
| THRESHOLD | 1000 | 二值化阈值（10-bit） |
| BOX_THICKNESS | 2 | 检测框线宽 |
| BOX_VALUE | 0 | 检测框颜色（0=黑） |
| MORPH_FRAME_LIMIT | 338 | 形态学策略切换帧号 |
| CORDIC_STAGES | 16 | CORDIC 流水线级数 |

## 顶层接口

### 相机输入（与 camera_capture 相同）

| 信号 | 位宽 | 说明 |
|------|------|------|
| pclk | 1 | 像素时钟 |
| reset_n | 1 | 低有效复位 |
| cam_data | 10 | 相机并行数据 |
| cam_href | 1 | 行有效 |
| cam_vsync | 1 | 帧同步 |

### 视频输出

| 信号 | 位宽 | 说明 |
|------|------|------|
| output_data | 10 | 叠加了检测框的灰度图 |
| output_valid | 1 | 输出有效 |
| output_frame_start / line_start / line_end | 1 | 同步信号 |
| output_x / output_y | 16 | 坐标 |
| output_box_active | 1 | 当前像素在检测框上 |

### 检测结果

| 信号 | 位宽 | 说明 |
|------|------|------|
| result_valid | 1 | 结果有效（每帧末） |
| target_found | 1 | 找到目标 |
| center_x / center_y | 16 | 目标中心 |
| bbox_left / right / top / bottom | 16 | 外接矩形 |
| blob_area | 24 | 目标面积 |
| blob_aspect_q16 | 16 | 长宽比 Q16 |

### LOS 输出

| 信号 | 位宽 | 说明 |
|------|------|------|
| los_valid | 1 | LOS 有效 |
| hfov_q16 / vfov_q16 | 32 | 视线角 Q29 |
| omega_valid | 1 | 角速率有效 |
| omega_hfov_q16 / omega_vfov_q16 | 32 | 角速率 Q24 (rad/s) |

### 调试输出

| 信号 | 位宽 | 说明 |
|------|------|------|
| debug_binary_data | 1 | CCL 输入端的二值数据（形态学后） |
| debug_binary_valid | 1 | 同步有效信号 |
