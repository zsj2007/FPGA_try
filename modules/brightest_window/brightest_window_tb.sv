`timescale 1ns / 1ps

module brightest_window_tb;

    localparam integer IMAGE_WIDTH      = 6;
    localparam integer IMAGE_HEIGHT     = 5;
    localparam integer WINDOW_WIDTH     = 2;
    localparam integer WINDOW_HEIGHT    = 2;
    localparam integer MIN_BRIGHT_COUNT = 3;
    localparam integer COUNT_WIDTH =
        $clog2(WINDOW_WIDTH * WINDOW_HEIGHT + 1);

    logic        clk = 1'b0;
    logic        reset_n = 1'b0;
    logic        binary_data = 1'b0;
    logic        pixel_valid = 1'b0;
    logic        frame_start = 1'b0;
    logic        line_start = 1'b0;
    logic        line_end = 1'b0;
    logic [15:0] pixel_x = 16'd0;
    logic [15:0] pixel_y = 16'd0;
    logic        result_valid;
    logic        target_found;
    logic [15:0] best_x;
    logic [15:0] best_y;
    logic [COUNT_WIDTH-1:0] best_bright_count;

    logic image [0:IMAGE_HEIGHT-1][0:IMAGE_WIDTH-1];
    integer x;
    integer y;

    always #5 clk = ~clk;

    brightest_window #(
        .IMAGE_WIDTH      (IMAGE_WIDTH),
        .IMAGE_HEIGHT     (IMAGE_HEIGHT),
        .WINDOW_WIDTH     (WINDOW_WIDTH),
        .WINDOW_HEIGHT    (WINDOW_HEIGHT),
        .MIN_BRIGHT_COUNT (MIN_BRIGHT_COUNT)
    ) dut (
        .clk               (clk),
        .reset_n           (reset_n),
        .binary_data       (binary_data),
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
        .best_bright_count (best_bright_count)
    );

    initial begin
        for (y = 0; y < IMAGE_HEIGHT; y = y + 1)
            for (x = 0; x < IMAGE_WIDTH; x = x + 1)
                image[y][x] = 1'b0;

        // A three-pixel distractor.
        image[0][0] = 1'b1;
        image[0][1] = 1'b1;
        image[1][0] = 1'b1;

        // Unique four-pixel 2x2 winner at top-left coordinate (3, 2).
        image[2][3] = 1'b1;
        image[2][4] = 1'b1;
        image[3][3] = 1'b1;
        image[3][4] = 1'b1;

        repeat (4) @(negedge clk);
        reset_n = 1'b1;

        for (y = 0; y < IMAGE_HEIGHT; y = y + 1) begin
            for (x = 0; x < IMAGE_WIDTH; x = x + 1) begin
                @(negedge clk);
                binary_data = image[y][x];
                pixel_valid = 1'b1;
                frame_start = (x == 0 && y == 0);
                line_start  = (x == 0);
                line_end    = (x == IMAGE_WIDTH - 1);
                pixel_x     = x;
                pixel_y     = y;
            end
        end

        @(negedge clk);
        pixel_valid = 1'b0;
        frame_start = 1'b0;
        line_start  = 1'b0;
        line_end    = 1'b0;

        @(negedge clk);

        if (!result_valid)
            $fatal(1, "No frame result was produced");
        if (!target_found)
            $fatal(1, "Target was not reported");
        if (best_x !== 16'd3 || best_y !== 16'd2)
            $fatal(1, "Best coordinate mismatch: expected (3,2), got (%0d,%0d)",
                   best_x, best_y);
        if (best_bright_count !== 4)
            $fatal(1, "Bright count mismatch: expected 4, got %0d",
                   best_bright_count);

        $display("PASS: brightest_window found (3,2), bright_count=4");
        $finish;
    end

endmodule

