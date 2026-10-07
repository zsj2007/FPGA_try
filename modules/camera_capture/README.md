# camera_capture：摄像头像素采集

## 1. 这个模块做什么

`camera_capture.sv` 位于物理摄像头和后续图像算法之间。

```text
OV9282摄像头
  │ PCLK、DATA[9:0]、HREF、VSYNC
  ↓
camera_capture
  │ 像素、有效标志、坐标、帧首、行首、行尾
  ↓
跨时钟域/视频流转换/图像算法
```

它在摄像头给出的 `PCLK` 上升沿读取一个10位黑白像素，并给这个像素附加位置信息。

## 2. 参数是什么意思

参数是在例化模块时确定的配置，不会随着每个时钟周期变化。

| 参数 | 默认值 | 含义 |
|---|---:|---|
| `IMAGE_WIDTH` | 640 | 每行有效像素数 |
| `IMAGE_HEIGHT` | 400 | 每帧有效行数 |
| `PIXEL_WIDTH` | 10 | 每个灰度像素的位数，10位范围为0～1023 |
| `HREF_ACTIVE_LEVEL` | 1 | `HREF` 为1时表示当前处于有效行 |
| `VSYNC_ACTIVE_LEVEL` | 1 | `VSYNC` 为1时表示帧同步有效 |

在测试中使用4×3小画面，便于直接观察：

```systemverilog
camera_capture #(
    .IMAGE_WIDTH  (4),
    .IMAGE_HEIGHT (3),
    .PIXEL_WIDTH  (10)
) dut (...);
```

## 3. 输入变量

| 输入 | 位宽 | 含义 |
|---|---:|---|
| `pclk` | 1 | Pixel Clock，摄像头输出的像素时钟 |
| `reset_n` | 1 | 低电平复位；`0` 清空状态，`1` 正常工作 |
| `cam_data` | 10 | 摄像头当前输出的黑白像素值 |
| `cam_href` | 1 | Horizontal Reference，当前是否处于一行有效像素区 |
| `cam_vsync` | 1 | Vertical Sync，用来宣布新的一帧 |

### `pclk`

摄像头每发送一个像素，就通过 `pclk` 给 FPGA 一个采样节拍。模块使用：

```systemverilog
always_ff @(posedge pclk ...)
```

也就是在 `pclk` 从0变成1的瞬间读取 `cam_data`、`cam_href` 和 `cam_vsync`。

### `cam_data[9:0]`

这是10位无符号灰度：

```text
0    = 最黑
1023 = 最亮
```

它不是 RGB，也不包含颜色信息。

### `cam_href`

默认情况下：

```text
cam_href = 1：cam_data 是一行中的有效像素
cam_href = 0：行间消隐，不接收像素
```

一次连续的高电平通常对应一整行。

### `cam_vsync`

模块检测 `cam_vsync` 进入有效状态的边沿，并把它当作新一帧的通知。VSYNC 本身出现时通常还没有有效像素，因此模块先记住“下一像素是帧首”，等第一个有效像素到来时再输出 `frame_start`。

## 4. 输出变量

| 输出 | 位宽 | 含义 |
|---|---:|---|
| `pixel_data` | 10 | 已在 `pclk` 上升沿锁存的灰度像素 |
| `pixel_valid` | 1 | 为1时，其他像素输出在当前周期有效 |
| `frame_start` | 1 | 当前有效像素是一帧的第一个像素 |
| `line_start` | 1 | 当前有效像素是一行的第一个像素 |
| `line_end` | 1 | 当前有效像素是一行的最后一个像素 |
| `pixel_x` | 16 | 当前像素的横坐标，从0开始 |
| `pixel_y` | 16 | 当前像素的纵坐标，从0开始 |

只有 `pixel_valid == 1` 时，才应该使用 `pixel_data`、坐标和边界标志。

例如4×3图像第一行：

| `pixel_data` | `pixel_x` | `pixel_y` | `frame_start` | `line_start` | `line_end` |
|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 1 | 1 | 0 |
| 1 | 1 | 0 | 0 | 0 | 0 |
| 2 | 2 | 0 | 0 | 0 | 0 |
| 3 | 3 | 0 | 0 | 0 | 1 |

## 5. 内部变量

这些变量只在模块内部使用，外部模块看不到。

| 内部变量 | 含义 |
|---|---|
| `href_active` | 把 HREF 极性参数处理后得到的“当前行有效”状态 |
| `vsync_active` | 把 VSYNC 极性参数处理后得到的“当前帧同步有效”状态 |
| `href_active_d` | 上一个 PCLK 周期的 `href_active` |
| `vsync_active_d` | 上一个 PCLK 周期的 `vsync_active` |
| `vsync_start` | 当前周期检测到 VSYNC 从无效进入有效 |
| `frame_start_pending` | 已经看见新帧，但还在等待第一个有效像素 |
| `x_count` | 下一个有效像素的横坐标计数器 |
| `y_count` | 当前有效行的纵坐标计数器 |

变量名结尾的 `_d` 表示 delayed，也就是“延迟一个时钟周期的旧值”。将当前值和旧值比较，就能检测信号边沿：

```systemverilog
vsync_start = vsync_active && !vsync_active_d;
```

含义是：当前为1、上一周期为0，因此刚刚出现了上升沿。

## 6. 每帧如何工作

1. `reset_n=0` 时，清零输出和坐标。
2. 检测到 VSYNC 有效边沿后，将 `x_count`、`y_count` 清零。
3. 同时置位 `frame_start_pending`，等待第一个像素。
4. 当 HREF 有效时，在每个 PCLK 上升沿锁存一个 `cam_data`。
5. 第一个有效像素同时输出 `frame_start=1` 和 `line_start=1`。
6. 每接收一个像素，`x_count` 加1。
7. 当横坐标为 `IMAGE_WIDTH-1` 时输出 `line_end=1`。
8. HREF 由有效变无效后，横坐标清零，纵坐标加1。

所有输出经过寄存器，与同一个被采样像素保持对齐。

## 7. 为什么没有 `ready`

物理摄像头不会因为 FPGA 下游忙就暂停发送数据，因此这个模块不能使用一个 `ready` 信号反向阻塞摄像头。

正确结构是：

```text
camera_capture（PCLK时钟域）
  → 异步FIFO或Xilinx视频输入模块
  → 系统时钟域AXI4-Stream
  → vision_pipeline
```

如果 FIFO 满了，只能报告溢出或丢帧，不能要求已经在工作的摄像头停在某个像素上。

## 8. 当前尚未实现

本模块不负责：

- 给摄像头生成 MCLK；
- 控制 `camera_reset` 和 `camera_poweron`；
- 通过 I²C/SCCB 配置 OV9282；
- 跨时钟域；
- 写入 DDR；
- 阈值化或形态学处理。

HREF、VSYNC 的真实极性以及像素在哪个 PCLK 边沿稳定，上板前还需要结合摄像头寄存器配置和 ILA 波形确认。

## 9. 测试文件

`camera_capture_tb.sv` 模拟一个4×3摄像头画面，依次发送像素0～11，并自动检查：

- 是否收到12个像素；
- 像素值是否正确；
- 坐标是否正确；
- 帧首、行首和行尾是否正确。

成功时打印：

```text
PASS: camera_capture received 12 pixels
```

