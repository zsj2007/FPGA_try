import re
path = r"D:\new_FPGA\sim\scripts\raw_to_video.py"
with open(path, "r", encoding="utf-8") as f:
    c = f.read()

# Remove --los argument
c = c.replace(
    '    parser.add_argument(\n        "--los", type=Path,\n        help="LOS guidance JSON for overlay")\n',
    "")

# Remove los_data loading block
c = c.replace(
    '    # Load LOS guidance data.\n    los_data: dict[int, dict] = {}\n    if args.los and args.los.exists():\n        raw_los = json.loads(args.los.read_text())\n        for item in raw_los:\n            los_data[item["frame"]] = item\n',
    "")

# Use det instead of los_data
c = c.replace(
    '        los = los_data.get(f_idx)\n        bgr = draw_los_overlay(bgr, los)\n',
    '        bgr = draw_los_overlay(bgr, det)\n')

# Update field names
c = c.replace(
    '            f"LOS H={los[\'hfov_deg\']:+.1f}  V={los[\'vfov_deg\']:+.1f} deg"',
    '            f"hfov={los[\'hfov_deg\']:+.1f}  vfov={los[\'vfov_deg\']:+.1f} deg"')
c = c.replace(
    '            f"omega H={los[\'omega_x_deg_s\']:+.0f}  V={los[\'omega_z_deg_s\']:+.0f} deg/s"',
    '            f"omega_h={los[\'omega_hfov\']:+.2f}  omega_v={los[\'omega_vfov\']:+.2f} rad/s"')

with open(path, "w", encoding="utf-8") as f:
    f.write(c)
print("done")
