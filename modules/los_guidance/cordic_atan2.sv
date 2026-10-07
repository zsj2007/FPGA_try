// Pipelined CORDIC vectoring-mode atan2(y, x).
//
// N pipeline stages, each stage does:
//   if (y >= 0)  x'=x+(y>>>i), y'=y-(x>>>i), angle'=angle+atan_table[i]
//   else         x'=x-(y>>>i), y'=y+(x>>>i), angle'=angle-atan_table[i]
//
// Input:  Q16.16 fixed-point x, y (signed 32-bit).
// Output: Q3.29 radian angle in range [-pi/2, +pi/2].
//
// Latency: STAGES + 1 clocks from start to done.

module cordic_atan2 #(
    parameter integer STAGES = 16
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,
    input  logic signed [31:0] x_in,
    input  logic signed [31:0] y_in,
    output logic        done,
    output logic signed [31:0] angle_out
);

    // atan(2^-i) in Q3.29 radians.
    localparam logic signed [31:0] ATAN_TABLE [0:STAGES-1] = '{
        32'sh1921FB54,  // atan(2^0)  = 0.785398 rad
        32'sh0ED63383,  // atan(2^-1) = 0.463648
        32'sh07D6DD7E,  // atan(2^-2) = 0.244979
        32'sh03FAB753,  // atan(2^-3) = 0.124355
        32'sh01FE5592,  // atan(2^-4) = 0.062419
        32'sh00FFEAAC,  // atan(2^-5) = 0.031240
        32'sh007FFD55,  // atan(2^-6) = 0.015624
        32'sh003FFFAA,  // atan(2^-7) = 0.007812
        32'sh001FFFF5,  // atan(2^-8) = 0.003906
        32'sh000FFFFE,  // atan(2^-9) = 0.001953
        32'sh0007FFFF,  // atan(2^-10)= 0.000977
        32'sh0003FFFF,  // atan(2^-11)= 0.000488
        32'sh0001FFFF,  // atan(2^-12)= 0.000244
        32'sh0000FFFF,  // atan(2^-13)= 0.000122
        32'sh00007FFF,  // atan(2^-14)= 0.000061
        32'sh00003FFF   // atan(2^-15)= 0.000031
    };

    // Pipeline registers -- MUST be signed for correct arithmetic.
    logic signed [31:0] x_pipe [0:STAGES];
    logic signed [31:0] y_pipe [0:STAGES];
    logic signed [31:0] z_pipe [0:STAGES];
    logic [STAGES:0] valid_pipe;

    // Stage 0: load inputs on start pulse.
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            x_pipe[0]     <= 32'sd0;
            y_pipe[0]     <= 32'sd0;
            z_pipe[0]     <= 32'sd0;
            valid_pipe[0] <= 1'b0;
        end else if (start) begin
            x_pipe[0]     <= x_in;
            y_pipe[0]     <= y_in;
            z_pipe[0]     <= 32'sd0;
            valid_pipe[0] <= 1'b1;
        end else begin
            valid_pipe[0] <= 1'b0;
        end
    end

    // Stages 1..STAGES: CORDIC iterations.
    generate
        for (genvar s = 0; s < STAGES; s = s + 1) begin : cordic_stage
            always_ff @(posedge clk) begin
                if (valid_pipe[s]) begin
                    if (y_pipe[s] >= 32'sd0) begin
                        x_pipe[s+1] <= x_pipe[s] + (y_pipe[s] >>> s);
                        y_pipe[s+1] <= y_pipe[s] - (x_pipe[s] >>> s);
                        z_pipe[s+1] <= z_pipe[s] + ATAN_TABLE[s];
                    end else begin
                        x_pipe[s+1] <= x_pipe[s] - (y_pipe[s] >>> s);
                        y_pipe[s+1] <= y_pipe[s] + (x_pipe[s] >>> s);
                        z_pipe[s+1] <= z_pipe[s] - ATAN_TABLE[s];
                    end
                    valid_pipe[s+1] <= 1'b1;
                end else begin
                    valid_pipe[s+1] <= 1'b0;
                end
            end
        end
    endgenerate

    assign done      = valid_pipe[STAGES];
    assign angle_out = z_pipe[STAGES];

endmodule
