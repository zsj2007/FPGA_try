"""Convert MP4 video to concatenated headerless RAW8 grayscale frames.

Each frame is resized to the target dimensions and converted to 8-bit
grayscale, then all frames are written back-to-back as a single RAW8 file.
Frame count, resolution, and original FPS are saved as sidecar metadata.
"""

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert MP4/AVI/MOV to concatenated 8-bit grayscale RAW."
    )
    parser.add_argument("input_video", type=Path)
    parser.add_argument("output_raw", type=Path)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=400)
    parser.add_argument(
        "--fit",
        choices=("crop", "contain", "stretch"),
        default="crop",
    )
    parser.add_argument(
        "--max-frames",
        type=int,
        default=0,
        help="Maximum frames to convert (0 = all frames)",
    )
    args = parser.parse_args()

    cap = cv2.VideoCapture(str(args.input_video))
    if not cap.isOpened():
        raise SystemExit(f"Cannot open video: {args.input_video}")

    src_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    src_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    print(f"Input: {src_w}x{src_h} @ {fps:.2f} FPS, {total_frames} frames")

    frame_limit = args.max_frames if args.max_frames > 0 else total_frames
    print(f"Output: {args.width}x{args.height}, max {frame_limit} frames")

    raw_bytes = bytearray()
    frame_idx = 0
    while frame_idx < frame_limit:
        ret, frame_bgr = cap.read()
        if not ret:
            break

        gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
        h, w = gray.shape

        # Fit to target size.
        if args.fit == "crop":
            scale = max(args.width / w, args.height / h)
            new_w = int(w * scale)
            new_h = int(h * scale)
            resized = cv2.resize(gray, (new_w, new_h))
            left = (new_w - args.width) // 2
            top = (new_h - args.height) // 2
            frame = resized[top:top + args.height, left:left + args.width]
        elif args.fit == "contain":
            scale = min(args.width / w, args.height / h)
            new_w = int(w * scale)
            new_h = int(h * scale)
            resized = cv2.resize(gray, (new_w, new_h))
            frame = np.zeros((args.height, args.width), dtype=np.uint8)
            left = (args.width - new_w) // 2
            top = (args.height - new_h) // 2
            frame[top:top + new_h, left:left + new_w] = resized
        else:
            frame = cv2.resize(gray, (args.width, args.height))

        raw_bytes.extend(frame.tobytes())
        frame_idx += 1
        if (frame_idx) % 50 == 0:
            print(f"  converted {frame_idx} / {frame_limit} frames...")

    cap.release()
    actual_frames = frame_idx
    print(f"Converted {actual_frames} frames")

    if actual_frames == 0:
        raise SystemExit("No frames extracted from video")

    args.output_raw.parent.mkdir(parents=True, exist_ok=True)
    args.output_raw.write_bytes(raw_bytes)

    meta = {
        "source": str(args.input_video),
        "fps": fps,
        "width": args.width,
        "height": args.height,
        "frame_count": actual_frames,
        "source_width": src_w,
        "source_height": src_h,
        "fit": args.fit,
    }
    meta_path = args.output_raw.with_suffix(args.output_raw.suffix + ".json")
    meta_path.write_text(json.dumps(meta, indent=2))
    print(f"Metadata: {meta_path}")
    print(
        f"Wrote {args.output_raw}: {args.width}x{args.height}, "
        f"{actual_frames} frames, "
        f"{args.output_raw.stat().st_size:,} bytes"
    )


if __name__ == "__main__":
    main()