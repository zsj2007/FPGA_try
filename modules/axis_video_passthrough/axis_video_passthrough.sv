`timescale 1ns / 1ps

// Combinational AXI4-Stream-style video pass-through.
// tuser marks start-of-frame and tlast marks end-of-line.
module axis_video_passthrough #(
    parameter integer PIXEL_WIDTH = 10
) (
    input  logic [PIXEL_WIDTH-1:0] s_axis_tdata,
    input  logic                   s_axis_tvalid,
    output logic                   s_axis_tready,
    input  logic                   s_axis_tuser,
    input  logic                   s_axis_tlast,

    output logic [PIXEL_WIDTH-1:0] m_axis_tdata,
    output logic                   m_axis_tvalid,
    input  logic                   m_axis_tready,
    output logic                   m_axis_tuser,
    output logic                   m_axis_tlast
);

    always_comb begin
        s_axis_tready = m_axis_tready;
        m_axis_tdata  = s_axis_tdata;
        m_axis_tvalid = s_axis_tvalid;
        m_axis_tuser  = s_axis_tuser;
        m_axis_tlast  = s_axis_tlast;
    end

endmodule

