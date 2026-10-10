# blob_analyzer — 光斑检测与分析

三个子模块，构成二值图像→目标坐标的完整流水线。

## 子模块

| 模块 | 功能 |
|------|------|
| roi_gate | ROI 中心区域掩码（零延迟组合逻辑） |
| ccl_analyzer | 连通域标记 + 长宽比筛选 |

---

## roi_gate — 感兴趣区域裁剪

零延迟组合逻辑。只放行 `binary_data=1` 且像素位于图像中心 30%~70% 区域内的像素，其它位置强制为 0。

### 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| ROI_X_FRAC_MIN / MAX | 0.30 / 0.70 | 水平裁剪范围（比例） |
| ROI_Y_FRAC_MIN / MAX | 0.30 / 0.70 | 垂直裁剪范围 |

> 注：当前 vision_pipeline 中 ROI 已旁路，保留模块供后续使用。

---

## ccl_analyzer — 连通域标记 + 目标筛选

### Stage 1：流式 CCL（单 Pass）

- 逐像素扫描，使用行缓冲 + 等价表实现单 Pass 八连通标记
- 实时累加每个标签的面积、sum_x、sum_y、外接矩形

### Stage 2：帧后处理

1. **标签合并**：解析等价表，将等价标签的统计量合并
2. **目标筛选**：在所有 `area >= MIN_AREA` 的连通域中，选 **长宽比最接近 1:1** 的（即 `|width - height|` 最小）
3. **平局决胜**：|w-h| 相同时选面积更大的

### 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| IMAGE_WIDTH | 640 | 图像宽度 |
| IMAGE_HEIGHT | 400 | 图像高度 |
| MAX_LABELS | 64 | 最大标签数 |
| MIN_AREA | 25 | 最小面积门限 |
| CIRC_TARGET_Q16 | 51471 | π/4 × 65536（保留，当前未用） |

### 接口

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| pixel_valid / binary_data | input | 1 | 二值像素流 |
| pixel_x / pixel_y | input | 16 | 像素坐标 |
| result_valid | output | 1 | 结果有效（每帧末脉冲） |
| target_found | output | 1 | 是否找到目标 |
| center_x / center_y | output | 16 | 目标中心坐标 |
| bbox_left / right / top / bottom | output | 16 | 外接矩形 |
| area | output | 24 | 目标面积（像素数） |
| ratio_q16 | output | 16 | 长宽比 Q16 格式 |
