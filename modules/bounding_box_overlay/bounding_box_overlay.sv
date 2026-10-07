`timescale 1ns / 1ps

// Draw the most recently detected target bounding box on a grayscale pixel
// stream. Accepts dynamic bbox coordinates from blob_analyzer.
// Detection normally completes at the end of one frame, so the stored
// rectangle is displayed on the following frame.

module bounding_box_overlay #(
    parameter integer PIXEL_WIDTH   = 10,
    parameter integer BOX_THICKNESS = 1,
    parameter logic [PIXEL_WIDTH-1:0] BOX_VALUE = {PIXEL_WIDTH{1'b1}}
) (
    input  logic                   clk,
    input  logic                   reset_n,

    input  logic [PIXEL_WIDTH-1:0] pixel_data,
    input  logic                   pixel_valid,
    input  logic                   frame_start,
    input  logic                   line_start,
    input  logic                   line_end,
    input  logic [15:0]            pixel_x,
    input  logic [15:0]            pixel_y,

    // One-cycle result pulse from blob_analyzer (per frame)
    input  logic                   result_valid,
    input  logic                   target_found,
    // Dynamic bbox from blob_analyzer
    input  logic [15:0]            bbox_left,
    input  logic [15:0]            bbox_right,
    input  logic [15:0]            bbox_top,
    input  logic [15:0]            bbox_bottom,

    output logic [PIXEL_WIDTH-1:0] boxed_data,
    output logic                   boxed_valid,
    output logic                   boxed_frame_start,
    output logic                   boxed_line_start,
    output logic                   boxed_line_end,
    output logic [15:0]            boxed_x,
    output logic [15:0]            boxed_y,
    output logic                   box_active
);

    logic        saved_target_found;
    logic [15:0] saved_box_left, saved_box_right;
    logic [15:0] saved_box_top, saved_box_bottom;

    logic [16:0] pixel_x_ext, pixel_y_ext;
    logic [16:0] box_l, box_r, box_t, box_b;
    logic [16:0] inner_l, inner_r, inner_t, inner_b;
    logic        eff_target_found;
    logic        inside_box, on_box_border;

    always_comb begin
        eff_target_found = result_valid ? target_found : saved_target_found;
        box_l = result_valid ? {1'b0, bbox_left}   : {1'b0, saved_box_left};
        box_r = result_valid ? {1'b0, bbox_right}  : {1'b0, saved_box_right};
        box_t = result_valid ? {1'b0, bbox_top}    : {1'b0, saved_box_top};
        box_b = result_valid ? {1'b0, bbox_bottom} : {1'b0, saved_box_bottom};

        inner_l = box_l + BOX_THICKNESS;
        inner_r = box_r - BOX_THICKNESS + 17'd1;  // +1: exclusive -> inclusive
        inner_t = box_t + BOX_THICKNESS;
        inner_b = box_b - BOX_THICKNESS + 17'd1;

        pixel_x_ext = {1'b0, pixel_x};
        pixel_y_ext = {1'b0, pixel_y};

        inside_box = eff_target_found
                     && (pixel_x_ext >= box_l) && (pixel_x_ext <= box_r)
                     && (pixel_y_ext >= box_t) && (pixel_y_ext <= box_b);

        on_box_border = inside_box
                        && ((pixel_x_ext <  inner_l) || (pixel_x_ext >  inner_r)
                         || (pixel_y_ext <  inner_t) || (pixel_y_ext >  inner_b));
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            saved_target_found <= 1'b0;
            saved_box_left     <= 16'd0;
            saved_box_right    <= 16'd0;
            saved_box_top      <= 16'd0;
            saved_box_bottom   <= 16'd0;
        end else if (result_valid) begin
            saved_target_found <= target_found;
            saved_box_left     <= bbox_left;
            saved_box_right    <= bbox_right;
            saved_box_top      <= bbox_top;
            saved_box_bottom   <= bbox_bottom;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            boxed_data        <= '0;
            boxed_valid       <= 1'b0;
            boxed_frame_start <= 1'b0;
            boxed_line_start  <= 1'b0;
            boxed_line_end    <= 1'b0;
            boxed_x           <= 16'd0;
            boxed_y           <= 16'd0;
            box_active        <= 1'b0;
        end else begin
            boxed_valid       <= pixel_valid;
            boxed_frame_start <= 1'b0;
            boxed_line_start  <= 1'b0;
            boxed_line_end    <= 1'b0;
            box_active        <= pixel_valid && on_box_border;

            if (pixel_valid) begin
                boxed_data        <= on_box_border ? BOX_VALUE : pixel_data;
                boxed_frame_start <= frame_start;
                boxed_line_start  <= line_start;
                boxed_line_end    <= line_end;
                boxed_x           <= pixel_x;
                boxed_y           <= pixel_y;
            end else begin
                boxed_data <= '0;
            end
        end
    end

endmodule
