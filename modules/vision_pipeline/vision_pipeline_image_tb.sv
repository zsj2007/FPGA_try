`timescale 1ns / 1ps

// Full-size file-driven simulation for testing a desktop image.
// The input file contains one 640x400 RAW8 frame. It is sent twice: frame 0
// finds the target and frame 1 receives the rectangle computed from frame 0.
module vision_pipeline_image_tb;

    localparam integer IMAGE_WIDTH      = 640;
    localparam integer IMAGE_HEIGHT     = 400;
    localparam integer PIXEL_WIDTH      = 10;
    localparam integer PIXEL_COUNT      = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam integer WINDOW_WIDTH     = 20;
    localparam integer WINDOW_HEIGHT    = 20;

    // These are the first parameters to tune when testing real images.
    localparam logic [9:0] THRESHOLD    = 10'd512;
    localparam integer MIN_BRIGHT_COUNT = 100;

    localparam INPUT_FILE  = "D:/new_FPGA/sim/data/input/input_640x400.raw";
    localparam OUTPUT_FILE = "D:/new_FPGA/sim/data/output/boxed_640x400.raw";

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
    logic [15:0] best_x;
    logic [15:0] best_y;
    logic [8:0]  best_bright_count;

    logic [7:0] input_pixels [0:PIXEL_COUNT-1];
    integer input_file;
    integer output_file;
    integer bytes_read;
    integer output_frame_index = -1;
    integer written_pixels = 0;
    integer detected_x = 0;
    integer detected_y = 0;
    integer detected_count = 0;
    logic   first_result_received = 1'b0;

    always #5 pclk = ~pclk;

    vision_pipeline #(
        .IMAGE_WIDTH      (IMAGE_WIDTH),
        .IMAGE_HEIGHT     (IMAGE_HEIGHT),
        .PIXEL_WIDTH      (PIXEL_WIDTH),
        .THRESHOLD        (THRESHOLD),
        .WINDOW_WIDTH     (WINDOW_WIDTH),
        .WINDOW_HEIGHT    (WINDOW_HEIGHT),
        .MIN_BRIGHT_COUNT (MIN_BRIGHT_COUNT),
        .BOX_THICKNESS    (1),
        // A black border is easy to see inside the brightest region.
        .BOX_VALUE        (10'd0)
    ) dut (
        .pclk                (pclk),
        .reset_n             (reset_n),
        .cam_data            (cam_data),
        .cam_href            (cam_href),
        .cam_vsync           (cam_vsync),
        .output_data         (output_data),
        .output_valid        (output_valid),
        .output_frame_start  (output_frame_start),
        .output_line_start   (output_line_start),
        .output_line_end     (output_line_end),
        .output_x            (output_x),
        .output_y            (output_y),
        .output_box_active   (output_box_active),
        .result_valid        (result_valid),
        .target_found        (target_found),
        .best_x              (best_x),
        .best_y              (best_y),
        .best_bright_count   (best_bright_count)
    );

    task automatic send_image_frame;
        integer index;
        begin
            @(negedge pclk);
            cam_href  = 1'b0;
            cam_vsync = 1'b1;
            @(negedge pclk);
            cam_vsync = 1'b0;

            for (integer y = 0; y < IMAGE_HEIGHT; y = y + 1) begin
                for (integer x = 0; x < IMAGE_WIDTH; x = x + 1) begin
                    index = y * IMAGE_WIDTH + x;
                    @(negedge pclk);
                    cam_href = 1'b1;
                    // Expand ordinary RAW8 into the camera's 10-bit range.
                    cam_data = {input_pixels[index], 2'b00};
                end
                @(negedge pclk);
                cam_href = 1'b0;
                cam_data = 10'd0;
            end

            // Allow threshold/window pipeline stages to finish the frame.
            repeat (8) @(negedge pclk);
        end
    endtask

    always @(posedge pclk) begin
        #1;

        if (result_valid) begin
            $display("Detection result: found=%0d, x=%0d, y=%0d, bright_count=%0d",
                     target_found, best_x, best_y, best_bright_count);
            if (!first_result_received) begin
                first_result_received = 1'b1;
                detected_x = best_x;
                detected_y = best_y;
                detected_count = best_bright_count;
            end
        end

        if (output_valid) begin
            if (output_frame_start)
                output_frame_index = output_frame_index + 1;

            // Save only frame 1: the copy carrying frame 0's detection box.
            if (output_frame_index == 1) begin
                $fwrite(output_file, "%c%c",
                        output_data[7:0], {6'd0, output_data[9:8]});
                written_pixels = written_pixels + 1;
            end
        end
    end

    initial begin
        input_file = $fopen(INPUT_FILE, "rb");
        if (input_file == 0)
            $fatal(1, "Cannot open input file: %s", INPUT_FILE);

        bytes_read = $fread(input_pixels, input_file);
        $fclose(input_file);
        if (bytes_read != PIXEL_COUNT)
            $fatal(1, "Expected %0d RAW8 bytes, read %0d",
                   PIXEL_COUNT, bytes_read);

        output_file = $fopen(OUTPUT_FILE, "wb");
        if (output_file == 0)
            $fatal(1, "Cannot open output file: %s", OUTPUT_FILE);

        repeat (4) @(negedge pclk);
        reset_n = 1'b1;

        $display("Frame 0: detecting target in desktop image");
        send_image_frame();
        $display("Frame 1: drawing previous-frame result");
        send_image_frame();

        wait (written_pixels == PIXEL_COUNT);
        repeat (4) @(posedge pclk);
        $fclose(output_file);

        if (!first_result_received)
            $fatal(1, "No first-frame detection result was produced");
        if (written_pixels != PIXEL_COUNT)
            $fatal(1, "Expected %0d output pixels, wrote %0d",
                   PIXEL_COUNT, written_pixels);

        $display("Wrote boxed frame: %s", OUTPUT_FILE);
        $display("First-frame box: x=%0d, y=%0d, bright_count=%0d",
                 detected_x, detected_y, detected_count);
        $display("PASS: desktop image pipeline simulation completed");
        $finish;
    end

endmodule
