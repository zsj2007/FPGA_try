# FPGA 视觉管线 — 演示操作手册

## 目录结构

```
D:\new_FPGA\
├── sim\data\input\          ← 放 RAW 输入文件
├── sim\data\output\         ← 仿真输出 (.raw / .json / .mp4)
├── sim\scripts\             ← Python 转换脚本
├── modules\vision_pipeline\ ← 主模块 + TB
├── vivado\                  ← Vivado TCL 脚本
└── build\vivado\            ← Vivado 工程
```

---

## 1. 视频 → RAW 格式转换

FPGA 仿真吃 RAW8 灰度裸数据（640×400，逐帧拼接，无头）。

```powershell
cd D:\new_FPGA

# 基本用法（默认 640×400，crop 居中裁切）
python sim/scripts/video_to_raw.py "C:\你的视频.mp4" sim/data/input/my_video_640x400.raw

# 只取前 N 帧
python sim/scripts/video_to_raw.py "C:\视频.mp4" sim/data/input/my.raw --max-frames 200
```

生成的 `.raw` 文件大小 = `帧数 × 640 × 400` 字节。

---

## 2. 修改 TB 指向你的视频

编辑 `modules/vision_pipeline/vision_pipeline_video_tb.sv`，改这三行：

```verilog
localparam string INPUT_FILE  = "D:/new_FPGA/sim/data/input/my_video_640x400.raw";   // ← 你的输入
localparam string OUTPUT_FILE = "D:/new_FPGA/sim/data/output/my_video_boxed_640x400.raw"; // ← 输出
localparam string DETS_FILE   = "D:/new_FPGA/sim/data/output/my_video_dets.json";         // ← 检测数据
```

> **注意**：路径用 `/`，`\` 在 Verilog string 里是转义符。

---

## 3. 用 Vivado 跑仿真

打开 **Vivado 2023.2** → Tcl Console，依次输入：

```tcl
# 切到工程目录
cd D:/new_FPGA

# 创建/更新工程
source vivado/create_project.tcl

# 跑仿真（大约 10 分钟 / 677 帧）
source vivado/run_sim.tcl
```

或者在 PowerShell 里一键跑（不打开 GUI）：

```powershell
D:\Xilinx\Vivado\2023.2\bin\vivado.bat -mode batch -source D:\new_FPGA\vivado\run_sim.tcl -tclargs vision_pipeline_video_tb D:/new_FPGA/build/vivado/new_fpga.xpr
```

> 跑完后 `sim/data/output/` 下会生成 `*_boxed_640x400.raw`、`*_dets.json`。

---

## 4. 输出 RAW → MP4

```powershell
cd D:\new_FPGA

python -c "
import numpy as np, cv2
W, H = 640, 400
# 先看文件大小算帧数
import os
fsize = os.path.getsize(r'sim/data/output/my_video_boxed_640x400.raw')
FRAMES = fsize // (W * H * 2)   # 输出是 16-bit，每个像素 2 字节
print(f'Frames: {FRAMES}')

raw16 = np.fromfile(r'sim/data/output/my_video_boxed_640x400.raw', dtype=np.uint16)
raw16 = raw16.reshape(FRAMES, H, W)
raw8 = (raw16 >> 2).astype(np.uint8)   # 10-bit → 8-bit

out = cv2.VideoWriter(r'sim/data/output/my_video_boxed.mp4',
                       cv2.VideoWriter_fourcc(*'mp4v'), 30, (W, H))
for i in range(FRAMES):
    out.write(cv2.cvtColor(raw8[i], cv2.COLOR_GRAY2BGR))
out.release()
print('Done: sim/data/output/my_video_boxed.mp4')
"
```

---

## 5. 快速演示流程（已有 2727 视频）

如果只是想快速跑一遍看效果：

```powershell
# 1. 仿真
D:\Xilinx\Vivado\2023.2\bin\vivado.bat -mode batch -source D:\new_FPGA\vivado\run_sim.tcl -tclargs vision_pipeline_video_tb D:/new_FPGA/build/vivado/new_fpga.xpr

# 2. 转 MP4
python -c "
import numpy as np, cv2
W,H,FRAMES=640,400,677
raw16=np.fromfile(r'D:/new_FPGA/sim/data/output/vid_2727_boxed_640x400.raw',dtype=np.uint16).reshape(FRAMES,H,W)
raw8=(raw16>>2).astype(np.uint8)
out=cv2.VideoWriter(r'D:/new_FPGA/sim/data/output/vid_2727_boxed.mp4',cv2.VideoWriter_fourcc(*'mp4v'),30,(W,H))
for i in range(FRAMES): out.write(cv2.cvtColor(raw8[i],cv2.COLOR_GRAY2BGR))
out.release()
print('Done')
"
```

---

## 6. 查看检测数据

```powershell
python -c "
import json
with open(r'D:/new_FPGA/sim/data/output/vid_2727_dets.json') as f:
    dets = json.load(f)
for d in dets[::50]:
    print(f'Frame {d[\"frame\"]:3d}: found={d[\"found\"]} x={d[\"x\"]:4d} y={d[\"y\"]:4d} area={d[\"area\"]:6d}')
"
```

---

## 关键参数速查

| 位置 | 参数 | 默认值 | 含义 |
|------|------|--------|------|
| `vision_pipeline.sv:30` | `THRESHOLD` | `10'd1000` | 二值化阈值 (10-bit) |
| `vision_pipeline.sv:41` | `MORPH_FRAME_LIMIT` | `338` | 前 N 帧只膨胀，之后腐蚀+膨胀 |
| `ccl_analyzer.sv:13` | `MIN_AREA` | `25` | 最小检测面积 |
| `ccl_analyzer.sv:12` | `MAX_LABELS` | `64` | 最大连通域数 |
| `vision_pipeline_video_tb.sv:16` | `MAX_FRAMES` | `0` | 0=全跑，改数字=只跑前N帧测试 |
