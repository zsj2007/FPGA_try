`timescale 1ns / 1ps

module vision_pipeline_tb;

    localparam integer IMAGE_WIDTH      = 8;
    localparam integer IMAGE_HEIGHT     = 6;
    localparam integer PIXEL_WIDTH      = 10;
    localparam integer WINDOW_WIDTH     = 4;
    localparam integer WINDOW_HEIGHT    = 3;
    localparam integer MIN_BRIGHT_COUNT = 12;

    logic                   pclk = 1'b0;
    logic                   reset_n = 1'b0;
    logic [PIXEL_WIDTH-1:0] cam_data = '0;
    logic                   cam_href = 1'b0;
    logic                   cam_vsync = 1'b0;
    logic [PIXEL_WIDTH-1:0] output_data;
    logic                   output_valid;
    logic                   output_frame_start;
    logic                   output_line_start;
    logic                   output_line_end;
    logic [15:0]            output_x;
    logic [15:0]            output_y;
    logic                   output_box_active;
    logic                   result_valid;
    logic                   target_found;
    logic [15:0]            best_x;
    logic [15:0]            best_y;
    logic [$clog2(WINDOW_WIDTH * WINDOW_HEIGHT + 1)-1:0]
                            best_bright_count;

    integer output_frame_index = -1;
    integer frame_pixel_count = 0;
    integer second_frame_border_count = 0;
    integer result_count = 0;

    always #5 pclk = ~pclk;

    vision_pipeline #(
        .IMAGE_WIDTH      (IMAGE_WIDTH),
        .IMAGE_HEIGHT     (IMAGE_HEIGHT),
        .PIXEL_WIDTH      (PIXEL_WIDTH),
        .THRESHOLD        (10'd512),
        .WINDOW_WIDTH     (WINDOW_WIDTH),
        .WINDOW_HEIGHT    (WINDOW_HEIGHT),
        .MIN_BRIGHT_COUNT (MIN_BRIGHT_COUNT),
        .BOX_THICKNESS    (1),
        .BOX_VALUE        (10'd1023)
    ) dut (
        .pclk                  (pclk),
        .reset_n               (reset_n),
        .cam_data              (cam_data),
        .cam_href              (cam_href),
        .cam_vsync             (cam_vsync),
        .output_data           (output_data),
        .output_valid          (output_valid),
        .output_frame_start    (output_frame_start),
        .output_line_start     (output_line_start),
        .output_line_end       (output_line_end),
        .output_x              (output_x),
        .output_y              (output_y),
        .output_box_active     (output_box_active),
        .result_valid          (result_valid),
        .target_found          (target_found),
        .best_x                (best_x),
        .best_y                (best_y),
        .best_bright_count     (best_bright_count)
    );

    function automatic logic [PIXEL_WIDTH-1:0] frame_one_pixel(
        input integer x,
        input integer y
    );
        begin
            if ((x >= 2) && (x < 2 + WINDOW_WIDTH) &&
                (y >= 1) && (y < 1 + WINDOW_HEIGHT))
                frame_one_pixel = 10'd900;
            else
                frame_one_pixel = 10'd100;
        end
    endfunction

    function automatic logic is_expected_border(
        input integer x,
        input integer y
    );
        logic is_inside_box;
        begin
            is_inside_box = (x >= 2) && (x < 2 + WINDOW_WIDTH) &&
                            (y >= 1) && (y < 1 + WINDOW_HEIGHT);
            is_expected_border = is_inside_box &&
                                 ((x == 2) ||
                                  (x == 2 + WINDOW_WIDTH - 1) ||
                                  (y == 1) ||
                                  (y == 1 + WINDOW_HEIGHT - 1));
        end
    endfunction

    task automatic send_frame(input integer frame_number);
        begin
            @(negedge pclk);
            cam_href  = 1'b0;
            cam_vsync = 1'b1;
            @(negedge pclk);
            cam_vsync = 1'b0;

            for (integer y = 0; y < IMAGE_HEIGHT; y = y + 1) begin
                for (integer x = 0; x < IMAGE_WIDTH; x = x + 1) begin
                    @(negedge pclk);
                    cam_href = 1'b1;
                    if (frame_number == 0)
                        cam_data = frame_one_pixel(x, y);
                    else
                        cam_data = 10'd100;
                end

                @(negedge pclk);
                cam_href = 1'b0;
                cam_data = '0;
            end

            repeat (8) @(negedge pclk);
        end
    endtask

    always @(posedge pclk) begin
        #1;

        if (result_valid) begin
            if (result_count == 0) begin
                if (!target_found)
                    $fatal(1, "First frame target was not found");
                if ((best_x !== 16'd2) || (best_y !== 16'd1))
                    $fatal(1, "Expected best window (2,1), got (%0d,%0d)",
                           best_x, best_y);
                if (best_bright_count !== 12)
                    $fatal(1, "Expected 12 bright pixels, got %0d",
                           best_bright_count);
            end else if (result_count == 1) begin
                if (target_found)
                    $fatal(1, "Dark second frame unexpectedly found a target");
            end
            result_count = result_count + 1;
        end

        if (output_valid) begin
            if (output_frame_start) begin
                output_frame_index = output_frame_index + 1;
                frame_pixel_count = 0;
            end

            frame_pixel_count = frame_pixel_count + 1;

            if (output_line_start !== (output_x == 0))
                $fatal(1, "line_start mismatch at frame %0d (%0d,%0d)",
                       output_frame_index, output_x, output_y);
            if (output_line_end !== (output_x == IMAGE_WIDTH - 1))
                $fatal(1, "line_end mismatch at frame %0d (%0d,%0d)",
                       output_frame_index, output_x, output_y);

            if (output_frame_index == 0) begin
                if (output_box_active)
                    $fatal(1, "A box was drawn before the first result existed");
                if (output_data !== frame_one_pixel(output_x, output_y))
                    $fatal(1, "First-frame grayscale changed at (%0d,%0d)",
                           output_x, output_y);
            end else if (output_frame_index == 1) begin
                if (is_expected_border(output_x, output_y)) begin
                    if (!output_box_active || output_data !== 10'd1023)
                        $fatal(1, "Missing box pixel at (%0d,%0d)",
                               output_x, output_y);
                    second_frame_border_count = second_frame_border_count + 1;
                end else begin
                    if (output_box_active || output_data !== 10'd100)
                        $fatal(1, "Unexpected change at (%0d,%0d)",
                               output_x, output_y);
                end
            end
        end
    end

    initial begin
        repeat (4) @(negedge pclk);
        reset_n = 1'b1;

        send_frame(0);
        send_frame(1);

        cam_href  = 1'b0;
        cam_vsync = 1'b0;
        repeat (6) @(posedge pclk);
        #1;

        if (output_frame_index != 1)
            $fatal(1, "Expected two output frames, last index was %0d",
                   output_frame_index);
        if (frame_pixel_count != IMAGE_WIDTH * IMAGE_HEIGHT)
            $fatal(1, "Second frame contained %0d pixels", frame_pixel_count);
        if (second_frame_border_count != 10)
            $fatal(1, "Expected 10 second-frame border pixels, got %0d",
                   second_frame_border_count);
        if (result_count != 2)
            $fatal(1, "Expected two detection results, got %0d", result_count);

        $display("PASS: complete pipeline found (2,1) and boxed the next frame");
        $finish;
    end

endmodule
