`timescale 1ns / 1ps
// Four-connected raster CCL. Equivalence edges, NOT parent pointers, go to PS.
// See ccl_split/README.md for the eight-word event format and timing contract.
module ccl_analyzer_pl #(
    parameter integer IMAGE_WIDTH = 640,
    parameter integer IMAGE_HEIGHT = 400,
    parameter integer MAX_LABELS = 64 // includes background label 0; 2..256
) (
    input logic clk, reset_n,
    input logic pixel_valid,
    output logic pixel_ready,
    input logic frame_start,
    input logic [15:0] pixel_x, pixel_y,
    input logic binary_data,
    output logic event_valid,
    input logic event_ready,
    output logic [255:0] event_data
);
    typedef enum logic [1:0] {SCAN, DUMP, FINISH} state_t;
    state_t state;
    logic [7:0] line_buf [0:IMAGE_WIDTH-1];
    logic [7:0] left_label;
    logic [8:0] next_label, dump_idx;
    logic overflow, active;
    logic [31:0] areas [0:MAX_LABELS-1];
    logic [31:0] sums_x [0:MAX_LABELS-1], sums_y [0:MAX_LABELS-1];
    logic [15:0] min_x [0:MAX_LABELS-1], max_x [0:MAX_LABELS-1];
    logic [15:0] min_y [0:MAX_LABELS-1], max_y [0:MAX_LABELS-1];
    wire slot_free = !event_valid || event_ready;
    assign pixel_ready = (state == SCAN) && slot_free;

    initial begin
        if (MAX_LABELS < 2 || MAX_LABELS > 256) $fatal(1, "MAX_LABELS must be 2..256");
        if (IMAGE_WIDTH < 1 || IMAGE_WIDTH > 65536 || IMAGE_HEIGHT < 1 || IMAGE_HEIGHT > 65536)
            $fatal(1, "Invalid dimensions");
        if (64'(IMAGE_WIDTH) * IMAGE_HEIGHT * (IMAGE_WIDTH-1) > 64'hffffffff ||
            64'(IMAGE_WIDTH) * IMAGE_HEIGHT * (IMAGE_HEIGHT-1) > 64'hffffffff)
            $fatal(1, "Dimensions exceed 32-bit statistic capacity");
    end

    always_ff @(posedge clk or negedge reset_n) begin : process
        logic [7:0] l, u, chosen;
        logic [8:0] next_work;
        logic fresh;
        if (!reset_n) begin
            state <= SCAN;
            active <= 0;
            left_label <= 0;
            next_label <= 1;
            dump_idx <= 1;
            overflow <= 0;
            event_valid <= 0;
            event_data <= 0;
        end else begin
            if (event_valid && event_ready) event_valid <= 0;
            case (state)
                SCAN: if (pixel_valid && pixel_ready && (active || frame_start)) begin
                    next_work = frame_start ? 9'd1 : next_label;
                    l = (frame_start || pixel_x == 0) ? 8'd0 : left_label;
                    u = 0;
                    // First row is always background above: no RAM clearing required.
                    if (!frame_start && pixel_y != 0 && pixel_x < IMAGE_WIDTH)
                        u = line_buf[pixel_x];
                    chosen = 0;
                    fresh = 0;
                    if (frame_start) begin
                        active <= 1;
                        overflow <= 0;
                        event_valid <= 1;
                        event_data <= 0; // START
                    end
                    if (binary_data && pixel_x < IMAGE_WIDTH && pixel_y < IMAGE_HEIGHT) begin
                        if (l != 0) chosen = l;
                        else if (u != 0) chosen = u;
                        else if (next_work < MAX_LABELS) begin
                            chosen = next_work[7:0];
                            next_work = next_work + 1'b1;
                            fresh = 1;
                        end else overflow <= 1;
                        if (l != 0 && u != 0 && l != u) begin
                            event_valid <= 1;
                            event_data <= 0;
                            event_data[7:0] <= 8'd1; // UNION edge
                            event_data[15:8] <= l;
                            event_data[23:16] <= u;
                        end
                    end
                    next_label <= next_work;
                    left_label <= chosen;
                    if (pixel_x < IMAGE_WIDTH) line_buf[pixel_x] <= chosen;
                    if (chosen != 0) begin
                        areas[chosen] <= fresh ? 32'd1 : areas[chosen] + 1'b1;
                        sums_x[chosen] <= fresh ? {16'd0,pixel_x} : sums_x[chosen] + {16'd0,pixel_x};
                        sums_y[chosen] <= fresh ? {16'd0,pixel_y} : sums_y[chosen] + {16'd0,pixel_y};
                        if (fresh || pixel_x < min_x[chosen]) min_x[chosen] <= pixel_x;
                        if (fresh || pixel_x > max_x[chosen]) max_x[chosen] <= pixel_x;
                        if (fresh || pixel_y < min_y[chosen]) min_y[chosen] <= pixel_y;
                        if (fresh || pixel_y > max_y[chosen]) max_y[chosen] <= pixel_y;
                    end
                    if (pixel_x == IMAGE_WIDTH-1 && pixel_y == IMAGE_HEIGHT-1) begin
                        state <= DUMP;
                        dump_idx <= 1;
                        active <= 0;
                    end
                end
                DUMP: if (slot_free) begin
                    if (dump_idx < next_label) begin
                        event_valid <= 1;
                        event_data <= 0;
                        event_data[7:0] <= 8'd2; // STAT
                        event_data[15:8] <= dump_idx[7:0];
                        event_data[63:32] <= areas[dump_idx];
                        event_data[95:64] <= sums_x[dump_idx];
                        event_data[127:96] <= sums_y[dump_idx];
                        event_data[159:128] <= {max_x[dump_idx],min_x[dump_idx]};
                        event_data[191:160] <= {max_y[dump_idx],min_y[dump_idx]};
                        dump_idx <= dump_idx + 1'b1;
                    end else state <= FINISH;
                end
                FINISH: if (slot_free) begin
                    event_valid <= 1;
                    event_data <= 0;
                    event_data[7:0] <= 8'd3; // END
                    event_data[15:8] <= 8'(next_label - 1'b1);
                    event_data[32] <= overflow;
                    state <= SCAN;
                end
                default: state <= SCAN;
            endcase
        end
    end
endmodule
