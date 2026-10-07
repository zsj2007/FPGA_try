`timescale 1ns / 1ps

// vision_pipeline with CCL-based blob detection and LOS guidance.
//
// Pipeline:
//   camera_capture -> binary_threshold -> ccl_analyzer
//       |                |                    |
//       v                v               /         \
//   (grayscale)    (binary)            v            v
//       |                        los_guidance   (bbox+area+ratio)
//       v                             |
//   bounding_box_overlay              v
//       |                    hfov/vfov/omega
//       v
//   output_data (grayscale + detection box)

module vision_pipeline #(
    parameter integer IMAGE_WIDTH      = 640,
    parameter integer IMAGE_HEIGHT     = 400,
    parameter integer PIXEL_WIDTH      = 10,
    parameter logic [PIXEL_WIDTH-1:0] THRESHOLD = 10'd1000,
    parameter integer BOX_THICKNESS    = 1,
    parameter logic [PIXEL_WIDTH-1:0] BOX_VALUE = {PIXEL_WIDTH{1'b1}},
    parameter bit HREF_ACTIVE_LEVEL    = 1'b1,
    parameter bit VSYNC_ACTIVE_LEVEL   = 1'b1,
    parameter logic [31:0] FOCUS_PX_X = 32'd21512192,
    parameter logic [31:0] FOCUS_PX_Y = 32'd21430272,
    parameter logic [31:0] CENTER_CX  = 32'd20971520,
    parameter logic [31:0] CENTER_CY  = 32'd13107200,
    parameter integer CORDIC_STAGES   = 16,
    parameter logic [31:0] DT_FACTOR  = 32'd1966080
) (
    input  logic                   pclk,
    input  logic                   reset_n,
    input  logic [PIXEL_WIDTH-1:0] cam_data,
    input  logic                   cam_href,
    input  logic                   cam_vsync,
    output logic [PIXEL_WIDTH-1:0] output_data,
    output logic                   output_valid,
    output logic                   output_frame_start,
    output logic                   output_line_start,
    output logic                   output_line_end,
    output logic [15:0]            output_x,
    output logic [15:0]            output_y,
    output logic                   output_box_active,
    output logic                   result_valid,
    output logic                   target_found,
    output logic [15:0]            center_x,
    output logic [15:0]            center_y,
    output logic [15:0]            bbox_left,
    output logic [15:0]            bbox_right,
    output logic [15:0]            bbox_top,
    output logic [15:0]            bbox_bottom,
    output logic [23:0]            blob_area,
    output logic [15:0]            blob_ratio_q16,
    output logic                   los_valid,
    output logic [31:0]            hfov_q16,
    output logic [31:0]            vfov_q16,
    output logic [31:0]            omega_hfov_q16,
    output logic [31:0]            omega_vfov_q16,
    output logic                   omega_valid
);

    // ---- Camera capture ----
    logic [PIXEL_WIDTH-1:0] captured_data;
    logic                   captured_valid, captured_frame_start;
    logic                   captured_line_start, captured_line_end;
    logic [15:0]            captured_x, captured_y;

    camera_capture #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .HREF_ACTIVE_LEVEL(HREF_ACTIVE_LEVEL),
        .VSYNC_ACTIVE_LEVEL(VSYNC_ACTIVE_LEVEL)
    ) u_camera_capture (
        .pclk(pclk), .reset_n(reset_n),
        .cam_data(cam_data), .cam_href(cam_href), .cam_vsync(cam_vsync),
        .pixel_data(captured_data), .pixel_valid(captured_valid),
        .frame_start(captured_frame_start),
        .line_start(captured_line_start), .line_end(captured_line_end),
        .pixel_x(captured_x), .pixel_y(captured_y)
    );

    // ---- Binary threshold (1000) ----
    logic        binary_data, binary_valid;
    logic        binary_frame_start, binary_line_start, binary_line_end;
    logic [15:0] binary_x, binary_y;

    binary_threshold #(
        .PIXEL_WIDTH(PIXEL_WIDTH), .THRESHOLD(THRESHOLD)
    ) u_binary_threshold (
        .clk(pclk), .reset_n(reset_n),
        .pixel_data(captured_data), .pixel_valid(captured_valid),
        .frame_start(captured_frame_start),
        .line_start(captured_line_start), .line_end(captured_line_end),
        .pixel_x(captured_x), .pixel_y(captured_y),
        .binary_data(binary_data), .binary_valid(binary_valid),
        .binary_frame_start(binary_frame_start),
        .binary_line_start(binary_line_start),
        .binary_line_end(binary_line_end),
        .binary_x(binary_x), .binary_y(binary_y)
    );

    // ---- CCL Analyzer (connected component labeling + circularity) ----
    logic        ccl_result_valid;
    logic        ccl_target_found;
    logic [15:0] ccl_center_x, ccl_center_y;
    logic [15:0] ccl_bbox_l, ccl_bbox_r, ccl_bbox_t, ccl_bbox_b;
    logic [23:0] ccl_area;
    logic [15:0] ccl_ratio;

    ccl_analyzer #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) u_ccl_analyzer (
        .clk(pclk), .reset_n(reset_n),
        .pixel_valid(binary_valid),
        .frame_start(binary_frame_start),
        .line_start(binary_line_start),
        .line_end(binary_line_end),
        .pixel_x(binary_x), .pixel_y(binary_y),
        .binary_data(binary_data),
        .result_valid(ccl_result_valid),
        .target_found(ccl_target_found),
        .center_x(ccl_center_x), .center_y(ccl_center_y),
        .bbox_left(ccl_bbox_l), .bbox_right(ccl_bbox_r),
        .bbox_top(ccl_bbox_t), .bbox_bottom(ccl_bbox_b),
        .area(ccl_area),
        .ratio_q16(ccl_ratio)
    );

    // ---- Wire outputs ----
    assign result_valid   = ccl_result_valid;
    assign target_found   = ccl_target_found;
    assign center_x       = ccl_center_x;
    assign center_y       = ccl_center_y;
    assign bbox_left      = ccl_bbox_l;
    assign bbox_right     = ccl_bbox_r;
    assign bbox_top       = ccl_bbox_t;
    assign bbox_bottom    = ccl_bbox_b;
    assign blob_area      = ccl_area;
    assign blob_ratio_q16 = ccl_ratio;

    // ---- Bounding box overlay ----
    bounding_box_overlay #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .BOX_THICKNESS(BOX_THICKNESS),
        .BOX_VALUE(BOX_VALUE)
    ) u_bounding_box_overlay (
        .clk(pclk), .reset_n(reset_n),
        .pixel_data(captured_data), .pixel_valid(captured_valid),
        .frame_start(captured_frame_start),
        .line_start(captured_line_start), .line_end(captured_line_end),
        .pixel_x(captured_x), .pixel_y(captured_y),
        .result_valid(ccl_result_valid),
        .target_found(ccl_target_found),
        .bbox_left(ccl_bbox_l), .bbox_right(ccl_bbox_r),
        .bbox_top(ccl_bbox_t), .bbox_bottom(ccl_bbox_b),
        .boxed_data(output_data), .boxed_valid(output_valid),
        .boxed_frame_start(output_frame_start),
        .boxed_line_start(output_line_start),
        .boxed_line_end(output_line_end),
        .boxed_x(output_x), .boxed_y(output_y),
        .box_active(output_box_active)
    );

    // ---- LOS guidance ----
    logic [31:0] target_cx_q16, target_cy_q16;
    logic [31:0] dx_q16, dy_q16;

    assign target_cx_q16 = {ccl_center_x, 16'd0};
    assign target_cy_q16 = {ccl_center_y, 16'd0};
    assign dx_q16 = CENTER_CX - target_cx_q16;
    assign dy_q16 = target_cy_q16 - CENTER_CY;

    logic        cordic_start;
    logic        cordic_h_done, cordic_v_done;
    logic signed [31:0] cordic_h_angle, cordic_v_angle;

    cordic_atan2 #(.STAGES(CORDIC_STAGES)) u_cordic_h (
        .clk(pclk), .reset_n(reset_n), .start(cordic_start),
        .x_in(FOCUS_PX_X), .y_in(dx_q16),
        .done(cordic_h_done), .angle_out(cordic_h_angle)
    );
    cordic_atan2 #(.STAGES(CORDIC_STAGES)) u_cordic_v (
        .clk(pclk), .reset_n(reset_n), .start(cordic_start),
        .x_in(FOCUS_PX_Y), .y_in(dy_q16),
        .done(cordic_v_done), .angle_out(cordic_v_angle)
    );

    logic signed [31:0] prev_hfov, prev_vfov;
    logic               prev_valid;
    logic signed [31:0] delta_h, delta_v;

    typedef enum logic [1:0] { LOS_IDLE, LOS_WAIT_CORDIC, LOS_COMPUTE_OMEGA } los_state_t;
    los_state_t los_state;

    wire signed [63:0] prod_h = 64'(delta_h) * 64'(DT_FACTOR);
    wire signed [63:0] prod_v = 64'(delta_v) * 64'(DT_FACTOR);

    always_ff @(posedge pclk or negedge reset_n) begin
        if (!reset_n) begin
            los_state     <= LOS_IDLE;
            cordic_start  <= 1'b0;
            los_valid     <= 1'b0;
            omega_valid   <= 1'b0;
            hfov_q16      <= 32'd0;
            vfov_q16      <= 32'd0;
            omega_hfov_q16 <= 32'd0;
            omega_vfov_q16 <= 32'd0;
            prev_hfov     <= 32'd0;
            prev_vfov     <= 32'd0;
            prev_valid    <= 1'b0;
            delta_h       <= 32'd0;
            delta_v       <= 32'd0;
        end else begin
            los_valid   <= 1'b0;
            omega_valid <= 1'b0;
            cordic_start <= 1'b0;

            case (los_state)
                LOS_IDLE: begin
                    if (ccl_result_valid && ccl_target_found) begin
                        cordic_start <= 1'b1;
                        los_state <= LOS_WAIT_CORDIC;
                    end
                end

                LOS_WAIT_CORDIC: begin
                    if (cordic_h_done && cordic_v_done) begin
                        hfov_q16 <= cordic_h_angle;
                        vfov_q16 <= cordic_v_angle;
                        los_valid <= 1'b1;
                        if (prev_valid) begin
                            delta_h <= cordic_h_angle - prev_hfov;
                            delta_v <= cordic_v_angle - prev_vfov;
                            los_state <= LOS_COMPUTE_OMEGA;
                        end else begin
                            prev_hfov  <= cordic_h_angle;
                            prev_vfov  <= cordic_v_angle;
                            prev_valid <= 1'b1;
                            los_state <= LOS_IDLE;
                        end
                    end
                end

                LOS_COMPUTE_OMEGA: begin
                    omega_hfov_q16 <= 32'(prod_h >>> 21);
                    omega_vfov_q16 <= 32'(prod_v >>> 21);
                    omega_valid <= 1'b1;
                    prev_hfov   <= hfov_q16;
                    prev_vfov   <= vfov_q16;
                    prev_valid  <= 1'b1;
                    los_state <= LOS_IDLE;
                end
            endcase
        end
    end

endmodule
