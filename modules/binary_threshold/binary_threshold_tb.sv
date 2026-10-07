`timescale 1ns / 1ps

module binary_threshold_tb;

    localparam integer PIXEL_WIDTH = 10;

    logic                   clk = 1'b0;
    logic                   reset_n = 1'b0;
    logic [PIXEL_WIDTH-1:0] pixel_data = '0;
    logic                   pixel_valid = 1'b0;
    logic                   frame_start = 1'b0;
    logic                   line_start = 1'b0;
    logic                   line_end = 1'b0;
    logic [15:0]            pixel_x = 16'd0;
    logic [15:0]            pixel_y = 16'd0;
    logic                   binary_data;
    logic                   binary_valid;
    logic                   binary_frame_start;
    logic                   binary_line_start;
    logic                   binary_line_end;
    logic [15:0]            binary_x;
    logic [15:0]            binary_y;

    always #5 clk = ~clk;

    binary_threshold #(
        .PIXEL_WIDTH (PIXEL_WIDTH),
        .THRESHOLD   (10'd900)
    ) dut (
        .clk                (clk),
        .reset_n            (reset_n),
        .pixel_data         (pixel_data),
        .pixel_valid        (pixel_valid),
        .frame_start        (frame_start),
        .line_start         (line_start),
        .line_end           (line_end),
        .pixel_x            (pixel_x),
        .pixel_y            (pixel_y),
        .binary_data        (binary_data),
        .binary_valid       (binary_valid),
        .binary_frame_start (binary_frame_start),
        .binary_line_start  (binary_line_start),
        .binary_line_end    (binary_line_end),
        .binary_x           (binary_x),
        .binary_y           (binary_y)
    );

    task automatic send_and_check(
        input logic [PIXEL_WIDTH-1:0] value,
        input logic                   expected_binary,
        input logic                   expected_frame_start,
        input logic                   expected_line_start,
        input logic                   expected_line_end,
        input logic [15:0]            expected_x,
        input logic [15:0]            expected_y
    );
        begin
            @(negedge clk);
            pixel_data  = value;
            pixel_valid = 1'b1;
            frame_start = expected_frame_start;
            line_start  = expected_line_start;
            line_end    = expected_line_end;
            pixel_x     = expected_x;
            pixel_y     = expected_y;

            @(posedge clk);
            #1;

            if (!binary_valid)
                $fatal(1, "Output was not valid for input value %0d", value);
            if (binary_data !== expected_binary)
                $fatal(1, "Threshold mismatch for %0d: expected %0d, got %0d",
                       value, expected_binary, binary_data);
            if (binary_frame_start !== expected_frame_start ||
                binary_line_start  !== expected_line_start  ||
                binary_line_end    !== expected_line_end)
                $fatal(1, "Boundary flag mismatch for input value %0d", value);
            if (binary_x !== expected_x || binary_y !== expected_y)
                $fatal(1, "Coordinate mismatch for input value %0d", value);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset_n = 1'b1;

        // Test the darkest value, both sides of the threshold, and maximum.
        send_and_check(10'd0,    1'b0, 1'b1, 1'b1, 1'b0, 16'd0, 16'd0);
        send_and_check(10'd511,  1'b0, 1'b0, 1'b0, 1'b0, 16'd1, 16'd0);
        send_and_check(10'd512,  1'b1, 1'b0, 1'b0, 1'b0, 16'd2, 16'd0);
        send_and_check(10'd1023, 1'b1, 1'b0, 1'b0, 1'b1, 16'd3, 16'd0);

        @(negedge clk);
        pixel_valid = 1'b0;
        frame_start = 1'b0;
        line_start  = 1'b0;
        line_end    = 1'b0;

        @(posedge clk);
        #1;
        if (binary_valid)
            $fatal(1, "binary_valid did not follow an invalid input cycle");

        $display("PASS: binary_threshold boundary values");
        $finish;
    end

endmodule
