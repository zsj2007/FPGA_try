path = r"D:\new_FPGA\modules\blob_analyzer\ccl_analyzer.sv"
with open(path, "r") as f:
    lines = f.readlines()

# Fix line 236
lines[235] = "                                best_cx <= 16'(lbl_sum_x[scan_idx] / {8'd0, lbl_area[scan_idx]});\n"
# Fix line 237
lines[236] = "                                best_cy <= 16'(lbl_sum_y[scan_idx] / {8'd0, lbl_area[scan_idx]});\n"

with open(path, "w") as f:
    f.writelines(lines)
print("Fixed")
print(lines[235].rstrip())
print(lines[236].rstrip())
