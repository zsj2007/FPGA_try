"""End-to-end RTL -> event words -> C -> independent flood-fill comparison.
Requires Python, Icarus Verilog (iverilog/vvp), and GCC on PATH.
Run: python software/ccl_split/test_split.py
"""
import pathlib
import random
import subprocess
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
RTL = HERE.parents[1] / 'modules/blob_analyzer/ccl_analyzer_pl.sv'

def run(args, cwd):
    return subprocess.run([str(x) for x in args], cwd=cwd, check=True,
                          text=True, capture_output=True).stdout

def reference(bits, width, height):
    visited = set()
    blobs = []
    for p, bit in enumerate(bits):
        if not bit or p in visited:
            continue
        pending, points = [p], []
        visited.add(p)
        while pending:
            q = pending.pop()
            x, y = q % width, q // width
            points.append((x, y))
            for nx, ny in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                n = ny * width + nx
                if 0 <= nx < width and 0 <= ny < height and bits[n] and n not in visited:
                    visited.add(n)
                    pending.append(n)
        xs, ys = zip(*points)
        blobs.append((len(points),sum(xs),sum(ys),min(xs),max(xs),min(ys),max(ys)))
    return sorted(blobs)

RUNNER = r'''
#include "ccl_ps.h"
#include <stdio.h>
#include <assert.h>
static ccl_context ctx;
int main(void) {
    uint32_t w[8];
    FILE *f = fopen("events.txt", "r");
    assert(f);
    while (fscanf(f,"%x %x %x %x %x %x %x %x", &w[0], &w[1], &w[2], &w[3],
                  &w[4], &w[5], &w[6], &w[7]) == 8) {
        int result = ccl_ps_feed(&ctx,w);
        if ((w[0]&255) != 3) assert(result == 0);
        else {
            if (w[1]) { assert(result == -1); puts("OVERFLOW"); }
            else {
                assert(result == 1);
                for (unsigned i=1; i<CCL_LABELS; ++i) {
                    ccl_blob *b = &ctx.blobs[i];
                    if (b->area) printf("%llu %llu %llu %u %u %u %u\n",
                        (unsigned long long)b->area, (unsigned long long)b->sum_x,
                        (unsigned long long)b->sum_y,b->min_x,b->max_x,b->min_y,b->max_y);
                }
                ccl_target t = ccl_ps_select(&ctx,1);
                assert(t.valid == (ctx.count != 0));
                if (t.valid) {
                    assert(t.center_x == t.blob.sum_x/t.blob.area);
                    assert(t.center_y == t.blob.sum_y/t.blob.area);
                }
            }
            puts("END");
        }
    }
    fclose(f);
    // Repeated/reversed edges and long chains cannot create parent cycles.
    uint32_t start[8]={0}, edge[8]={1}, end[8]={3};
    assert(ccl_ps_feed(&ctx,start)==0);
    for (unsigned i=1;i<255;++i) {
        edge[0]=1 | (i<<8) | ((i+1)<<16);
        assert(ccl_ps_feed(&ctx,edge)==0);
        edge[0]=1 | ((i+1)<<8) | (i<<16);
        assert(ccl_ps_feed(&ctx,edge)==0);
    }
    assert(ccl_ps_feed(&ctx,end)==-1); // missing STAT records
    assert(!ccl_ps_select(&ctx,1).valid);
    return 0;
}
'''

def exercise(width, height, limit, frames, tmp):
    (tmp/'pixels.mem').write_text('\n'.join(str(b) for f in frames for b in f))
    tb = r'''
module tb;
localparam W=@W@, H=@H@, N=@N@;
reg clk=0, reset_n=0, pixel_valid=0, frame_start=0, binary_data=0;
reg [15:0] pixel_x=0, pixel_y=0;
wire pixel_ready, event_valid;
reg event_ready=0;
wire [255:0] event_data;
reg pixels[0:W*H*N-1];
integer fd, completed=0;
reg held=0;
reg [255:0] held_data;
ccl_analyzer_pl #(.IMAGE_WIDTH(W),.IMAGE_HEIGHT(H),.MAX_LABELS(@L@)) dut(.*);
always #5 clk=~clk;
always @(negedge clk) event_ready <= ($urandom_range(0,3)!=0);
always @(posedge clk) if (reset_n) begin
    if (held && (!event_valid || event_data !== held_data)) $fatal(1,"unstable event");
    held = event_valid && !event_ready;
    held_data = event_data;
    if (event_valid && event_ready) begin
        for (integer j=0;j<8;j=j+1) $fwrite(fd,"%08x ",event_data[j*32+:32]);
        $fwrite(fd,"\n");
        if (event_data[7:0]==3) completed=completed+1;
    end
end
initial begin
    $readmemb("pixels.mem",pixels);
    fd=$fopen("events.txt","w");
    repeat(3) @(negedge clk);
    reset_n=1;
    for (integer f=0;f<N;f=f+1) begin
        for(integer p=0;p<W*H;p=p+1) begin
            @(negedge clk);
            pixel_valid=0;
            if ($urandom_range(0,3)==0) @(negedge clk);
            pixel_valid=1; pixel_x=p%W; pixel_y=p/W;
            frame_start=(p==0); binary_data=pixels[f*W*H+p];
            @(posedge clk);
            while (!pixel_ready) @(posedge clk);
        end
        @(negedge clk); pixel_valid=0; frame_start=0;
        while (completed < f+1) @(negedge clk);
    end
    $fclose(fd); $finish;
end
initial begin #10000000; $fatal(1,"timeout"); end
endmodule
'''
    for key,value in [('W',width),('H',height),('N',len(frames)),('L',limit)]:
        tb=tb.replace('@'+key+'@',str(value))
    (tmp/'tb.sv').write_text(tb)
    run(['iverilog','-g2012','-s','tb','-o',tmp/'sim',RTL,tmp/'tb.sv'],tmp)
    run(['vvp',tmp/'sim'],tmp)
    out=run([tmp/'test.exe'],tmp)
    groups=out.split('END\n')[:-1]
    assert len(groups)==len(frames)
    overflow=0
    for bits,group in zip(frames,groups):
        if group.strip()=='OVERFLOW':
            assert limit==8
            overflow+=1
        else:
            actual=sorted(tuple(map(int,row.split())) for row in group.splitlines() if row)
            assert actual==reference(bits,width,height),(actual,reference(bits,width,height))
    if limit==8:
        assert overflow==1

def main():
    rng=random.Random(20261016)
    w,h=16,12
    frames=[[0]*(w*h),[1]*(w*h),[int(i==w*h-1) for i in range(w*h)],
            [int((i%w+i//w)%2==0) for i in range(w*h)]]
    # Repeated bridges between runs, then 100 independently checked random images.
    frames.append([int(y%2 or x%2==0) for y in range(h) for x in range(w)])
    frames.extend([[int(rng.random()<density) for _ in range(w*h)]
                   for density in [0.15,0.35,0.5,0.75,0.9] for _ in range(20)])
    with tempfile.TemporaryDirectory() as d:
        tmp=pathlib.Path(d)
        (tmp/'runner.c').write_text(RUNNER)
        run(['gcc','-std=c11','-Wall','-Wextra','-Werror','-I',HERE,
             HERE/'ccl_ps.c',tmp/'runner.c','-o',tmp/'test.exe'],tmp)
        exercise(w,h,256,frames,tmp)
        exercise(1,1,256,[[1],[0],[1]],tmp)
        exercise(w,h,8,[frames[3],frames[1],frames[0]],tmp)
    print('PASS: 111 frames; RTL backpressure, C union/find, flood-fill statistics, overflow recovery.')

if __name__=='__main__':
    main()
