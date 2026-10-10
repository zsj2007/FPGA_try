# brightest_window — 滑动窗口最亮区域检测

## 功能

在二值图像中寻找包含最多白像素的 WINDOW_WIDTH × WINDOW_HEIGHT 滑动窗口。使用高效的行增量更新算法（每滑动一列只需加减一列，不需重新计算整个窗口）。输出窗口内白像素数量及窗口左上角坐标。

## 接口

| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| pixel_valid / binary_data | input | 1 | 二值像素流 |
| pixel_x / pixel_y | input | 16 | 坐标 |
| frame_start / line_end | input | 1 | 帧/行同步 |
| result_valid | output | 1 | 结果有效 |
| best_x / best_y | output | 16 | 最佳窗口左上角坐标 |
| best_bright_count | output | clog2(W×H+1) | 窗口内白像素数 |

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| WINDOW_WIDTH | 20 | 窗口宽度 |
| WINDOW_HEIGHT | 20 | 窗口高度 |

## 说明

这是早期的简单检测方法——直接找最亮窗口。已被 ccl_analyzer（连通域检测+长宽比筛选）取代，但保留模块供参考。
