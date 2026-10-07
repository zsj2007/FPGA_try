import re

path = r"D:\new_FPGA\modules\vision_pipeline\vision_pipeline_video_tb.sv"
with open(path, "r") as f:
    content = f.read()

# Strategy: find the always block with "Detection + LOS collector" and replace entire block
# Using a different approach - find marker and reconstruct

marker = "// Detection + LOS collector."
idx = content.find(marker)
if idx < 0:
    print("Marker not found")
    exit(1)

# Find the "always" before this marker (it's the next non-comment line)
before = content[:idx]
after_marker = content[idx:]

# Find the always block start
always_start = after_marker.find("always @(posedge pclk)")
if always_start < 0:
    print("always block not found")
    exit(1)

block_start_in_full = idx + always_start

# Now find matching end - count begin/end
remaining = content[block_start_in_full:]
depth = 0
pos = 0
found_begin = False
while pos < len(remaining):
    line = remaining[pos:].split("\n")[0]
    stripped = line.strip()
    if stripped.startswith("begin"):
        depth += 1
        found_begin = True
    elif stripped.startswith("end"):
        depth -= 1
        if found_begin and depth <= 0:
            pos += len(line) + 1  # include newline
            break
    pos += len(line) + 1

block_end = block_start_in_full + pos

# Build replacement
new_block = """    // Buffered detection + LOS collector.
    // LOS arrives ~18 cycles after result_valid (CORDIC pipeline delay),
    // so we buffer detection info and write JSON when LOS data is ready.
    logic        det_buf_valid;
    logic        det_buf_found;
    logic [15:0] det_buf_x, det_buf_y;
    logic [8:0]  det_buf_count;
    integer      det_buf_frame;

    always @(posedge pclk) begin
        #1;

        // Buffer detection result.
        if (result_valid) begin
            $display("[frame %0d] det: found=%0d x=%0d y=%0d bright=%0d",
                     current_frame, target_found, best_x, best_y,
                     best_bright_count);
            det_buf_valid <= 1'b1;
            det_buf_found <= target_found;
            det_buf_x     <= best_x;
            det_buf_y     <= best_y;
            det_buf_count <= best_bright_count;
            det_buf_frame <= current_frame;
        end

        if (los_valid)
            $display("[frame %0d] los: hfov=%.2f deg, vfov=%.2f deg",
                     current_frame,
                     $itor($signed(hfov_q16)) * 180.0 / (3.14159265 * (1 << 29)),
                     $itor($signed(vfov_q16)) * 180.0 / (3.14159265 * (1 << 29)));
        if (omega_valid)
            $display("[frame %0d] omega: hfov=%.2f rad/s, vfov=%.2f rad/s",
                     current_frame,
                     $itor($signed(omega_hfov_q16)) / (1 << 24),
                     $itor($signed(omega_vfov_q16)) / (1 << 24));

        // Write JSON when LOS data (omega_valid) arrives.
        if (det_buf_valid && omega_valid) begin
            if (dets_file != 0) begin
                if (dets_written == 0)
                    $fwrite(dets_file, "[\n");
                else
                    $fwrite(dets_file, ",\n");

                if (det_buf_found)
                    $fwrite(dets_file,
                        "  {\"frame\":%0d,\"x\":%0d,\"y\":%0d,",
                        det_buf_frame, det_buf_x, det_buf_y);
                else
                    $fwrite(dets_file,
                        "  {\"frame\":%0d,\"x\":-1,\"y\":-1,",
                        det_buf_frame);

                $fwrite(dets_file,
                    "\"count\":%0d,\"found\":%s,\"box_w\":%0d,\"box_h\":%0d",
                    det_buf_count, det_buf_found ? "true" : "false",
                    WINDOW_WIDTH, WINDOW_HEIGHT);

                $fwrite(dets_file,
                    ",\"hfov_deg\":%.4f,\"vfov_deg\":%.4f",
                    $itor($signed(hfov_q16)) * 180.0 / (3.14159265 * (1 << 29)),
                    $itor($signed(vfov_q16)) * 180.0 / (3.14159265 * (1 << 29)));
                $fwrite(dets_file,
                    ",\"omega_hfov\":%.4f,\"omega_vfov\":%.4f",
                    $itor($signed(omega_hfov_q16)) / (1 << 24),
                    $itor($signed(omega_vfov_q16)) / (1 << 24));

                $fwrite(dets_file, "}");
                dets_written = dets_written + 1;
            end
            det_buf_valid <= 1'b0;
        end
    end"""

result = before + new_block + content[block_end:]
with open(path, "w") as f:
    f.write(result)
print(f"Replaced {block_start_in_full} to {block_end}")
print("Done")
