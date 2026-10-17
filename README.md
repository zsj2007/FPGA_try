# FPGA Vision Pipeline — 飞镖导引灯实时检测与视线角解算

基于 Xilinx 7-series FPGA (xc7z010) 的实时视觉导引流水线，用于飞镖制导系统中导引灯（LED）的检测、跟踪与视线角速率解算。

## 整体架构

```
 camera_capture → binary_threshold → morphology → ccl_analyzer → bounding_box_overlay → 输出标记视频
                                                    │
                                                    ▼
                                            los_guidance → 视线角/角速率
```

## 模块一览

| 模块 | 路径 | 功能 |
|------|------|------|
| camera_capture | `modules/camera_capture/` | 并行相机接口，输出像素流 + 帧/行同步 |
| binary_threshold | `modules/binary_threshold/` | 灰度阈值二值化 |
| BinaryConvCore | `modules/morphology/` | N×N 滑动窗口生成器 |
| morph_erode | `modules/morphology/` | 形态学腐蚀（3×3 窗口） |
| morph_dilate | `modules/morphology/` | 形态学膨胀（3×3 窗口） |
| roi_gate | `modules/blob_analyzer/` | ROI 中心区域裁剪 |
| ccl_analyzer | `modules/blob_analyzer/` | 连通域标记 + 长宽比筛选 |
| bounding_box_overlay | `modules/bounding_box_overlay/` | 检测框叠加到灰度图 |
| cordic_atan2 | `modules/los_guidance/` | 流水线 CORDIC atan2 |
| los_guidance | `modules/los_guidance/` | 针孔模型视线角 + 角速率 |
| vision_pipeline | `modules/vision_pipeline/` | 顶层集成流水线 |
| ccl_frontend | `modules/ccl_frontend/` | **NEW** 流式 CCL 前端（标签分配+统计） |
| axi_ccl_bridge | `modules/axi_bridge/` | **NEW** AXI4-Lite 双缓冲 BRAM 桥 |
| ps_ccl_merge | `software/` | **NEW** PS 端并查集归并 + 目标筛选 (C) |



## PS/PL 协同架构（开发中）

```
 PL (FPGA)                              PS (ARM A9)
 ────────────────────────              ──────────────────
 camera_capture                        ccl_merge_labels()
      ↓                                       ↑ AXI read
 binary_threshold                             │
      ↓                              union-find 归并
 morphology (erode/dilate)                   │
      ↓                              ccl_select_target()
 ccl_frontend (标签分配+统计)              │
      ↓                                       ↓ AXI write
 axi_ccl_bridge (双缓冲 BRAM) ←──AXI4-Lite──→ 结果回写
      │
 bounding_box_overlay ←── 读 PS 结果画框
      │
 los_guidance ←── 读 PS 结果解算 LOS
```

PS 和 PL 处理不同帧：PL 处理帧 N 时，PS 归并帧 N-1 的标签并回写结果。

## 仿真

需要 Vivado 2023.2，推荐 xsim 仿真器。

```bash
# 1. 创建工程
vivado -mode batch -source vivado/create_project.tcl -tclargs build/vivado

# 2. 运行仿真
vivado -mode batch -source vivado/run_sim.tcl -tclargs vision_pipeline_video_tb build/vivado/new_fpga.xpr
```

## 视频转换工具

`sim/scripts/` 目录下提供 Python 脚本：
- `video_to_raw.py` — MP4 转 RAW（供仿真输入）
- `raw_to_video.py` — RAW 转 MP4（查看仿真输出）

