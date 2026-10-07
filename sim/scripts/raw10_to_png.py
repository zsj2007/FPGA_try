"""Convert little-endian 16-bit words containing 10-bit pixels to PNG."""

import argparse
from array import array
from pathlib import Path
import sys

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert packed RAW10-in-16-bit simulation output to PNG."
    )
    parser.add_argument("input_raw", type=Path)
    parser.add_argument("output_png", type=Path)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=400)
    parser.add_argument("--frame", type=int, default=0)
    args = parser.parse_args()

    raw = args.input_raw.read_bytes()
    frame_words = args.width * args.height
    frame_bytes = frame_words * 2
    if len(raw) % frame_bytes:
        raise SystemExit(
            f"Input size {len(raw)} is not a whole number of RAW10/16 frames "
            f"({frame_bytes} bytes/frame)."
        )
    frame_count = len(raw) // frame_bytes
    if not 0 <= args.frame < frame_count:
        raise SystemExit(
            f"Frame index {args.frame} is out of range; "
            f"file contains {frame_count} frame(s)."
        )

    start = args.frame * frame_bytes
    words = array("H")
    words.frombytes(raw[start : start + frame_bytes])
    if sys.byteorder != "little":
        words.byteswap()

    invalid = sum(value > 1023 for value in words)
    if invalid:
        raise SystemExit(f"Output contains {invalid} value(s) outside 10-bit range.")

    # Convert 0..1023 to 0..255. The FPGA input expansion uses RAW8 << 2,
    # so shifting back by two reconstructs ordinary image brightness.
    pixels = bytes(value >> 2 for value in words)
    args.output_png.parent.mkdir(parents=True, exist_ok=True)
    Image.frombytes("L", (args.width, args.height), pixels).save(args.output_png)
    print(
        f"Wrote {args.output_png}: frame {args.frame} of {frame_count}, "
        f"{args.width}x{args.height} 10-bit grayscale scaled to PNG"
    )


if __name__ == "__main__":
    main()
