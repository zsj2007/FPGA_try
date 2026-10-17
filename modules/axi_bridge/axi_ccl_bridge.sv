`timescale 1ns / 1ps

// ============================================================================
// axi_ccl_bridge  AXI4-Lite slave capturing CCL dump into dual-buffer BRAM.
//
// Bank A: written by CCL front-end dump at frame end
// Bank B: readable by PS through AXI4-Lite
// Banks are swapped when PS signals it has finished processing.
//
// Memory map (each bank same layout):
//   Offset 0x000-0x0FC : label stats  (64 labels x 5 words of 32 bits)
//   Offset 0x100       : num_labels[7:0]
//   Offset 0x104       : control/status (bit0=bank_swap W, bit1=frame_ready R)
//   Offset 0x200-0x210 : PS result write-back
// ============================================================================

module axi_ccl_bridge #(
    parameter integer MAX_LABELS  = 64,
    parameter integer LABEL_BITS  = 8,
    parameter integer AXI_ADDR_W  = 10,
    parameter integer AXI_DATA_W  = 32
) (
    input  logic                   ccl_dump_valid,
    input  logic [LABEL_BITS-1:0]  ccl_dump_label,
    input  logic [23:0]            ccl_dump_area,
    input  logic [31:0]            ccl_dump_sum_x,
    input  logic [31:0]            ccl_dump_sum_y,
    input  logic [15:0]            ccl_dump_min_x,
    input  logic [15:0]            ccl_dump_max_x,
    input  logic [15:0]            ccl_dump_min_y,
    input  logic [15:0]            ccl_dump_max_y,
    input  logic [LABEL_BITS-1:0]  ccl_dump_equiv_parent,
    input  logic                   ccl_frame_done,
    input  logic [LABEL_BITS-1:0]  ccl_num_labels,

    input  logic                   s_axi_aclk,
    input  logic                   s_axi_aresetn,
    input  logic [AXI_ADDR_W-1:0]  s_axi_awaddr,
    input  logic                   s_axi_awvalid,
    output logic                   s_axi_awready,
    input  logic [AXI_DATA_W-1:0]  s_axi_wdata,
    input  logic                   s_axi_wvalid,
    output logic                   s_axi_wready,
    output logic                   s_axi_bvalid,
    input  logic                   s_axi_bready,
    output logic [1:0]             s_axi_bresp,
    input  logic [AXI_ADDR_W-1:0]  s_axi_araddr,
    input  logic                   s_axi_arvalid,
    output logic                   s_axi_arready,
    output logic [AXI_DATA_W-1:0]  s_axi_rdata,
    output logic                   s_axi_rvalid,
    input  logic                   s_axi_rready,
    output logic [1:0]             s_axi_rresp
);

    localparam integer WORDS_PER_LABEL = 5;
    localparam integer BANK_SIZE       = MAX_LABELS * WORDS_PER_LABEL;
    localparam integer BANK_ADDR_BITS  = $clog2(BANK_SIZE + 16);

    // ========================================================================
    //  All module-scope logic declarations (must precede always_ff for Vivado)
    // ========================================================================

    // Dual-bank BRAM
    logic                  wr_bank;
    logic                  rd_bank;
    logic [BANK_ADDR_BITS-1:0] wr_addr;
    logic [31:0]           wr_data;
    logic                  wr_en;

    (* ram_style = "block" *)
    logic [31:0] bank_a [0:BANK_SIZE+15];
    (* ram_style = "block" *)
    logic [31:0] bank_b [0:BANK_SIZE+15];

    // Read port
    logic [BANK_ADDR_BITS-1:0] rd_addr;
    logic [31:0] rd_data;

    // CCL dump write controller
    logic [2:0] word_idx;
    logic       dumping;
    logic       dump_armed;

    // Bank swap / frame ready
    logic bank_swap_pulse;
    logic frame_ready;

    // AXI4-Lite handshake
    logic axi_aw_hs, axi_w_hs, axi_wr_hs;
    logic axi_ar_hs, axi_r_hs;

    // ========================================================================
    //  Combinational assignments
    // ========================================================================
    assign axi_aw_hs = s_axi_awvalid && s_axi_awready;
    assign axi_w_hs  = s_axi_wvalid  && s_axi_wready;
    assign axi_wr_hs = axi_aw_hs && axi_w_hs;

    assign axi_ar_hs = s_axi_arvalid && s_axi_arready;
    assign axi_r_hs  = s_axi_rvalid  && s_axi_rready;

    // ========================================================================
    //  Sequential logic
    // ========================================================================

    // ---- Dual-bank BRAM write port ----
    always_ff @(posedge s_axi_aclk) begin
        if (wr_en) begin
            if (!wr_bank)
                bank_a[wr_addr] <= wr_data;
            else
                bank_b[wr_addr] <= wr_data;
        end
    end

    // ---- Dual-bank BRAM read port ----
    always_ff @(posedge s_axi_aclk) begin
        rd_addr <= s_axi_araddr[BANK_ADDR_BITS+1:2];
        if (!rd_bank)
            rd_data <= bank_a[rd_addr];
        else
            rd_data <= bank_b[rd_addr];
    end

    // ---- CCL dump write controller ----
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            wr_en      <= 1'b0;
            wr_addr    <= '0;
            wr_data    <= '0;
            word_idx   <= '0;
            dumping    <= 1'b0;
            dump_armed <= 1'b0;
        end else begin
            dump_armed <= ccl_dump_valid;

            if (dump_armed) begin
                dumping  <= 1'b1;
                wr_en    <= 1'b1;
                word_idx <= '0;
                wr_addr  <= ccl_dump_label * WORDS_PER_LABEL;
                wr_data[23:0]  <= ccl_dump_area;
                wr_data[31:24] <= ccl_dump_equiv_parent;
            end else if (dumping) begin
                word_idx <= word_idx + 3'd1;
                wr_addr  <= ccl_dump_label * WORDS_PER_LABEL + (BANK_ADDR_BITS)'(word_idx + 3'd1);

                case (word_idx)
                    0: wr_data <= ccl_dump_sum_x;
                    1: wr_data <= ccl_dump_sum_y;
                    2: wr_data <= {ccl_dump_min_x, ccl_dump_max_x};
                    3: wr_data <= {ccl_dump_min_y, ccl_dump_max_y};
                    default: begin
                        wr_en   <= 1'b0;
                        dumping <= 1'b0;
                    end
                endcase
            end

            // Write num_labels to status area
            if (ccl_frame_done) begin
                wr_en   <= 1'b1;
                wr_addr <= BANK_SIZE + 0;
                wr_data <= {24'd0, ccl_num_labels};
            end
        end
    end

    // ---- Frame-ready flag ----
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            frame_ready <= 1'b0;
        end else begin
            if (ccl_frame_done)
                frame_ready <= 1'b1;
            if (bank_swap_pulse)
                frame_ready <= 1'b0;
        end
    end

    // ---- Bank swap ----
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            wr_bank         <= 1'b0;
            rd_bank         <= 1'b0;
            bank_swap_pulse <= 1'b0;
        end else begin
            bank_swap_pulse <= 1'b0;
            if (axi_wr_hs && (s_axi_awaddr[BANK_ADDR_BITS+1:2] == BANK_SIZE + 2)
                && s_axi_wdata[0]) begin
                wr_bank         <= ~wr_bank;
                rd_bank         <= wr_bank;
                bank_swap_pulse <= 1'b1;
            end
        end
    end

    // ---- AXI4-Lite slave ----
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= '0;
            s_axi_rresp   <= 2'b00;
        end else begin
            // Write channel
            s_axi_awready <= !axi_aw_hs;
            s_axi_wready  <= !axi_w_hs;
            if (axi_wr_hs) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
            end
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // Read channel
            s_axi_arready <= !axi_ar_hs;
            if (axi_ar_hs) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
                if (s_axi_araddr[BANK_ADDR_BITS+1:2] == BANK_SIZE + 0)
                    s_axi_rdata <= {24'd0, ccl_num_labels};
                else if (s_axi_araddr[BANK_ADDR_BITS+1:2] == BANK_SIZE + 1)
                    s_axi_rdata <= {31'd0, frame_ready};
                else
                    s_axi_rdata <= rd_data;
            end
            if (axi_r_hs) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule