`timescale 1ns / 1ps

module camera_capture_tb;

    localparam integer IMAGE_WIDTH  = 4;
    localparam integer IMAGE_HEIGHT = 3;
    localparam integer PIXEL_WIDTH  = 10;
    localparam integer PIXEL_COUNT  = IMAGE_WIDTH * IMAGE_HEIGHT;

    logic                   pclk = 1'b0;
    logic                   reset_n = 1'b0;
    logic [PIXEL_WIDTH-1:0] cam_data = '0;
    logic                   cam_href = 1'b0;
    logic                   cam_vsync = 1'b0;
    logic [PIXEL_WIDTH-1:0] pixel_data;
    logic                   pixel_valid;
    logic                   frame_start;
    logic                   line_start;
    logic                   line_end;
    logic [15:0]            pixel_x;
    logic [15:0]            pixel_y;

    integer received = 0;

    always #8 pclk = ~pclk;

    camera_capture #(
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .PIXEL_WIDTH  (PIXEL_WIDTH)
    ) dut (
        .pclk        (pclk),
        .reset_n     (reset_n),
        .cam_data    (cam_data),
        .cam_href    (cam_href),
        .cam_vsync   (cam_vsync),
        .pixel_data  (pixel_data),
        .pixel_valid (pixel_valid),
        .frame_start (frame_start),
        .line_start  (line_start),
        .line_end    (line_end),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y)
    );

    // Sample after nonblocking assignments from the DUT have settled.
    always @(posedge pclk) begin
        #1;
        if (reset_n && pixel_valid) begin
            if (pixel_data !== received[PIXEL_WIDTH-1:0])
                $fatal(1, "Pixel mismatch: expected %0d, got %0d", received, pixel_data);

            if (pixel_x !== (received % IMAGE_WIDTH))
                $fatal(1, "X mismatch at pixel %0d: got %0d", received, pixel_x);

            if (pixel_y !== (received / IMAGE_WIDTH))
                $fatal(1, "Y mismatch at pixel %0d: got %0d", received, pixel_y);

            if (frame_start !== (received == 0))
                $fatal(1, "frame_start mismatch at pixel %0d", received);

            if (line_start !== ((received % IMAGE_WIDTH) == 0))
                $fatal(1, "line_start mismatch at pixel %0d", received);

            if (line_end !== ((received % IMAGE_WIDTH) == IMAGE_WIDTH - 1))
                $fatal(1, "line_end mismatch at pixel %0d", received);

            received = received + 1;
        end
    end

    initial begin : stimulus
        integer x;
        integer y;

        repeat (4) @(negedge pclk);
        reset_n = 1'b1;

        // Active-high VSYNC pulse announces the next frame.
        @(negedge pclk);
        cam_vsync = 1'b1;
        repeat (2) @(negedge pclk);
        cam_vsync = 1'b0;
        repeat (2) @(negedge pclk);

        for (y = 0; y < IMAGE_HEIGHT; y = y + 1) begin
            cam_href = 1'b1;
            for (x = 0; x < IMAGE_WIDTH; x = x + 1) begin
                cam_data = y * IMAGE_WIDTH + x;
                @(negedge pclk);
            end

            cam_href = 1'b0;
            cam_data = '0;
            repeat (2) @(negedge pclk);
        end

        repeat (4) @(posedge pclk);

        if (received != PIXEL_COUNT)
            $fatal(1, "Expected %0d pixels, received %0d", PIXEL_COUNT, received);

        $display("PASS: camera_capture received %0d pixels", received);
        $finish;
    end

endmodule

