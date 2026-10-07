`timescale 1ns / 1ps

// ROI Gate — zero-latency combinational mask.
// Only passes binary_data=1 when pixel is inside the center ROI region.
// ROI defaults to 30%-70% of image width and height.

module roi_gate #(
    parameter integer IMAGE_WIDTH  = 640,
    parameter integer IMAGE_HEIGHT = 400,
    parameter real    ROI_X_FRAC_MIN = 0.30,
    parameter real    ROI_X_FRAC_MAX = 0.70,
    parameter real    ROI_Y_FRAC_MIN = 0.30,
    parameter real    ROI_Y_FRAC_MAX = 0.70
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

    output logic        roi_data,
    output logic        roi_valid,
    output logic        roi_frame_start,
    output logic        roi_line_start,
    output logic        roi_line_end,
    output logic [15:0] roi_x,
    output logic [15:0] roi_y
);

    localparam integer ROI_X_MIN = integer'(IMAGE_WIDTH  * ROI_X_FRAC_MIN);
    localparam integer ROI_X_MAX = integer'(IMAGE_WIDTH  * ROI_X_FRAC_MAX - 1.0);
    localparam integer ROI_Y_MIN = integer'(IMAGE_HEIGHT * ROI_Y_FRAC_MIN);
    localparam integer ROI_Y_MAX = integer'(IMAGE_HEIGHT * ROI_Y_FRAC_MAX - 1.0);

    logic in_roi;
    assign in_roi = (pixel_x >= ROI_X_MIN) && (pixel_x <= ROI_X_MAX) &&
                    (pixel_y >= ROI_Y_MIN) && (pixel_y <= ROI_Y_MAX);

    // Zero-latency: outputs are combinational on inputs
    assign roi_data        = binary_data && in_roi;
    assign roi_valid       = pixel_valid;
    assign roi_frame_start = frame_start;
    assign roi_line_start  = line_start;
    assign roi_line_end    = line_end;
    assign roi_x           = pixel_x;
    assign roi_y           = pixel_y;

endmodule
