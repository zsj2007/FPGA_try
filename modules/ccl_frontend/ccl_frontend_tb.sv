`timescale 1ns / 1ps

// ============================================================================
// ccl_frontend_tb  standalone test for the streaming CCL front-end.
// ============================================================================

module ccl_frontend_tb;

    localparam integer IMAGE_WIDTH  = 16;
    localparam integer IMAGE_HEIGHT = 8;
    localparam integer MAX_LABELS   = 8;
    localparam integer LABEL_BITS   = 4;

    logic clk = 0;
    logic reset_n = 0;
    logic pixel_valid, frame_start, line_start, line_end;
    logic [15:0] pixel_x, pixel_y;
    logic binary_data;

    logic                   dump_valid;
    logic [LABEL_BITS-1:0]  dump_label;
    logic [23:0]            dump_area;
    logic [31:0]            dump_sum_x, dump_sum_y;
    logic [15:0]            dump_min_x, dump_max_x, dump_min_y, dump_max_y;
    logic [LABEL_BITS-1:0]  dump_equiv_parent;
    logic                   frame_done;
    logic [LABEL_BITS-1:0]  num_labels;

    always #5 clk = ~clk;

    ccl_frontend #(
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .MAX_LABELS  (MAX_LABELS),
        .LABEL_BITS  (LABEL_BITS)
    ) dut (.*);

    // Frame generator
    task automatic send_frame(input bit [IMAGE_WIDTH-1:0] frame_bitmap [0:IMAGE_HEIGHT-1]);
        begin
            @(negedge clk);
            pixel_valid <= 1'b0; frame_start <= 1'b0;
            line_start <= 1'b0; line_end <= 1'b0;
            @(negedge clk); @(negedge clk);

            for (int y = 0; y < IMAGE_HEIGHT; y++) begin
                for (int x = 0; x < IMAGE_WIDTH; x++) begin
                    @(negedge clk);
                    pixel_valid <= 1'b1;
                    pixel_x <= x; pixel_y <= y;
                    binary_data <= frame_bitmap[y][x];
                    frame_start <= (y == 0 && x == 0);
                    line_start  <= (x == 0);
                    line_end    <= (x == IMAGE_WIDTH - 1);
                end
                @(negedge clk);
                pixel_valid <= 1'b0; line_start <= 1'b0;
                line_end <= 1'b0; frame_start <= 1'b0;
            end
            repeat (MAX_LABELS + 10) @(negedge clk);
        end
    endtask

    // Capture dump data (on negedge to avoid race with DUT posedge outputs)
    typedef struct {
        logic [23:0] area;
        logic [31:0] sum_x, sum_y;
        logic [15:0] min_x, max_x, min_y, max_y;
        logic [LABEL_BITS-1:0] parent;
    } label_stat_t;

    label_stat_t captured [0:MAX_LABELS-1];

    always @(negedge clk) begin
        if (dump_valid) begin
            captured[dump_label].area   <= dump_area;
            captured[dump_label].sum_x  <= dump_sum_x;
            captured[dump_label].sum_y  <= dump_sum_y;
            captured[dump_label].min_x  <= dump_min_x;
            captured[dump_label].max_x  <= dump_max_x;
            captured[dump_label].min_y  <= dump_min_y;
            captured[dump_label].max_y  <= dump_max_y;
            captured[dump_label].parent <= dump_equiv_parent;
        end
    end

    bit [IMAGE_WIDTH-1:0] bitmap [0:IMAGE_HEIGHT-1];

    initial begin
        reset_n = 0;
        repeat (4) @(negedge clk);
        reset_n = 1;
        repeat (4) @(negedge clk);

        // Test 1: Single 2x2 blob
        $display("=== Test 1: Single 2x2 blob ===");
        for (int y = 0; y < IMAGE_HEIGHT; y++) bitmap[y] = '0;
        bitmap[3][4] = 1; bitmap[3][5] = 1;
        bitmap[4][4] = 1; bitmap[4][5] = 1;
        send_frame(bitmap);
        $display("  Label 1: area=%0d bbox=(%0d,%0d,%0d,%0d) parent=%0d",
                 captured[1].area,
                 captured[1].min_x, captured[1].max_x,
                 captured[1].min_y, captured[1].max_y,
                 captured[1].parent);
        if (captured[1].area == 4 && captured[1].min_x == 4 && captured[1].max_x == 5 &&
            captured[1].min_y == 3 && captured[1].max_y == 4)
            $display("  PASS");
        else
            $display("  FAIL");

        // Test 2: U-shaped blob (merge)
        $display("=== Test 2: U-shaped blob (merge) ===");
        for (int y = 0; y < IMAGE_HEIGHT; y++) bitmap[y] = '0;
        bitmap[2][2] = 1; bitmap[2][3] = 1;
        bitmap[3][2] = 1;                    bitmap[3][4] = 1;
        bitmap[4][2] = 1; bitmap[4][3] = 1; bitmap[4][4] = 1;
        send_frame(bitmap);
        $display("  Label 1: area=%0d bbox=(%0d,%0d,%0d,%0d) parent=%0d",
                 captured[1].area,
                 captured[1].min_x, captured[1].max_x,
                 captured[1].min_y, captured[1].max_y,
                 captured[1].parent);
        $display("  Label 2: area=%0d parent=%0d", captured[2].area, captured[2].parent);
        $display("  Label 3: area=%0d parent=%0d", captured[3].area, captured[3].parent);

        // Test 3: Two disconnected blobs
        $display("=== Test 3: Two disconnected blobs ===");
        for (int y = 0; y < IMAGE_HEIGHT; y++) bitmap[y] = '0;
        bitmap[1][1] = 1; bitmap[1][2] = 1;
        bitmap[1][10]= 1; bitmap[2][10]= 1;
        send_frame(bitmap);
        $display("  Label 1: area=%0d bbox=(%0d,%0d,%0d,%0d)",
                 captured[1].area,
                 captured[1].min_x, captured[1].max_x,
                 captured[1].min_y, captured[1].max_y);
        $display("  Label 2: area=%0d bbox=(%0d,%0d,%0d,%0d)",
                 captured[2].area,
                 captured[2].min_x, captured[2].max_x,
                 captured[2].min_y, captured[2].max_y);

        // Test 4: Full white
        $display("=== Test 4: Full white frame (label overflow) ===");
        for (int y = 0; y < IMAGE_HEIGHT; y++) bitmap[y] = '1;
        send_frame(bitmap);
        $display("  num_labels=%0d (max=%0d)", num_labels, MAX_LABELS);
        $display("  Label 1: area=%0d", captured[1].area);

        $display("=== All tests done ===");
        $finish;
    end

endmodule