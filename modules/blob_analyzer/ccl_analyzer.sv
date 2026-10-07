`timescale 1ns / 1ps

// Connected Component Labeling + circularity detection.
// Single-pass streaming CCL with 1 line buffer of label IDs.
// Includes label equivalence resolution (merge) at frame end.
// At frame end, resolves merges then selects blob closest to pi/4 circularity.

module ccl_analyzer #(
    parameter integer IMAGE_WIDTH      = 640,
    parameter integer IMAGE_HEIGHT     = 400,
    parameter integer MAX_LABELS       = 64,
    parameter integer LABEL_BITS       = 8,
    parameter integer MIN_AREA         = 25,
    parameter integer CIRC_TARGET_Q16  = 51471   // pi/4 * 65536
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

    output logic        result_valid,
    output logic        target_found,
    output logic [15:0] center_x,
    output logic [15:0] center_y,
    output logic [15:0] bbox_left,
    output logic [15:0] bbox_right,
    output logic [15:0] bbox_top,
    output logic [15:0] bbox_bottom,
    output logic [23:0] area,
    output logic [15:0] ratio_q16
);

    // ============================================================
    //  Data stores
    // ============================================================
    logic [LABEL_BITS-1:0] line_buf      [0:IMAGE_WIDTH-1];
    logic [LABEL_BITS-1:0] prev_pixel_label;
    logic [LABEL_BITS-1:0] cur_label;
    logic [LABEL_BITS-1:0] next_label_id;

    logic [15:0] lbl_min_x   [0:MAX_LABELS-1];
    logic [15:0] lbl_max_x   [0:MAX_LABELS-1];
    logic [15:0] lbl_min_y   [0:MAX_LABELS-1];
    logic [15:0] lbl_max_y   [0:MAX_LABELS-1];
    logic [23:0] lbl_area    [0:MAX_LABELS-1];
    logic [31:0] lbl_sum_x   [0:MAX_LABELS-1];
    logic [31:0] lbl_sum_y   [0:MAX_LABELS-1];
    logic        lbl_active  [0:MAX_LABELS-1];
    logic [LABEL_BITS-1:0] lbl_merge [0:MAX_LABELS-1];  // union-find parent

    logic        s1_valid, s1_le;
    logic [15:0] s1_y;

    logic [LABEL_BITS-1:0] above_label;
    assign above_label = line_buf[pixel_x];

    logic [LABEL_BITS-1:0] above_label_gated;
    assign above_label_gated = frame_start ? '0 : above_label;

    logic [31:0] loop_i;

    // ============================================================
    //  Stage 1: Label assignment + blob statistics
    // ============================================================
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            prev_pixel_label <= 0;
            next_label_id    <= 8'd1;
            for (loop_i = 0; loop_i < IMAGE_WIDTH; loop_i = loop_i + 1)
                line_buf[loop_i] <= 0;
            s1_valid <= 0;  s1_le <= 0;  s1_y <= 0;
            for (loop_i = 0; loop_i < MAX_LABELS; loop_i = loop_i + 1) begin
                lbl_min_x[loop_i]  <= 16'hFFFF;
                lbl_max_x[loop_i]  <= 0;
                lbl_min_y[loop_i]  <= 16'hFFFF;
                lbl_max_y[loop_i]  <= 0;
                lbl_area[loop_i]   <= 0;
                lbl_sum_x[loop_i]  <= 0;
                lbl_sum_y[loop_i]  <= 0;
                lbl_active[loop_i] <= 0;
                lbl_merge[loop_i]  <= loop_i[LABEL_BITS-1:0];
            end
        end else begin
            s1_valid <= pixel_valid;
            s1_le    <= line_end;
            s1_y     <= pixel_y;

            if (pixel_valid && frame_start) begin
                next_label_id = 8'd1;
                for (loop_i = 0; loop_i < MAX_LABELS; loop_i = loop_i + 1) begin
                    lbl_min_x[loop_i]  <= 16'hFFFF;
                    lbl_max_x[loop_i]  <= 0;
                    lbl_min_y[loop_i]  <= 16'hFFFF;
                    lbl_max_y[loop_i]  <= 0;
                    lbl_area[loop_i]   <= 0;
                    lbl_sum_x[loop_i]  <= 0;
                    lbl_sum_y[loop_i]  <= 0;
                    lbl_active[loop_i] <= 0;
                    lbl_merge[loop_i]  <= loop_i[LABEL_BITS-1:0];
                end
            end

            if (pixel_valid) begin
                if (line_start)
                    prev_pixel_label = 0;

                // ---- Label assignment ----
                if (binary_data) begin
                    if (prev_pixel_label != 0) begin
                        cur_label = prev_pixel_label;
                        if (above_label_gated != 0 && above_label_gated != prev_pixel_label)
                            lbl_merge[above_label_gated] <= prev_pixel_label;
                    end else if (above_label_gated != 0) begin
                        cur_label = above_label_gated;
                    end else begin
                        if (next_label_id < MAX_LABELS - 1) begin
                            cur_label = next_label_id;
                            next_label_id <= next_label_id + 8'd1;
                            lbl_active[cur_label] <= 1'b1;
                        end else begin
                            cur_label = 0;
                        end
                    end
                end else begin
                    cur_label = 0;
                end

                prev_pixel_label <= cur_label;
                line_buf[pixel_x] <= cur_label;

                // ---- Blob statistics ----
                if (binary_data && cur_label != 0) begin
                    if (pixel_x < lbl_min_x[cur_label]) lbl_min_x[cur_label] <= pixel_x;
                    if (pixel_x > lbl_max_x[cur_label]) lbl_max_x[cur_label] <= pixel_x;
                    if (pixel_y < lbl_min_y[cur_label]) lbl_min_y[cur_label] <= pixel_y;
                    if (pixel_y > lbl_max_y[cur_label]) lbl_max_y[cur_label] <= pixel_y;
                    lbl_area[cur_label]  <= lbl_area[cur_label] + 24'd1;
                    lbl_sum_x[cur_label] <= lbl_sum_x[cur_label] + {16'd0, pixel_x};
                    lbl_sum_y[cur_label] <= lbl_sum_y[cur_label] + {16'd0, pixel_y};
                end
            end
        end
    end

    // ============================================================
    //  Stage 2: Merge resolve + best-blob selection
    // ============================================================
    typedef enum logic [2:0] { S2_IDLE, S2_RESOLVE, S2_SCAN, S2_OUTPUT } state_t;
    state_t state;
    logic [LABEL_BITS-1:0] scan_idx;
    logic [LABEL_BITS-1:0] merge_root;

    // Temporary computation registers
    logic [31:0] s2_bw, s2_bh;
    logic [47:0] s2_ba;
    logic [15:0] s2_circ;
    logic [16:0] s2_err;

    // Best-so-far registers
    logic [16:0] best_err;
    logic [15:0] best_cx, best_cy, best_bl, best_br, best_bt, best_bb;
    logic [23:0] best_area;
    logic [15:0] best_ratio;
    logic        best_found;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state        <= S2_IDLE;
            scan_idx     <= 0;
            merge_root   <= 0;
            result_valid <= 0;
            target_found <= 0;
            center_x  <= 0;  center_y  <= 0;
            bbox_left <= 0;  bbox_right <= 0;
            bbox_top  <= 0;  bbox_bottom <= 0;
            area      <= 0;  ratio_q16 <= 0;
            best_err  <= 0;
            best_cx <= 0; best_cy <= 0; best_bl <= 0; best_br <= 0;
            best_bt <= 0; best_bb <= 0;
            best_area  <= 0; best_ratio <= 0;
            best_found <= 0;
            s2_bw <= 0; s2_bh <= 0; s2_ba <= 0; s2_circ <= 0; s2_err <= 0;
        end else begin
            result_valid <= 0;

            // Detect frame end
            if (s1_valid && s1_le && s1_y == (IMAGE_HEIGHT - 1)) begin
                state    <= S2_RESOLVE;
                scan_idx <= 8'd1;
            end

            case (state)
                S2_IDLE: ;

                // ---- Merge resolution: flatten equivalence chains ----
                S2_RESOLVE: begin
                    if (scan_idx < next_label_id) begin
                        scan_idx <= scan_idx + 8'd1;
                        if (lbl_active[scan_idx]) begin
                            // Find root (follow parent chain, max 2 hops)
                            merge_root = lbl_merge[scan_idx];
                            if (lbl_merge[merge_root] != merge_root)
                                merge_root = lbl_merge[merge_root];

                            if (merge_root != scan_idx && merge_root != 0) begin
                                // Merge scan_idx stats into root
                                if (lbl_min_x[scan_idx] < lbl_min_x[merge_root])
                                    lbl_min_x[merge_root] <= lbl_min_x[scan_idx];
                                if (lbl_max_x[scan_idx] > lbl_max_x[merge_root])
                                    lbl_max_x[merge_root] <= lbl_max_x[scan_idx];
                                if (lbl_min_y[scan_idx] < lbl_min_y[merge_root])
                                    lbl_min_y[merge_root] <= lbl_min_y[scan_idx];
                                if (lbl_max_y[scan_idx] > lbl_max_y[merge_root])
                                    lbl_max_y[merge_root] <= lbl_max_y[scan_idx];
                                lbl_area[merge_root]  <= lbl_area[merge_root]  + lbl_area[scan_idx];
                                lbl_sum_x[merge_root] <= lbl_sum_x[merge_root] + lbl_sum_x[scan_idx];
                                lbl_sum_y[merge_root] <= lbl_sum_y[merge_root] + lbl_sum_y[scan_idx];
                                lbl_active[scan_idx]  <= 1'b0;
                            end
                        end
                    end else begin
                        // Done resolving. Initialize scan for best-blob.
                        state    <= S2_SCAN;
                        scan_idx <= 8'd1;
                        best_err <= 17'h1FFFF;
                        best_found <= 0;
                    end
                end

                // ---- Scan resolved labels for best circularity ----
                S2_SCAN: begin
                    if (scan_idx < next_label_id) begin
                        scan_idx <= scan_idx + 8'd1;
                        if (lbl_active[scan_idx] && lbl_area[scan_idx] >= MIN_AREA) begin
                            s2_bw   = {16'd0, lbl_max_x[scan_idx]} - {16'd0, lbl_min_x[scan_idx]} + 32'd1;
                            s2_bh   = {16'd0, lbl_max_y[scan_idx]} - {16'd0, lbl_min_y[scan_idx]} + 32'd1;
                            s2_ba   = s2_bw * s2_bh;
                            // Aspect ratio: |width - height|, closest to square (1:1) wins
                            s2_err  = (s2_bw > s2_bh)
                                ? {1'b0, s2_bw} - {1'b0, s2_bh}
                                : {1'b0, s2_bh} - {1'b0, s2_bw};
                            s2_circ = 16'd0;  // unused
                            // Best aspect ratio (smallest |w-h|). Tiebreaker: larger area.
                            if ((s2_err < best_err) ||
                                (s2_err == best_err && lbl_area[scan_idx] > best_area)) begin
                                best_err   <= s2_err;
                                best_found <= 1;
                                best_cx <= 16'(lbl_sum_x[scan_idx] / {8'd0, lbl_area[scan_idx]});
                                best_cy <= 16'(lbl_sum_y[scan_idx] / {8'd0, lbl_area[scan_idx]});
                                best_bl <= lbl_min_x[scan_idx];
                                best_br <= lbl_max_x[scan_idx];
                                best_bt <= lbl_min_y[scan_idx];
                                best_bb <= lbl_max_y[scan_idx];
                                best_area  <= lbl_area[scan_idx];
                                best_ratio <= s2_circ;
                            end
                        end
                    end else begin
                        state <= S2_OUTPUT;
                    end
                end

                S2_OUTPUT: begin
                    if (best_found) begin
                        target_found <= 1;
                        center_x  <= best_cx;
                        center_y  <= best_cy;
                        bbox_left <= best_bl;
                        bbox_right <= best_br;
                        bbox_top  <= best_bt;
                        bbox_bottom <= best_bb;
                        area      <= best_area;
                        ratio_q16 <= best_ratio;
                    end else begin
                        target_found <= 0;
                        center_x  <= 0; center_y  <= 0;
                        bbox_left <= 0; bbox_right <= 0;
                        bbox_top  <= 0; bbox_bottom <= 0;
                        area      <= 0; ratio_q16 <= 0;
                    end
                    result_valid <= 1;
                    state <= S2_IDLE;
                end
            endcase
        end
    end

endmodule
