`timescale 1ns / 1ps
module ccl_axi_lite_tb;
    logic aclk=0, aresetn=0;
    always #5 aclk=~aclk;
    logic pixel_valid=0, frame_start=0, binary_data=0, start_pixels=0;
    logic [15:0] pixel_x=0,pixel_y=0;
    wire pixel_ready;
    logic [7:0] s_axi_awaddr=0,s_axi_araddr=0;
    logic s_axi_awvalid=0,s_axi_wvalid=0,s_axi_bready=0,s_axi_arvalid=0,s_axi_rready=0;
    logic [31:0] s_axi_wdata=0;
    logic [3:0] s_axi_wstrb=0;
    wire s_axi_awready,s_axi_wready,s_axi_bvalid,s_axi_arready,s_axi_rvalid;
    wire [1:0] s_axi_bresp,s_axi_rresp;
    wire [31:0] s_axi_rdata;
    wire result_valid,target_found;
    wire [15:0] center_x,center_y,bbox_left,bbox_right,bbox_top,bbox_bottom;
    wire [31:0] area,result_frame_id;
    integer completed=0,commits=0,blocked=0,fd;
    integer parent[0:255], areas[0:255], sx[0:255], sy[0:255];
    integer lx[0:255],rx[0:255],ty[0:255],by[0:255];
    integer a,b,r,total,stats,edges;
    reg [31:0] words[0:7],value,again;
    ccl_axi_lite #(.IMAGE_WIDTH(8),.IMAGE_HEIGHT(4),.MAX_LABELS(8),.FIFO_DEPTH(3)) dut(.*);

    task automatic axi_write(input [7:0] addr,input [31:0] data,input [3:0] strb,
                             input integer aw_delay,input integer w_delay,input [1:0] resp);
        reg [1:0] saved;
        fork
            begin
                repeat(aw_delay) @(negedge aclk);
                @(negedge aclk); s_axi_awaddr=addr; s_axi_awvalid=1;
                @(posedge aclk); while(!s_axi_awready) @(posedge aclk);
                @(negedge aclk); s_axi_awvalid=0;
            end
            begin
                repeat(w_delay) @(negedge aclk);
                @(negedge aclk); s_axi_wdata=data; s_axi_wstrb=strb; s_axi_wvalid=1;
                @(posedge aclk); while(!s_axi_wready) @(posedge aclk);
                @(negedge aclk); s_axi_wvalid=0;
            end
        join
        while(!s_axi_bvalid) @(negedge aclk);
        saved=s_axi_bresp;
        repeat(3) begin
            @(negedge aclk);
            if (!s_axi_bvalid || s_axi_bresp !== saved) $fatal(1,"B unstable");
        end
        if(saved !== resp) $fatal(1,"BRESP addr=%h got=%h expected=%h",addr,saved,resp);
        s_axi_bready=1;
        @(negedge aclk); s_axi_bready=0;
    endtask
    task automatic axi_read(input [7:0] addr,output [31:0] data,input [1:0] resp);
        reg [31:0] saved;
        reg [1:0] saved_resp;
        @(negedge aclk); s_axi_araddr=addr; s_axi_arvalid=1;
        @(posedge aclk); while(!s_axi_arready) @(posedge aclk);
        @(negedge aclk); s_axi_arvalid=0;
        while(!s_axi_rvalid) @(negedge aclk);
        saved=s_axi_rdata; saved_resp=s_axi_rresp;
        repeat(2) begin
            @(negedge aclk);
            if(!s_axi_rvalid || s_axi_rdata !== saved || s_axi_rresp !== saved_resp)
                $fatal(1,"R unstable");
        end
        if(saved_resp !== resp) $fatal(1,"RRESP addr=%h",addr);
        data=saved;
        s_axi_rready=1;
        @(negedge aclk); s_axi_rready=0;
    endtask
    function automatic integer root(input integer x);
        integer p;
        p=x;
        while(parent[p]!=p) p=parent[p];
        return p;
    endfunction
    function automatic bit foreground(input integer f,x,y);
        case(f)
            0: return (y==0 && (x==0 || x==2)) || (y==1 && x<=2) ||
                      (y==2 && x==2) || (y==3 && x==7);
            1: return 0;
            2: return ((x+y)%2)==0;
            3: return 1;
            default: return (y%2==1 || x%2==0);
        endcase
    endfunction
    always @(posedge aclk) if(aresetn) begin
        if(pixel_valid && !pixel_ready) blocked=blocked+1;
        if(result_valid) commits=commits+1;
    end

    initial begin : producer
        wait(start_pixels);
        for(integer f=0;f<5;f=f+1) begin
            for(integer p=0;p<32;p=p+1) begin
                @(negedge aclk);
                pixel_valid=1; frame_start=(p==0); pixel_x=p%8; pixel_y=p/8;
                binary_data=foreground(f,p%8,p/8);
                @(posedge aclk); while(!pixel_ready) @(posedge aclk);
            end
            @(negedge aclk); pixel_valid=0; frame_start=0;
            wait(completed>f);
        end
    end
    initial begin : consumer
        fd=$fopen("ccl_axi_events.txt","w");
        repeat(4) @(negedge aclk); aresetn=1;
        // Empty/invalid accesses must fail explicitly; disabled byte lanes are no-op.
        axi_read(8'h20,value,2'b10);
        axi_write(8'h08,1,4'hf,0,3,2'b10);
        axi_write(8'hfc,0,4'hf,3,0,2'b10);
        axi_read(8'h01,value,2'b10);
        axi_write(8'h40,32'h11223344,4'hf,0,4,0);
        axi_write(8'h40,32'haabbccdd,4'b0101,4,0,0);
        axi_read(8'h40,value,0);
        if(value !== 32'h11bb33dd) $fatal(1,"WSTRB failed");
        if(commits!=0 || target_found) $fatal(1,"shadow writes changed outputs");
        start_pixels=1;

        while(completed<5) begin
            axi_read(0,value,0);
            if(value[0]) begin
                for(integer j=0;j<8;j=j+1) axi_read(8'h20+j*4,words[j],0);
                axi_read(8'h20,again,0);
                if(again !== words[0]) $fatal(1,"head moved without POP");
                for(integer j=0;j<8;j=j+1) $fwrite(fd,"%08x ",words[j]);
                $fwrite(fd,"\n");
                axi_write(8'h08,1,0,0,0,0); // no strobe: no pop
                axi_read(8'h20,again,0);
                if(again !== words[0]) $fatal(1,"POP ignored WSTRB");
                axi_write(8'h08,1,4'h1,completed%3,(completed+1)%3,0);
                a=words[0][15:8]; b=words[0][23:16];
                case(words[0][7:0])
                    0: begin
                        stats=0; edges=0;
                        for(integer k=0;k<256;k=k+1) begin
                            parent[k]=k; areas[k]=0; sx[k]=0; sy[k]=0;
                            lx[k]=65535; rx[k]=0; ty[k]=65535; by[k]=0;
                        end
                    end
                    1: begin parent[root(b)]=root(a); edges=edges+1; end
                    2: begin
                        stats=stats+1; r=root(a);
                        areas[r]=areas[r]+words[1]; sx[r]=sx[r]+words[2]; sy[r]=sy[r]+words[3];
                        if(words[4][15:0]<lx[r]) lx[r]=words[4][15:0];
                        if(words[4][31:16]>rx[r]) rx[r]=words[4][31:16];
                        if(words[5][15:0]<ty[r]) ty[r]=words[5][15:0];
                        if(words[5][31:16]>by[r]) by[r]=words[5][31:16];
                    end
                    3: begin
                        if(stats!=a) $fatal(1,"STAT count mismatch");
                        case(completed)
                            0: begin
                                r=root(1);
                                if(edges==0 || a!=3 || root(2)!=r || areas[r]!=6 || sx[r]!=7 || sy[r]!=5 ||
                                   lx[r]!=0 || rx[r]!=2 || ty[r]!=0 || by[r]!=2 ||
                                   areas[root(3)]!=1 || sx[root(3)]!=7 || sy[root(3)]!=3 || words[1]!=0)
                                    $fatal(1,"bridge component incorrect");
                            end
                            1: if(a!=0 || words[1]!=0) $fatal(1,"empty frame incorrect");
                            2: if(a!=7 || words[1]!=1) $fatal(1,"overflow incorrect");
                            3: if(a!=1 || words[1]!=0 || areas[root(1)]!=32 || sx[root(1)]!=112 || sy[root(1)]!=48)
                                   $fatal(1,"overflow recovery incorrect");
                            4: if(a!=4 || edges!=3 || words[1]!=0 || areas[root(1)]!=24 ||
                                  sx[root(1)]!=80 || sy[root(1)]!=40)
                                   $fatal(1,"multiple bridges incorrect");
                        endcase
                        // PS bus model writes a known result; actual ARM C is not executed here.
                        axi_write(8'h40,32'h00000001,15,0,2,0);
                        axi_write(8'h44,32'h00020000,15,2,0,0);
                        axi_write(8'h48,32'h00020000,15,0,0,0);
                        axi_write(8'h4c,6,15,0,0,0);
                        axi_write(8'h50,(completed==0),15,0,0,0);
                        axi_write(8'h54,completed,15,0,0,0);
                        axi_write(8'h58,1,0,0,0,0);
                        if(commits!=completed) $fatal(1,"commit WSTRB ignored");
                        axi_write(8'h58,1,1,3,0,0);
                        if(commits!=completed+1 || target_found!==(completed==0) ||
                           center_x!=1 || center_y!=0 || bbox_left!=0 || bbox_right!=2 ||
                           bbox_top!=0 || bbox_bottom!=2 || area!=6 || result_frame_id!=completed)
                            $fatal(1,"result commit incorrect");
                        $display("Frame %0d checked: labels=%0d edges=%0d overflow=%0d",completed,a,edges,words[1]);
                        completed=completed+1;
                    end
                    default: $fatal(1,"unknown event");
                endcase
            end
        end
        if(blocked==0) $fatal(1,"FIFO backpressure not exercised");
        axi_read(4,value,0); if(value!=0) $fatal(1,"FIFO not drained");
        // Reset with an unmatched AW request must discard it and clear results.
        @(negedge aclk); s_axi_awvalid=1; s_axi_awaddr=8'h58;
        @(negedge aclk); s_axi_awvalid=0; aresetn=0;
        repeat(3) @(negedge aclk); aresetn=1;
        axi_read(4,value,0);
        if(value!=0 || target_found || s_axi_bvalid) $fatal(1,"reset failed");
        $fclose(fd);
        fd=$fopen("ccl_axi_pass.txt","w");
        $fdisplay(fd,"PASS: 5 frames, AXI channel skew, R/B stalls, WSTRB, FIFO backpressure, merge, overflow, commit, reset");
        $fclose(fd);
        $display("PASS: CCL AXI4-Lite integration; blocked pixel cycles=%0d",blocked);
        $finish;
    end
    initial begin #2000000; $fatal(1,"simulation timeout"); end
endmodule
