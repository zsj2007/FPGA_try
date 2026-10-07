`timescale 1ns / 1ps

// Find the sliding window containing the greatest number of binary-one pixels.
// Input pixels have already been thresholded: 1 means bright and 0 means dark.
module brightest_window #(
    parameter integer IMAGE_WIDTH      = 640,
    parameter integer IMAGE_HEIGHT     = 400,
    parameter integer WINDOW_WIDTH     = 20,
    parameter integer WINDOW_HEIGHT    = 20,
    parameter integer MIN_BRIGHT_COUNT = 0
) (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        binary_data,
    input  logic        pixel_valid,
    input  logic        frame_start,
    input  logic        line_start,
    input  logic        line_end,
    input  logic [15:0] pixel_x,
    input  logic [15:0] pixel_y,

    output logic        result_valid,
    output logic        target_found,
    output logic [15:0] best_x,
    output logic [15:0] best_y,
    output logic [$clog2(WINDOW_WIDTH * WINDOW_HEIGHT + 1)-1:0]
                        best_bright_count
);

    localparam integer WINDOW_PIXELS = WINDOW_WIDTH * WINDOW_HEIGHT;
    localparam integer COUNT_WIDTH   = $clog2(WINDOW_PIXELS + 1);
    localparam integer COL_CNT_WIDTH = $clog2(WINDOW_HEIGHT + 1);
    localparam integer HISTORY_DEPTH = IMAGE_WIDTH * WINDOW_HEIGHT;
    localparam integer ADDR_WIDTH =
        (HISTORY_DEPTH <= 1) ? 1 : $clog2(HISTORY_DEPTH);
    localparam integer HINDEX_WIDTH =
        (WINDOW_WIDTH <= 1) ? 1 : $clog2(WINDOW_WIDTH);

    // Circular history containing only one bit per pixel. With the default
    // parameters this is 20 * 640 = 12800 bits.
    (* ram_style = "block" *)
    logic pixel_history [0:HISTORY_DEPTH-1];

    logic [ADDR_WIDTH-1:0] write_row_base;
    logic [ADDR_WIDTH-1:0] history_address;
    logic                  old_binary_q;

    // One-cycle delayed input, aligned with the synchronous BRAM read.
    logic        stage_valid;
    logic        stage_binary;
    logic        stage_frame_start;
    logic        stage_line_start;
    logic        stage_line_end;
    logic [15:0] stage_x;
    logic [15:0] stage_y;

    // Each entry counts bright pixels in the most recent WINDOW_HEIGHT rows
    // at one X coordinate.
    logic [COL_CNT_WIDTH-1:0]
        column_bright_count [0:IMAGE_WIDTH-1];

    // Circular history of the most recent WINDOW_WIDTH column counts.
    logic [COL_CNT_WIDTH-1:0]
        horizontal_count_history [0:WINDOW_WIDTH-1];
    logic [HINDEX_WIDTH-1:0] horizontal_index;
    logic [COUNT_WIDTH-1:0]  running_window_count;

    logic [COUNT_WIDTH-1:0] frame_max_count;
    logic [15:0]            frame_max_x;
    logic [15:0]            frame_max_y;
    logic                   frame_has_candidate;

    logic [COL_CNT_WIDTH-1:0] next_column_count;
    logic [COUNT_WIDTH-1:0]   next_window_count;
    logic [HINDEX_WIDTH-1:0]  active_horizontal_index;
    logic [COL_CNT_WIDTH-1:0] outgoing_column_count;
    logic                     full_window_valid;
    logic                     count_is_eligible;

    logic [COL_CNT_WIDTH:0] column_count_math;
    logic [COUNT_WIDTH:0]   window_count_math;

    always_comb begin
        history_address = write_row_base + pixel_x[ADDR_WIDTH-1:0];
        if (frame_start)
            history_address = pixel_x[ADDR_WIDTH-1:0];
    end

    // Stage one: delay metadata and maintain the binary row history.
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            write_row_base    <= '0;
            stage_valid       <= 1'b0;
            stage_binary      <= 1'b0;
            stage_frame_start <= 1'b0;
            stage_line_start  <= 1'b0;
            stage_line_end    <= 1'b0;
            stage_x           <= 16'd0;
            stage_y           <= 16'd0;
        end else begin
            stage_valid <= pixel_valid;

            if (pixel_valid) begin
                stage_binary      <= binary_data;
                stage_frame_start <= frame_start;
                stage_line_start  <= line_start;
                stage_line_end    <= line_end;
                stage_x           <= pixel_x;
                stage_y           <= pixel_y;

                if (frame_start)
                    write_row_base <= '0;

                if (line_end) begin
                    if (write_row_base >= (WINDOW_HEIGHT - 1) * IMAGE_WIDTH)
                        write_row_base <= '0;
                    else
                        write_row_base <= write_row_base + IMAGE_WIDTH;
                end
            end else begin
                stage_frame_start <= 1'b0;
                stage_line_start  <= 1'b0;
                stage_line_end    <= 1'b0;
            end
        end
    end

    // Memory contents need no reset. The first WINDOW_HEIGHT rows of every
    // frame ignore the old value and overwrite the complete circular history.
    always_ff @(posedge clk) begin
        if (pixel_valid) begin
            if (pixel_y >= WINDOW_HEIGHT)
                old_binary_q <= pixel_history[history_address];
            else
                old_binary_q <= 1'b0;

            pixel_history[history_address] <= binary_data;
        end
    end

    // Update the vertical count for this X coordinate, then slide horizontally
    // by removing the left column and adding the new right column.
    always_comb begin
        column_count_math = '0;

        if (stage_y == 0) begin
            column_count_math = stage_binary;
        end else if (stage_y < WINDOW_HEIGHT) begin
            column_count_math = {1'b0, column_bright_count[stage_x]} +
                                stage_binary;
        end else begin
            column_count_math = {1'b0, column_bright_count[stage_x]} +
                                stage_binary - old_binary_q;
        end

        next_column_count = column_count_math[COL_CNT_WIDTH-1:0];

        active_horizontal_index = stage_line_start ? '0 : horizontal_index;
        outgoing_column_count = '0;

        if (stage_x >= WINDOW_WIDTH)
            outgoing_column_count =
                horizontal_count_history[active_horizontal_index];

        if (stage_line_start) begin
            window_count_math = next_column_count;
        end else begin
            window_count_math = {1'b0, running_window_count} +
                                next_column_count - outgoing_column_count;
        end

        next_window_count = window_count_math[COUNT_WIDTH-1:0];

        full_window_valid = stage_valid &&
                            (stage_x >= WINDOW_WIDTH - 1) &&
                            (stage_y >= WINDOW_HEIGHT - 1);
        count_is_eligible = (next_window_count >= MIN_BRIGHT_COUNT);
    end

    // Array writes are reset-free so Vivado may infer RAM resources.
    always_ff @(posedge clk) begin
        if (stage_valid) begin
            column_bright_count[stage_x] <= next_column_count;
            horizontal_count_history[active_horizontal_index]
                <= next_column_count;
        end
    end

    // Track the densest bright window. Equal counts keep the earlier window,
    // which is the uppermost and then leftmost one in raster scan order.
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            horizontal_index     <= '0;
            running_window_count <= '0;
            frame_max_count      <= '0;
            frame_max_x          <= 16'd0;
            frame_max_y          <= 16'd0;
            frame_has_candidate  <= 1'b0;
            result_valid         <= 1'b0;
            target_found         <= 1'b0;
            best_x               <= 16'd0;
            best_y               <= 16'd0;
            best_bright_count    <= '0;
        end else begin
            result_valid <= 1'b0;

            if (stage_valid) begin
                running_window_count <= next_window_count;

                if (active_horizontal_index == WINDOW_WIDTH - 1)
                    horizontal_index <= '0;
                else
                    horizontal_index <= active_horizontal_index + 1'b1;

                if (stage_frame_start) begin
                    frame_max_count      <= '0;
                    frame_max_x          <= 16'd0;
                    frame_max_y          <= 16'd0;
                    frame_has_candidate  <= 1'b0;
                end

                if (full_window_valid && count_is_eligible &&
                    (!frame_has_candidate ||
                     next_window_count > frame_max_count)) begin
                    frame_max_count     <= next_window_count;
                    frame_max_x         <= stage_x - (WINDOW_WIDTH - 1);
                    frame_max_y         <= stage_y - (WINDOW_HEIGHT - 1);
                    frame_has_candidate <= 1'b1;
                end

                if (stage_line_end && stage_y == IMAGE_HEIGHT - 1) begin
                    result_valid <= 1'b1;

                    // Include the final candidate before publishing the frame.
                    if (full_window_valid && count_is_eligible &&
                        (!frame_has_candidate ||
                         next_window_count > frame_max_count)) begin
                        target_found      <= 1'b1;
                        best_bright_count <= next_window_count;
                        best_x <= stage_x - (WINDOW_WIDTH - 1);
                        best_y <= stage_y - (WINDOW_HEIGHT - 1);
                    end else if (frame_has_candidate) begin
                        target_found      <= 1'b1;
                        best_bright_count <= frame_max_count;
                        best_x            <= frame_max_x;
                        best_y            <= frame_max_y;
                    end else begin
                        target_found      <= 1'b0;
                        best_bright_count <= '0;
                        best_x            <= 16'd0;
                        best_y            <= 16'd0;
                    end
                end
            end
        end
    end

endmodule

