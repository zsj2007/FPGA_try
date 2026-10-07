import re

path = r"D:\new_FPGA\modules\vision_pipeline\vision_pipeline_video_tb.sv"
with open(path, "r") as f:
    content = f.read()

# Find the corrupted buffered block and replace with original working code
marker = "// Buffered detection + LOS collector."
idx = content.find(marker)
if idx < 0:
    print("No corruption found")
    exit(0)

# Find endmodule to locate the end of the file (the corrupted block extends to before endmodule)
endmodule_idx = content.find("endmodule", idx)
before = content[:idx]

# Find the "endmodule" and the code that follows it (output pixel writer + initial block)
# The corrupted code replaced the always block + some of the initial block
# Actually we need to find the output pixel writer
output_writer = "// Output pixel writer."
ow_idx = content.find(output_writer)
if ow_idx < 0:
    print("Cannot find output pixel writer")
    exit(1)

after = content[ow_idx:]

# The original working collector block
orig_collector = """    // Detection + LOS collector.
    always @(posedge pclk) begin
        #1;

        // Detection result per frame.
        if (result_valid) begin
""" + chr(36) + """display("[frame %0d] det: found=%0d x=%0d y=%0d bright=%0d",
                     current_frame, target_found, best_x, best_y,
                     best_bright_count);

            if (dets_file != 0) begin
                if (dets_written == 0)
                    """ + chr(36) + """fwrite(dets_file, "[\n");
                else
                    """ + chr(36) + """fwrite(dets_file, ",\n");

                if (target_found)
                    """ + chr(36) + """fwrite(dets_file,
                        "  {\"frame\":%0d,\"x\":%0d,\"y\":%0d,",
                        current_frame, best_x, best_y);
                else
                    """ + chr(36) + """fwrite(dets_file,
                        "  {\"frame\":%0d,\"x\":-1,\"y\":-1,",
                        current_frame);

                """ + chr(36) + """fwrite(dets_file,
                    "\"count\":%0d,\"found\":%s,\"box_w\":%0d,\"box_h\":%0d",
                    best_bright_count, target_found ? "true" : "false",
                    WINDOW_WIDTH, WINDOW_HEIGHT);

                // Append LOS data if available for this frame.
                if (los_valid || omega_valid) begin
                    """ + chr(36) + """fwrite(dets_file,
                        ",\"hfov_deg\":%.4f,\"vfov_deg\":%.4f",
                        """ + chr(36) + """itor(""" + chr(36) + """signed(hfov_q16)) * 180.0 / (3.14159265 * (1 << 29)),
                        """ + chr(36) + """itor(""" + chr(36) + """signed(vfov_q16)) * 180.0 / (3.14159265 * (1 << 29)));
                    """ + chr(36) + """fwrite(dets_file,
                        ",\"omega_hfov\":%.4f,\"omega_vfov\":%.4f",
                        """ + chr(36) + """itor(""" + chr(36) + """signed(omega_hfov_q16)) / (1 << 24),
                        """ + chr(36) + """itor(""" + chr(36) + """signed(omega_vfov_q16)) / (1 << 24));
                end

                """ + chr(36) + """fwrite(dets_file, "}");
                dets_written = dets_written + 1;
            end
        end

        if (los_valid)
            """ + chr(36) + """display("[frame %0d] los: hfov=%.2f deg, vfov=%.2f deg",
                     current_frame,
                     """ + chr(36) + """itor(""" + chr(36) + """signed(hfov_q16)) * 180.0 / (3.14159265 * (1 << 29)),
                     """ + chr(36) + """itor(""" + chr(36) + """signed(vfov_q16)) * 180.0 / (3.14159265 * (1 << 29)));
        if (omega_valid)
            """ + chr(36) + """display("[frame %0d] omega: hfov=%.2f rad/s, vfov=%.2f rad/s",
                     current_frame,
                     """ + chr(36) + """itor(""" + chr(36) + """signed(omega_hfov_q16)) / (1 << 24),
                     """ + chr(36) + """itor(""" + chr(36) + """signed(omega_vfov_q16)) / (1 << 24));
    end"""

result = before + orig_collector + "\n\n" + after
with open(path, "w") as f:
    f.write(result)
print("Restored! Length:", len(result))