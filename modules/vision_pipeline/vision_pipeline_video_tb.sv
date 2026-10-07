`timescale 1ns / 1ps

module vision_pipeline_video_tb;

    localparam integer IMAGE_WIDTH      = 640;
    localparam integer IMAGE_HEIGHT     = 400;
    localparam integer PIXEL_WIDTH      = 10;
    localparam integer PIXEL_COUNT      = IMAGE_WIDTH * IMAGE_HEIGHT;
    
    localparam logic [9:0] THRESHOLD    = 10'd1000;
    localparam integer BOX_THICKNESS    = 2;

    localparam string INPUT_FILE  = "D:/new_FPGA/sim/data/input/vid_2727_640x400.raw";
    localparam string OUTPUT_FILE = "D:/new_FPGA/sim/data/output/vid_2727_boxed_640x400.raw";
    localparam string DETS_FILE   = "D:/new_FPGA/sim/data/output/vid_2727_dets.json";
    localparam integer MAX_FRAMES = 0;

    logic        pclk = 1'b0;
    logic        reset_n = 1'b0;
    logic [9:0]  cam_data = 10'd0;
    logic        cam_href = 1'b0;
    logic        cam_vsync = 1'b0;

    logic [9:0]  output_data;
    logic        output_valid;
    logic        output_frame_start;
    logic        output_line_start;
    logic        output_line_end;
    logic [15:0] output_x;
    logic [15:0] output_y;
    logic        output_box_active;
    logic        result_valid;
    logic        target_found;
    logic [15:0] center_x;
    logic [15:0] center_y;
    logic [15:0] bbox_left;
    logic [15:0] bbox_right;
    logic [15:0] bbox_top;
    logic [15:0] bbox_bottom;
    logic [23:0] blob_area;
    logic [15:0] blob_ratio_q16;
    logic        los_valid;
    logic [31:0] hfov_q16;
    logic [31:0] vfov_q16;
    logic [31:0] omega_hfov_q16;
    logic [31:0] omega_vfov_q16;
    logic        omega_valid;

    integer input_file, output_file, dets_file;
    integer bytes_read, file_size, total_frames, process_frames;
    integer current_frame = 0;
    integer dets_written = 0;

    logic [7:0] frame_pixels [0:PIXEL_COUNT-1];

    always #5 pclk = ~pclk;

    vision_pipeline #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT), .PIXEL_WIDTH(PIXEL_WIDTH),
        .THRESHOLD(THRESHOLD), .BOX_THICKNESS(BOX_THICKNESS), .BOX_VALUE(10'd0)
    ) dut (
        .pclk(pclk), .reset_n(reset_n), .cam_data(cam_data), .cam_href(cam_href), .cam_vsync(cam_vsync),
        .output_data(output_data), .output_valid(output_valid),
        .output_frame_start(output_frame_start), .output_line_start(output_line_start), .output_line_end(output_line_end),
        .output_x(output_x), .output_y(output_y), .output_box_active(output_box_active),
        .result_valid(result_valid), .target_found(target_found),
        .center_x(center_x), .center_y(center_y),
        .bbox_left(bbox_left), .bbox_right(bbox_right),
        .bbox_top(bbox_top), .bbox_bottom(bbox_bottom),
        .blob_area(blob_area), .blob_ratio_q16(blob_ratio_q16),
        .los_valid(los_valid), .hfov_q16(hfov_q16), .vfov_q16(vfov_q16),
        .omega_hfov_q16(omega_hfov_q16), .omega_vfov_q16(omega_vfov_q16), .omega_valid(omega_valid)
    );

    task automatic send_frame;
        integer index;
        begin
            @(negedge pclk);
            cam_href = 1'b0; cam_vsync = 1'b1;
            @(negedge pclk);
            cam_vsync = 1'b0;
            for (integer y = 0; y < IMAGE_HEIGHT; y = y + 1) begin
                for (integer x = 0; x < IMAGE_WIDTH; x = x + 1) begin
                    index = y * IMAGE_WIDTH + x;
                    @(negedge pclk);
                    cam_href = 1'b1;
                    cam_data = {frame_pixels[index], 2'b00};
                end
                @(negedge pclk);
                cam_href = 1'b0; cam_data = 10'd0;
            end
            repeat (1024) @(negedge pclk);
        end
    endtask

    always @(posedge pclk) begin
        #1;
        if (result_valid) begin
            $display("[frame %0d] det: found=%0d cx=%0d cy=%0d area=%0d ratio=%0d",
                     current_frame, target_found, center_x, center_y, blob_area, blob_ratio_q16);
            $display("        bbox: l=%0d r=%0d t=%0d b=%0d",
                     bbox_left, bbox_right, bbox_top, bbox_bottom);

            if (dets_file != 0) begin
                if (dets_written == 0)
                    $fwrite(dets_file, "[\n");
                else
                    $fwrite(dets_file, ",\n");
                if (target_found)
                    $fwrite(dets_file, "  {\"frame\":%0d,\"x\":%0d,\"y\":%0d,", current_frame, center_x, center_y);
                else
                    $fwrite(dets_file, "  {\"frame\":%0d,\"x\":-1,\"y\":-1,", current_frame);
                $fwrite(dets_file, "\"area\":%0d,\"found\":%s,\"bbox_l\":%0d,\"bbox_r\":%0d,\"bbox_t\":%0d,\"bbox_b\":%0d}",
                    blob_area, target_found ? "true" : "false", bbox_left, bbox_right, bbox_top, bbox_bottom);
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
    end

    always @(posedge pclk) begin
        #1;
        if (output_valid)
            $fwrite(output_file, "%c%c",
                    output_data[7:0], {6'd0, output_data[9:8]});
    end

    initial begin
        input_file = $fopen(INPUT_FILE, "rb");
        if (input_file == 0)
            $fatal(1, "Cannot open: %s", INPUT_FILE);
        $fseek(input_file, 0, 2);
        file_size = $ftell(input_file);
        $fseek(input_file, 0, 0);
        if ((file_size % PIXEL_COUNT) != 0)
            $fatal(1, "File size %0d not multiple of %0d", file_size, PIXEL_COUNT);
        total_frames = file_size / PIXEL_COUNT;
        process_frames = (MAX_FRAMES > 0 && MAX_FRAMES < total_frames)
                         ? MAX_FRAMES : total_frames;
        $display("Video: %0d frames available, processing %0d", total_frames, process_frames);

        output_file = $fopen(OUTPUT_FILE, "wb");
        dets_file   = $fopen(DETS_FILE, "w");

        repeat (4) @(negedge pclk);
        reset_n = 1'b1;

        for (current_frame = 0; current_frame < process_frames;
             current_frame = current_frame + 1) begin
            bytes_read = $fread(frame_pixels, input_file);
            if (bytes_read != PIXEL_COUNT)
                $fatal(1, "Frame %0d: expected %0d bytes, got %0d",
                       current_frame, PIXEL_COUNT, bytes_read);
            $display("Frame %0d / %0d: sending...",
                     current_frame + 1, process_frames);
            send_frame();
        end

        repeat (64) @(posedge pclk);

        if (dets_written > 0)
            $fwrite(dets_file, "\n]\n");
        else
            $fwrite(dets_file, "[]\n");

        $fclose(input_file);
        $fclose(output_file);
        $fclose(dets_file);

        $display("===========================================");
        $display("Video simulation complete: %0d frames", process_frames);
        $display("PASS");
        $finish;
    end

endmodule
