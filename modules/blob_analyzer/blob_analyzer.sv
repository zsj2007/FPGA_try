`timescale 1ns / 1ps

// Blob analyzer: tracks the largest white region in a binary stream.
//
// After morphological opening (erode + dilate), the binary image contains
// one dominant white blob (the guidance light). This module tracks:
//   - bounding box (l, r, t, b)
//   - total white pixel count (area)
//   - sum of x and y coordinates (for centroid)
//
// At frame end, selects the largest blob and outputs:
//   center_x = sum_x / area
//   center_y = sum_y / area
//   bbox left/right/top/bottom
//   area
//   ratio = area / (bbox_w * bbox_h)  in Q16

module blob_analyzer #(
    parameter integer IMAGE_WIDTH  = 640,
    parameter integer IMAGE_HEIGHT = 400,
    parameter integer MIN_AREA     = 25
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

    // ---- Frame-level accumulators ----
    logic [15:0] min_x, max_x, min_y, max_y;
    logic [23:0] white_count;
    logic [31:0] sum_x, sum_y;

    // ---- Track frame end ----
    logic        frame_active;
    logic [15:0] prev_x;
    logic        prev_valid;

    // ---- Detection ----
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            min_x      <= 16'hFFFF;
            max_x      <= 16'd0;
            min_y      <= 16'hFFFF;
            max_y      <= 16'd0;
            white_count <= 24'd0;
            sum_x      <= 32'd0;
            sum_y      <= 32'd0;
            frame_active <= 1'b0;
            prev_x     <= 16'd0;
            prev_valid <= 1'b0;
        end else begin
            if (frame_start && pixel_valid) begin
                // Reset for new frame
                min_x       <= 16'hFFFF;
                max_x       <= 16'd0;
                min_y       <= 16'hFFFF;
                max_y       <= 16'd0;
                white_count <= 24'd0;
                sum_x       <= 32'd0;
                sum_y       <= 32'd0;
                frame_active <= 1'b1;
            end

            prev_x     <= pixel_x;
            prev_valid <= pixel_valid;

            if (frame_active && pixel_valid && binary_data) begin
                // Update bbox
                if (pixel_x < min_x) min_x <= pixel_x;
                if (pixel_x > max_x) max_x <= pixel_x;
                if (pixel_y < min_y) min_y <= pixel_y;
                if (pixel_y > max_y) max_y <= pixel_y;

                // Accumulate
                white_count <= white_count + 24'd1;
                sum_x       <= sum_x + {16'd0, pixel_x};
                sum_y       <= sum_y + {16'd0, pixel_y};
            end
        end
    end

    // ---- Frame-end computation ----
    logic        compute_done;
    logic [23:0] saved_area;
    logic [15:0] saved_min_x, saved_max_x, saved_min_y, saved_max_y;
    logic [31:0] saved_sum_x, saved_sum_y;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            compute_done  <= 1'b0;
            saved_area    <= 24'd0;
            saved_min_x   <= 16'd0;
            saved_max_x   <= 16'd0;
            saved_min_y   <= 16'd0;
            saved_max_y   <= 16'd0;
            saved_sum_x   <= 32'd0;
            saved_sum_y   <= 32'd0;
        end else begin
            compute_done <= 1'b0;

            // Detect end of frame: pixel_valid goes low after last pixel,
            // or line_end with y at max, or frame_start of next frame
            // Simplest: latch when line_end and y == IMAGE_HEIGHT-1
            if (pixel_valid && line_end && pixel_y == (IMAGE_HEIGHT-1)) begin
                saved_area  <= white_count;
                saved_min_x <= min_x;
                saved_max_x <= max_x;
                saved_min_y <= min_y;
                saved_max_y <= max_y;
                saved_sum_x <= sum_x;
                saved_sum_y <= sum_y;
                compute_done <= 1'b1;
            end
        end
    end

    // ---- Output computation (combinational from saved values) ----
    logic [31:0] bbox_w, bbox_h;
    logic [47:0] bbox_area_ext;  // bbox_w * bbox_h

    assign bbox_w       = {16'd0, saved_max_x} - {16'd0, saved_min_x} + 32'd1;
    assign bbox_h       = {16'd0, saved_max_y} - {16'd0, saved_min_y} + 32'd1;
    assign bbox_area_ext = bbox_w * bbox_h;

    // Ratio = area / (w*h) * 65536, computed in Q16
    wire [47:0] ratio_ext = bbox_area_ext > 0
        ? ({24'd0, saved_area} * 48'd65536) / bbox_area_ext
        : 48'd0;

    // Center = sum / area  (integer pixel position)
    wire [31:0] cx = saved_area > 0 ? (saved_sum_x / {8'd0, saved_area}) : 32'd0;
    wire [31:0] cy = saved_area > 0 ? (saved_sum_y / {8'd0, saved_area}) : 32'd0;

    // ---- Output register ----
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            result_valid <= 1'b0;
            target_found <= 1'b0;
            center_x     <= 16'd0;
            center_y     <= 16'd0;
            bbox_left    <= 16'd0;
            bbox_right   <= 16'd0;
            bbox_top     <= 16'd0;
            bbox_bottom  <= 16'd0;
            area         <= 24'd0;
            ratio_q16    <= 16'd0;
        end else begin
            result_valid <= 1'b0;

            if (compute_done) begin
                if (saved_area >= MIN_AREA && bbox_w > 0 && bbox_h > 0) begin
                    target_found <= 1'b1;
                    center_x     <= cx[15:0];
                    center_y     <= cy[15:0];
                    bbox_left    <= saved_min_x;
                    bbox_right   <= saved_max_x;
                    bbox_top     <= saved_min_y;
                    bbox_bottom  <= saved_max_y;
                    area         <= saved_area;
                    ratio_q16    <= ratio_ext[15:0];
                end else begin
                    target_found <= 1'b0;
                    center_x     <= 16'd0;
                    center_y     <= 16'd0;
                    bbox_left    <= 16'd0;
                    bbox_right   <= 16'd0;
                    bbox_top     <= 16'd0;
                    bbox_bottom  <= 16'd0;
                    area         <= 24'd0;
                    ratio_q16    <= 16'd0;
                end
                result_valid <= 1'b1;
            end
        end
    end

endmodule
