`timescale 1ns / 1ps

module los_guidance_tb;

    localparam integer CORDIC_STAGES = 16;
    localparam real    FOCUS_MM      = 2.0;
    localparam real    PIXEL_X_MM    = 3.9 / 640.0;
    localparam real    PIXEL_Y_MM    = 2.45 / 400.0;
    localparam real    FOCUS_PX_X_R  = FOCUS_MM / PIXEL_X_MM;
    localparam real    FOCUS_PX_Y_R  = FOCUS_MM / PIXEL_Y_MM;
    localparam logic [31:0] FOCUS_PX_X = int'(FOCUS_PX_X_R * 65536.0 + 0.5);
    localparam logic [31:0] FOCUS_PX_Y = int'(FOCUS_PX_Y_R * 65536.0 + 0.5);
    localparam logic [31:0] CENTER_CX  = 32'd20971520;  // 320.0
    localparam logic [31:0] CENTER_CY  = 32'd13107200;  // 200.0

    logic        clk = 0;
    logic        reset_n = 0;
    logic        result_valid = 0;
    logic        target_found = 0;
    logic [15:0] best_x = 0;
    logic [15:0] best_y = 0;
    logic        los_valid;
    logic [31:0] hfov_q16;
    logic [31:0] vfov_q16;
    logic [31:0] omega_hfov_q16;
    logic [31:0] omega_vfov_q16;
    logic        omega_valid;

    always #5 clk = ~clk;

    los_guidance #(
        .CORDIC_STAGES(CORDIC_STAGES),
        .FOCUS_PX_X(FOCUS_PX_X),
        .FOCUS_PX_Y(FOCUS_PX_Y),
        .CENTER_CX(CENTER_CX),
        .CENTER_CY(CENTER_CY)
    ) dut (.*);

    // Expected: target=(415,110), box 20x20 -> centre (425,120)
    // dx=320-425=-105, dy=120-200=-80
    // hfov = atan2(-105, 328.2) ~ -0.3094 rad
    // vfov = atan2(-80,  327.0) ~ -0.2397 rad
    // CORDIC tolerance: 0.005 rad (16-stage CORDIC precision)
    localparam real TOLERANCE = 0.005;

    function automatic real q29_to_real(logic [31:0] v);
        return $itor($signed(v)) / (1 << 29);
    endfunction

    task automatic check_angle(
        input string name,
        input logic [31:0] got,
        input real expected
    );
        real val = q29_to_real(got);
        real err = val - expected;
        if (err < 0) err = -err;
        $display("%s = 0x%h (%.4f rad)  expected ~%.4f rad  err=%.6f",
                 name, got, val, expected, err);
        if (err > TOLERANCE)
            $fatal(1, "%s out of tolerance: %.6f rad", name, err);
    endtask

    initial begin
        repeat (4) @(negedge clk);
        reset_n = 1;

        // Frame 0
        @(negedge clk);
        result_valid = 1; target_found = 1; best_x = 415; best_y = 110;
        @(negedge clk);
        result_valid = 0; target_found = 0;

        wait (los_valid);
        check_angle("HFOV", hfov_q16, -0.3094);
        check_angle("VFOV", vfov_q16, -0.2397);

        repeat (8) @(negedge clk);

        // Frame 1: target moved right by 10 px -> centre (435, 125)
        // hfov = atan2(-115, 328.2) ~ -0.3367 rad
        // vfov = atan2(-75,  327.0) ~ -0.2251 rad
        @(negedge clk);
        result_valid = 1; target_found = 1; best_x = 425; best_y = 115;
        @(negedge clk);
        result_valid = 0; target_found = 0;

        wait (los_valid);
        check_angle("HFOV", hfov_q16, -0.3367);
        check_angle("VFOV", vfov_q16, -0.2251);

        wait (omega_valid);
        $display("Omega: wx=%.4f rad/s, wz=%.4f rad/s",
                 $itor($signed(omega_hfov_q16)) / (1 << 24),
                 $itor($signed(omega_vfov_q16)) / (1 << 24));

        // Frame 2: no target
        repeat (8) @(negedge clk);
        @(negedge clk);
        result_valid = 1; target_found = 0;
        @(negedge clk);
        result_valid = 0;

        repeat (32) @(negedge clk);

        $display("PASS: los_guidance simulation completed");
        $finish;
    end

endmodule
