# vision_pipeline：第一版完整流水线

## 功能

该模块把目前已经完成的四个模块连接成可以端到端工作的第一版：

```text
摄像头 PCLK / DATA / HREF / VSYNC
                 │
                 ▼
          camera_capture
                 │ 10位原始灰度、坐标、边界标志
                 ├──────────────────────────────────┐
                 ▼                                  │
         binary_threshold                           │
                 │ 1位二值像素                      │
                 ▼                                  │
         brightest_window                           │
                 │ 最大窗口坐标                     │
                 ▼                                  ▼
                 └──────────────────► bounding_box_overlay
                                                    │
                                                    ▼
                                           带框10位灰度像素流
```

检测第N帧时，灰度显示支路仍输出原图。帧末得到 `best_x/best_y` 后，在第N+1帧对应位置画框。

## 为什么使用 `pclk` 而不是 AXI `ready`

摄像头会按自己的像素时钟连续输出，FPGA不能通过 `ready=0` 让摄像头暂停。因此第一版全链路都运行在摄像头 `pclk` 时钟域，并采用 `valid + 坐标 + 边界标志`。

如果以后需要连接另一个时钟域、DDR或AXI视频模块，应在本流水线外增加异步FIFO/视频流适配器。

## 参数

| 参数 | 默认值 | 含义 |
|---|---:|---|
| `IMAGE_WIDTH` | 640 | 有效图像宽度 |
| `IMAGE_HEIGHT` | 400 | 有效图像高度 |
| `PIXEL_WIDTH` | 10 | 摄像头灰度位宽 |
| `THRESHOLD` | 512 | 二值化亮度阈值，像素大于等于该值记为1 |
| `WINDOW_WIDTH` | 20 | 搜索窗口和显示框宽度 |
| `WINDOW_HEIGHT` | 20 | 搜索窗口和显示框高度 |
| `MIN_BRIGHT_COUNT` | 0 | 窗口成为目标至少需要的亮像素数 |
| `BOX_THICKNESS` | 1 | 显示框厚度 |
| `BOX_VALUE` | 1023 | 10位输出中的框线灰度 |
| `HREF_ACTIVE_LEVEL` | 1 | 摄像头HREF有效电平 |
| `VSYNC_ACTIVE_LEVEL` | 1 | 摄像头VSYNC有效电平 |

首次上板前建议不要让 `MIN_BRIGHT_COUNT` 保持0。20×20窗口共有400个像素，可以先从例如100开始，再根据真实画面调整。

## 摄像头输入

| 输入 | 含义 |
|---|---|
| `pclk` | 摄像头像素时钟，也是第一版算法时钟 |
| `reset_n` | 低电平复位 |
| `cam_data` | 10位黑白像素 |
| `cam_href` | 行有效信号 |
| `cam_vsync` | 帧同步信号 |

## 带框视频输出

| 输出 | 含义 |
|---|---|
| `output_data` | 带框10位灰度像素 |
| `output_valid` | 当前输出像素有效 |
| `output_frame_start` | 当前输出像素是帧首 |
| `output_line_start/end` | 当前输出像素是行首/行尾 |
| `output_x/y` | 当前输出像素坐标 |
| `output_box_active` | 当前输出像素属于框线 |

输出比 `camera_capture` 的灰度流多一个寄存器周期延迟，但所有像素、坐标和边界标志保持对齐。

## 检测结果输出

| 输出 | 含义 |
|---|---|
| `result_valid` | 一帧检测结束，结果更新一个周期 |
| `target_found` | 是否有窗口满足最小亮像素数 |
| `best_x/y` | 最佳窗口左上角 |
| `best_bright_count` | 最佳窗口中的二值亮像素数量 |

这些端口可以接ILA观察，也可以交给后续控制模块计算目标中心：

```text
center_x = best_x + WINDOW_WIDTH / 2
center_y = best_y + WINDOW_HEIGHT / 2
```

## Testbench

| 文件 | 用途 |
|---|---|
| `vision_pipeline_tb.sv` | 8×6小画面单元测试（2帧） |
| `vision_pipeline_image_tb.sv` | 桌面图片端到端测试（640×400，2帧） |
| `vision_pipeline_video_tb.sv` | 视频多帧处理（任意帧数） |

### 视频仿真

```powershell
# 一键运行：MP4 → RAW → 仿真 → 标注MP4
& .\sim\scripts\test_desktop_video.ps1 "C:\path\to\video.mp4"

# 限制帧数（测试用）
& .\sim\scripts\test_desktop_video.ps1 "C:\path\to\video.mp4" -MaxFrames 10
```

视频仿真流程：

1. `video_to_raw.py`：MP4 → 多帧拼接 RAW8
2. Vivado 仿真 `vision_pipeline_video_tb`：逐帧处理
3. `raw_to_video.py`：RAW10/16 输出 → 带标注 MP4

输出视频每帧左下角显示帧号和检测坐标，实际检测框线直接画在灰度画面上。