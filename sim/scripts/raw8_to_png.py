"""Convert one or more headerless RAW8 grayscale frames to a PNG preview."""

import argparse
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert RAW8 grayscale to PNG.")
    parser.add_argument("input_raw", type=Path)
    parser.add_argument("output_png", type=Path)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=400)
    parser.add_argument("--frame", type=int, default=0)
    args = parser.parse_args()

    data = args.input_raw.read_bytes()
    frame_bytes = args.width * args.height
    if len(data) % frame_bytes:
        raise SystemExit(
            f"Input size {len(data)} is not a whole number of RAW8 frames "
            f"({frame_bytes} bytes/frame)."
        )
    frame_count = len(data) // frame_bytes
    if not 0 <= args.frame < frame_count:
        raise SystemExit(
            f"Frame index {args.frame} is out of range; "
            f"file contains {frame_count} frame(s)."
        )

    start = args.frame * frame_bytes
    frame = data[start : start + frame_bytes]
    args.output_png.parent.mkdir(parents=True, exist_ok=True)
    Image.frombytes("L", (args.width, args.height), frame).save(args.output_png)
    print(
        f"Wrote {args.output_png}: frame {args.frame} of {frame_count}, "
        f"{args.width}x{args.height} RAW8 grayscale"
    )


if __name__ == "__main__":
    main()
