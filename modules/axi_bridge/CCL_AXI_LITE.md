# CCL AXI4-Lite 接口（已用 Vivado 2023.2 XSim 验证）

RTL 顶层：`ccl_axi_lite.sv`，内部连接 `ccl_analyzer_pl.sv` 与事件 FIFO，再通过 AXI4-Lite 供 PS 访问。与同目录原有 `axi_ccl_bridge.sv` 是独立的实现，接口/地址不兼容。

## 运行仿真

PowerShell，任意目录运行：

```powershell
& 'D:\Xilinx\Vivado\2023.2\bin\vivado.bat' -mode batch -source D:\new_FPGA\vivado\run_ccl_axi_sim.tcl
```

脚本创建独立工程 `D:/new_FPGA/build/ccl_axi/ccl_axi.xpr`，以 `ccl_axi_lite_tb` 为仿真顶层。也可在 Vivado 打开此工程，点击 Run Behavioral Simulation，在波形中查看 DUT 的 AXI 总线、FIFO count、pixel_ready、结果输出。

通过标志：控制台 `PASS: CCL AXI4-Lite integration`；输出目录 `build/ccl_axi/ccl_axi.sim/sim_1/behav/xsim/` 中有 `ccl_axi_pass.txt`、`simulate.log`、`ccl_axi_events.txt` 和波形数据库。脚本在本轮没有产生 PASS 文件时返回错误，避免 `$fatal` 后仍误报通过。

`vivado/create_project.tcl` 也已包含新增 RTL 和 testbench；重建主工程后可将 `ccl_axi_lite_tb` 设为 Simulation Top。旧工程已打开时需手动 Add Sources 或直接打开上面的独立工程。

## 寄存器（相对于 PS 分配的 AXI 基地址）

32 位数据，8 位字节地址，所有访问 4 字节对齐。支持独立 AW/W、WSTRB、B/R 响应背压，一次一个未完成读、一个未完成写。

| 字节偏移 | 访问 | 内容 |
|---|---|---|
| 0x00 | R | bit0: FIFO 非空；bit1: FIFO 满；bit2: pixel_ready |
| 0x04 | R | FIFO 当前完整事件数 |
| 0x08 | W | bit0 写1：POP 一条事件；空 FIFO POP 返回 SLVERR |
| 0x20..0x3C | R | FIFO 队头事件，8×32 位，先读完再 POP；空读 SLVERR |
| 0x40 | RW | 暂存质心：高16位 y，低16位 x |
| 0x44 | RW | 暂存包围盒 x：高16位 right，低16位 left |
| 0x48 | RW | 暂存包围盒 y：高16位 bottom，低16位 top |
| 0x4C | RW | 暂存面积，32位 |
| 0x50 | RW | 暂存目标有效标志 bit0 |
| 0x54 | RW | 暂存软件帧号，32位 |
| 0x58 | W | bit0 写1：COMMIT，原子更新全部结果输出，result_valid 拉高一周期 |

未定义地址、非对齐地址及写只读寄存器返回 SLVERR。命令只有 WSTRB[0] 有效时执行。暂存寄存器支持逐字节写，读回的是暂存值。写 0 或零 strobe 的命令不执行。

队头事件只在 POP 时移动，因此 PS 可用 8 次 MMIO 读取同一事件，不会读到混合记录。事件格式见 `software/ccl_split/README.md`。只允许一个软件消费者，不能在事件读取中途 POP。

## PS C 调用

新增 `software/ccl_split/ccl_axi.h/.c` 与 `ccl_ps.h/.c` 一起编译。典型处理循环：

```c
static ccl_context context;
static uint32_t frame_id;
uint32_t words[8];
// axi_base 由 Vitis BSP 的地址定义获得；映射为 Device/uncached。
if (ccl_axi_read_event(axi_base, words)) {
    int status = ccl_ps_feed(&context, words);
    if ((words[0] & 255u) == 3u) {
        ccl_target target = {0};
        if (status == 1) target = ccl_ps_select(&context, 25);
        ccl_axi_write_target(axi_base, &target, frame_id++);
    }
}
```

在主循环重复调用，或配合平台驱动调度。这里使用轮询，没有中断输出。MMIO 顺序与屏障需遵循板级 BSP 和 ARM Device 内存属性要求；不要把寄存器映射成普通可缓存 RAM。

PS 实际代码离线重放测试（输入由 XSim 的 AXI 主机模型读取）：

```powershell
Set-Location D:\new_FPGA
gcc -std=c11 -Wall -Wextra -Werror -I software/ccl_split software/ccl_split/ccl_ps.c software/ccl_split/ccl_axi.c software/ccl_split/test_xsim_events.c -o build/ccl_axi/test_xsim_events.exe
& ./build/ccl_axi/test_xsim_events.exe ./build/ccl_axi/ccl_axi.sim/sim_1/behav/xsim/ccl_axi_events.txt
```

## 验证范围与板级连接

XSim 中的 SystemVerilog 总线主机模拟 PS 的 AXI 访问，检查合并事件、结果暂存/提交；ARM 处理器并未在 XSim 执行 C。实际 C 使用 XSim 导出的事件另行重放。5 帧覆盖面积/坐标和/包围盒、空帧、溢出及恢复，多条 UNION；AXI 覆盖 AW/W 不同时到达、R/B 背压、WSTRB、错误访问、未 POP 队头稳定、FIFO 满阻塞、复位清除未匹配 AW。仿真 FIFO 深度3，覆盖非2次幂指针回绕。

板级接线：Zynq PS M_AXI_GP0 → AXI Interconnect/SmartConnect → 本模块 S_AXI。ACLK 与该 AXI 总线同频；aresetn 使用同步到 aclk 的外部复位释放。像素输入也必须属于 aclk 时钟域且遵守 pixel_ready。摄像头 pclk 不同时必须加异步 FIFO；不可直接跨时钟。

本模块有真实 AXI4-Lite slave，但尚未生成包含 PS7 的 Block Design、固定 PS 基地址或替换旧 `vision_pipeline` 的摄像头路径。结果输出可接 overlay；COMMIT 原子更新不代表与视频帧边界对齐，应用仍需按 result_frame_id 在帧边界锁存结果。

AXI4-Lite 轮询适合当前接口验证，实际高帧率事件量大时建议换成 AXI Stream DMA。FIFO 满会反压到像素接口；不能暂停的摄像头需要额外缓存/丢整帧策略。尚未进行综合、时序或开发板验证。
