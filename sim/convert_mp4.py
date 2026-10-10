"""Convert boxed RAW16 output to MP4 video."""
import sys, numpy as np, cv2, os

def main():
    if len(sys.argv) < 3:
        print("Usage: python convert_mp4.py <input.raw> <output.mp4> [width] [height]")
        sys.exit(1)

    raw_path = sys.argv[1]
    out_path = sys.argv[2]
    W = int(sys.argv[3]) if len(sys.argv) > 3 else 640
    H = int(sys.argv[4]) if len(sys.argv) > 4 else 400

    fsize = os.path.getsize(raw_path)
    frames = fsize // (W * H * 2)
    print(f"  Input: {raw_path} ({fsize} bytes, {frames} frames)")

    raw16 = np.fromfile(raw_path, dtype=np.uint16).reshape(frames, H, W)
    raw8 = (raw16 >> 2).astype(np.uint8)

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(out_path, fourcc, 30, (W, H))
    for i in range(frames):
        bgr = cv2.cvtColor(raw8[i], cv2.COLOR_GRAY2BGR)
        out.write(bgr)
    out.release()
    print(f"  Output: {out_path} ({os.path.getsize(out_path) // 1024} KB)")

if __name__ == "__main__":
    main()
