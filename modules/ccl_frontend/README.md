# ccl_frontend — PL 端流式 CCL 前端

## 功能

每周期处理一个二值像素，完成：
1. 四邻域（左、上）临时标签分配
2. 每标签实时统计累加：面积、sum_x、sum_y、外接矩形 min/max
3. 标签等价关系记录（union-find parent 指针）
4. 帧末通过 dump 接口将所有标签数据导出给 AXI 桥

## 设计要点

- **分布式 RAM**：行缓冲（640×8bit）、统计表（64×152bit）、等价表（64×8bit）全部用 LUTRAM，读写均为组合逻辑或单周期，无 RAW 冲突
- **首行门控**：`first_line` 标志位屏蔽新帧首行的 `above_label` 读取，防止读到上帧末行残留标签
- **标签溢出**：`label_full` 标志位，超过 MAX_LABELS 后新白像素强制标签 0（丢弃）
- 帧末 dump 逐标签输出所有 MAX_LABELS 条目，PS 侧按 area > 0 过滤有效标签

## 接口

### 输入（来自形态学模块）

| 信号 | 说明 |
|------|------|
| pixel_valid / frame_start / line_start / line_end | 像素流控制 |
| pixel_x / pixel_y | 坐标 |
| binary_data | 二值输入（1=白） |

### 输出（dump 接口 → axi_ccl_bridge）

| 信号 | 说明 |
|------|------|
| dump_valid | dump 有效（持续 MAX_LABELS 周期） |
| dump_label | 当前标签号 |
| dump_area / dump_sum_x / dump_sum_y | 面积、坐标累加和 |
| dump_min_x / max_x / min_y / max_y | 外接矩形 |
| dump_equiv_parent | 等价表 parent 指针 |
| frame_done | dump 完成脉冲 |
| num_labels | 本帧使用的标签数 |

## 资源估算

| 资源 | 用量 | 说明 |
|------|------|------|
| SLICEM LUT | ~250 | 分布式 RAM |
| FF | ~100 | 控制寄存器 |
| BRAM | 0 | 全部使用 LUTRAM |
