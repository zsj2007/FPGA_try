"""
Pinhole-camera line-of-sight (LOS) guidance module.

Converts per-frame target detections (box center in image coordinates)
to LOS angles and angular rates using the pinhole camera model.

Reference: dart_-application alg_proportional_navigation.c

Default parameters:
  - Image: 640x400
  - Sensor region: 3.9mm x 2.45mm
  - Focal length: 2.0mm (user-specified default)
  - FPS: 30 (from video metadata)
"""

import argparse
import json
import math
from pathlib import Path


# ---- Physical constants (from dart_-application) ----
PHOTO_WIDTH  = 640.0       # px
PHOTO_HEIGHT = 400.0       # px

IMAGE_REGION_X = 3.9       # mm — sensor physical width
IMAGE_REGION_Y = 2.45      # mm — sensor physical height

PIXEL_X = IMAGE_REGION_X / PHOTO_WIDTH   # mm/px
PIXEL_Y = IMAGE_REGION_Y / PHOTO_HEIGHT  # mm/px

# Default focal length
DEFAULT_FOCUS_LENGTH_MM = 2.0  # mm

# Default image center (geometric center of 640x400)
DEFAULT_CENTER_CX = 320.0
DEFAULT_CENTER_CY = 200.0


def compute_los(
    target_x_px: float,
    target_y_px: float,
    focus_mm: float = DEFAULT_FOCUS_LENGTH_MM,
    center_cx: float = DEFAULT_CENTER_CX,
    center_cy: float = DEFAULT_CENTER_CY,
) -> dict:
    """Compute line-of-sight angles from image target coordinates.

    Parameters
    ----------
    target_x_px, target_y_px : float
        Target centre in image pixel coordinates.
    focus_mm : float
        Focal length in mm.
    center_cx, center_cy : float
        Optical centre in image pixel coordinates.

    Returns
    -------
    dict with keys:
        dx_px, dy_px    — offset from optical centre (px)
        dx_mm, dy_mm    — offset on sensor plane (mm)
        hfov, vfov  — LOS angles (radians)
        hfov_deg, vfov_deg  — LOS angles (degrees)
    """
    focus_px_x = focus_mm / PIXEL_X  # focal length in horizontal pixels
    focus_px_y = focus_mm / PIXEL_Y  # focal length in vertical pixels

    # Offset from optical centre.  X is negated per dart convention
    # (camera x-axis points opposite to image x-axis).
    dx_px = -(target_x_px - center_cx)
    dy_px =   target_y_px - center_cy

    dx_mm = dx_px * PIXEL_X
    dy_mm = dy_px * PIXEL_Y

    hfov = math.atan2(dx_px, focus_px_x)
    vfov = math.atan2(dy_px, focus_px_y)

    return {
        "dx_px":     dx_px,
        "dy_px":     dy_px,
        "dx_mm":     dx_mm,
        "dy_mm":     dy_mm,
        "hfov":  hfov,
        "vfov":  vfov,
        "hfov_deg":  math.degrees(hfov),
        "vfov_deg":  math.degrees(vfov),
    }


def process_detections(
    detections: list[dict],
    fps: float = 30.0,
    focus_mm: float = DEFAULT_FOCUS_LENGTH_MM,
    center_cx: float = DEFAULT_CENTER_CX,
    center_cy: float = DEFAULT_CENTER_CY,
    window_w: int = 20,
    window_h: int = 20,
) -> list[dict]:
    """Process detection frames and compute LOS angles + angular rates.

    Parameters
    ----------
    detections : list[dict]
        Per-frame detection records (from video_detections.json).
    fps : float
        Frame rate for angular-rate computation.
    focus_mm, center_cx, center_cy : float
        Camera intrinsic parameters.

    Returns
    -------
    list[dict] — one entry per frame, adding LOS fields.
    """
    dt = 1.0 / fps if fps > 0 else 1.0 / 30.0
    results = []
    prev_hfov = None
    prev_vfov = None

    for det in detections:
        frame_idx = det["frame"]
        found = det["found"]

        entry = {
            "frame": frame_idx,
            "found": found,
            "target_x_px": None,
            "target_y_px": None,
            "hfov": None,
            "vfov": None,
            "hfov_deg": None,
            "vfov_deg": None,
            "omega_hfov": None,
            "omega_vfov": None,
            "omega_hfov_deg": None,
            "omega_vfov_deg": None,
        }

        if found:
            # Target centre = box top-left + half window size
            cx = det["x"] + window_w / 2.0
            cy = det["y"] + window_h / 2.0
            entry["target_x_px"] = cx
            entry["target_y_px"] = cy

            los = compute_los(cx, cy, focus_mm, center_cx, center_cy)
            entry["hfov"] = los["hfov"]
            entry["vfov"] = los["vfov"]
            entry["hfov_deg"] = los["hfov_deg"]
            entry["vfov_deg"] = los["vfov_deg"]

            # Angular rate (finite difference).
            if prev_hfov is not None and prev_vfov is not None:
                entry["omega_hfov"] = (los["hfov"] - prev_hfov) / dt
                entry["omega_vfov"] = (los["vfov"] - prev_vfov) / dt
                entry["omega_hfov_deg"] = math.degrees(entry["omega_hfov"])
                entry["omega_vfov_deg"] = math.degrees(entry["omega_vfov"])

            prev_hfov = los["hfov"]
            prev_vfov = los["vfov"]
        else:
            # Reset angular rate continuity on target loss.
            prev_hfov = None
            prev_vfov = None

        results.append(entry)

    return results


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compute LOS angles and angular rates from detection JSON."
    )
    parser.add_argument("detections_json", type=Path,
                        help="Path to video_detections.json")
    parser.add_argument("--output", "-o", type=Path,
                        help="Output JSON path (default: <input>_los.json)")
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--focus-mm", type=float, default=DEFAULT_FOCUS_LENGTH_MM,
                        help=f"Focal length in mm (default: {DEFAULT_FOCUS_LENGTH_MM})")
    parser.add_argument("--center-cx", type=float, default=DEFAULT_CENTER_CX)
    parser.add_argument("--center-cy", type=float, default=DEFAULT_CENTER_CY)
    parser.add_argument("--window-w", type=int, default=20)
    parser.add_argument("--window-h", type=int, default=20)
    args = parser.parse_args()

    dets = json.loads(args.detections_json.read_text())
    print(f"Processing {len(dets)} detection entries...")

    results = process_detections(
        dets,
        fps=args.fps,
        focus_mm=args.focus_mm,
        center_cx=args.center_cx,
        center_cy=args.center_cy,
        window_w=args.window_w,
        window_h=args.window_h,
    )

    out_path = args.output or args.detections_json.with_suffix(
        args.detections_json.suffix + "_los.json"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(results, indent=2))

    # Summary
    found_count = sum(1 for r in results if r["found"])
    rate_count = sum(1 for r in results if r["omega_hfov"] is not None)
    print(f"Wrote {out_path}: {len(results)} frames, "
          f"{found_count} with target, {rate_count} with angular rate")


if __name__ == "__main__":
    main()
