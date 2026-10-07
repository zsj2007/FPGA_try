`timescale 1ns / 1ps

// vision_pipeline with CCL-based blob detection and LOS guidance.
//
// Pipeline:
//   camera_capture -> binary_threshold
//                         |
//         +---------------+---------------+
//         |                               |
//   [dilate_only: frame 0-337]    [erode+dilate: frame 338+]
//   bypass_erode(2cy) -> dilate   erode(3x3) -> dilate(3x3)
//         |                               |
//         +---------------+---------------+
//                         |
//                    ccl_analyzer
//                    (aspect ratio)
//                                         |
//                    +--------------------+--------------------+
//                    |                    |                    |
//          frame_buffer (1-frame delay)   los_guidance      (outputs)
//                    |
//          bounding_box_overlay (frame N grayscale + frame N bbox)
//                    |
//              output_data

module vision_pipeline #(
    parameter integer IMAGE_WIDTH      = 640,
    parameter integer IMAGE_HEIGHT     = 400,
    parameter integer PIXEL_WIDTH      = 10,
    parameter logic [PIXEL_WIDTH-1:0] THRESHOLD = 10'd1000,
    parameter integer BOX_THICKNESS    = 2,
    parameter logic [PIXEL_WIDTH-1:0] BOX_VALUE = {PIXEL_WIDTH{1'b1}},
    parameter bit HREF_ACTIVE_LEVEL    = 1'b1,
    parameter bit VSYNC_ACTIVE_LEVEL   = 1'b1,
    parameter logic [31:0] FOCUS_PX_X = 32'd21512192,
    parameter logic [31:0] FOCUS_PX_Y = 32'd21430272,
    parameter logic [31:0] CENTER_CX  = 32'd20971520,
    parameter logic [31:0] CENTER_CY  = 32'd13107200,
    parameter integer CORDIC_STAGES   = 16,
    parameter logic [31:0] DT_FACTOR  = 32'd1966080,
    parameter integer MORPH_FRAME_LIMIT = 338
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
    output logic [15:0]            blob_aspect_q16,
    output logic                   los_valid,
    output logic [31:0]            hfov_q16,
    output logic [31:0]            vfov_q16,
    output logic [31:0]            omega_hfov_q16,
    output logic [31:0]            omega_vfov_q16,
    output logic                   omega_valid,
    output logic                   debug_binary_data,
    output logic                   debug_binary_valid
);

    // ============================================================
    //  Camera capture
    // ============================================================
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

    // ============================================================
    //  Binary threshold
    // ============================================================
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

    // ============================================================
    //  Frame counter (count binary_frame_start pulses)
    // ============================================================
    logic [31:0] frame_count;
    always_ff @(posedge pclk or negedge reset_n) begin
        if (!reset_n) begin
            frame_count <= 0;
        end else if (binary_frame_start && binary_valid) begin
            frame_count <= frame_count + 32'd1;
        end
    end

    wire dilate_only = (frame_count < MORPH_FRAME_LIMIT);

    // ============================================================
    //  Erosion bypass: 2-cycle delay to match erosion latency
    //  When dilate_only (first half): binary -> bypass -> dilate
    // ============================================================
    localparam integer ERODE_LATENCY = 2;

    logic [ERODE_LATENCY-1:0] eb_valid_sr, eb_fs_sr, eb_ls_sr, eb_le_sr, eb_data_sr;
    logic [15:0] eb_x_sr [0:ERODE_LATENCY-1];
    logic [15:0] eb_y_sr [0:ERODE_LATENCY-1];

    always_ff @(posedge pclk or negedge reset_n) begin
        if (!reset_n) begin
            eb_valid_sr <= '0; eb_fs_sr <= '0; eb_ls_sr <= '0;
            eb_le_sr <= '0; eb_data_sr <= '0;
            for (int i = 0; i < ERODE_LATENCY; i++) begin
                eb_x_sr[i] <= '0; eb_y_sr[i] <= '0;
            end
        end else begin
            eb_valid_sr <= {eb_valid_sr[ERODE_LATENCY-2:0], binary_valid};
            eb_fs_sr    <= {eb_fs_sr[ERODE_LATENCY-2:0],    binary_frame_start};
            eb_ls_sr    <= {eb_ls_sr[ERODE_LATENCY-2:0],    binary_line_start};
            eb_le_sr    <= {eb_le_sr[ERODE_LATENCY-2:0],    binary_line_end};
            eb_data_sr  <= {eb_data_sr[ERODE_LATENCY-2:0],  binary_data};
            for (int i = 0; i < ERODE_LATENCY; i++) begin
                if (i == 0) begin
                    eb_x_sr[i] <= binary_x; eb_y_sr[i] <= binary_y;
                end else begin
                    eb_x_sr[i] <= eb_x_sr[i-1]; eb_y_sr[i] <= eb_y_sr[i-1];
                end
            end
        end
    end

    logic        morph_data, morph_valid;
    logic        morph_frame_start, morph_line_start, morph_line_end;
    logic [15:0] morph_x, morph_y;

    logic        erode_data, erode_valid;
    logic        erode_frame_start, erode_line_start, erode_line_end;
    logic [15:0] erode_x, erode_y;

    // ============================================================
    //  Erosion: 3x3 morphological erosion (always runs)
    //  Output only used when dilate_only = 0 (second half)
    // ============================================================
    morph_erode #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .WINDOW_SIZE(3)
    ) u_morph_erode (
        .clk(pclk), .reset_n(reset_n),
        .pixel_valid(binary_valid),
        .frame_start(binary_frame_start),
        .line_start(binary_line_start), .line_end(binary_line_end),
        .pixel_x(binary_x), .pixel_y(binary_y),
        .binary_data(binary_data),
        .eroded_valid(erode_valid), .eroded_data(erode_data),
        .eroded_frame_start(erode_frame_start),
        .eroded_line_start(erode_line_start),
        .eroded_line_end(erode_line_end),
        .eroded_x(erode_x), .eroded_y(erode_y)
    );

    // ============================================================
    //  MUX: dilate input = dilate_only ? erosion_bypass : erosion_output
    // ============================================================
    logic        dilate_in_data, dilate_in_valid;
    logic        dilate_in_frame_start, dilate_in_line_start, dilate_in_line_end;
    logic [15:0] dilate_in_x, dilate_in_y;

    assign dilate_in_data        = dilate_only ? eb_data_sr[ERODE_LATENCY-1] : erode_data;
    assign dilate_in_valid       = dilate_only ? eb_valid_sr[ERODE_LATENCY-1] : erode_valid;
    assign dilate_in_frame_start = dilate_only ? eb_fs_sr[ERODE_LATENCY-1]    : erode_frame_start;
    assign dilate_in_line_start  = dilate_only ? eb_ls_sr[ERODE_LATENCY-1]    : erode_line_start;
    assign dilate_in_line_end    = dilate_only ? eb_le_sr[ERODE_LATENCY-1]    : erode_line_end;
    assign dilate_in_x           = dilate_only ? eb_x_sr[ERODE_LATENCY-1]     : erode_x;
    assign dilate_in_y           = dilate_only ? eb_y_sr[ERODE_LATENCY-1]     : erode_y;

    // ============================================================
    //  Dilation: 3x3 morphological dilation (always active)
    //  Latency from binary_threshold: 4 cycles (bypass/erode 2 + dilate 2)
    // ============================================================
    morph_dilate #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .WINDOW_SIZE(3)
    ) u_morph_dilate (
        .clk(pclk), .reset_n(reset_n),
        .pixel_valid(dilate_in_valid),
        .frame_start(dilate_in_frame_start),
        .line_start(dilate_in_line_start), .line_end(dilate_in_line_end),
        .pixel_x(dilate_in_x), .pixel_y(dilate_in_y),
        .binary_data(dilate_in_data),
        .dilated_valid(morph_valid), .dilated_data(morph_data),
        .dilated_frame_start(morph_frame_start),
        .dilated_line_start(morph_line_start),
        .dilated_line_end(morph_line_end),
        .dilated_x(morph_x), .dilated_y(morph_y)
    );

    // ============================================================
    //  CCL Analyzer — always takes morphology (dilate) output
    // ============================================================
    logic        ccl_in_data, ccl_in_valid;
    logic        ccl_in_frame_start, ccl_in_line_start, ccl_in_line_end;
    logic [15:0] ccl_in_x, ccl_in_y;

    logic        ccl_result_valid, ccl_target_found;
    logic [15:0] ccl_center_x, ccl_center_y;
    logic [15:0] ccl_bbox_l, ccl_bbox_r, ccl_bbox_t, ccl_bbox_b;
    logic [23:0] ccl_area;
    logic [15:0] ccl_aspect;

    assign ccl_in_data        = morph_data;
    assign ccl_in_valid       = morph_valid;
    assign ccl_in_frame_start = morph_frame_start;
    assign ccl_in_line_start  = morph_line_start;
    assign ccl_in_line_end    = morph_line_end;
    assign ccl_in_x           = morph_x;
    assign ccl_in_y           = morph_y;

    ccl_analyzer #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) u_ccl_analyzer (
        .clk(pclk), .reset_n(reset_n),
        .pixel_valid(ccl_in_valid),
        .frame_start(ccl_in_frame_start),
        .line_start(ccl_in_line_start), .line_end(ccl_in_line_end),
        .pixel_x(ccl_in_x), .pixel_y(ccl_in_y),
        .binary_data(ccl_in_data),
        .result_valid(ccl_result_valid), .target_found(ccl_target_found),
        .center_x(ccl_center_x), .center_y(ccl_center_y),
        .bbox_left(ccl_bbox_l), .bbox_right(ccl_bbox_r),
        .bbox_top(ccl_bbox_t), .bbox_bottom(ccl_bbox_b),
        .area(ccl_area), .ratio_q16(ccl_aspect)
    );

    // ============================================================
    //  Wire outputs
    // ============================================================
    assign result_valid     = ccl_result_valid;
    assign target_found     = ccl_target_found;
    assign center_x         = ccl_center_x;
    assign center_y         = ccl_center_y;
    assign bbox_left        = ccl_bbox_l;
    assign bbox_right       = ccl_bbox_r;
    assign bbox_top         = ccl_bbox_t;
    assign bbox_bottom      = ccl_bbox_b;
    assign blob_area        = ccl_area;
    assign blob_aspect_q16  = ccl_aspect;

    // ============================================================
    //  Frame buffer: 1-frame delay for grayscale
    //  Read-before-write using the pixel (x,y) as address.
    //  Read returns previous frame's pixel; write stores current.
    //  Adds 1 cycle latency → control signals also delayed 1 cycle.
    // ============================================================
    localparam integer FB_SIZE = IMAGE_WIDTH * IMAGE_HEIGHT;

    (* ram_style = "block" *)
    logic [7:0] frame_buf [0:FB_SIZE-1];

    logic [17:0] fb_addr;
    logic [7:0]  fb_wdata, fb_rdata;

    assign fb_addr  = captured_y * IMAGE_WIDTH + captured_x;
    assign fb_wdata = captured_data[9:2];  // 8-bit storage

    // Read-before-write in same cycle
    always_ff @(posedge pclk) begin
        if (captured_valid) begin
            fb_rdata <= frame_buf[fb_addr];       // read old
            frame_buf[fb_addr] <= fb_wdata;        // write new
        end
    end

    // 1-cycle delay for control signals (match fb_rdata latency)
    logic        delayed_valid, delayed_frame_start;
    logic        delayed_line_start, delayed_line_end;
    logic [15:0] delayed_x, delayed_y;
    logic [PIXEL_WIDTH-1:0] delayed_data;

    always_ff @(posedge pclk or negedge reset_n) begin
        if (!reset_n) begin
            delayed_valid       <= 1'b0;
            delayed_frame_start <= 1'b0;
            delayed_line_start  <= 1'b0;
            delayed_line_end    <= 1'b0;
            delayed_x           <= 16'd0;
            delayed_y           <= 16'd0;
            delayed_data        <= '0;
        end else begin
            delayed_valid       <= captured_valid;
            delayed_frame_start <= captured_frame_start;
            delayed_line_start  <= captured_line_start;
            delayed_line_end    <= captured_line_end;
            delayed_x           <= captured_x;
            delayed_y           <= captured_y;
            delayed_data        <= {fb_rdata, 2'b00};  // 8→10 bit
        end
    end

    // ============================================================
    //  Bounding box overlay (uses delayed grayscale + CCL result)
    //  Frame N's grayscale is paired with frame N's bbox
    // ============================================================
    bounding_box_overlay #(
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .BOX_THICKNESS(BOX_THICKNESS),
        .BOX_VALUE(BOX_VALUE)
    ) u_bounding_box_overlay (
        .clk(pclk), .reset_n(reset_n),
        .pixel_data(delayed_data),
        .pixel_valid(delayed_valid),
        .frame_start(delayed_frame_start),
        .line_start(delayed_line_start),
        .line_end(delayed_line_end),
        .pixel_x(delayed_x), .pixel_y(delayed_y),
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

    // ============================================================
    //  LOS guidance
    // ============================================================
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

    // Debug: output the binary stream going into CCL (post-ROI, post-morph)
    assign debug_binary_data  = ccl_in_data;
    assign debug_binary_valid = ccl_in_valid;

endmodule
