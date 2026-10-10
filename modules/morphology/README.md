# morphology — 形态学滤波

包含三个子模块：

## BinaryConvCore — N×N 滑动窗口

通过行缓冲 + 移位寄存器链生成 N×N 滑动窗口。延迟 1 周期。

### 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| IMAGE_WIDTH | 640 | 图像宽度 |
| WINDOW_SIZE | 9 | 窗口尺寸（当前实际用 3） |

## morph_erode — 腐蚀

输出 1 当且仅当 N×N 窗口内所有像素均为 1。延迟 2 周期（BinaryConvCore 1 拍 + 控制信号延迟 2 拍）。

## morph_dilate — 膨胀

输出 1 当窗口内任意像素为 1。延迟 2 周期。

### 接口（morph_erode / morph_dilate 相同）

| 信号 | 方向 | 说明 |
|------|------|------|
| pixel_valid / frame_start / line_start / line_end | input | 控制信号 |
| pixel_x / pixel_y | input | 像素坐标 |
| binary_data | input | 二值输入 |
| eroded_valid / dilated_valid | output | 有效信号（延迟 2 拍） |
| eroded_data / dilated_data | output | 处理后的二值输出 |
| eroded_x / dilated_x 等 | output | 延迟对齐的控制信号 |

### 当前配置

vision_pipeline 中两模块均例化为 `WINDOW_SIZE=3`（3×3 窗口）。

### 流水线策略

- 前一半帧（frame 0~337）：仅膨胀（bypass 腐蚀），帮助连接小光斑
- 后一半帧（frame 338+）：腐蚀→膨胀（开运算），去除噪声
