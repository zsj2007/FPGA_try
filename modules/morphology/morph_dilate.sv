`timescale 1ns / 1ps

// 9x9 morphological dilation: output 1 if any window pixel is 1.
// Uses BinaryConvCore for sliding window generation.

module morph_dilate #(
    parameter integer IMAGE_WIDTH  = 640,
    parameter integer IMAGE_HEIGHT = 400,
    parameter integer WINDOW_SIZE  = 9
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
    output logic        dilated_valid,
    output logic        dilated_frame_start,
    output logic        dilated_line_start,
    output logic        dilated_line_end,
    output logic [15:0] dilated_x,
    output logic [15:0] dilated_y,
    output logic        dilated_data
);
    localparam integer WIN_BITS = WINDOW_SIZE * WINDOW_SIZE;
    localparam integer LATENCY  = 2;

    logic clk_en;
    logic [WIN_BITS-1:0] window;
    logic any_white;

    assign clk_en = pixel_valid;

    BinaryConvCore #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .WINDOW_SIZE(WINDOW_SIZE)
    ) u_conv (
        .clk(clk), .reset_n(reset_n), .clk_en(clk_en),
        .data_in(binary_data), .window(window)
    );

    assign any_white = (window != {WIN_BITS{1'b0}});

    logic [LATENCY-1:0] valid_sr, fs_sr, ls_sr, le_sr, data_sr;
    logic [15:0] x_sr [0:LATENCY-1];
    logic [15:0] y_sr [0:LATENCY-1];

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            valid_sr <= '0; fs_sr <= '0; ls_sr <= '0; le_sr <= '0; data_sr <= '0;
        end else begin
            valid_sr <= {valid_sr[LATENCY-2:0], pixel_valid};
            fs_sr    <= {fs_sr[LATENCY-2:0],    frame_start};
            ls_sr    <= {ls_sr[LATENCY-2:0],    line_start};
            le_sr    <= {le_sr[LATENCY-2:0],    line_end};
            data_sr  <= {data_sr[LATENCY-2:0],  any_white};

            for (int i = 0; i < LATENCY; i++) begin
                if (i == 0) begin x_sr[i] <= pixel_x; y_sr[i] <= pixel_y; end
                else begin x_sr[i] <= x_sr[i-1]; y_sr[i] <= y_sr[i-1]; end
            end
        end
    end

    assign dilated_valid       = valid_sr[LATENCY-1];
    assign dilated_frame_start = fs_sr[LATENCY-1];
    assign dilated_line_start  = ls_sr[LATENCY-1];
    assign dilated_line_end    = le_sr[LATENCY-1];
    assign dilated_x           = x_sr[LATENCY-1];
    assign dilated_y           = y_sr[LATENCY-1];
    assign dilated_data        = data_sr[LATENCY-1];

endmodule
