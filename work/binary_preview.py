"""
binary_preview.py — 将原始视频按阈值二值化，输出MP4预览。
配置从 threshold_config.json 读取，命令行可覆盖。
用法:
    python binary_preview.py                           # 用配置文件
    python binary_preview.py --threshold 800           # 覆盖阈值
    python binary_preview.py -i input.mp4 -t 900       # 覆盖输入和阈值
"""
import cv2
import json
import os
import argparse
import numpy as np

# ── 默认值 ──────────────────────────────────────────
CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "threshold_config.json")

DEFAULTS = {
    "threshold": 1000,
    "input_video": "",
    "output_video": "",
    "width": 640,
    "height": 400,
    "fps": 30,
    "invert": False
}

# ── 加载配置 ────────────────────────────────────────
def load_config(path):
    cfg = DEFAULTS.copy()
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            file_cfg = json.load(f)
        cfg.update(file_cfg)
    return cfg

# ── 主逻辑 ──────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Binary threshold preview")
    parser.add_argument("-i", "--input", help="Input MP4 path")
    parser.add_argument("-o", "--output", help="Output MP4 path")
    parser.add_argument("-t", "--threshold", type=int, help="Threshold (0-1023)")
    parser.add_argument("--invert", action="store_true", help="Invert: white->black")
    parser.add_argument("--width", type=int, help="Resize width")
    parser.add_argument("--height", type=int, help="Resize height")
    args = parser.parse_args()

    cfg = load_config(CONFIG_PATH)

    # 命令行覆盖
    if args.threshold is not None:
        cfg["threshold"] = args.threshold
    if args.input:
        cfg["input_video"] = args.input
    if args.output:
        cfg["output_video"] = args.output
    if args.invert:
        cfg["invert"] = True
    if args.width:
        cfg["width"] = args.width
    if args.height:
        cfg["height"] = args.height

    # 校验
    if not cfg["input_video"] or not os.path.exists(cfg["input_video"]):
        print(f"ERROR: input video not found: {cfg['input_video']}")
        return

    os.makedirs(os.path.dirname(cfg["output_video"]), exist_ok=True)

    threshold = cfg["threshold"]
    w, h = cfg["width"], cfg["height"]
    invert = cfg["invert"]
    high_val = 255
    low_val = 0

    cap = cv2.VideoCapture(cfg["input_video"])
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cfg["fps"]

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(cfg["output_video"], fourcc, fps, (w, h), isColor=True)

    print(f"Input:  {cfg['input_video']} ({total} frames)")
    print(f"Output: {cfg['output_video']}")
    print(f"Threshold: {threshold}  Size: {w}x{h}  Invert: {invert}  FPS: {fps}")
    print()

    for i in range(total):
        ret, frame = cap.read()
        if not ret:
            break

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        resized = cv2.resize(gray, (w, h))

        # 二值化 (10-bit 范围, 但视频是 8-bit, 阈值是 10-bit 尺度)
        # 输入 8-bit 灰度 [0,255] -> 扩展到 10-bit [0,1023]
        pixels_10bit = resized.astype(np.uint16) << 2
        binary_10bit = (pixels_10bit >= threshold).astype(np.uint8)

        if invert:
            binary_10bit = 1 - binary_10bit

        # 输出: 白=255, 黑=0
        vis = binary_10bit * 255
        vis_bgr = cv2.cvtColor(vis, cv2.COLOR_GRAY2BGR)

        # 叠加上帧号和阈值信息
        cv2.putText(vis_bgr, f"Frame: {i+1}/{total}  Thresh: {threshold}",
                    (8, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)

        # 统计白像素数
        white_count = np.sum(binary_10bit)
        cv2.putText(vis_bgr, f"White px: {white_count} ({100*white_count/(w*h):.1f}%)",
                    (8, 42), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)

        out.write(vis_bgr)

        if (i + 1) % 100 == 0:
            print(f"  {i+1}/{total} frames...")

    cap.release()
    out.release()

    size_mb = os.path.getsize(cfg["output_video"]) / 1024 / 1024
    print(f"\nDone. Output: {cfg['output_video']} ({size_mb:.1f} MB)")

    # 回写配置（记录最后使用的参数）
    cfg_to_save = {
        "threshold": cfg["threshold"],
        "input_video": cfg["input_video"].replace("\\", "/"),
        "output_video": cfg["output_video"].replace("\\", "/"),
        "width": cfg["width"],
        "height": cfg["height"],
        "fps": cfg["fps"],
        "invert": cfg["invert"]
    }
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg_to_save, f, indent=4, ensure_ascii=False)


if __name__ == "__main__":
    main()
