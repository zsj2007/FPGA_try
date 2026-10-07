import json, numpy as np

# 1. Detection JSON for frame 637
with open(r"D:\new_FPGA\sim\data\output\vid_2727_dets.json", "r") as f:
    dets = json.load(f)
d = dets[636]
print("=== FPGA CCL detection (frame 637) ===")
for k, v in d.items():
    print(f"  {k}: {v}")
bw = d["bbox_r"] - d["bbox_l"] + 1
bh = d["bbox_b"] - d["bbox_t"] + 1
print(f"  bbox size: {bw} x {bh}")

# 2. Binary preview
raw = np.fromfile(r"D:\new_FPGA\sim\data\input\vid_2727_640x400.raw", dtype=np.uint8)
frame = raw[636*640*400:(636+1)*640*400].reshape(400, 640)
p10 = frame.astype(np.uint16) << 2
binary = p10 >= 1000
ys, xs = np.where(binary)
print(f"\n=== Binary (thresh=1000) frame 637 ===")
print(f"  White pixels: {len(xs)}")
if len(xs) > 0:
    print(f"  True X: {xs.min()}-{xs.max()}  Y: {ys.min()}-{ys.max()}")
    print(f"  True bbox: ({xs.min()},{ys.min()})-({xs.max()},{ys.max()})")
    tw = xs.max() - xs.min() + 1
    th = ys.max() - ys.min() + 1
    print(f"  True size: {tw} x {th}")
    print(f"  First 40 coords:")
    pts = list(zip(xs[:40], ys[:40]))
    for i, (x, y) in enumerate(pts):
        print(f"    ({x},{y})", end="" if (i+1) % 10 else "\n")
    print()
    
    # Compare
    print(f"\n=== COMPARISON ===")
    print(f"  FPGA bbox:   ({d['bbox_l']},{d['bbox_t']})-({d['bbox_r']},{d['bbox_b']})")
    print(f"  True bbox:   ({xs.min()},{ys.min()})-({xs.max()},{ys.max()})")
    match_l = d["bbox_l"] == xs.min()
    match_r = d["bbox_r"] == xs.max()
    match_t = d["bbox_t"] == ys.min()
    match_b = d["bbox_b"] == ys.max()
    print(f"  left  match: {match_l}")
    print(f"  right match: {match_r}")
    print(f"  top   match: {match_t}")
    print(f"  bot   match: {match_b}")
