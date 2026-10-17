`timescale 1ns / 1ps

// ============================================================================
// ccl_frontend  streaming connected-component labeling front-end (PL side).
//
// Scans one pixel per cycle and:
//   1. Assigns temporary labels to white pixels (4-neighbor: left & above)
//   2. Accumulates per-label statistics in distributed RAM
//   3. Records label equivalences (merges) in a union-find parent table
//
// At frame-end the accumulated tables are dumped word-by-word over a simple
// streaming interface so that the PS can read them through an AXI bridge
// and finish the merge + selection in software.
// ============================================================================

module ccl_frontend #(
    parameter integer IMAGE_WIDTH  = 640,
    parameter integer IMAGE_HEIGHT = 400,
    parameter integer MAX_LABELS   = 64,
    parameter integer LABEL_BITS   = 8
) (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        pixel_valid,
    input  logic        frame_start,
    input  logic        line_start,
    input  logic        line_end,
    input  logic [15:0] pixel_x,
    input  logic [15:0] pixel_y,
    input  logic        binary_data,

    output logic                   dump_valid,
    output logic [LABEL_BITS-1:0]  dump_label,
    output logic [23:0]            dump_area,
    output logic [31:0]            dump_sum_x,
    output logic [31:0]            dump_sum_y,
    output logic [15:0]            dump_min_x,
    output logic [15:0]            dump_max_x,
    output logic [15:0]            dump_min_y,
    output logic [15:0]            dump_max_y,
    output logic [LABEL_BITS-1:0]  dump_equiv_parent,
    output logic                   frame_done,
    output logic [LABEL_BITS-1:0]  num_labels
);

    localparam integer BANK_ADDR_BITS = $clog2(MAX_LABELS * 5 + 16);

    // Distributed RAM storage
    (* ram_style = "distributed" *)
    logic [LABEL_BITS-1:0] line_buf [0:IMAGE_WIDTH-1];

    (* ram_style = "distributed" *)
    logic [23:0]  stat_area  [0:MAX_LABELS-1];
    (* ram_style = "distributed" *)
    logic [31:0]  stat_sum_x [0:MAX_LABELS-1];
    (* ram_style = "distributed" *)
    logic [31:0]  stat_sum_y [0:MAX_LABELS-1];
    (* ram_style = "distributed" *)
    logic [15:0]  stat_min_x [0:MAX_LABELS-1];
    (* ram_style = "distributed" *)
    logic [15:0]  stat_max_x [0:MAX_LABELS-1];
    (* ram_style = "distributed" *)
    logic [15:0]  stat_min_y [0:MAX_LABELS-1];
    (* ram_style = "distributed" *)
    logic [15:0]  stat_max_y [0:MAX_LABELS-1];

    (* ram_style = "distributed" *)
    logic [LABEL_BITS-1:0] equiv_table [0:MAX_LABELS-1];

    // Pipeline registers
    logic [LABEL_BITS-1:0] prev_pixel_label;
    logic [LABEL_BITS-1:0] cur_label;
    logic [LABEL_BITS-1:0] next_label_id;
    logic                  label_full;
    logic                  first_line;

    // Dump state machine
    typedef enum logic [1:0] { DUMP_IDLE, DUMP_SCAN, DUMP_DONE } dump_state_t;
    dump_state_t dump_state;
    logic [LABEL_BITS-1:0] dump_idx;

    // Combinational
    logic [LABEL_BITS-1:0] above_label;
    logic [LABEL_BITS-1:0] above_label_gated;
    assign above_label       = line_buf[pixel_x];
    assign above_label_gated = first_line ? '0 : above_label;

    // ========================================================================
    //  Stage 1: Label assignment + statistics
    // ========================================================================
    always_ff @(posedge clk or negedge reset_n) begin
        logic is_new_label;
        logic [LABEL_BITS-1:0] lbl;

        if (!reset_n) begin
            prev_pixel_label <= '0;
            next_label_id    <= 8'd1;
            label_full       <= 1'b0;
            cur_label        <= '0;
            first_line       <= 1'b0;
        end else begin
            is_new_label = 1'b0;

            if (pixel_valid) begin
                if (frame_start) begin
                    next_label_id    = 8'd1;   // blocking: reset before label assignment
                    prev_pixel_label <= '0;
                    label_full       <= 1'b0;
                    first_line       <= 1'b1;
                end

                if (line_start)
                    prev_pixel_label <= '0;

                if (binary_data) begin
                    // ---- Label assignment ----
                    if (prev_pixel_label != 0) begin
                        cur_label = prev_pixel_label;
                        if (above_label_gated != 0 && above_label_gated != prev_pixel_label)
                            equiv_table[above_label_gated] <= prev_pixel_label;
                    end else if (above_label_gated != 0) begin
                        cur_label = above_label_gated;
                    end else begin
                        if (!label_full && next_label_id < MAX_LABELS) begin
                            lbl = next_label_id;
                            cur_label      = lbl;
                            next_label_id  <= next_label_id + 8'd1;
                            is_new_label   = 1'b1;
                            stat_area [lbl] <= 24'd1;
                            stat_sum_x[lbl] <= {16'd0, pixel_x};
                            stat_sum_y[lbl] <= {16'd0, pixel_y};
                            stat_min_x[lbl] <= pixel_x;
                            stat_max_x[lbl] <= pixel_x;
                            stat_min_y[lbl] <= pixel_y;
                            stat_max_y[lbl] <= pixel_y;
                            equiv_table[lbl] <= lbl;
                        end else begin
                            cur_label  = '0;   // blocking
                            label_full <= 1'b1;
                        end
                    end

                    // ---- Update statistics for existing labels ----
                    if (cur_label != 0 && !is_new_label) begin
                        stat_area [cur_label] <= stat_area [cur_label] + 24'd1;
                        stat_sum_x[cur_label] <= stat_sum_x[cur_label] + {16'd0, pixel_x};
                        stat_sum_y[cur_label] <= stat_sum_y[cur_label] + {16'd0, pixel_y};
                        if (pixel_x < stat_min_x[cur_label])
                            stat_min_x[cur_label] <= pixel_x;
                        if (pixel_x > stat_max_x[cur_label])
                            stat_max_x[cur_label] <= pixel_x;
                        if (pixel_y < stat_min_y[cur_label])
                            stat_min_y[cur_label] <= pixel_y;
                        if (pixel_y > stat_max_y[cur_label])
                            stat_max_y[cur_label] <= pixel_y;
                    end
                end else begin
                    cur_label = '0;   // blocking: must be 0 so prev_pixel_label=0 for next pixel
                end

                line_buf[pixel_x] <= cur_label;
                prev_pixel_label  <= cur_label;
            end

            if (pixel_valid && line_end)
                first_line <= 1'b0;
        end
    end

    // ========================================================================
    //  Stage 2: Frame-end dump
    // ========================================================================
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            dump_state  <= DUMP_IDLE;
            dump_idx    <= '0;
            dump_valid  <= 1'b0;
            frame_done  <= 1'b0;
            num_labels  <= '0;
            {dump_area, dump_sum_x, dump_sum_y,
             dump_min_x, dump_max_x, dump_min_y, dump_max_y,
             dump_equiv_parent} <= '0;
        end else begin
            dump_valid <= 1'b0;
            frame_done <= 1'b0;

            case (dump_state)
                DUMP_IDLE: begin
                    if (pixel_valid && line_end && pixel_y == IMAGE_HEIGHT - 1) begin
                        dump_state <= DUMP_SCAN;
                        dump_idx   <= '0;
                        num_labels <= next_label_id;
                    end
                end

                DUMP_SCAN: begin
                    dump_valid        <= 1'b1;
                    dump_label        <= dump_idx;
                    dump_area         <= stat_area  [dump_idx];
                    dump_sum_x        <= stat_sum_x [dump_idx];
                    dump_sum_y        <= stat_sum_y [dump_idx];
                    dump_min_x        <= stat_min_x [dump_idx];
                    dump_max_x        <= stat_max_x [dump_idx];
                    dump_min_y        <= stat_min_y [dump_idx];
                    dump_max_y        <= stat_max_y [dump_idx];
                    dump_equiv_parent <= equiv_table[dump_idx];
                    if (dump_idx == MAX_LABELS - 1)
                        dump_state <= DUMP_DONE;
                    else
                        dump_idx <= dump_idx + 1'b1;
                end

                DUMP_DONE: begin
                    frame_done <= 1'b1;
                    dump_state <= DUMP_IDLE;
                end
            endcase
        end
    end

endmodule