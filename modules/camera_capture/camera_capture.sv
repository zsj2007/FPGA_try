`timescale 1ns / 1ps

// Capture a parallel monochrome camera stream in the camera PCLK domain.
//
// The camera is a free-running source: it cannot be back-pressured. Therefore
// this module deliberately uses a native pixel-valid interface instead of an
// AXI4-Stream ready/valid interface. A later adapter/FIFO will perform clock
// domain crossing and AXI4-Stream conversion.
module camera_capture #(
    parameter integer IMAGE_WIDTH        = 640,
    parameter integer IMAGE_HEIGHT       = 400,
    parameter integer PIXEL_WIDTH        = 10,
    parameter bit     HREF_ACTIVE_LEVEL  = 1'b1,
    parameter bit     VSYNC_ACTIVE_LEVEL = 1'b1
) (
    input  logic                   pclk,
    input  logic                   reset_n,

    input  logic [PIXEL_WIDTH-1:0] cam_data,
    input  logic                   cam_href,
    input  logic                   cam_vsync,

    output logic [PIXEL_WIDTH-1:0] pixel_data,
    output logic                   pixel_valid,
    output logic                   frame_start,
    output logic                   line_start,
    output logic                   line_end,
    output logic [15:0]            pixel_x,
    output logic [15:0]            pixel_y
);

    logic href_active_d;
    logic vsync_active_d;
    logic frame_start_pending;
    logic [15:0] x_count;
    logic [15:0] y_count;

    wire href_active  = (cam_href  == HREF_ACTIVE_LEVEL);
    wire vsync_active = (cam_vsync == VSYNC_ACTIVE_LEVEL);
    wire vsync_start  = vsync_active && !vsync_active_d;

    always_ff @(posedge pclk or negedge reset_n) begin
        if (!reset_n) begin
            href_active_d      <= 1'b0;
            vsync_active_d     <= 1'b0;
            frame_start_pending <= 1'b0;
            x_count            <= 16'd0;
            y_count            <= 16'd0;
            pixel_data         <= '0;
            pixel_valid        <= 1'b0;
            frame_start        <= 1'b0;
            line_start         <= 1'b0;
            line_end           <= 1'b0;
            pixel_x            <= 16'd0;
            pixel_y            <= 16'd0;
        end else begin
            href_active_d  <= href_active;
            vsync_active_d <= vsync_active;

            pixel_valid <= 1'b0;
            frame_start <= 1'b0;
            line_start  <= 1'b0;
            line_end    <= 1'b0;

            // A VSYNC active edge announces a new frame. The frame_start flag
            // is held pending until the first valid pixel arrives.
            if (vsync_start) begin
                frame_start_pending <= 1'b1;
                x_count             <= 16'd0;
                y_count             <= 16'd0;
            end

            if (href_active) begin
                pixel_data  <= cam_data;
                pixel_valid <= 1'b1;
                pixel_x     <= x_count;
                pixel_y     <= y_count;
                line_start  <= !href_active_d;
                line_end    <= (x_count == IMAGE_WIDTH - 1);

                if (frame_start_pending || vsync_start) begin
                    frame_start         <= 1'b1;
                    frame_start_pending <= 1'b0;
                end

                x_count <= x_count + 1'b1;
            end else if (href_active_d) begin
                // HREF just became inactive: the completed line advances Y.
                x_count <= 16'd0;
                if (y_count < IMAGE_HEIGHT - 1)
                    y_count <= y_count + 1'b1;
            end
        end
    end

endmodule

