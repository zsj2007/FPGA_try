import re

path = r"D:\new_FPGA\modules\vision_pipeline\vision_pipeline_video_tb.sv"
with open(path, "r") as f:
    c = f.read()

# The fix: buffer detection result and write JSON when LOS arrives.
# Find and replace the always block that handles result_valid.

# Strategy: replace the body inside the always @(posedge pclk) for the collector.
# I'll locate the specific block and rewrite it.

old_block = """    // Detection + LOS collector.
    always @(posedge pclk) begin
        #1;

        // Detection result per frame.
        if (result_valid) begin
            $display("[frame %0d] det: found=%0d x=%0d y=%0d bright=%0d",
                     current_frame, target_found, best_x, best_y,
                     best_bright_count);

            if (dets_file != 0) begin
                if (dets_written == 0)
                    $fwrite(dets_file, "[\n");
                else
                    $fwrite(dets_file, ",\n");

                if (target_found)
                    $fwrite(dets_file,
                        "  {\"frame\":%0d,\"x\":%0d,\"y\":%0d,",
                        current_frame, best_x, best_y);
                else
                    $fwrite(dets_file,
                        "  {\"frame\":%0d,\"x\":-1,\"y\":-1,",
                        current_frame);

                $fwrite(dets_file,
                    "\"count\":%0d,\"found\":%s,\"box_w\":%0d,\"box_h\":%0d",
                    best_bright_count, target_found ? "true" : "false",
                    WINDOW_WIDTH, WINDOW_HEIGHT);

                // Append LOS data if available for this frame.
                if (los_valid || omega_valid) begin
                    $fwrite(dets_file,
                        ",\"hfov_deg\":%.4f,\"vfov_deg\":%.4f",
                        $itor($signed(hfov_q16)) * 180.0 / (3.14159265 * (1 << 29)),
                        $itor($signed(vfov_q16)) * 180.0 / (3.14159265 * (1 << 29)));
                    $fwrite(dets_file,
                        ",\"omega_hfov\":%.4f,\"omega_vfov\":%.4f",
                        $itor($signed(omega_hfov_q16)) / (1 << 24),
                        $itor($signed(omega_vfov_q16)) / (1 << 24));
                end

                $fwrite(dets_file, "}");
                dets_written = dets_written + 1;
            end
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
    end"""

new_block = """    // Buffered detection + LOS collector.
    // LOS arrives ~18 cycles after result_valid (CORDIC pipeline), so we
    // buffer the detection info and write the full JSON entry when LOS is ready.
    logic        det_buf_valid;
    logic        det_buf_found;
    logic [15:0] det_buf_x, det_buf_y;
    logic [8:0]  det_buf_count;
    integer      det_buf_frame;

    always @(posedge pclk) begin
        #1;

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

        // Write JSON entry when LOS data arrives.
        if (det_buf_valid && (los_valid || omega_valid)) begin
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

            if (!det_buf_found)
                det_buf_valid <= 1'b0;
        end

        if (omega_valid)
            det_buf_valid <= 1'b0;
    end"""

c = c.replace(old_block, new_block)
with open(path, "w") as f:
    f.write(c)
print("done")
