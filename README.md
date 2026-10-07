# new_FPGA

XC7Z010-CLG400 PL 侧重构工程。开发环境以 Vivado 2023.2 为准。

## 当前里程碑

阶段 0：建立清晰的仓库结构，验证摄像头采集、亮度二值化、固定窗口最大亮度搜索和目标框绘制。

当前已实现摄像头像素采集、亮度二值化、最大亮点窗口搜索和灰度框线叠加，完成各自单元测试，并已接入第一版完整 `vision_pipeline`；还没有加入 Block Design 或板级引脚。

## 目录职责

- `modules/`：每个模块自己的实现、testbench和说明文档。
- `sim/`：多个模块共用的仿真模型、输入数据和辅助脚本。
- `vivado/`：创建工程、仿真和生成 bitstream 的 Tcl 脚本。
- `constraints/`：引脚与时序约束。
- `docs/`：架构、接口和操作说明。
- `build/`：Vivado 生成物，不提交 Git。

## 创建 Vivado 工程

在 Vivado Tcl Console 中执行：

```tcl
cd D:/new_FPGA
source vivado/create_project.tcl
```

脚本会创建并打开：

```text
D:/new_FPGA/build/vivado/new_fpga.xpr
```

然后选择：

```text
Flow Navigator -> Simulation -> Run Behavioral Simulation
```

也可以在 PowerShell 中运行完整的命令行仿真：

```powershell
& "D:\Xilinx\Vivado\2023.2\bin\vivado.bat" -mode batch -source vivado/create_project.tcl
& "D:\Xilinx\Vivado\2023.2\bin\vivado.bat" -mode batch -source vivado/run_sim.tcl
```

运行指定模块的测试：

```powershell
& "D:\Xilinx\Vivado\2023.2\bin\vivado.bat" -mode batch -source vivado/run_sim.tcl -tclargs camera_capture_tb

& "D:\Xilinx\Vivado\2023.2\bin\vivado.bat" -mode batch -source vivado/run_sim.tcl -tclargs binary_threshold_tb

& "D:\Xilinx\Vivado\2023.2\bin\vivado.bat" -mode batch -source vivado/run_sim.tcl -tclargs brightest_window_tb

& "D:\Xilinx\Vivado\2023.2\bin\vivado.bat" -mode batch -source vivado/run_sim.tcl -tclargs bounding_box_overlay_tb

& "D:\Xilinx\Vivado\2023.2\bin\vivado.bat" -mode batch -source vivado/run_sim.tcl -tclargs vision_pipeline_tb
```

## 桌面图片测试

使用桌面图片运行完整流水线：

```powershell
& .\sim\scripts\test_desktop_image.ps1 "C:\Users\Lenovo\Desktop\111.png"
```

## 视频测试（新）

将 MP4 视频逐帧送入 FPGA 仿真流水线，输出带检测框的标注视频：

```powershell
# 完整处理
& .\sim\scripts\test_desktop_video.ps1 "C:\path\to\video.mp4"

# 限制帧数（快速验证）
& .\sim\scripts\test_desktop_video.ps1 "C:\path\to\video.mp4" -MaxFrames 10
```

视频处理流程：

1. **MP4 → RAW8**：`video_to_raw.py` 逐帧提取灰度图并拼接
2. **Vivado 仿真**：`vision_pipeline_video_tb` 逐帧运行检测+画框
3. **RAW10/16 → MP4**：`raw_to_video.py` 还原灰度帧，叠加帧号和检测坐标，输出 MP4

输出视频中每帧左下角标注帧号和检测结果（坐标 + 亮像素数），绿色矩形框标记检测到的目标位置。

也可以手动分步运行：

```powershell
# Step 1: MP4 -> RAW8
C:\Users\Lenovo\miniconda3\python.exe sim/scripts/video_to_raw.py video.mp4 sim/data/input/video_640x400.raw

# Step 2: 运行仿真
& "D:\Xilinx\Vivado\2023.2\bin\vivado.bat" -mode batch -source vivado/run_sim.tcl -tclargs vision_pipeline_video_tb

# Step 3: RAW10/16 -> 标注 MP4
C:\Users\Lenovo\miniconda3\python.exe sim/scripts/raw_to_video.py sim/data/output/boxed_video_640x400.raw sim/data/output/boxed_result.mp4 --fps 30
```

详细步骤见 `docs/仿真操作手册.md`。

独立综合检查指定模块：

```powershell
& "D:\Xilinx\Vivado\2023.2\bin\vivado.bat" -mode batch -source vivado/check_synth.tcl -tclargs brightest_window
```

仿真自动结束，并在 Tcl Console 中打印：

```text
PASS: brightest_window found (3,2), bright_count=4
```

## 编辑规则

主要使用 VS Code 编辑仓库中的源码，使用 Vivado 仿真、综合、实现和下载。

不要编辑 `build/` 中的文件；它们随时可能被重新生成。

## 模块目录规则

每个模块都放在独立目录中：

```text
modules/
  camera_capture/
    camera_capture.sv       可综合实现
    camera_capture_tb.sv    独立测试
    README.md               变量、接口、时序和限制
```

新增模块时也遵循相同结构。跨多个模块共用的图片、RAW数据和Python工具仍放在 `sim/`。