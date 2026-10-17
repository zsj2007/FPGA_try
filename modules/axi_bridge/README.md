# axi_ccl_bridge — AXI4-Lite 双缓冲 BRAM 桥

## 功能

连接 PL 端 CCL dump 接口与 PS 端 AXI4-Lite 总线。实现双缓冲机制：CCL 写完一个 Bank 后 PS 读取，同时 CCL 可写另一个 Bank（乒乓操作）。

## 内存映射

| 偏移 | 内容 |
|------|------|
| 0x000-0x0FC | 标签统计表（64 标签 × 5 字） |
| 0x100 | num_labels[7:0] |
| 0x104 | 控制/状态寄存器 |
| 0x200-0x210 | PS 回写目标结果 |

### 标签统计表（每标签 5×32bit）

| 字 | 位 | 内容 |
|----|-----|------|
| 0 | [23:0] | area |
| 0 | [31:24] | equiv_parent |
| 1 | [31:0] | sum_x |
| 2 | [31:0] | sum_y |
| 3 | [15:0] | min_x |
| 3 | [31:16] | max_x |
| 4 | [15:0] | min_y |
| 4 | [31:16] | max_y |

### 控制寄存器（0x104）

| 位 | 方向 | 说明 |
|----|------|------|
| 0 | W | bank_swap：写 1 交换缓冲区（自清） |
| 1 | R | frame_ready：新帧数据就绪 |

## 接口

| 信号组 | 说明 |
|--------|------|
| CCL dump | 来自 ccl_frontend 的逐标签导出 |
| AXI4-Lite | PS 主设备读写接口 |

## 双缓冲流程

```
帧 N 结束 → CCL dump 写 Bank A → PS 读 Bank A (处理帧 N)
                                    ↓
                              PS 写回结果 → overlayer 读
帧 N+1 结束 → CCL dump 写 Bank B → PS 读 Bank B (处理帧 N+1)
```
