# los_guidance — 视线角解算与角速率

基于针孔相机模型，从目标像素坐标解算视线角（LOS angle），并计算帧间角速率，供比例导引（PN）算法使用。

## 子模块

### cordic_atan2 — 流水线 CORDIC atan2

- N 级流水线，每级做条件加减 + 移位
- 输入 (x, y)，输出角度 angle（Q29 定点格式，范围 [-π/2, π/2]）
- latency = STAGES + 2 周期

### los_guidance — 视线角顶层

1. 从目标中心像素坐标计算相对于图像中心的偏移 `dx, dy`
2. 通过两个 CORDIC 分别计算水平角（hfov）和垂直角（vfov）
3. 帧间差分计算角速率 ω

## 针孔相机模型

```
tan(hfov) = dx / FOCUS_PX_X     （水平）
tan(vfov) = dy / FOCUS_PX_Y     （垂直）
```

其中 FOCUS_PX_X/Y 是从焦距换算的像素焦距：
- FOCUS_PX_X = (焦距 / 像元大小) × 65536
- FOCUS_PX_Y = (焦距 / 像元大小) × 65536
- 默认：焦距 2mm，像元 6μm → 333.33 px → Q16 = 21845333

## 接口

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| result_valid / target_found | input | 1 | CCL 结果 |
| center_x / center_y | input | 16 | 目标中心 |
| los_valid | output | 1 | LOS 角有效 |
| hfov_q16 / vfov_q16 | output | 32 | 视线角 Q29 格式 |
| omega_valid | output | 1 | 角速率有效 |
| omega_hfov_q16 / omega_vfov_q16 | output | 32 | 角速率 Q24 格式 (rad/s) |

## 角速率计算

```
ω = (angle_current - angle_prev) / frame_period
```

帧周期默认 33.33ms（30fps），Q24 格式输出。连续两帧均有有效检测时才更新 ω。
