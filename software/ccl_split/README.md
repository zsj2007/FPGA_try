# CCL 拆分：PL 临时标签，PS 并查集

本实现从 `modules/blob_analyzer/ccl_analyzer.sv` 拆出算法职责，新增：

- `modules/blob_analyzer/ccl_analyzer_pl.sv`：PL 四连通扫描、临时标签分配、逐标签统计、等价关系输出。
- `software/ccl_split/ccl_ps.h/.c`：PS 用 C 做按秩合并、路径压缩、统计汇总及目标筛选。
- `software/ccl_split/test_split.py`：RTL → 事件 → C → 独立 flood-fill 对照验证。

现有 `ccl_analyzer.sv` 和 `vision_pipeline.sv` 仍为原来的纯 PL 路径。现在已新增 AXI4-Lite 接口、结果回写驱动和 Vivado XSim 工程入口，见 `modules/axi_bridge/CCL_AXI_LITE.md`；尚未完成开发板 PS Block Design、DMA、缓存一致性、中断、CDC 和视频叠框集成。原来未提交的 `modules/ccl_frontend/`、`modules/axi_bridge/axi_ccl_bridge.sv`、`software/ps_ccl_merge.*` 保持原样；它们的协议与本实现不兼容。

## 为什么不能只把旧 parent 数组搬到 PS

扫描到前景像素时，只看左邻 L、上邻 U：两者为 0 则分配新标签；只有一个非零则继承；两者非零则采用 L，并记录 `union(L,U)`。

PL 不查祖先，也不改 parent。临时标签之间可以存在多条等价边，必须全部保留。旧代码 `lbl_merge[above] = left` 会覆盖旧关系，直接连任意标签还可能成环；帧末最多追两级也无法解决任意深度的关系。PS 必须先 `find(L)`、`find(U)`，再连接两个根。

每个前景像素恰好记入一个临时标签的统计。PS 接收全部 UNION 后，将每个 STAT 加入最终根一次，避免漏计或重复计数。重复或反向 UNION 无害。这里维持原代码的四连通语义，斜对角接触不合并。

## PL 接口及边界

输入按完整图像从左到右、从上到下发送，包含背景像素，坐标从 `(0,0)` 开始。`frame_start` 与首像素一起有效。只有 `pixel_valid && pixel_ready` 才接收像素；阻塞期间发送方必须保持数据、坐标和 `frame_start` 不变。行边界由 x 坐标判断，帧结束由最后坐标判断，无需额外 line_start/line_end。

输出为 256 位 ready/valid 事件，阻塞时保持不变。只有 `event_valid && event_ready` 才传输。第一行屏蔽上方标签，行首屏蔽左标签，因此 RAM 不需要逐帧清零。每个新标签初始化自己的统计。

扫描末尾暂停输入，导出本帧所有 STAT 和 END，然后接收下一帧。这是单缓冲结构；下游持续 ready 时，帧间需约 `临时标签数 + 2` 个周期完成导出，背压会延长时间。

`MAX_LABELS` 范围 2..256，标签 0 为背景，因此最多 `MAX_LABELS-1` 个临时标签。注意临时标签数可远大于最终连通域数。耗尽时 END 标记 overflow，PS 丢弃整帧结果，下一 START 恢复。不能把截断帧当成有效识别结果。

单标签面积、坐标和为 32 位；维度约束在 RTL elaboration 检查，默认 640×400 满足要求。PS 使用 64 位累加。

## 事件协议

一个事件固定 8 个 `uint32_t`，`words[0] = event_data[31:0]`，以此类推。传输适配层必须保证事件完整、有序；不允许丢弃 UNION。未使用位为 0。

| 类型 | words[0] | words[1] | words[2] | words[3] | words[4] | words[5] |
|---|---|---|---|---|---|---|
| START | 0 | 0 | 0 | 0 | 0 | 0 |
| UNION | `1 \| (L<<8) \| (U<<16)` | 0 | 0 | 0 | 0 | 0 |
| STAT | `2 \| (label<<8)` | area | sum_x | sum_y | `(max_x<<16) \| min_x` | `(max_y<<16) \| min_y` |
| END | `3 \| (count<<8)` | bit0: overflow | 0 | 0 | 0 | 0 |

`words[6:7]` 保留为 0。顺序严格为 START → 零到多个 UNION → 标签 1..count 的 STAT → END。count 不包含背景，范围 0..255。全黑帧只有 START 和 END。

PS 调用示例（传输层提供完整事件）：

```c
static ccl_context context; // 静态零初始化，避免占用裸机小栈
uint32_t words[8];
// transport_read_event(words); // 由板级驱动实现
int status = ccl_ps_feed(&context, words);
if (status == 1) {
    ccl_target result = ccl_ps_select(&context, 25);
    // 回写 result.valid、质心及包围盒；空帧需清除旧目标。
} else if (status < 0) {
    // 本帧无效，等待下一个 START；不要提交部分统计。
}
```

`ccl_ps_select` 保留原代码实际的筛选规则：最小 `abs(width-height)`，并列取面积较大者。质心为坐标和除面积取整。这不是严格的圆度检测；原来的 `CIRC_TARGET_Q16` 并未参与实际筛选，因此没有迁入新接口。

## 接入视频与 PS

建议路径：二值/形态学 → 输入缓冲 → ccl_analyzer_pl → 事件 FIFO/AXI Stream DMA → DDR → PS C → 结果寄存器 → PL overlay。

1. 摄像头不能响应 ready 时，要保证输入缓冲覆盖事件阻塞和帧尾导出，或增加双缓冲。不能直接忽略 `pixel_ready`。持续下游拥塞无法靠有限 FIFO 消除，需设计丢整帧/重同步策略。
2. 不同时钟域用异步 FIFO；软件不应逐像素轮询事件。事件最坏可接近每像素一条 32 字节记录，必须按实际帧率和最坏图案核算 DMA 带宽及缓存容量；后续可用等价边去重降低典型带宽。
3. 传输适配层负责固定长度事件封包、帧序号及 DMA 完成边界。PS 读 DMA 缓存前做平台要求的 cache invalidate。
4. PS 结果按帧号或约定延迟回写，并在 PL 帧边界原子更新；软件处理延迟未必是一帧，不能沿用原来默认的一帧叠框对齐假设。
5. `vivado/create_project.tcl` 已包含新 RTL 和 AXI testbench，独立仿真入口为 `vivado/run_ccl_axi_sim.tcl`。新增 `ccl_axi_lite` 顶层引出 AXI 和结果回写接口；开发板需完成 PS Block Design 及摄像头 CDC 后才能替换旧实例。这里未固定 PS 基地址，未修改原视频顶层连接。

## 验证

在仓库根目录运行 `python software/ccl_split/test_split.py`，需要 PATH 中的 Python、GCC、Icarus Verilog。

覆盖 111 帧：全黑/全白、末像素首次分配标签、棋盘格、桥接图案、100 帧随机图、1×1 连续帧、标签溢出及恢复。随机插入输入空拍和输出背压，检查 stalled 事件稳定；将全部有效帧的每个连通域面积、坐标和及包围盒与 Python 独立四连通搜索比较。另检查长链、重复/反向等价边及缺失统计拒绝。GCC 使用 `-Wall -Wextra -Werror`。尚未进行 Vivado 综合、时序收敛和上板验证。
