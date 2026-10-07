`timescale 1ns / 1ps

// Sliding window generator for binary pixel stream.
// Produces an NxN window: window[r*WINDOW_SIZE + c] = pixel at
// (current_row - r, current_col - c).

module BinaryConvCore #(
    parameter integer IMAGE_WIDTH  = 640,
    parameter integer WINDOW_SIZE  = 9
) (
    input  logic clk,
    input  logic reset_n,
    input  logic clk_en,
    input  logic data_in,
    output logic [WINDOW_SIZE*WINDOW_SIZE-1:0] window
);

    logic [IMAGE_WIDTH-1:0] line_buf [0:WINDOW_SIZE-2];
    logic [WINDOW_SIZE-1:0] h_shift [0:WINDOW_SIZE-1];

    // Line buffer chain (generate)
    genvar i;
    generate
        for (i = 0; i < WINDOW_SIZE-1; i = i + 1) begin : gen_line_buf
            always_ff @(posedge clk or negedge reset_n) begin
                if (!reset_n) begin
                    line_buf[i] <= '0;
                end else if (clk_en) begin
                    line_buf[i] <= {line_buf[i][IMAGE_WIDTH-2:0],
                                    (i == 0 ? data_in : line_buf[i-1][IMAGE_WIDTH-1])};
                end
            end
        end
    endgenerate

    // h_shift logic (procedural, to avoid genvar-in-procedural-for issues)
    integer jj, kk;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (jj = 0; jj < WINDOW_SIZE; jj = jj + 1)
                h_shift[jj] <= '0;
        end else if (clk_en) begin
            // Col 0 gets the line-delayed value
            h_shift[0][0] <= data_in;
            for (jj = 1; jj < WINDOW_SIZE; jj = jj + 1)
                h_shift[jj][0] <= line_buf[jj-1][IMAGE_WIDTH-1];
            // Shift right
            for (jj = 0; jj < WINDOW_SIZE; jj = jj + 1) begin
                for (kk = 1; kk < WINDOW_SIZE; kk = kk + 1)
                    h_shift[jj][kk] <= h_shift[jj][kk-1];
            end
        end
    end

    // Window assembly (combinational)
    integer ri, ci;
    always_comb begin
        for (ri = 0; ri < WINDOW_SIZE; ri = ri + 1) begin
            for (ci = 0; ci < WINDOW_SIZE; ci = ci + 1) begin
                window[ri*WINDOW_SIZE + ci] = h_shift[ri][ci];
            end
        end
    end

endmodule
