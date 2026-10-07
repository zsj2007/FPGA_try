`timescale 1ns / 1ps

// Convert a monochrome pixel stream into a one-bit binary image.
// A pixel is white (1) when pixel_data >= THRESHOLD, otherwise black (0).
module binary_threshold #(
    parameter integer PIXEL_WIDTH = 10,
    parameter logic [PIXEL_WIDTH-1:0] THRESHOLD = 10'd900
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

    output logic                   binary_data,
    output logic                   binary_valid,
    output logic                   binary_frame_start,
    output logic                   binary_line_start,
    output logic                   binary_line_end,
    output logic [15:0]            binary_x,
    output logic [15:0]            binary_y
);

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            binary_data        <= 1'b0;
            binary_valid       <= 1'b0;
            binary_frame_start <= 1'b0;
            binary_line_start  <= 1'b0;
            binary_line_end    <= 1'b0;
            binary_x           <= 16'd0;
            binary_y           <= 16'd0;
        end else begin
            // Boundary flags are meaningful only together with binary_valid.
            binary_valid       <= pixel_valid;
            binary_frame_start <= 1'b0;
            binary_line_start  <= 1'b0;
            binary_line_end    <= 1'b0;

            if (pixel_valid) begin
                binary_data        <= (pixel_data >= THRESHOLD);
                binary_frame_start <= frame_start;
                binary_line_start  <= line_start;
                binary_line_end    <= line_end;
                binary_x           <= pixel_x;
                binary_y           <= pixel_y;
            end else begin
                binary_data <= 1'b0;
            end
        end
    end

endmodule
