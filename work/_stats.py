import json
with open(r"D:\new_FPGA\sim\data\output\vid_2727_dets.json", "r") as f:
    dets = json.load(f)
total = len(dets)
found = sum(1 for d in dets if d["found"])
nofound = total - found
areas = [d["area"] for d in dets if d["found"]]
ratios = [d["ratio"] for d in dets if d["found"]]
zero_ratio = sum(1 for r in ratios if r == 0)
print(f"Total frames: {total}")
print(f"Target found: {found}, not found: {nofound}")
if areas:
    print(f"Area: min={min(areas)} max={max(areas)} avg={sum(areas)/len(areas):.0f}")
if ratios:
    print(f"Ratio Q16: min={min(ratios)} max={max(ratios)} avg={sum(ratios)/len(ratios):.0f}")
    print(f"Zero ratios: {zero_ratio}/{len(ratios)} ({100*zero_ratio/len(ratios):.0f}%)")
print("\nFirst 3:")
for d in dets[:3]:
    print(f"  f={d['frame']} found={d['found']} x={d['x']} y={d['y']} area={d['area']} bbox=({d['bbox_l']},{d['bbox_t']})-({d['bbox_r']},{d['bbox_b']})")
print("Last 3:")
for d in dets[-3:]:
    print(f"  f={d['frame']} found={d['found']} x={d['x']} y={d['y']} area={d['area']} bbox=({d['bbox_l']},{d['bbox_t']})-({d['bbox_r']},{d['bbox_b']})")
