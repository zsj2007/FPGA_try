# PS 端软件 — CCL 标签归并与目标筛选

## 文件

| 文件 | 说明 |
|------|------|
| `ps_ccl_merge.h` | API 头文件：数据结构 + 函数声明 |
| `ps_ccl_merge.c` | 并查集归并 + 长宽比筛选 + AXI 读写 |

## 处理流程

```
ccl_wait_frame()           — 轮询 frame_ready
    ↓
ccl_read_labels()          — 通过 AXI4-Lite 读 PL BRAM 标签统计表
    ↓
ccl_merge_labels()         — union-find 标签归并（路径压缩）
    ↓
ccl_select_target()        — 长宽比筛选：|w-h| 最小者胜，平局选大面积
    ↓
ccl_write_result()         — 写目标特征回 PL BRAM
    ↓
ccl_swap_banks()           — 交换缓冲区，通知 PL 继续
```

## 目标筛选逻辑

1. 过滤 area < MIN_AREA（默认 25）
2. 只考虑 root 标签（parent == self）
3. 计算 `|w - h|` 最小 → 长宽比最接近 1:1
4. 平局决胜：area 更大者胜

## 编译

ARM Cortex-A9 bare-metal（Xilinx Vitis / SDK）：
```bash
arm-none-eabi-gcc -mcpu=cortex-a9 -O2 -c ps_ccl_merge.c
```
