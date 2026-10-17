`timescale 1ns / 1ps
// Single clock domain. 32-bit AXI4-Lite slave, independent AW/W channels.
// Event FIFO head is stable until software explicitly POPs it.
module ccl_axi_lite #(
    parameter integer IMAGE_WIDTH=640, IMAGE_HEIGHT=400, MAX_LABELS=64,
    parameter integer FIFO_DEPTH=16
) (
    input logic aclk, aresetn,
    input logic pixel_valid, frame_start, binary_data,
    input logic [15:0] pixel_x, pixel_y,
    output logic pixel_ready,
    input logic [7:0] s_axi_awaddr,
    input logic s_axi_awvalid,
    output logic s_axi_awready,
    input logic [31:0] s_axi_wdata,
    input logic [3:0] s_axi_wstrb,
    input logic s_axi_wvalid,
    output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input logic s_axi_bready,
    input logic [7:0] s_axi_araddr,
    input logic s_axi_arvalid,
    output logic s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0] s_axi_rresp,
    output logic s_axi_rvalid,
    input logic s_axi_rready,
    output logic result_valid, target_found,
    output logic [15:0] center_x, center_y,
    output logic [15:0] bbox_left, bbox_right, bbox_top, bbox_bottom,
    output logic [31:0] area, result_frame_id
);
    localparam integer PTR_W = (FIFO_DEPTH < 2) ? 1 : $clog2(FIFO_DEPTH);
    logic [255:0] fifo [0:FIFO_DEPTH-1];
    logic [PTR_W-1:0] wr_ptr, rd_ptr;
    logic [PTR_W:0] count;
    wire event_valid, event_ready;
    wire [255:0] event_data;
    logic aw_pending, w_pending;
    logic [7:0] awaddr;
    logic [31:0] wdata;
    logic [3:0] wstrb;
    logic [31:0] shadow [0:5];
    wire execute_write = aw_pending && w_pending && !s_axi_bvalid;
    wire pop = execute_write && awaddr == 8'h08 && wstrb[0] && wdata[0] && count != 0;
    wire push = event_valid && event_ready;
    assign event_ready = count < FIFO_DEPTH;
    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready = !w_pending && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    ccl_analyzer_pl #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
        .MAX_LABELS(MAX_LABELS)) frontend (
        .clk(aclk),.reset_n(aresetn),.pixel_valid(pixel_valid),.pixel_ready(pixel_ready),
        .frame_start(frame_start),.pixel_x(pixel_x),.pixel_y(pixel_y),.binary_data(binary_data),
        .event_valid(event_valid),.event_ready(event_ready),.event_data(event_data));
    initial if (FIFO_DEPTH < 1) $fatal(1,"FIFO_DEPTH must be positive");

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            count <= 0; wr_ptr <= 0; rd_ptr <= 0;
        end else begin
            if (push) begin
                fifo[wr_ptr] <= event_data;
                wr_ptr <= (wr_ptr == FIFO_DEPTH-1) ? 0 : wr_ptr + 1'b1;
            end
            if (pop) rd_ptr <= (rd_ptr == FIFO_DEPTH-1) ? 0 : rd_ptr + 1'b1;
            case ({push,pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ;
            endcase
        end
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            aw_pending <= 0; w_pending <= 0; awaddr <= 0; wdata <= 0; wstrb <= 0;
            s_axi_bvalid <= 0; s_axi_bresp <= 0;
            s_axi_rvalid <= 0; s_axi_rresp <= 0; s_axi_rdata <= 0;
            result_valid <= 0; target_found <= 0;
            center_x <= 0; center_y <= 0; bbox_left <= 0; bbox_right <= 0;
            bbox_top <= 0; bbox_bottom <= 0; area <= 0; result_frame_id <= 0;
            for (integer i=0;i<6;i=i+1) shadow[i] <= 0;
        end else begin
            result_valid <= 0;
            if (s_axi_awvalid && s_axi_awready) begin aw_pending <= 1; awaddr <= s_axi_awaddr; end
            if (s_axi_wvalid && s_axi_wready) begin
                w_pending <= 1; wdata <= s_axi_wdata; wstrb <= s_axi_wstrb;
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
            if (execute_write) begin
                aw_pending <= 0; w_pending <= 0;
                s_axi_bvalid <= 1; s_axi_bresp <= 0;
                if (awaddr == 8'h08) begin
                    if (wstrb[0] && wdata[0] && count == 0) s_axi_bresp <= 2'b10;
                end else if (awaddr >= 8'h40 && awaddr <= 8'h54 && awaddr[1:0]==0) begin
                    for (integer j=0;j<4;j=j+1)
                        if (wstrb[j]) shadow[(awaddr-8'h40)>>2][j*8+:8] <= wdata[j*8+:8];
                end else if (awaddr == 8'h58) begin
                    if (wstrb[0] && wdata[0]) begin
                        result_valid <= 1;
                        {center_y,center_x} <= shadow[0];
                        {bbox_right,bbox_left} <= shadow[1];
                        {bbox_bottom,bbox_top} <= shadow[2];
                        area <= shadow[3]; target_found <= shadow[4][0];
                        result_frame_id <= shadow[5];
                    end
                end else s_axi_bresp <= 2'b10;
            end
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 0;
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1; s_axi_rresp <= 0; s_axi_rdata <= 0;
                case (s_axi_araddr)
                    8'h00: s_axi_rdata <= {29'd0, pixel_ready, (count == FIFO_DEPTH), (count != 0)};
                    8'h04: s_axi_rdata <= count;
                    default: begin
                        if (s_axi_araddr >= 8'h20 && s_axi_araddr <= 8'h3c && s_axi_araddr[1:0]==0) begin
                            if (count != 0) s_axi_rdata <= fifo[rd_ptr][((s_axi_araddr-8'h20)>>2)*32+:32];
                            else s_axi_rresp <= 2'b10;
                        end else if (s_axi_araddr >= 8'h40 && s_axi_araddr <= 8'h54 && s_axi_araddr[1:0]==0)
                            s_axi_rdata <= shadow[(s_axi_araddr-8'h40)>>2];
                        else s_axi_rresp <= 2'b10;
                    end
                endcase
            end
        end
    end
endmodule
