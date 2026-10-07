"""Convert a normal image to one headerless RAW8 grayscale frame."""

import argparse
from pathlib import Path

from PIL import Image, ImageOps


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert PNG/JPEG/BMP to headerless 8-bit grayscale RAW."
    )
    parser.add_argument("input_image", type=Path)
    parser.add_argument("output_raw", type=Path)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=400)
    parser.add_argument(
        "--fit",
        choices=("crop", "contain", "stretch"),
        default="crop",
        help="crop fills the frame; contain adds black borders; stretch may distort",
    )
    args = parser.parse_args()

    with Image.open(args.input_image) as source:
        gray = ImageOps.exif_transpose(source).convert("L")
        size = (args.width, args.height)
        if args.fit == "crop":
            frame = ImageOps.fit(gray, size, method=Image.Resampling.LANCZOS)
        elif args.fit == "contain":
            frame = ImageOps.pad(
                gray, size, method=Image.Resampling.LANCZOS, color=0
            )
        else:
            frame = gray.resize(size, Image.Resampling.LANCZOS)

    args.output_raw.parent.mkdir(parents=True, exist_ok=True)
    args.output_raw.write_bytes(frame.tobytes())
    print(
        f"Wrote {args.output_raw}: {args.width}x{args.height}, "
        f"{args.output_raw.stat().st_size} bytes (one RAW8 grayscale frame)"
    )


if __name__ == "__main__":
    main()
