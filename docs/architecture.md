# 架构说明

## 分层

```text
board_top
  -> 摄像头/板级接口
  -> pl_top
       -> vision_pipeline
            -> camera_capture（10位灰度流）
                 |-> binary_threshold（二值流）
                 |    -> brightest_window（本帧最佳窗口坐标）
                 |
                 `-> bounding_box_overlay（在下一帧灰度流上画框）
```

`camera_capture` 从 `PCLK + data[9:0] + HREF + VSYNC` 采集灰度像素，并生成有效标志、坐标和图像边界标志。第一版 `vision_pipeline` 已将采集、二值化、最大窗口搜索和下一帧框线叠加正式集成。

下一模块 `binary_threshold` 根据10位灰度亮度生成1位二值像素，默认阈值为512。两个模块暂时分别完成单元测试，之后再做流水线集成。

`brightest_window` 在全画面中以1像素步长搜索默认20×20窗口，统计二值图中每个窗口的亮像素数量，并输出亮像素最多的窗口左上角。

`bounding_box_overlay` 保存该检测结果，并在下一帧的原始灰度流上绘制固定20×20矩形边框。原始灰度流不经过二值化支路；使用下一帧显示可以避免缓存整张图像。

## 设计规则

1. `modules/<模块名>/` 是该模块实现、测试和说明的唯一来源。
2. 一个文件只定义一个主要模块，文件名与模块名一致。
3. 每个模块目录至少包含实现 `.sv`、测试 `_tb.sv` 和 `README.md`。
4. 算法模块不直接依赖 Vivado Block Design。
5. Xilinx 专用 IP 与算法 RTL 隔离。
6. 每个算法模块先有独立 testbench，再进入完整流水线。
7. 代码搬迁与算法修改分别提交。
