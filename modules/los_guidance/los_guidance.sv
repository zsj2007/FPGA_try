// LOS (Line-of-Sight) angle computation using pipelined CORDIC atan2.
//
// Converts target box centre pixel coordinates into horizontal and vertical
// line-of-sight angles via the pinhole camera model.  Also computes the
// frame-to-frame angular rate (omega) for proportional navigation.
//
// Reference: dart_-application alg_proportional_navigation.c

module los_guidance #(
    parameter integer IMAGE_WIDTH       = 640,
    parameter integer IMAGE_HEIGHT      = 400,
    parameter integer WINDOW_WIDTH      = 20,
    parameter integer WINDOW_HEIGHT     = 20,
    parameter logic [31:0] FOCUS_PX_X   = 32'd21512192,
    parameter logic [31:0] FOCUS_PX_Y   = 32'd21430272,
    parameter logic [31:0] CENTER_CX    = 32'd20971520,
    parameter logic [31:0] CENTER_CY    = 32'd13107200,
    parameter integer CORDIC_STAGES     = 16,
    parameter logic [31:0] DT_FACTOR    = 32'd1966080
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        result_valid,
    input  logic        target_found,
    input  logic [15:0] best_x,
    input  logic [15:0] best_y,
    output logic        los_valid,
    output logic [31:0] hfov_q16,
    output logic [31:0] vfov_q16,
    output logic [31:0] omega_hfov_q16,
    output logic [31:0] omega_vfov_q16,
    output logic        omega_valid
);

    logic [31:0] target_cx_q16, target_cy_q16;
    logic [31:0] dx_q16, dy_q16;
    assign target_cx_q16 = (best_x + (WINDOW_WIDTH  >> 1)) << 16;
    assign target_cy_q16 = (best_y + (WINDOW_HEIGHT >> 1)) << 16;
    assign dx_q16 = CENTER_CX - target_cx_q16;
    assign dy_q16 = target_cy_q16 - CENTER_CY;

    logic        cordic_start;
    logic        cordic_h_done, cordic_v_done;
    logic signed [31:0] cordic_h_angle, cordic_v_angle;

    cordic_atan2 #(.STAGES(CORDIC_STAGES)) u_cordic_h (
        .clk, .reset_n, .start(cordic_start),
        .x_in(FOCUS_PX_X), .y_in(dx_q16),
        .done(cordic_h_done), .angle_out(cordic_h_angle)
    );
    cordic_atan2 #(.STAGES(CORDIC_STAGES)) u_cordic_v (
        .clk, .reset_n, .start(cordic_start),
        .x_in(FOCUS_PX_Y), .y_in(dy_q16),
        .done(cordic_v_done), .angle_out(cordic_v_angle)
    );

    logic signed [31:0] prev_hfov, prev_vfov;
    logic               prev_valid;
    logic signed [31:0] delta_h, delta_v;

    typedef enum logic [1:0] { IDLE, WAIT_CORDIC, COMPUTE_OMEGA } state_t;
    state_t state;

    // Omega product wires (combinational, used only in COMPUTE_OMEGA).
    wire signed [63:0] prod_h = 64'(delta_h) * 64'(DT_FACTOR);
    wire signed [63:0] prod_v = 64'(delta_v) * 64'(DT_FACTOR);

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state        <= IDLE;
            cordic_start <= 1'b0;
            los_valid    <= 1'b0;
            omega_valid  <= 1'b0;
            hfov_q16 <= 32'd0;
            vfov_q16 <= 32'd0;
            omega_hfov_q16  <= 32'd0;
            omega_vfov_q16  <= 32'd0;
            prev_hfov    <= 32'd0;
            prev_vfov    <= 32'd0;
            prev_valid   <= 1'b0;
            delta_h      <= 32'd0;
            delta_v      <= 32'd0;
        end else begin
            los_valid   <= 1'b0;
            omega_valid <= 1'b0;
            cordic_start <= 1'b0;

            case (state)
                IDLE: begin
                    if (result_valid && target_found) begin
                        cordic_start <= 1'b1;
                        state <= WAIT_CORDIC;
                    end
                end

                WAIT_CORDIC: begin
                    if (cordic_h_done && cordic_v_done) begin
                        hfov_q16 <= cordic_h_angle;
                        vfov_q16 <= cordic_v_angle;
                        los_valid    <= 1'b1;
                        if (prev_valid) begin
                            delta_h <= cordic_h_angle - prev_hfov;
                            delta_v <= cordic_v_angle - prev_vfov;
                            state   <= COMPUTE_OMEGA;
                        end else begin
                            prev_hfov  <= cordic_h_angle;
                            prev_vfov  <= cordic_v_angle;
                            prev_valid <= 1'b1;
                            state <= IDLE;
                        end
                    end
                end

                COMPUTE_OMEGA: begin
                    omega_hfov_q16 <= 32'(prod_h >>> 21);
                    omega_vfov_q16 <= 32'(prod_v >>> 21);
                    omega_valid <= 1'b1;
                    prev_hfov   <= hfov_q16;
                    prev_vfov   <= vfov_q16;
                    prev_valid  <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
