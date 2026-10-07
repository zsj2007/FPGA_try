"""Convert concatenated RAW10/16 frames to annotated MP4 video.

Reads a multi-frame simulation output file containing little-endian 16-bit
words (each word holds a 10-bit grayscale pixel).  Each frame is scaled to
8 bits and written into an MP4 with optional overlay information including
detection results and LOS guidance data computed via pinhole camera model.
"""

import argparse
import json
import math
from array import array
from pathlib import Path
import sys

import cv2
import numpy as np


def compute_los(detections, width, height, fps):
    sensor_w_mm = 3.9
    sensor_h_mm = 2.45
    focal_mm = 2.0
    cx = width / 2.0
    cy = height / 2.0
    pixel_size_w = sensor_w_mm / width
    pixel_size_h = sensor_h_mm / height
    dt = 1.0 / fps if fps > 0 else 1.0 / 30.0

    prev_hfov = None
    prev_vfov = None

    for f_idx in sorted(detections.keys()):
        d = detections[f_idx]
        if not d.get("found"):
            d["hfov_deg"] = None
            d["vfov_deg"] = None
            d["omega_hfov"] = None
            d["omega_vfov"] = None
            prev_hfov = None
            prev_vfov = None
            continue

        dx_px = d["x"] + d.get("box_w", 20) / 2.0 - cx
        dy_px = d["y"] + d.get("box_h", 20) / 2.0 - cy

        dx_mm = dx_px * pixel_size_w
        dy_mm = dy_px * pixel_size_h

        hfov_rad = math.atan2(dx_mm, focal_mm)
        vfov_rad = math.atan2(dy_mm, focal_mm)
        hfov_deg = math.degrees(hfov_rad)
        vfov_deg = math.degrees(vfov_rad)
        d["hfov_deg"] = hfov_deg
        d["vfov_deg"] = vfov_deg

        if prev_hfov is not None:
            d["omega_hfov"] = (hfov_rad - prev_hfov) / dt
            d["omega_vfov"] = (vfov_rad - prev_vfov) / dt
        else:
            d["omega_hfov"] = 0.0
            d["omega_vfov"] = 0.0

        prev_hfov = hfov_rad
        prev_vfov = vfov_rad


def draw_overlay(frame, frame_idx, total_frames, detection):
    h, w = frame.shape[:2]
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, h - 36), (w, h), (0, 0, 0), -1)
    frame = cv2.addWeighted(frame, 0.6, overlay, 0.4, 0)

    text = f"Frame {frame_idx + 1} / {total_frames}"
    cv2.putText(frame, text, (8, h - 20), cv2.FONT_HERSHEY_SIMPLEX,
                0.45, (200, 200, 200), 1, cv2.LINE_AA)

    if detection and detection.get("found"):
        d = detection
        area = d.get("area", d.get("count", 0)); bbox_l = d.get("bbox_l",0); bbox_r = d.get("bbox_r",0); label = f"cx={d['x']} cy={d['y']} area={area} bbox=({bbox_l},{d.get('bbox_t',0)})-({bbox_r},{d.get('bbox_b',0)})"
        cv2.putText(frame, label, (8, h - 4), cv2.FONT_HERSHEY_SIMPLEX,
                    0.40, (200, 200, 200), 1, cv2.LINE_AA)

    return frame


def draw_los_overlay(frame, los):
    if los is None:
        return frame
    h, w = frame.shape[:2]
    text_lines = []
    if los.get("hfov_deg") is not None:
        text_lines.append(
            f"hfov={los['hfov_deg']:+.1f}  vfov={los['vfov_deg']:+.1f} deg")
    if los.get("omega_hfov") is not None:
        text_lines.append(
            f"omega_h={los['omega_hfov']:+.2f}  omega_v={los['omega_vfov']:+.2f} rad/s")
    for i, line in enumerate(text_lines):
        y = 12 + i * 14
        cv2.putText(frame, line, (w - 320, y), cv2.FONT_HERSHEY_SIMPLEX,
                    0.38, (0, 255, 255), 1, cv2.LINE_AA)
    return frame


def main():
    parser = argparse.ArgumentParser(
        description="Convert RAW10/16 simulation output to annotated MP4."
    )
    parser.add_argument("input_raw", type=Path)
    parser.add_argument("output_video", type=Path)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=400)
    parser.add_argument("--box-w", type=int, default=20)
    parser.add_argument("--box-h", type=int, default=20)
    parser.add_argument("--detections", type=Path, help="JSON file with per-frame detection results")
    parser.add_argument("--fps", type=float, default=0, help="Output FPS (0 = use input metadata FPS)")
    parser.add_argument("--max-frames", type=int, default=0, help="Maximum frames to process (0 = all)")
    args = parser.parse_args()

    raw = args.input_raw.read_bytes()
    frame_words = args.width * args.height
    frame_bytes = frame_words * 2

    if len(raw) % frame_bytes:
        raise SystemExit(
            f"Input size {len(raw)} is not a multiple of RAW10/16 frames "
            f"({frame_bytes} bytes/frame)")
    num_frames = len(raw) // frame_bytes
    print(f"Input: {num_frames} frame(s), {args.width}x{args.height}")

    frame_limit = args.max_frames if args.max_frames > 0 else num_frames
    frame_limit = min(frame_limit, num_frames)

    detections = {}
    if args.detections and args.detections.exists():
        raw_dets = json.loads(args.detections.read_text())
        for item in raw_dets:
            detections[item["frame"]] = item

    if args.fps > 0:
        fps = args.fps
    else:
        meta_path = args.input_raw.with_suffix(args.input_raw.suffix + ".json")
        if meta_path.exists():
            meta = json.loads(meta_path.read_text())
            fps = meta.get("fps", 30)
        else:
            fps = 30
    print(f"Output FPS: {fps:.2f}")

    compute_los(detections, args.width, args.height, fps)

    fourcc_options = [("avc1", "H.264"), ("mp4v", "MPEG-4"), ("MJPG", "M-JPEG")]
    out = None
    for fourcc_name, desc in fourcc_options:
        fourcc = cv2.VideoWriter_fourcc(*fourcc_name)
        out = cv2.VideoWriter(str(args.output_video), fourcc, fps, (args.width, args.height), True)
        if out.isOpened():
            print(f"Video encoder: {desc} ({fourcc_name})")
            break
        out.release()
        out = None

    if out is None:
        raise SystemExit("No video encoder available.")

    words = array("H")
    words.frombytes(raw)
    if sys.byteorder != "little":
        words.byteswap()

    invalid = sum(v > 1023 for v in words)
    if invalid:
        print(f"Warning: {invalid} pixel(s) outside 10-bit range, clamping.")

    for f_idx in range(frame_limit):
        start = f_idx * frame_words
        frame_pixels = words[start : start + frame_words]

        gray = np.frombuffer(
            bytes(min(v, 1023) >> 2 for v in frame_pixels),
            dtype=np.uint8,
        ).reshape((args.height, args.width))

        bgr = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)

        det = detections.get(f_idx)
        los = det
        bgr = draw_overlay(bgr, f_idx, frame_limit, det)
        bgr = draw_los_overlay(bgr, los)

        out.write(bgr)

        if (f_idx + 1) % 50 == 0:
            print(f"  wrote {f_idx + 1} / {frame_limit} frames...")

    out.release()
    print(f"Wrote {args.output_video}: {frame_limit} frames at {fps:.2f} FPS")


if __name__ == "__main__":
    main()
