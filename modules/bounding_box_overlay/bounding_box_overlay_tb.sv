`timescale 1ns / 1ps

module bounding_box_overlay_tb;

    localparam integer IMAGE_WIDTH  = 8;
    localparam integer IMAGE_HEIGHT = 6;
    localparam integer BOX_WIDTH    = 4;
    localparam integer BOX_HEIGHT   = 3;

    logic        clk = 1'b0;
    logic        reset_n = 1'b0;
    logic [9:0]  pixel_data = 10'd0;
    logic        pixel_valid = 1'b0;
    logic        frame_start = 1'b0;
    logic        line_start = 1'b0;
    logic        line_end = 1'b0;
    logic [15:0] pixel_x = 16'd0;
    logic [15:0] pixel_y = 16'd0;
    logic        result_valid = 1'b0;
    logic        target_found = 1'b0;
    logic [15:0] best_x = 16'd0;
    logic [15:0] best_y = 16'd0;

    logic [9:0]  boxed_data;
    logic        boxed_valid;
    logic        boxed_frame_start;
    logic        boxed_line_start;
    logic        boxed_line_end;
    logic [15:0] boxed_x;
    logic [15:0] boxed_y;
    logic        box_active;

    integer border_pixel_count = 0;
    integer output_pixel_count = 0;

    always #5 clk = ~clk;

    bounding_box_overlay #(
        .PIXEL_WIDTH   (10),
        .BOX_WIDTH     (BOX_WIDTH),
        .BOX_HEIGHT    (BOX_HEIGHT),
        .BOX_THICKNESS (1),
        .BOX_VALUE     (10'd1023)
    ) dut (
        .clk               (clk),
        .reset_n           (reset_n),
        .pixel_data        (pixel_data),
        .pixel_valid       (pixel_valid),
        .frame_start       (frame_start),
        .line_start        (line_start),
        .line_end          (line_end),
        .pixel_x           (pixel_x),
        .pixel_y           (pixel_y),
        .result_valid      (result_valid),
        .target_found      (target_found),
        .best_x            (best_x),
        .best_y            (best_y),
        .boxed_data        (boxed_data),
        .boxed_valid       (boxed_valid),
        .boxed_frame_start (boxed_frame_start),
        .boxed_line_start  (boxed_line_start),
        .boxed_line_end    (boxed_line_end),
        .boxed_x           (boxed_x),
        .boxed_y           (boxed_y),
        .box_active        (box_active)
    );

    always @(posedge clk) begin
        #1;
        if (boxed_valid) begin
            output_pixel_count = output_pixel_count + 1;

            if (box_active) begin
                border_pixel_count = border_pixel_count + 1;
                if (boxed_data !== 10'd1023)
                    $fatal(1, "Border pixel (%0d,%0d) was not highlighted",
                           boxed_x, boxed_y);
            end else if (boxed_data !== 10'd100) begin
                $fatal(1, "Non-border pixel (%0d,%0d) was modified",
                       boxed_x, boxed_y);
            end

            if (boxed_frame_start !== ((boxed_x == 0) && (boxed_y == 0)))
                $fatal(1, "frame_start misaligned at (%0d,%0d)",
                       boxed_x, boxed_y);
            if (boxed_line_start !== (boxed_x == 0))
                $fatal(1, "line_start misaligned at (%0d,%0d)",
                       boxed_x, boxed_y);
            if (boxed_line_end !== (boxed_x == IMAGE_WIDTH - 1))
                $fatal(1, "line_end misaligned at (%0d,%0d)",
                       boxed_x, boxed_y);
        end
    end

    task automatic send_pixel(input integer x, input integer y);
        begin
            @(negedge clk);
            pixel_data  = 10'd100;
            pixel_valid = 1'b1;
            pixel_x     = x;
            pixel_y     = y;
            frame_start = (x == 0) && (y == 0);
            line_start  = (x == 0);
            line_end    = (x == IMAGE_WIDTH - 1);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset_n = 1'b1;

        // Pretend the previous frame's brightest 4x3 window began at (2,1).
        @(negedge clk);
        result_valid = 1'b1;
        target_found = 1'b1;
        best_x = 16'd2;
        best_y = 16'd1;

        @(negedge clk);
        result_valid = 1'b0;

        for (integer y = 0; y < IMAGE_HEIGHT; y = y + 1)
            for (integer x = 0; x < IMAGE_WIDTH; x = x + 1)
                send_pixel(x, y);

        @(negedge clk);
        pixel_valid = 1'b0;
        frame_start = 1'b0;
        line_start  = 1'b0;
        line_end    = 1'b0;

        repeat (2) @(posedge clk);
        #1;

        if (output_pixel_count != IMAGE_WIDTH * IMAGE_HEIGHT)
            $fatal(1, "Expected %0d output pixels, got %0d",
                   IMAGE_WIDTH * IMAGE_HEIGHT, output_pixel_count);
        if (border_pixel_count != 10)
            $fatal(1, "Expected 10 border pixels, got %0d",
                   border_pixel_count);

        $display("PASS: bounding_box_overlay drew a 4x3 box at (2,1)");
        $finish;
    end

endmodule
