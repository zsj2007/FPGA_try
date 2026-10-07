# axis_video_passthrough

这是最简单的视频流模块：输入数据和控制信号直接连接到输出。

它用于学习 AXI4-Stream 风格的 `valid/ready` 握手，也作为后续算法流水线尚未实现时的占位模块。

一次传输只在下面条件同时为1时发生：

```text
tvalid && tready
```

| 信号 | 含义 |
|---|---|
| `s_axis_*` | 从上游进入本模块的流 |
| `m_axis_*` | 本模块发送给下游的流 |
| `tdata` | 像素数据 |
| `tvalid` | 上游提供的数据有效 |
| `tready` | 下游当前能够接收数据 |
| `tuser` | 一帧的第一个像素 |
| `tlast` | 一行的最后一个像素 |

这里的 `s` 表示 slave/input side，`m` 表示 master/output side。

测试文件 `axis_video_passthrough_tb.sv` 检查像素和控制信号能否原样通过，以及下游 `ready` 能否传回上游。

