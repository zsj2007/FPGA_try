# los_guidance：视线角速度计算模块

## 功能

将目标框中心像素坐标转换为视线角（LOS angle），并计算帧间角速度（omega）。

硬件实现参照 `dart_-application` 中的 `alg_proportional_navigation.c`，
用 CORDIC 算法替代软件 `atan2()`，全流水线固定点数实现。

## 针孔相机模型

```
    传感器平面               镜头              目标
    ┌─────────┐              │
    │  (cx,cy)│── dx_px ────▶│───▶ 视线角 hfov
    │    ●    │              │
    │    │    │              │ focal length
    │   dy_px │              │
    │    │    │              │
    │    ▼    │              │
    └─────────┘              │
       ◄─ PIXEL_X * 640 ──►
```

```
  hfov = atan2( target_cx - CENTER_CX,  FOCUS_PX_X )
  vfov = atan2( target_cy - CENTER_CY,  FOCUS_PX_Y )
  omega = (angle - prev_angle) * fps
```

## 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `FOCUS_PX_X` | 21512192 | 水平焦距（像素单位，Q16.16），对应 2mm / (3.9mm/640) |
| `FOCUS_PX_Y` | 21430272 | 垂直焦距（像素单位，Q16.16），对应 2mm / (2.45mm/400) |
| `CENTER_CX` | 20971520 | 光心 X（Q16.16，=320.0） |
| `CENTER_CY` | 13107200 | 光心 Y（Q16.16，=200.0） |
| `CORDIC_STAGES` | 16 | CORDIC 迭代级数 |
| `DT_FACTOR` | 1966080 | 帧率倒数*65536（Q16.16，=30.0） |

## 接口

| 信号 | 方向 | 说明 |
|---|---|---|
| `result_valid` | in | 帧检测完成脉冲 |
| `target_found` | in | 本帧是否找到目标 |
| `best_x / best_y` | in | 目标框左上角像素坐标 |
| `los_valid` | out | LOS 角度有效（CORDIC 流水线延迟后） |
| `hfov_rad_q16` | out | 水平视线角（Q3.29 rad） |
| `vfov_rad_q16` | out | 垂直视线角（Q3.29 rad） |
| `omega_valid` | out | 角速度有效（首帧无输出） |
| `omega_x_q16` | out | 水平角速度（Q8.24 rad/s） |
| `omega_z_q16` | out | 垂直角速度（Q8.24 rad/s） |

## 定标说明

- Q3.29：±4 rad 范围，精度 ~1.86e-9 rad
- Q8.24：±128 rad/s 范围，精度 ~5.96e-8 rad/s
- Q16.16：像素坐标精度 ~1.53e-5 px

## CORDIC 延迟

`CORDIC_STAGES + 2` 个时钟周期。默认 16 级 → 18 个周期，
在 100 MHz 时钟下对应 180 ns，显著低于帧间隔。

## 与软件实现的对应关系

| C++ (`alg_proportional_navigation.c`) | Verilog (`los_guidance.sv`) |
|---|---|
| `atan2f(photo_target_x, FOCUS_LENGTH_X)` | `cordic_atan2(dx_q16, FOCUS_PX_X)` |
| `(current - last) / dt` | `(delta * DT_FACTOR) >> 16` |
| `Filter_Lowpass(...)` | 未实现（可按需添加） |
| `Change_PN_Target_to_World(...)` | 未实现（需要 IMU roll 数据） |
