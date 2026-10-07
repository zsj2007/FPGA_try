`timescale 1ns / 1ps

module axis_video_passthrough_tb;

    logic [9:0] s_axis_tdata;
    logic       s_axis_tvalid;
    logic       s_axis_tready;
    logic       s_axis_tuser;
    logic       s_axis_tlast;
    logic [9:0] m_axis_tdata;
    logic       m_axis_tvalid;
    logic       m_axis_tready;
    logic       m_axis_tuser;
    logic       m_axis_tlast;

    axis_video_passthrough dut (
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tuser  (s_axis_tuser),
        .s_axis_tlast  (s_axis_tlast),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tuser  (m_axis_tuser),
        .m_axis_tlast  (m_axis_tlast)
    );

    initial begin
        s_axis_tdata  = 10'd42;
        s_axis_tvalid = 1'b1;
        s_axis_tuser  = 1'b1;
        s_axis_tlast  = 1'b0;
        m_axis_tready = 1'b0;
        #1;

        if (s_axis_tready !== 1'b0 || m_axis_tdata !== 10'd42 ||
            m_axis_tvalid !== 1'b1 || m_axis_tuser !== 1'b1 ||
            m_axis_tlast !== 1'b0)
            $fatal(1, "Pass-through failed while downstream was not ready");

        m_axis_tready = 1'b1;
        #1;

        if (s_axis_tready !== 1'b1)
            $fatal(1, "Ready was not propagated upstream");

        $display("PASS: axis_video_passthrough");
        $finish;
    end

endmodule

